data "digitalocean_kubernetes_versions" "current" {
  version_prefix = var.kubernetes_version_prefix
}

resource "digitalocean_vpc" "main" {
  name   = "${var.cluster_name}-vpc"
  region = var.region
}

resource "digitalocean_kubernetes_cluster" "main" {
  name     = var.cluster_name
  region   = var.region
  version  = data.digitalocean_kubernetes_versions.current.latest_version
  vpc_uuid = digitalocean_vpc.main.id

  # Patch upgrades apply during the maintenance window; surge upgrade adds a
  # replacement node before draining the old one.
  auto_upgrade  = true
  surge_upgrade = true

  maintenance_policy {
    day        = "sunday"
    start_time = "03:00"
  }

  node_pool {
    name       = "${var.cluster_name}-workers"
    size       = var.node_size
    node_count = var.node_count

    auto_scale = true
    min_nodes  = var.node_min
    max_nodes  = var.node_max
  }

  tags = ["marketplace"]
}
