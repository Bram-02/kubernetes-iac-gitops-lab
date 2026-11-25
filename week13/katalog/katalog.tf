# Workload Katalog di umkm-prod: lolos Pod Security "restricted" (slide 14).
# Namespace dan ServiceAccount dimiliki lapisan platform (week13/rbac).
resource "kubernetes_deployment_v1" "katalog" {
  metadata {
    name      = "katalog-web"
    namespace = "umkm-prod"
  }
  spec {
    replicas = 2
    selector {
      match_labels = {
        app = "katalog"
      }
    }
    template {
      metadata {
        labels = {
          app = "katalog"
        }
      }
      spec {
        service_account_name            = "katalog"
        automount_service_account_token = false
        security_context {
          run_as_non_root = true
          run_as_user     = 101
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }
        container {
          name  = "web"
          image = "nginxinc/nginx-unprivileged:1.31.7-alpine3.24@sha256:b5047b9b76845eac124358373c6852377c52e4b05834a47647e955dd91cb8f1e"
          port {
            container_port = 8080
          }
          # Provider mengirim false untuk boolean yang tidak ditulis, dan nilai container
          # mengalahkan nilai Pod. Jadi runAsNonRoot wajib ditulis lagi di sini.
          security_context {
            run_as_non_root            = true
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities {
              drop = ["ALL"]
            }
          }
          # Root filesystem read-only: nginx hanya boleh menulis file sementara di /tmp
          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }
        }
        volume {
          name = "tmp"
          empty_dir {}
        }
      }
    }
  }
  timeouts {
    create = "3m"
    update = "3m"
  }
}

resource "kubernetes_service_v1" "katalog" {
  metadata {
    name      = "katalog"
    namespace = "umkm-prod"
  }
  spec {
    selector = {
      app = "katalog"
    }
    port {
      port        = 80
      target_port = 8080
    }
  }
}
