terraform {
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 3.5" }
  }
}

# Cluster kind dari week10/cluster (pengganti Minikube di modul praktikum)
data "terraform_remote_state" "cluster" {
  backend = "local"
  config = {
    path = "../../week10/cluster/terraform.tfstate"
  }
}

provider "kubernetes" {
  config_path = data.terraform_remote_state.cluster.outputs.kubeconfig_path
}
