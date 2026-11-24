resource "kubernetes_persistent_volume_v1" "nginx" {
  metadata {
    name = "nginx-pv"
  }
  spec {
    capacity = {
      storage = "1Gi"
    }
    access_modes                     = ["ReadWriteOnce"]
    persistent_volume_reclaim_policy = "Retain"
    # Kelas sendiri, supaya PVC tidak diambil StorageClass bawaan kind ("standard")
    storage_class_name = "manual"
    persistent_volume_source {
      host_path {
        path = "/data/nginx"
        type = "DirectoryOrCreate"
      }
    }
    # Cluster kind punya 2 worker: hostPath hanya ada di satu node, jadi PV dikunci ke node itu
    node_affinity {
      required {
        node_selector_term {
          match_expressions {
            key      = "kubernetes.io/hostname"
            operator = "In"
            values   = ["skomawan-lab-worker"]
          }
        }
      }
    }
  }
}
