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
    # Applies the cert-manager ClusterIssuers. Used instead of
    # kubernetes_manifest, which needs the CRD to exist at plan time and so
    # cannot create a custom resource in the same run that installs its CRD.
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.3"
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

provider "kubectl" {
  host                   = digitalocean_kubernetes_cluster.main.endpoint
  cluster_ca_certificate = base64decode(digitalocean_kubernetes_cluster.main.kube_config[0].cluster_ca_certificate)
  token                  = digitalocean_kubernetes_cluster.main.kube_config[0].token
  load_config_file       = false
}
