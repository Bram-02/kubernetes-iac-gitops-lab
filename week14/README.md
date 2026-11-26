# Week 14: Secrets management (Sealed Secrets dan encryption at rest)

Rahasia aplikasi (password database Katalog) disimpan **di Git dalam bentuk terenkripsi** sehingga tetap bisa dikelola GitOps, tanpa pernah menulis password asli ke file atau layar. Di dalam cluster, Secret hasilnya juga dienkripsi di etcd (encryption at rest).

## Cara kerja

1. Controller Sealed Secrets di `kube-system` membuat pasangan kunci. Kunci privat tidak pernah keluar dari cluster.
2. `kubeseal` di laptop mengenkripsi Secret dengan kunci publik controller dan menghasilkan objek `SealedSecret`, yang aman di-commit.
3. Controller mendekripsi `SealedSecret` menjadi `Secret` biasa di namespace tujuan.

| Komponen | Versi | Dipasang dengan |
| --- | --- | --- |
| Chart `sealed-secrets` | 2.22.0 (repo `https://bitnami.github.io/sealed-secrets`) | OpenTofu `helm_release` (`secrets/main.tf`) |
| Controller | 0.41.2, nama `sealed-secrets-controller` di `kube-system` (bawaan kubeseal) | Chart di atas |
| CLI `kubeseal` | 0.41.2, checksum SHA-256 diverifikasi dari rilis resmi | `~/.local/bin` |

## Membuat SealedSecret

```bash
kubectl create secret generic katalog-db -n umkm-prod \
  --from-literal=username=katalog \
  --from-literal=password="$(openssl rand -base64 18)" \
  --dry-run=client -o yaml \
  | kubeseal --format yaml > secrets/katalog-db.sealedsecret.yaml
kubectl apply -f secrets/katalog-db.sealedsecret.yaml   # dalam GitOps penuh dikerjakan Argo CD
```

Password dibuat acak di dalam pipa: tidak tampil, tidak tersimpan di file. Hasil di cluster: `SYNCED True`, `secret/katalog-db` dengan `password: 24 bytes`, `username: 7 bytes`.

## Yang dibuktikan

| Uji | Hasil |
| --- | --- |
| SealedSecret yang sama disalin ke namespace `umkm-dev` | `no key could decrypt secret (password, username)`, tidak ada Secret terbentuk: enkripsi terikat ke nama dan namespace |
| Kunci privat dihapus, controller di-restart | Controller membuat kunci baru; file yang sama dari Git gagal didekripsi |
| Kunci dipulihkan dari backup, controller di-restart | File dari Git kembali `SYNCED True` dan Secret terbentuk lagi |

## Backup kunci

Semua SealedSecret di Git hanya bisa dibuka oleh kunci privat controller. Tanpa backup, kehilangan cluster berarti semua rahasia di Git tidak bisa dibuka lagi.

```bash
secrets/backup-kunci.sh    # bawaan: ~/.secrets/sealed-secrets-key-backup.yaml
```

Skrip menolak menulis ke dalam repo Git, tidak menyentuh backup lama bila cluster tidak punya kunci, dan hanya menampilkan nama serta waktu pembuatan kunci.

- File backup setara dengan semua password yang pernah di-seal: tidak pernah di-commit (dijaga `.gitignore`), tidak ditampilkan, disimpan terpisah dari cluster (password manager atau vault offline).
- Controller memakai kunci **terbaru** untuk mengenkripsi dan membuat kunci baru secara berkala (bawaan 30 hari). Backup harus diulang setiap ada kunci baru; backup lama tidak bisa membuka rahasia yang di-seal dengan kunci yang lebih baru.
- Kunci aktif ditentukan dari waktu sertifikatnya. Setelah restore, `creationTimestamp` kunci lama justru lebih baru, tetapi sidik jari SHA-256 dari `kubeseal --fetch-cert` tetap sama dengan kunci terbaru (`d4rtf`).
- Pemulihan: `kubectl apply -f` file backup, lalu `kubectl rollout restart deploy/sealed-secrets-controller -n kube-system`.

## Encryption at rest di etcd

Setelah dibuka controller, SealedSecret menjadi Secret biasa. Isinya hanya base64, dan bawaan kind menyimpannya **polos** di etcd. Siapa pun yang memegang file atau snapshot etcd bisa membacanya, tanpa kunci Sealed Secrets dan tanpa izin RBAC.

| Lapisan | Ancaman | Pelindung |
| --- | --- | --- |
| Git | Repo bocor atau dibaca publik | Sealed Secrets |
| API Kubernetes | Pengguna yang boleh `get secrets` | RBAC (Week 13, `matriks-akses.txt`) |
| etcd | File, disk, atau snapshot etcd | Encryption at rest (`secretbox`) |

