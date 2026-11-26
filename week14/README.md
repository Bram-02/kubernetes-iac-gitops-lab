# Week 14: Secrets management dengan Sealed Secrets

Rahasia aplikasi (password database Katalog) disimpan **di Git dalam bentuk terenkripsi** sehingga tetap bisa dikelola GitOps, tanpa pernah menulis password asli ke file atau layar.

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
- Pemulihan: `kubectl apply -f` file backup, lalu `kubectl rollout restart deploy/sealed-secrets-controller -n kube-system`.
