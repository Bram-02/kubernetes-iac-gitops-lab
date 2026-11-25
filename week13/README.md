# Week 13: Security, Identity, Access Control

Lab Week 13 di cluster kind (dibangun OpenTofu di `week10/cluster`). Semua izin, aturan namespace, dan aturan jaringan ditulis sebagai kode OpenTofu, lalu diuji, bukan dicoba-coba.

## Struktur

```
week13/
├── rbac/                     # Lapisan platform
│   ├── namespaces.tf         # umkm-dev (PSA warn restricted), umkm-prod (PSA enforce restricted), versi v1.37
│   ├── rbac.tf               # Role pod-reader + RoleBinding grup students (contoh slide 9-10)
│   ├── akses.tf              # katalog-dev, platform-team, Argo CD, SA katalog
│   ├── networkpolicy.tf      # default-deny-ingress di umkm-prod
│   ├── matriks-akses.txt     # Siapa, harapan, verb, resource, namespace (18 baris)
│   └── cek-akses.sh          # Menguji setiap baris matriks dengan kubectl auth can-i --as
└── katalog/                  # Lapisan aplikasi
    ├── katalog.tf            # Deployment + Service yang lolos Pod Security restricted
    └── networkpolicy.tf      # Hanya Pod peran=frontend dari umkm-dev yang boleh masuk, port 8080
```

## Matriks akses

| Pihak | Identitas | umkm-dev | umkm-prod | Alasan |
| --- | --- | --- | --- | --- |
| Mahasiswa | Grup `students` | Baca Pod dan log | Tidak ada | Contoh slide: hanya mengamati |
| Pengembang Katalog | Grup `katalog-dev` | `edit` (termasuk Secret dev) | `view` (tanpa Secret) | Bebas bereksperimen di dev, prod hanya dilihat |
| Tim platform | Grup `platform-team` | `admin` | `admin` | Mengatur RBAC per namespace; bukan `cluster-admin` |
| Argo CD | SA `argocd/argocd-application-controller` | `admin` | `admin` | Men-deploy hanya ke namespace aplikasi, bukan seluruh cluster |
| Workload Katalog | SA `umkm-prod/katalog` | Tidak ada | Tidak ada | Aplikasi tidak memanggil API Kubernetes; token tidak dipasang |

Semua memakai ClusterRole bawaan (`admin`, `edit`, `view`) lewat **RoleBinding**, sehingga izinnya hanya berlaku di namespace tempat binding dibuat.

```bash
cd week13/rbac
./cek-akses.sh     # 18 baris OK, kode keluar 0; satu saja yang meleset membuat kode keluar 1
```

## Temuan

**Drift RBAC hanya terdeteksi sebagian.** Slide menyatakan izin yang ditambahkan manual terdeteksi sebagai drift. Diuji dua kali:

| Perubahan manual | `cek-akses.sh` | `tofu plan -detailed-exitcode` |
| --- | --- | --- |
| Menambah verb `delete` ke Role `pod-reader` (dikelola OpenTofu) | SALAH (students bisa menghapus Pod) | Terdeteksi, kode 2; `apply` mengembalikan |
| RoleBinding baru `jalan-pintas` (students jadi admin di prod) | SALAH (students bisa membaca Pod prod) | **Tidak terdeteksi**, `No changes`, kode 0 |

OpenTofu hanya mengenal resource di state-nya. Izin tambahan yang dibuat di luar OpenTofu ditangkap oleh uji matriks dan audit `kubectl auth can-i --list`, bukan oleh `tofu plan`. Keduanya diperlukan.

**Pod Security restricted.** Pod nginx resmi di `umkm-prod` ditolak dengan 4 pelanggaran (`allowPrivilegeEscalation`, `capabilities`, `runAsNonRoot`, `seccompProfile`); di `umkm-dev` hanya peringatan. Workload Katalog lolos dengan user 101, seccomp `RuntimeDefault`, `capabilities: drop ALL`, root filesystem read-only (`/tmp` lewat emptyDir), `automountServiceAccountToken: false`, dan image dikunci dengan digest. Bukti di dalam Pod: `Read-only file system`, tidak ada folder token ServiceAccount, HTTP 200 tetap jalan.

**Jebakan provider Kubernetes.** Dengan blok `security_context` di container, provider mengirim `runAsNonRoot: false` untuk atribut yang tidak ditulis, dan nilai container mengalahkan nilai Pod. Akibatnya Pod ditolak (`must not set securityContext.runAsNonRoot=false`) dan `apply` gagal setelah timeout 3 menit. Perbaikan: tulis `run_as_non_root = true` juga di tingkat container.

**NetworkPolicy ditegakkan oleh CNI kind (kindnet).**

| Dari umkm-dev | Sebelum policy | Sesudah policy |
| --- | --- | --- |
| Pod biasa | Welcome to nginx | **timed out** |
| Pod `peran=frontend` | Welcome to nginx | Welcome to nginx |

`namespace_selector` dan `pod_selector` dalam satu blok `from` berarti DAN; port di policy adalah port Pod (8080), bukan port Service (80).

## Menjalankan

```bash
export KUBECONFIG=~/.kube/kind-skomawan-lab
cd week13/rbac && tofu init && tofu apply      # platform dulu: namespace, RBAC, default deny
cd ../katalog && tofu init && tofu apply       # lalu aplikasi
cd ../rbac && ./cek-akses.sh
```
