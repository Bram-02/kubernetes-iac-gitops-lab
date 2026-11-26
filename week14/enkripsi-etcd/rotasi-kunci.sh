#!/usr/bin/env bash
# Rotasi kunci encryption at rest etcd, dua tahap dengan penulisan ulang Secret di antaranya:
#   ./rotasi-kunci.sh tambah      kunci baru di urutan pertama (dipakai menulis), kunci lama tetap untuk membaca
#   kubectl get secrets -A -o json | kubectl replace -f -
#   ./rotasi-kunci.sh buang-lama  hanya jalan bila SEMUA Secret sudah memakai kunci terbaru
# Kunci tidak pernah ditampilkan; hanya nama kunci yang dicetak.
set -euo pipefail

tahap="${1:-}"
node="${2:-skomawan-lab-control-plane}"
konfig=/etc/kubernetes/enc/enc.yaml
cadangan="$HOME/.secrets/etcd-encryption-config.yaml"
folder_skrip="$(cd "$(dirname "$0")" && pwd)"

daftar_kunci() { docker exec "$node" sed -n 's/^ *- name: //p' "$konfig"; }

simpan_cadangan() {
  ( umask 077; docker exec "$node" cat "$konfig" > "$cadangan" )
  echo "Salinan kunci diperbarui: $cadangan"
}

# Perubahan isi file konfigurasi tidak memicu kubelet; container apiserver dihentikan agar kubelet menjalankannya ulang
restart_apiserver() {
  echo -n "Restart kube-apiserver agar membaca konfigurasi baru"
  docker exec "$node" sh -c 'crictl stop $(crictl ps -q --name kube-apiserver)' >/dev/null
  sleep 5
  for _ in $(seq 1 60); do
    if [ "$(kubectl get --raw /readyz 2>/dev/null)" = "ok" ]; then echo " siap"; return 0; fi
    echo -n "."; sleep 3
  done
  echo; echo "kube-apiserver belum siap setelah 3 menit" >&2
  return 1
}

case "$tahap" in
  tambah)
    baru="key$(date -u +%Y%m%d%H%M%S)"
    # Ditulis ke file baru lalu mv: volume apiserver memasang FOLDER enc, jadi file pengganti langsung terlihat
    docker exec -i -e BARU="$baru" "$node" sh -s <<'NODE'
set -e; umask 077; cd /etc/kubernetes/enc
K=$(head -c 32 /dev/urandom | base64) awk '{print} /^ *keys:$/{print "            - name: " ENVIRON["BARU"]; print "              secret: " ENVIRON["K"]}' enc.yaml > enc.yaml.baru
mv enc.yaml.baru enc.yaml
NODE
    echo "Kunci di konfigurasi (urutan pertama dipakai menulis): $(daftar_kunci | paste -sd ' ')"
    simpan_cadangan
    restart_apiserver
    echo "Berikutnya: tulis ulang semua Secret, lalu: HARAP_KUNCI=$baru $folder_skrip/cek-enkripsi.sh"
    ;;
  buang-lama)
    terbaru=$(daftar_kunci | head -n 1)
    if [ "$(daftar_kunci | wc -l)" -le 1 ]; then
      echo "Hanya ada kunci $terbaru, tidak ada yang dibuang"; exit 0
    fi
    if ! HARAP_KUNCI="$terbaru" "$folder_skrip/cek-enkripsi.sh" "$node"; then
      echo "Masih ada Secret yang belum memakai $terbaru. Tulis ulang dulu; kunci lama TIDAK dibuang." >&2
      exit 1
    fi
    docker exec -i "$node" sh -s <<'NODE'
set -e; umask 077; cd /etc/kubernetes/enc
awk '/^ *- name: /{n++} !(n >= 2 && (/^ *- name: / || /^ *secret: /))' enc.yaml > enc.yaml.baru
mv enc.yaml.baru enc.yaml
NODE
    echo "Kunci tersisa: $(daftar_kunci | paste -sd ' ')"
    simpan_cadangan
    restart_apiserver
    kubectl get secret katalog-db -n umkm-prod -o name >/dev/null && echo "Secret masih terbaca lewat API"
    ;;
  *)
    echo "Pemakaian: $0 tambah|buang-lama [node]" >&2
    exit 2
    ;;
esac
