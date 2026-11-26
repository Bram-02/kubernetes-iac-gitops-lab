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
git add secrets/katalog-db.sealedsecret.yaml && git commit && git push   # Argo CD (katalog-secrets) yang menerapkan
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

## GitOps: Argo CD menerapkan SealedSecret

Dua file di `week11/apps/` (diawasi Application `root`):

| File | Isi |
| --- | --- |
| `project-katalog.yaml` | AppProject `katalog`: hanya repo ini, hanya namespace `umkm-prod`, hanya objek `bitnami.com/SealedSecret`, tanpa objek tingkat cluster |
| `katalog-secrets.yaml` | Application yang mengawasi `week14/secrets/*.sealedsecret.yaml`; `prune` dan `selfHeal` aktif; sengaja tanpa finalizer |

Argo CD hanya pernah melihat ciphertext; yang membukanya tetap controller Sealed Secrets di cluster. Mengubah rahasia sekarang cukup lewat commit.

| Uji | Hasil |
| --- | --- |
| SealedSecret yang sebelumnya dibuat dengan `kubectl apply` | Diambil alih Argo CD (`tracking-id` `katalog-secrets:bitnami.com/SealedSecret:umkm-prod/katalog-db`), `Synced Healthy` |
| `kubectl delete sealedsecret katalog-db` | Dalam hitungan detik SealedSecret dan Secret kembali dari Git; sidik password sama sebelum dan sesudah |
| Application uji (tidak di-commit) memakai project `katalog` untuk overlay website | Ditolak: `resource :ConfigMap`, `:Service`, dan `apps:Deployment is not permitted in project katalog`; di `umkm-prod` tetap hanya `katalog-web` |

- Tanpa finalizer, menghapus Application tidak ikut menghapus SealedSecret dan Secret-nya: kehilangan password database lebih mahal daripada objek yatim yang bisa dibersihkan manual.
- Self-heal juga berarti perubahan rahasia harus lewat Git; perubahan manual di cluster dikembalikan ke isi Git.

## Memperbarui SealedSecret: re-encrypt dan rotasi password

| Tindakan | Cara | Password | Kapan |
| --- | --- | --- | --- |
| Re-encrypt | `kubeseal --re-encrypt --format yaml` ke file baru, lalu `mv` | Tetap: sidik SHA-256 sebelum = sesudah | Setelah controller membuat kunci baru, agar file di Git memakai kunci terbaru |
| Rotasi password | Secret baru dengan password acak dari `openssl rand`, lalu `kubeseal` | Berubah: sidik berbeda | Terjadwal, dan segera bila kunci atau password diduga bocor |

- Re-encrypt tidak menghapus riwayat Git. Commit lama tetap menyimpan ciphertext lama yang bisa dibuka dengan kunci lama. Bila kunci bocor, yang melindungi hanya rotasi password, karena yang terbuka adalah password yang sudah tidak berlaku.
- Sidik dibandingkan dengan 12 karakter awal SHA-256 password, sehingga sama atau berbedanya terlihat tanpa membuka password.
- Keluaran `kubeseal --re-encrypt` ditulis ke file baru lalu `mv`, karena `> file` mengosongkan file sebelum sempat dibaca.
- Di sistem nyata, password baru juga diganti di database dan aplikasi di-restart agar membaca Secret baru. Di lab ini Katalog belum memakai database.

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
