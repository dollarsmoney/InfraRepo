#!/usr/bin/env bash
# One-time setup per cluster: ingress controller, cert-manager, issuers, namespace.
# Run against an already-selected kubectl context.
set -euo pipefail

ENVIRONMENT="${1:-}"
if [[ ! "$ENVIRONMENT" =~ ^(dev|demo|production)$ ]]; then
  echo "Usage: $0 <dev|demo|production>" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Bootstrapping '$ENVIRONMENT' on context: $(kubectl config current-context)"

echo "==> ingress-nginx"
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null
helm repo add jetstack https://charts.jetstack.io >/dev/null
helm repo update >/dev/null

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.externalTrafficPolicy=Local \
  --wait

echo "==> cert-manager"
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set crds.enabled=true \
  --wait

echo "==> ClusterIssuers"
kubectl apply -f "$ROOT/cert-manager/cluster-issuer-staging.yaml"
kubectl apply -f "$ROOT/cert-manager/cluster-issuer-production.yaml"

echo "==> namespace"
kubectl apply -f "$ROOT/namespaces/$ENVIRONMENT.yaml"

echo
echo "Done. Point these DNS records at the ingress controller's external IP:"
kubectl -n ingress-nginx get svc ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}{"\n"}' || true
echo
echo "Application secrets are created by the deploy workflow, not by this script."
