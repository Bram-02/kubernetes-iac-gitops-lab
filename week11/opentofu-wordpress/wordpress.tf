resource "kubernetes_deployment_v1" "wordpress" {
  metadata {
    name      = "wordpress"
    namespace = kubernetes_namespace_v1.wordpress.metadata[0].name
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "wordpress"
      }
    }
    template {
      metadata {
        labels = {
          app = "wordpress"
        }
      }
      spec {
        container {
          name  = "wordpress"
          image = "wordpress:6.9-apache"
          port {
            container_port = 80
          }
          env {
            name  = "WORDPRESS_DB_HOST"
            value = kubernetes_service_v1.mariadb.metadata[0].name
          }
          env {
            name  = "WORDPRESS_DB_USER"
            value = "root"
          }
          env {
            name = "WORDPRESS_DB_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.mariadb.metadata[0].name
                key  = "mariadb-password"
              }
            }
          }
          env {
            name  = "WORDPRESS_DB_NAME"
            value = "wordpress"
          }
          volume_mount {
            name       = "wordpress-storage"
            mount_path = "/var/www/html"
          }
        }
        volume {
          name = "wordpress-storage"
          empty_dir {}
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "wordpress" {
  metadata {
    name      = "wordpress-service"
    namespace = kubernetes_namespace_v1.wordpress.metadata[0].name
  }
  spec {
    selector = {
      app = "wordpress"
    }
    type = "NodePort"
    port {
      port        = 80
      target_port = 80
    }
  }
}
