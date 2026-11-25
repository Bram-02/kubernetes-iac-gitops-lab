# Grup students: hanya membaca Pod dan log Pod di umkm-dev (contoh slide 9-10)
resource "kubernetes_role_v1" "pod_reader" {
  metadata {
    name      = "pod-reader"
    namespace = kubernetes_namespace_v1.umkm["umkm-dev"].metadata[0].name
  }
  rule {
    api_groups = [""]
    resources  = ["pods", "pods/log"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_role_binding_v1" "students" {
  metadata {
    name      = "students-pod-reader"
    namespace = kubernetes_namespace_v1.umkm["umkm-dev"].metadata[0].name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.pod_reader.metadata[0].name
  }
  subject {
    kind      = "Group"
    name      = "students"
    api_group = "rbac.authorization.k8s.io"
  }
}