```bash
enkripsi-etcd/aktifkan-enkripsi.sh                      # sekali per cluster
kubectl get secrets -A -o json | kubectl replace -f -   # tulis ulang Secret lama
enkripsi-etcd/cek-enkripsi.sh                           # setiap Secret harus berheader k8s:enc:, dilaporkan per kunci
```

`aktifkan-enkripsi.sh` membuat kunci acak 32 byte di dalam node control-plane (tidak pernah tampil), menyalinnya ke `~/.secrets/etcd-encryption-config.yaml` (600), menyimpan manifest lama di luar folder `manifests`, lalu menunggu kube-apiserver **baru** siap. `cek-enkripsi.sh` hanya membaca header tiap nilai di etcd dan melaporkan kunci yang dipakai, misalnya `secretbox:key1=4`.

| Uji (langsung ke etcd dengan `etcdctl`) | Hasil |
| --- | --- |
| `katalog-db` sebelum enkripsi | Diawali `k8s\0` (protobuf polos); password asli ditemukan di nilai etcd |
| Secret baru setelah enkripsi aktif | Diawali `k8s:enc:secretbox:v1:key1:`, sisanya ciphertext |
| `katalog-db` lama setelah enkripsi aktif | Masih `k8s\0`: data lama tidak terenkripsi otomatis |
| Setelah semua Secret ditulis ulang | `4 Secret di etcd, 0 masih polos`; password tidak ditemukan lagi |

- Urutan provider menentukan: `secretbox` (pertama) dipakai untuk setiap tulis, `identity` hanya untuk membaca data lama yang belum ditulis ulang.
- Kunci etcd juga harus di-backup dan dijaga `.gitignore`: tanpanya snapshot etcd tidak bisa dibuka, dengannya semua Secret terbaca.
- Batasan: kunci statis tersimpan di disk node yang sama dengan etcd. Ini melindungi snapshot, backup, dan disk etcd yang bocor, bukan akses root ke node itu. Di produksi dipakai provider KMS v2 agar kunci berada di luar cluster.
- Perubahan dibuat langsung di node (static Pod), di luar OpenTofu `week10/cluster`. Cluster yang dibuat ulang dengan `tofu apply` kembali tanpa enkripsi: jalankan ulang skrip, tulis ulang Secret, lalu `cek-enkripsi.sh`.
- Versi pertama pengecek mati diam-diam karena SIGPIPE (`head -c 8` bersama `pipefail`) tanpa mencetak ringkasan. Pengecek harus selalu mencetak ringkasan, dan exit code-nya ikut diperiksa.

### Rotasi kunci etcd

Kunci lama tidak bisa langsung diganti: Secret yang dienkripsi dengannya tidak bisa dibaca lagi. `rotasi-kunci.sh` memisahkan tiga tahap:

```bash
enkripsi-etcd/rotasi-kunci.sh tambah                     # kunci baru di urutan pertama, kunci lama tetap untuk membaca
kubectl get secrets -A -o json | kubectl replace -f -    # semua Secret pindah ke kunci baru
enkripsi-etcd/rotasi-kunci.sh buang-lama                 # hanya jalan bila SEMUA Secret sudah memakai kunci terbaru
```

| Uji | Hasil |
| --- | --- |
| Awal | `secretbox:key1=4` |
| `tambah` | Konfigurasi `key20261126034916 key1`, kube-apiserver di-restart |
| `buang-lama` sebelum Secret ditulis ulang | Ditolak, `exit=1`: 4 Secret masih `key1` (termasuk kunci Sealed Secrets dan release Helm) |
| Setelah ditulis ulang | `secretbox:key20261126034916=4`, sekaligus bukti apiserver memuat konfigurasi baru |
| `buang-lama` | Tersisa `key20261126034916`, Secret masih terbaca lewat API, SealedSecret `katalog-db` tetap `SYNCED True` |

- Perubahan isi `enc.yaml` tidak memicu kubelet (beda dengan perubahan manifest), jadi skrip menghentikan container apiserver dengan `crictl stop` agar dijalankan ulang.
- Apiserver memasang **folder** `enc`, bukan file, sehingga file pengganti (tulis lalu `mv`) langsung terlihat.
- Setiap tahap memperbarui `~/.secrets/etcd-encryption-config.yaml`. Setelah `buang-lama`, snapshot etcd yang dibuat sebelum rotasi tidak bisa dibuka dengan salinan ini lagi.
