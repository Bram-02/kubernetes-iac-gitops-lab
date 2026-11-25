# Pod Security Admission per namespace (slide 13-14). Versi dikunci agar
# upgrade Kubernetes tidak diam-diam mengubah aturan.
locals {
  psa = {
    "umkm-dev" = {
      "pod-security.kubernetes.io/warn"         = "restricted"
      "pod-security.kubernetes.io/warn-version" = "v1.37"
    }
    "umkm-prod" = {
      "pod-security.kubernetes.io/enforce"         = "restricted"
      "pod-security.kubernetes.io/enforce-version" = "v1.37"
      "pod-security.kubernetes.io/warn"            = "restricted"
      "pod-security.kubernetes.io/warn-version"    = "v1.37"
    }
  }
}

resource "kubernetes_namespace_v1" "umkm" {
  for_each = local.psa
  metadata {
    name   = each.key
    labels = each.value
  }
}
