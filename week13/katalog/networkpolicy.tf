# Satu-satunya jalan masuk ke Katalog: Pod berlabel peran=frontend dari namespace umkm-dev, port 8080
resource "kubernetes_network_policy_v1" "katalog_dari_frontend" {
  metadata {
    name      = "katalog-dari-frontend"
    namespace = "umkm-prod"
  }
  spec {
    pod_selector {
      match_labels = {
        app = "katalog"
      }
    }
    policy_types = ["Ingress"]
    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "umkm-dev"
          }
        }
        pod_selector {
          match_labels = {
            peran = "frontend"
          }
        }
      }
      ports {
        port     = "8080"
        protocol = "TCP"
      }
    }
  }
}
