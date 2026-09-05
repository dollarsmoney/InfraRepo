# One deploy credential per environment, scoped to that namespace only. Each
# becomes the KUBE_CONFIG secret of the matching GitHub Environment, so the dev
# credential is forbidden from touching demo or production.

resource "kubernetes_service_account_v1" "deployer" {
  for_each = kubernetes_namespace_v1.environments

  metadata {
    name      = "marketplace-deployer"
    namespace = each.value.metadata[0].name
  }
}

# A manually created service-account token. Unlike the kubeconfig DigitalOcean
# issues, and unlike TokenRequest tokens, this one does not expire -- CI would
# otherwise start failing a week after setup.
resource "kubernetes_secret_v1" "deployer_token" {
  for_each = kubernetes_service_account_v1.deployer

  metadata {
    name      = "marketplace-deployer-token"
    namespace = each.value.metadata[0].namespace
    annotations = {
      "kubernetes.io/service-account.name" = each.value.metadata[0].name
    }
  }

  type                           = "kubernetes.io/service-account-token"
  wait_for_service_account_token = true
}

resource "kubernetes_role_v1" "deployer" {
  for_each = kubernetes_namespace_v1.environments

  metadata {
    name      = "marketplace-deployer"
    namespace = each.value.metadata[0].name
  }

  # Everything `helm upgrade --install --atomic --wait` touches for this chart.
  # Helm 3 keeps release history in Secrets, which the first rule covers.
  rule {
    api_groups = [""]
    resources  = ["configmaps", "secrets", "services", "serviceaccounts", "pods", "events"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods/log"]
    verbs      = ["get", "list"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "replicasets"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  # Read-only: lets the deploy job confirm cert-manager issued the certificate.
  rule {
    api_groups = ["cert-manager.io"]
    resources  = ["certificates"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_role_binding_v1" "deployer" {
  for_each = kubernetes_namespace_v1.environments

  metadata {
    name      = "marketplace-deployer"
    namespace = each.value.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.deployer[each.key].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.deployer[each.key].metadata[0].name
    namespace = each.value.metadata[0].name
  }
}
