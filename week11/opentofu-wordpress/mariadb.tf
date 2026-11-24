resource "kubernetes_deployment_v1" "mariadb" {
  metadata {
    name      = "mariadb"
    namespace = kubernetes_namespace_v1.wordpress.metadata[0].name
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "mariadb"
      }
    }
    template {
      metadata {
        labels = {
          app = "mariadb"
        }
      }
      spec {
        container {
          name  = "mariadb"
          image = "mariadb:11.8"
          port {
            container_port = 3306
          }
          env {
            name = "MARIADB_ROOT_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.mariadb.metadata[0].name
                key  = "mariadb-password"
              }
            }
          }
          env {
            name  = "MARIADB_DATABASE"
            value = "wordpress"
          }
          volume_mount {
            name       = "mariadb-storage"
            mount_path = "/var/lib/mysql"
          }
        }
        # Sama seperti modul: tanpa sumber penyimpanan = emptyDir (data hilang bila Pod dihapus)
        volume {
          name = "mariadb-storage"
          empty_dir {}
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "mariadb" {
  metadata {
    name      = "mariadb-service"
    namespace = kubernetes_namespace_v1.wordpress.metadata[0].name
  }
  spec {
    selector = {
      app = "mariadb"
    }
    cluster_ip = "None"
    port {
      port        = 3306
      target_port = 3306
    }
  }
}
