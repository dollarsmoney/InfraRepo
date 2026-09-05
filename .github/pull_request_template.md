## Jira ticket

- Ticket: [MKT-000](https://your-org.atlassian.net/browse/MKT-000)

## What changed

<!-- Which environment, and what this changes in the cluster. -->

## Environments affected

- [ ] dev
- [ ] demo
- [ ] production

## Checklist

- [ ] `helm lint` and `helm template` pass for all three environments
- [ ] No secret values are committed — secrets belong in GitHub Environment secrets
- [ ] Resource requests/limits, probes and replica counts reviewed for the target environment
- [ ] New config keys added to `values.yaml` and to every `values-<env>.yaml` that needs them
- [ ] If a new secret key was added, it is created in `helm-deploy.yml` and set in each GitHub Environment

## Rollback

<!-- Usually: helm rollback marketplace -n <env>. Note anything extra. -->
