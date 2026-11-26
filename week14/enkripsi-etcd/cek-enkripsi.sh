#!/usr/bin/env bash
# Periksa langsung di etcd: apakah setiap Secret tersimpan terenkripsi (header k8s:enc:)?
# Hanya membaca 8 byte pertama tiap nilai, isi rahasia tidak pernah ditampilkan.
set -euo pipefail

node="${1:-skomawan-lab-control-plane}"
etcd() {
  kubectl exec -n kube-system "etcd-$node" -- etcdctl \
    --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key "$@" </dev/null
}

total=0; polos=0
while read -r kunci; do
  [ -z "$kunci" ] && continue
  total=$((total + 1))
  # Baca 8 byte, lalu habiskan sisanya: tanpa ini kubectl kena SIGPIPE dan pipefail menghentikan skrip
  header=$(etcd get "$kunci" --print-value-only | { head -c 8; cat >/dev/null; } | tr -d '\0')
  if [ "$header" != "k8s:enc:" ]; then
    polos=$((polos + 1))
    echo "POLOS  $kunci"
  fi
done < <(etcd get /registry/secrets/ --prefix --keys-only)

echo "== $total Secret di etcd, $polos masih polos"
exit $(( polos > 0 ))
