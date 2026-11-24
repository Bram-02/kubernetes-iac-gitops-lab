variable "mariadb_password" {
  description = "Password root MariaDB; diisi lewat TF_VAR_mariadb_password, tidak pernah ditulis di file"
  type        = string
  sensitive   = true
}

resource "kubernetes_namespace_v1" "wordpress" {
  metadata {
    name = "wordpress"
  }
}

resource "kubernetes_secret_v1" "mariadb" {
  metadata {
    name      = "mariadb-secret"
    namespace = kubernetes_namespace_v1.wordpress.metadata[0].name
  }
  data = {
    "mariadb-password" = var.mariadb_password
  }
}
