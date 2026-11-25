# In-cluster GitOps

OLM subscriptions + Kustomize, matching [validated-pattern-aro-classic](https://github.com/rh-mobb/validated-pattern-aro-classic):

- OpenShift GitOps (`gitops/bootstrap/`)
- Web Terminal (`gitops/operators/web-terminal/`)
- Compliance Operator (`gitops/operators/compliance/`)
- External Secrets Operator — OLM + metadata Job (`gitops/operators/external-secrets/`)

Composed in `gitops/base/`; profile overlays (for example `gitops/overlays/public/`) reference `../../base`.

Bootstrap publishes `openshift-gitops/osd-platform-metadata` and runs the ESO metadata Job (GCP Secret Manager). Set `pull_secret_path` before `make cluster.<profile>.apply`.

```bash
make cluster.public.login
make cluster.public.bootstrap
```

Guide: [GitOps bootstrap](../docs/guides/gitops.md).
