#!/usr/bin/env bash
# Periksa langsung di etcd: apakah setiap Secret tersimpan terenkripsi (header k8s:enc:), dan dengan kunci apa?
# Hanya membaca header tiap nilai (64 byte pertama), isi rahasia tidak pernah ditampilkan.
# HARAP_KUNCI=<nama> : anggap bermasalah setiap Secret yang belum memakai kunci itu (dipakai saat rotasi).
set -euo pipefail

node="${1:-skomawan-lab-control-plane}"
harap="${HARAP_KUNCI:-}"
etcd() {
  kubectl exec -n kube-system "etcd-$node" -- etcdctl \
    --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key "$@" </dev/null
}

declare -A per_kunci=()
total=0; masalah=0
while read -r kunci; do
  [ -z "$kunci" ] && continue
  total=$((total + 1))
  # Baca header, lalu habiskan sisanya: tanpa ini kubectl kena SIGPIPE dan pipefail menghentikan skrip.
  # Byte tak tercetak (termasuk \0) diganti '?' agar aman disimpan di variabel.
  header=$(etcd get "$kunci" --print-value-only | { head -c 64; cat >/dev/null; } | tr -c '[:print:]' '?')
  if [[ $header == k8s:enc:* ]]; then
    label=$(cut -d: -f3,5 <<<"$header")    # contoh: secretbox:key1
  else
    label=POLOS
  fi
  per_kunci[$label]=$(( ${per_kunci[$label]:-0} + 1 ))
  if [[ $label == POLOS || ( -n $harap && $label != *":$harap" ) ]]; then
    masalah=$((masalah + 1))
    echo "$label  $kunci"
  fi
done < <(etcd get /registry/secrets/ --prefix --keys-only)

ringkas=""
for l in "${!per_kunci[@]}"; do ringkas+=" $l=${per_kunci[$l]}"; done
echo "== $total Secret di etcd:${ringkas:- (kosong)}"
echo "== $masalah bermasalah${harap:+ (harap kunci $harap)}"
exit $(( masalah > 0 ))
