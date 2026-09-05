terraform {
  required_version = ">= 1.9"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.100"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.2"
    }
  }
}

provider "digitalocean" {
  # Reads DIGITALOCEAN_TOKEN from the environment.
}

provider "kubernetes" {
  host                   = digitalocean_kubernetes_cluster.main.endpoint
  cluster_ca_certificate = base64decode(digitalocean_kubernetes_cluster.main.kube_config[0].cluster_ca_certificate)
  token                  = digitalocean_kubernetes_cluster.main.kube_config[0].token
}

provider "helm" {
  kubernetes = {
    host                   = digitalocean_kubernetes_cluster.main.endpoint
    cluster_ca_certificate = base64decode(digitalocean_kubernetes_cluster.main.kube_config[0].cluster_ca_certificate)
    token                  = digitalocean_kubernetes_cluster.main.kube_config[0].token
  }
}
