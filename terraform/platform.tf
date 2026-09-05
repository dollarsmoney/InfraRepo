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

# The two ClusterIssuers ship as a small local chart rather than through a
# dedicated Kubernetes-manifest provider. Those providers resolve the resource
# schema at plan time, so they cannot create a custom resource in the same run
# that installs its CRD. The Helm provider defers to apply, so this works from
# an empty account in one pass.
#
# Issuer names match ingress.clusterIssuer in the app's Helm values, so the
# application chart needs no change.
resource "helm_release" "cluster_issuers" {
  name      = "cluster-issuers"
  chart     = "${path.module}/charts/cluster-issuers"
  namespace = helm_release.cert_manager.namespace

  set = [
    {
      name  = "email"
      value = var.acme_email
    },
  ]

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
