resource "kubernetes_namespace_v1" "storage" {
  metadata {
    name = "storage-demo"
  }
}

resource "kubernetes_persistent_volume_claim_v1" "nginx" {
  metadata {
    name      = "nginx-pvc"
    namespace = kubernetes_namespace_v1.storage.metadata[0].name
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "manual"
    # Minta PV ini secara eksplisit
    volume_name = kubernetes_persistent_volume_v1.nginx.metadata[0].name
    resources {
      requests = {
        storage = "1Gi"
      }
    }
  }
}
