# Marketplace infrastructure

Desired Kubernetes state for the [marketplace application](https://github.com/dollarsmoney/Notion).

Application source code lives in the application repository. This repository
holds only deployment configuration: the Helm chart, per-environment values,
cert-manager issuers, namespaces and the CD workflows.

---

## How a change reaches a cluster

```
Developer
   │  PR (Jira ticket)
   ▼
Application repo
   │  CI: install → lint → typecheck → test → build
   ▼
Docker build (multi-stage)
   │
   ▼
GHCR   ghcr.io/dollarsmoney/notion-backend:sha-abc1234     ← stores images only
       ghcr.io/dollarsmoney/notion-frontend:sha-abc1234
   │
   │  the application repo's bump-infra job commits here:
   ▼
THIS REPO   helm/marketplace/values-<env>.yaml  →  image.tag: sha-abc1234
   │
   ▼
deploy.yml  path filter picks the environment
   │        GitHub Environment approval for demo and production
   ▼
helm upgrade --install marketplace ./helm/marketplace \
     -f values.yaml -f values-<env>.yaml -n <env>
   │
   ▼
Dev / Demo / Production cluster  ← pulls the image from GHCR
```

GHCR is a registry, not a deployer. The image tag recorded in this repository is
what decides which build each cluster runs, which means the git history here is
an audit log of what was deployed where and when.

Branch to environment mapping in the application repo:

| App branch | Values file updated | Cluster | Approval |
| --- | --- | --- | --- |
| `dev` | `values-dev.yaml` | dev | none, deploys automatically |
| `demo` | `values-demo.yaml` | demo | required reviewer |
| `production` | `values-production.yaml` | production | required reviewer |

---

## Layout

```
marketplace-infra/
├── helm/marketplace/
│   ├── Chart.yaml
│   ├── values.yaml                shared defaults
│   ├── values-dev.yaml            1 replica, small limits, LE staging
│   ├── values-demo.yaml           2 replicas, LE production
│   ├── values-production.yaml     3 replicas, larger limits, anti-affinity
│   └── templates/
│       ├── backend-deployment.yaml   frontend-deployment.yaml
│       ├── services.yaml             ingress.yaml
│       ├── configmap.yaml            serviceaccount.yaml
│       └── _helpers.tpl              NOTES.txt
├── cert-manager/                  Let's Encrypt ClusterIssuers (reference copies)
├── namespaces/                    namespace manifests (reference copies)
├── terraform/                     DOKS cluster, platform components, DNS, CD credentials
└── .github/workflows/
    ├── lint.yml                   helm lint/template + terraform fmt/validate
    ├── deploy.yml                 picks the environment
    └── helm-deploy.yml            reusable deploy job
```

One DigitalOcean cluster hosts all three environments as namespaces. They are
separated by RBAC: each `KUBE_CONFIG` is backed by a ServiceAccount that can act
in **one** namespace only, so a leaked dev credential cannot touch production.

Terraform applies the `cert-manager/` and `namespaces/` manifests itself; the
files are kept as readable reference and for applying by hand if needed.

---

## First-time cluster setup

Everything is provisioned by Terraform — see
[terraform/README.md](terraform/README.md) for the full procedure.

```bash
export DIGITALOCEAN_TOKEN=dop_v1_...
cd terraform && terraform init && terraform apply
```

That creates the cluster, installs ingress-nginx and cert-manager, applies both
ClusterIssuers, creates the three namespaces with their scoped deploy
credentials, and — because the domain is delegated to DigitalOcean — creates
every DNS record automatically:

| Record | Serves | Environment |
| --- | --- | --- |
| `kmdndd.name.ng` (apex) | frontend | production |
| `api.kmdndd.name.ng` | API | production |
| `demo.kmdndd.name.ng` | frontend | demo |
| `api.demo.kmdndd.name.ng` | API | demo |
| `dev.kmdndd.name.ng` | frontend | dev |
| `api.dev.kmdndd.name.ng` | API | dev |

All six are `A` records pointing at the single ingress load balancer, created
only after Terraform has waited for DigitalOcean to assign its IP. That ordering
matters: cert-manager solves an HTTP-01 challenge over port 80, so a name that
does not yet resolve to the ingress controller cannot be issued a certificate.

The one manual step is delegation. `kmdndd.name.ng` is delegated to
`nsa.whogohost.com` / `nsb.whogohost.com`; replace those in the WhoGoHost control
panel with `ns1`, `ns2` and `ns3.digitalocean.com`. Until that is done the
records exist on DigitalOcean's nameservers but resolve nowhere publicly, and
cert-manager cannot complete an HTTP-01 challenge. Set `manage_dns = false` if
you would rather keep DNS elsewhere and point the records at
`terraform output ingress_ip` yourself.

`name.ng` is a public suffix, so `kmdndd.name.ng` counts as its own registered
domain for Let's Encrypt rate limiting — the six names share one bucket of 50
certificates per week, which is ample. Dev uses the staging issuer so repeated
teardowns cannot exhaust it.

Application secrets are **not** created by Terraform. The deploy workflow creates
them from GitHub Environment secrets on every run.

---

## Configuration and secrets

| Kind | Where it lives | Contents |
| --- | --- | --- |
| ConfigMap | `values-<env>.yaml` → `config:` | `NODE_ENV`, `CURRENCY`, `SUPABASE_URL`, derived `FRONTEND_URL` / `CORS_ORIGINS` / `NEXT_PUBLIC_API_URL` |
| Kubernetes Secret | created at deploy time | `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `PAYSTACK_SECRET_KEY` |
| GitHub Environment secrets | GitHub settings | the same three values, plus `KUBE_CONFIG`, `GHCR_USERNAME`, `GHCR_TOKEN` |

No secret value is ever committed here. `helm-deploy.yml` builds the
`marketplace-secrets` Secret with
`kubectl create secret … --dry-run=client -o yaml | kubectl apply -f -`, and the
chart only references it by name through `secret.existingSecret`. `lint.yml`
fails the build if anything secret-shaped is committed.

### GitHub Environment secrets

Create environments `dev`, `demo` and `production` under
**Settings → Environments**, add required reviewers to `demo` and `production`,
and set in each:

| Secret | Value |
| --- | --- |
| `KUBE_CONFIG` | `terraform output -json kubeconfigs \| jq -r .<env>` — already base64, already scoped to that namespace |
| `SUPABASE_ANON_KEY` | that environment's Supabase anon / publishable key |
| `SUPABASE_SERVICE_ROLE_KEY` | that environment's Supabase service role key |
| `PAYSTACK_SECRET_KEY` | Paystack secret key (test keys for dev and demo) |
| `GHCR_USERNAME` | GitHub username or bot account |
| `GHCR_TOKEN` | PAT with `read:packages`, used for the image pull secret |

### How CD reaches the cluster

`KUBE_CONFIG` is the entire link between this repository and Kubernetes.
`helm-deploy.yml` declares `environment: ${{ inputs.environment }}`, which makes
GitHub inject that environment's secrets; the job decodes `KUBE_CONFIG` into
`~/.kube/config`, and every `kubectl` and `helm` command after that targets
whatever it points at. Change the secret and the same chart lands somewhere else.

Terraform generates these, each backed by a ServiceAccount token that **does not
expire**. Do not substitute the kubeconfig DigitalOcean issues natively — its
token expires after seven days, and CD would start failing a week after setup
with no other change.

To confirm the scoping is real:

```bash
terraform output -json kubeconfigs | jq -r .dev | base64 -d > /tmp/dev.kubeconfig
KUBECONFIG=/tmp/dev.kubeconfig kubectl -n dev get pods          # works
KUBECONFIG=/tmp/dev.kubeconfig kubectl -n production get pods   # Forbidden
```

---

## Deploying

Normally you do not deploy by hand — merging to `dev`, `demo` or `production` in
the application repo updates the tag here and that push triggers the deployment.

To deploy manually (rollback to a known tag, or redeploy after changing values):

**Actions → Deploy → Run workflow**, pick the environment and optionally an
image tag. Leaving the tag blank deploys whatever the values file already
records.

Locally:

```bash
helm upgrade --install marketplace ./helm/marketplace \
  --namespace dev \
  -f ./helm/marketplace/values.yaml \
  -f ./helm/marketplace/values-dev.yaml \
  --atomic --wait
```

### Rollback

```bash
helm history marketplace -n production
helm rollback marketplace <revision> -n production
```

`--atomic` means a failed upgrade rolls itself back automatically, so a bad
image never leaves a half-deployed release behind.

---

## What the chart deploys

Per environment: a backend Deployment and Service, a frontend Deployment and
Service, a ConfigMap, a ServiceAccount and one Ingress covering both hosts.

- **Probes** — backend `/healthz` (liveness) and `/readyz` (readiness, which
  fails when the database is unreachable so traffic stops being routed);
  frontend `/api/health` for both.
- **Resources** — requests and limits on every container, sized per environment.
- **Rolling updates** — `maxUnavailable: 0`, so a new pod is ready before an old
  one goes away.
- **Security** — `runAsNonRoot` as uid 1001, `readOnlyRootFilesystem`, all
  capabilities dropped, no privilege escalation, `RuntimeDefault` seccomp, and
  no service account token mounted. `emptyDir` volumes cover `/tmp` and the
  Next.js cache, which are the only writable paths needed.
- **Config changes** — deployments carry a checksum of the ConfigMap, so editing
  config rolls the pods rather than leaving them on stale values.

Image repository and tag are both Helm values (`backend.image.repository`,
`backend.image.tag`, and the frontend equivalents), so any registry or build can
be deployed without touching a template.

---

## TLS

cert-manager issues and renews certificates automatically via the ACME HTTP-01
challenge. The Ingress carries `cert-manager.io/cluster-issuer`, and cert-manager
writes each certificate into the Secret named in the Ingress `tls` block,
renewing about 30 days before expiry.

Dev uses `letsencrypt-staging` — untrusted certificates, but generous rate
limits while DNS is being sorted out. Demo and production use
`letsencrypt-production`. See [cert-manager/README.md](cert-manager/README.md).

---

## Making changes

Open a PR against `main` with a Jira ticket. `lint.yml` runs `helm lint`,
renders all three environments and scans for committed secrets. Merging a change
under `helm/` deploys the affected environments, subject to their approval gates.

Editing `templates/`, `values.yaml` or `Chart.yaml` affects all three
environments, so those changes deploy to all three — review them accordingly.
