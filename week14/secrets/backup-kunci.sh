#!/usr/bin/env bash
# Backup semua kunci privat Sealed Secrets ke luar repo (bawaan: ~/.secrets).
# Ulangi setiap controller membuat kunci baru (bawaan tiap 30 hari).
# Hasilnya setara semua rahasia yang pernah di-seal: jangan pernah di-commit atau ditampilkan.
set -euo pipefail

tujuan="${1:-$HOME/.secrets/sealed-secrets-key-backup.yaml}"
folder="$(dirname "$tujuan")"
label="sealedsecrets.bitnami.com/sealed-secrets-key"

[ -d "$folder" ] || install -d -m 700 "$folder"
if git -C "$folder" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Menolak: $folder berada di dalam repo Git" >&2
  exit 1
fi

jumlah=$(kubectl get secret -n kube-system -l "$label" -o name | wc -l)
if [ "$jumlah" -eq 0 ]; then
  echo "Tidak ada kunci ditemukan, backup lama tidak disentuh" >&2
  exit 1
fi

# Tulis ke file sementara (mode 600) lalu ganti sekaligus, agar backup lama tidak rusak bila gagal di tengah
sementara=$(mktemp "$folder/.kunci.XXXXXX")
trap 'rm -f "$sementara"' EXIT
kubectl get secret -n kube-system -l "$label" -o yaml > "$sementara"
mv "$sementara" "$tujuan"
trap - EXIT

echo "Backup $jumlah kunci ke $tujuan"
kubectl get secret -n kube-system -l "$label" --no-headers \
  -o custom-columns=KUNCI:.metadata.name,DIBUAT:.metadata.creationTimestamp
