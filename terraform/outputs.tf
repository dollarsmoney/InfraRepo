locals {
  # A self-contained kubeconfig per environment, built from the non-expiring
  # service-account token rather than DigitalOcean's 7-day credential.
  kubeconfigs = {
    for env, secret in kubernetes_secret_v1.deployer_token :
    env => base64encode(yamlencode({
      apiVersion = "v1"
      kind       = "Config"
      clusters = [{
        name = var.cluster_name
        cluster = {
          server                     = digitalocean_kubernetes_cluster.main.endpoint
          certificate-authority-data = digitalocean_kubernetes_cluster.main.kube_config[0].cluster_ca_certificate
        }
      }]
      users = [{
        name = "marketplace-deployer-${env}"
        user = { token = secret.data["token"] }
      }]
      contexts = [{
        name = env
        context = {
          cluster   = var.cluster_name
          user      = "marketplace-deployer-${env}"
          namespace = env
        }
      }]
      current-context = env
    }))
  }
}

output "cluster_name" {
  value = digitalocean_kubernetes_cluster.main.name
}

output "cluster_endpoint" {
  value = digitalocean_kubernetes_cluster.main.endpoint
}

output "ingress_ip" {
  description = "Load balancer IP that every DNS record points at"
  value       = local.ingress_ip
}

output "dns_records" {
  description = "Names served by this cluster"
  value       = [for r in local.dns_records : r == "@" ? var.domain : "${r}.${var.domain}"]
}

output "kubeconfigs" {
  description = "Base64 kubeconfig per environment. Paste into that GitHub Environment's KUBE_CONFIG secret: terraform output -raw kubeconfigs | jq -r .dev"
  value       = local.kubeconfigs
  sensitive   = true
}
