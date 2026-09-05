# Terraform — DigitalOcean Kubernetes

Provisions the cluster the application is deployed onto, installs the platform
components, manages DNS, and produces the `KUBE_CONFIG` secrets that the deploy
workflow consumes.

## What it creates

| Resource | Purpose |
| --- | --- |
| VPC + DOKS cluster | 2 × `s-2vcpu-4gb` workers, autoscaling 2→4, auto patch upgrades |
| ingress-nginx | One DigitalOcean load balancer, one public IP for every hostname |
| cert-manager | Issues and renews the TLS certificates |
| 2 ClusterIssuers | `letsencrypt-staging` and `letsencrypt-production`, matching `ingress.clusterIssuer` in the Helm values |
| 3 namespaces | `dev`, `demo`, `production` |
| 3 deploy credentials | A ServiceAccount per namespace, with a Role scoped to that namespace only |
| 6 DNS A records | Apex plus `api`, `dev`, `api.dev`, `demo`, `api.demo` |

Roughly **$60/month**: 2 nodes ($48) plus one load balancer ($12). The DOKS
control plane is free.

## Prerequisites

1. A DigitalOcean API token with read and write scope:
   ```bash
   export DIGITALOCEAN_TOKEN=dop_v1_...
   ```
2. **Delegate the domain to DigitalOcean.** At your `.ng` registrar, set the
   nameservers for `kmdndd.name.ng` to:
   ```
   ns1.digitalocean.com
   ns2.digitalocean.com
   ns3.digitalocean.com
   ```
   Terraform manages the records inside the zone, not the delegation itself. Set
   `manage_dns = false` to skip DNS entirely and wire records up by hand.

## Apply

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # optional, defaults are fine
terraform init
terraform plan
terraform apply
```

The first apply takes roughly 10 minutes, most of it waiting for DigitalOcean to
provision the load balancer. `ingress-nginx` is deployed with `wait = true`
specifically so the load balancer IP exists before the DNS records that point at
it are created.

## Wiring CD to the cluster

This is the link between the two repositories. Each GitHub Environment gets a
kubeconfig scoped to its own namespace:

```bash
terraform output -json kubeconfigs | jq -r .dev         # → GitHub env "dev"        → KUBE_CONFIG
terraform output -json kubeconfigs | jq -r .demo        # → GitHub env "demo"       → KUBE_CONFIG
terraform output -json kubeconfigs | jq -r .production  # → GitHub env "production" → KUBE_CONFIG
```

Each value is already base64-encoded, which is the form
`.github/workflows/helm-deploy.yml` expects. The workflow decodes it into
`~/.kube/config`, and from that point every `kubectl` and `helm` command targets
that cluster and namespace. Nothing else in the repository knows which cluster it
is talking to.

These tokens are built from ServiceAccount token Secrets, so they **do not
expire**. The kubeconfig DigitalOcean issues natively expires after seven days
and must not be used for CI.

## Checking the deploy credentials are properly scoped

```bash
terraform output -json kubeconfigs | jq -r .dev | base64 -d > /tmp/dev.kubeconfig
export KUBECONFIG=/tmp/dev.kubeconfig

kubectl -n dev get pods          # works
kubectl -n production get pods   # Forbidden
kubectl get nodes                # Forbidden
```

The last two failing is the point: a leaked dev credential cannot reach
production.

## After apply

```bash
terraform output ingress_ip     # every hostname resolves here
terraform output dns_records
```

Then confirm the platform is healthy — this needs your own admin kubeconfig
(`doctl kubernetes cluster kubeconfig save marketplace`), not a deploy credential:

```bash
kubectl get nodes
kubectl -n ingress-nginx get svc ingress-nginx-controller
kubectl get clusterissuer          # both should be Ready=True
```

A ClusterIssuer that is not `Ready` usually means Let's Encrypt could not
register the ACME account — check the email in `var.acme_email`.

## State

State is a local file and is gitignored. It contains the cluster CA and all
three ServiceAccount tokens, so treat `terraform.tfstate` as a secret and do not
commit it. Move to a DigitalOcean Spaces backend if more than one person needs to
run this.

## Notes

- `kubernetes_manifest` is deliberately avoided. It resolves the resource schema
  at plan time, so it cannot create a ClusterIssuer in the same run that installs
  cert-manager's CRDs. `kubectl_manifest` applies server-side and has no such
  constraint.
- If a first apply ever fails because the Kubernetes provider was configured
  before the cluster existed, run
  `terraform apply -target=digitalocean_kubernetes_cluster.main` and then a full
  `terraform apply`.
- Destroying: `terraform destroy` removes the cluster, the load balancer and the
  DNS zone. Helm releases deployed by CD live inside the cluster and go with it.
