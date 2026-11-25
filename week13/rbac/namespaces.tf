resource "kubernetes_namespace_v1" "umkm" {
  for_each = toset(["umkm-dev", "umkm-prod"])
  metadata {
    name = each.key
  }
}
