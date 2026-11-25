# Pihak lain dari slide 17. Semua memakai ClusterRole bawaan (admin, edit, view)
# lewat RoleBinding, sehingga izinnya hanya berlaku di namespace yang disebut.
locals {
  ikatan = {
    "katalog-dev-edit"    = { ns = "umkm-dev", role = "edit", kind = "Group", name = "katalog-dev" }
    "katalog-dev-view"    = { ns = "umkm-prod", role = "view", kind = "Group", name = "katalog-dev" }
    "platform-admin-dev"  = { ns = "umkm-dev", role = "admin", kind = "Group", name = "platform-team" }
    "platform-admin-prod" = { ns = "umkm-prod", role = "admin", kind = "Group", name = "platform-team" }
    "argocd-admin-dev"    = { ns = "umkm-dev", role = "admin", kind = "ServiceAccount", name = "argocd-application-controller" }
    "argocd-admin-prod"   = { ns = "umkm-prod", role = "admin", kind = "ServiceAccount", name = "argocd-application-controller" }
  }
}

resource "kubernetes_role_binding_v1" "akses" {
  for_each = local.ikatan
  metadata {
    name      = each.key
    namespace = kubernetes_namespace_v1.umkm[each.value.ns].metadata[0].name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = each.value.role
  }
  subject {
    kind      = each.value.kind
    name      = each.value.name
    api_group = each.value.kind == "Group" ? "rbac.authorization.k8s.io" : null
    namespace = each.value.kind == "ServiceAccount" ? "argocd" : null
  }
}

# Workload Katalog: SA sendiri (bukan default), tanpa izin API dan tanpa token otomatis
resource "kubernetes_service_account_v1" "katalog" {
  metadata {
    name      = "katalog"
    namespace = kubernetes_namespace_v1.umkm["umkm-prod"].metadata[0].name
  }
  automount_service_account_token = false
}
