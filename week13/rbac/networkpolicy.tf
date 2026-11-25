# Default deny: Pod di umkm-prod tidak menerima koneksi apa pun kecuali diizinkan policy lain (slide 15)
resource "kubernetes_network_policy_v1" "default_deny_ingress" {
  metadata {
    name      = "default-deny-ingress"
    namespace = kubernetes_namespace_v1.umkm["umkm-prod"].metadata[0].name
  }
  spec {
    pod_selector {}
    policy_types = ["Ingress"]
  }
}
