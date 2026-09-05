resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = "4.12.1"
  namespace        = "ingress-nginx"
  create_namespace = true

  # Blocks until DigitalOcean has provisioned the load balancer and assigned an
  # IP, so the DNS records below can be created in the same apply.
  wait    = true
  timeout = 900

  set = [
    {
      name  = "controller.service.type"
      value = "LoadBalancer"
    },
    {
      # Preserves the client source IP.
      name  = "controller.service.externalTrafficPolicy"
      value = "Local"
    },
    {
      name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/do-loadbalancer-name"
      value = "${var.cluster_name}-ingress"
    },
    {
      name  = "controller.replicaCount"
      value = "2"
    },
    {
      name  = "controller.ingressClassResource.default"
      value = "true"
    },
  ]
}

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "v1.17.1"
  namespace        = "cert-manager"
  create_namespace = true

  wait    = true
  timeout = 900

  set = [
    {
      name  = "crds.enabled"
      value = "true"
    },
  ]
}

locals {
  cluster_issuers = {
    "letsencrypt-staging" = {
      server = "https://acme-staging-v02.api.letsencrypt.org/directory"
      secret = "letsencrypt-staging-account-key"
    }
    "letsencrypt-production" = {
      server = "https://acme-v02.api.letsencrypt.org/directory"
      secret = "letsencrypt-production-account-key"
    }
  }
}

# Names match ingress.clusterIssuer in the Helm values, so the chart needs no change.
resource "kubectl_manifest" "cluster_issuer" {
  for_each = local.cluster_issuers

  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata   = { name = each.key }
    spec = {
      acme = {
        server              = each.value.server
        email               = var.acme_email
        privateKeySecretRef = { name = each.value.secret }
        solvers = [{
          http01 = {
            ingress = { ingressClassName = "nginx" }
          }
        }]
      }
    }
  })

  depends_on = [helm_release.cert_manager]
}

# Read after the release is ready, so the load balancer IP is populated.
data "kubernetes_service_v1" "ingress_nginx" {
  metadata {
    name      = "ingress-nginx-controller"
    namespace = helm_release.ingress_nginx.namespace
  }

  depends_on = [helm_release.ingress_nginx]
}

locals {
  ingress_ip = data.kubernetes_service_v1.ingress_nginx.status[0].load_balancer[0].ingress[0].ip
}
