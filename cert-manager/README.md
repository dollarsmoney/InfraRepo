# cert-manager

TLS certificates are issued and renewed automatically by cert-manager using the
ACME HTTP-01 challenge through the nginx ingress controller.

## Install (once per cluster)

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set crds.enabled=true
```

## Apply the issuers

Replace the `email` in both files with a real address first — Let's Encrypt
sends expiry warnings there.

```bash
kubectl apply -f cluster-issuer-staging.yaml
kubectl apply -f cluster-issuer-production.yaml
```

A `ClusterIssuer` is cluster-scoped, so all three namespaces share it. Each
environment picks one through `ingress.clusterIssuer` in its Helm values: dev
uses staging, demo and production use production.

## How renewal works

The chart's Ingress carries `cert-manager.io/cluster-issuer`. cert-manager sees
the annotation, solves the HTTP-01 challenge, and writes the certificate into
the Secret named in the Ingress `tls` block. It renews roughly 30 days before
expiry with no manual step.

## Checking a certificate

```bash
kubectl -n dev get certificate
kubectl -n dev describe certificate marketplace-app-tls
kubectl -n dev get challenges     # only present while a challenge is running
```

`READY=False` for more than a few minutes usually means DNS does not yet point
at the ingress controller's external IP, or port 80 is not reachable.
