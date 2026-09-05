resource "kubernetes_namespace_v1" "environments" {
  for_each = toset(var.environments)

  metadata {
    name = each.value
    labels = {
      "name"                               = each.value
      "marketplace.io/environment"         = each.value
      "pod-security.kubernetes.io/enforce" = "baseline"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
  }
}
