#!/usr/bin/env bash
# Uji matriks akses: setiap baris matriks-akses.txt = siapa, harapan, verb, resource, namespace.
set -uo pipefail
cd "$(dirname "$0")"
gagal=0
while read -r pihak harap verb res ns; do
  [[ -z ${pihak:-} || $pihak == \#* ]] && continue
  case $pihak in
    students)    id=(--as=test --as-group=students) ;;
    katalog-dev) id=(--as=dina --as-group=katalog-dev) ;;
    platform)    id=(--as=raka --as-group=platform-team) ;;
    argocd)      id=(--as=system:serviceaccount:argocd:argocd-application-controller) ;;
    katalog-sa)  id=(--as=system:serviceaccount:umkm-prod:katalog) ;;
    *) echo "pihak tidak dikenal: $pihak"; exit 2 ;;
  esac
  dapat=$(kubectl auth can-i "$verb" "$res" -n "$ns" "${id[@]}" 2>/dev/null || true)
  if [[ $dapat == "$harap" ]]; then tanda=OK; else tanda=SALAH; gagal=$((gagal + 1)); fi
  printf '%-5s %-11s %-6s %-40s %-11s harap=%-3s dapat=%s\n' "$tanda" "$pihak" "$verb" "$res" "$ns" "$harap" "$dapat"
done < matriks-akses.txt
echo "== $gagal baris tidak sesuai matriks"
exit $(( gagal > 0 ))
