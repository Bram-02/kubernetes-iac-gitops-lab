resource "kubernetes_deployment_v1" "nginx" {
  metadata {
    name      = "nginx-pv"
    namespace = kubernetes_namespace_v1.storage.metadata[0].name
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "nginx-pv"
      }
    }
    template {
      metadata {
        labels = {
          app = "nginx-pv"
        }
      }
      spec {
        container {
          name  = "nginx"
          image = "nginx:1.31-alpine"
          port {
            container_port = 80
          }
          volume_mount {
            name       = "nginx-storage"
            mount_path = "/usr/share/nginx/html"
          }
        }
        volume {
          name = "nginx-storage"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.nginx.metadata[0].name
          }
        }
      }
    }
  }
}
