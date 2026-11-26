terraform {
  required_providers {
    helm = { source = "hashicorp/helm", version = "~> 3.0" }
  }
}

data "terraform_remote_state" "cluster" {
  backend = "local"
  config = {
    path = "../../week10/cluster/terraform.tfstate"
  }
}

provider "helm" {
  kubernetes = {
    config_path = data.terraform_remote_state.cluster.outputs.kubeconfig_path
  }
}

# Controller Sealed Secrets: menyimpan kunci privat di cluster, mendekripsi SealedSecret menjadi Secret.
# Nama dan namespace bawaan kubeseal, jadi kubeseal tidak perlu flag tambahan.
resource "helm_release" "sealed_secrets" {
  name       = "sealed-secrets"
  repository = "https://bitnami.github.io/sealed-secrets"
  chart      = "sealed-secrets"
  version    = "2.22.0" # controller 0.41.2
  namespace  = "kube-system"

  set = [
    { name = "fullnameOverride", value = "sealed-secrets-controller" },
  ]
}
