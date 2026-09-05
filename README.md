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
├── cert-manager/                  Let's Encrypt ClusterIssuers
├── namespaces/                    dev, demo, production
├── scripts/bootstrap-cluster.sh   one-time per-cluster setup
└── .github/workflows/
    ├── lint.yml                   helm lint + template on every PR
    ├── deploy.yml                 picks the environment
    └── helm-deploy.yml            reusable deploy job
```

Each environment is a **separate cluster**, selected by that environment's
`KUBE_CONFIG` secret.

---

## First-time cluster setup

Run once per cluster, with kubectl pointed at it:

```bash
kubectl config use-context <your-context>
./scripts/bootstrap-cluster.sh dev
```

That installs ingress-nginx and cert-manager, applies both ClusterIssuers and
creates the namespace. It prints the ingress controller's external IP — create
`A` records for `app.<env>.example.com` and `api.<env>.example.com` pointing at
it before the first deploy, or certificate issuance will fail.

Application secrets are **not** created by this script. The deploy workflow
creates them from GitHub Environment secrets on every run.

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
| `KUBE_CONFIG` | base64 of that cluster's kubeconfig — `base64 -w0 ~/.kube/config` |
| `SUPABASE_ANON_KEY` | that environment's Supabase anon / publishable key |
| `SUPABASE_SERVICE_ROLE_KEY` | that environment's Supabase service role key |
| `PAYSTACK_SECRET_KEY` | Paystack secret key (test keys for dev and demo) |
| `GHCR_USERNAME` | GitHub username or bot account |
| `GHCR_TOKEN` | PAT with `read:packages`, used for the image pull secret |

Use a dedicated kubeconfig backed by a service account scoped to the target
namespace rather than a cluster-admin credential.

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
