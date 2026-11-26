#!/usr/bin/env bash
# Aktifkan encryption at rest untuk Secret di kube-apiserver cluster kind (provider secretbox).
# Kunci dibuat di dalam node control-plane dan tidak pernah ditampilkan; salinannya disimpan di ~/.secrets.
set -euo pipefail

node="${1:-skomawan-lab-control-plane}"
manifest=/etc/kubernetes/manifests/kube-apiserver.yaml
flag="--encryption-provider-config=/etc/kubernetes/enc/enc.yaml"
cadangan_kunci="$HOME/.secrets/etcd-encryption-config.yaml"

if docker exec "$node" grep -q -- "$flag" "$manifest"; then
  echo "Encryption at rest sudah aktif di $node, tidak ada yang diubah"
  exit 0
fi

# 1. Konfigurasi enkripsi. Urutan provider penting: secretbox (pertama) dipakai untuk setiap tulis baru,
#    identity tetap ada agar Secret lama yang masih polos masih bisa dibaca sampai ditulis ulang.
docker exec "$node" sh -c 'set -e; umask 077; mkdir -p /etc/kubernetes/enc
kunci=$(head -c 32 /dev/urandom | base64)
cat > /etc/kubernetes/enc/enc.yaml <<EOF
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources: ["secrets"]
    providers:
      - secretbox:
          keys:
            - name: key1
              secret: $kunci
      - identity: {}
EOF'
echo "1. Konfigurasi enkripsi dibuat di $node:/etc/kubernetes/enc/enc.yaml (mode 600)"

# 2. Salinan kunci ke luar node. Tanpa kunci ini, backup etcd tidak bisa dibaca lagi.
[ -d "$(dirname "$cadangan_kunci")" ] || install -d -m 700 "$(dirname "$cadangan_kunci")"
( umask 077; docker exec "$node" cat /etc/kubernetes/enc/enc.yaml > "$cadangan_kunci" )
echo "2. Salinan kunci: $cadangan_kunci"

# 3. Manifest lama disimpan di luar folder manifests (kubelet menjalankan SEMUA file di folder itu)
docker exec "$node" cp "$manifest" /root/kube-apiserver.yaml.sebelum-enkripsi
sementara=$(mktemp -d)
trap 'rm -rf "$sementara"' EXIT
docker exec "$node" cat "$manifest" > "$sementara/kube-apiserver.yaml"
python3 - "$sementara/kube-apiserver.yaml" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
tambahan = [
    ("    - kube-apiserver\n",
     "    - --encryption-provider-config=/etc/kubernetes/enc/enc.yaml\n"),
    ("    volumeMounts:\n",
     "    - mountPath: /etc/kubernetes/enc\n      name: enc\n      readOnly: true\n"),
    ("  volumes:\n",
     "  - hostPath:\n      path: /etc/kubernetes/enc\n      type: Directory\n    name: enc\n"),
]
for jangkar, baris in tambahan:
    if s.count(jangkar) != 1:
        sys.exit(f"Jangkar tidak ditemukan tepat satu kali: {jangkar.strip()}")
    s = s.replace(jangkar, jangkar + baris)
open(p, "w").write(s)
PY
# Tulis lalu mv di filesystem yang sama, agar kubelet tidak membaca file setengah jadi
docker exec -i "$node" sh -c 'cat > /etc/kubernetes/kube-apiserver.yaml.baru && mv /etc/kubernetes/kube-apiserver.yaml.baru /etc/kubernetes/manifests/kube-apiserver.yaml' \
  < "$sementara/kube-apiserver.yaml"
echo "3. Manifest kube-apiserver diperbarui (cadangan: $node:/root/kube-apiserver.yaml.sebelum-enkripsi)"

# 4. Tunggu kube-apiserver BARU (yang membawa flag) siap. Apiserver lama bisa masih menjawab sebentar.
echo -n "4. Menunggu kube-apiserver restart"
for _ in $(seq 1 60); do
  if kubectl get pod -n kube-system "kube-apiserver-$node" -o jsonpath='{.spec.containers[0].command}' 2>/dev/null \
       | grep -q encryption-provider-config \
     && [ "$(kubectl get --raw /readyz 2>/dev/null)" = "ok" ]; then
    echo " siap"
    exit 0
  fi
  echo -n "."; sleep 3
done
echo
echo "kube-apiserver belum siap setelah 3 menit. Pulihkan dengan:" >&2
echo "  docker exec $node cp /root/kube-apiserver.yaml.sebelum-enkripsi $manifest" >&2
exit 1
