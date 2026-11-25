# GitOps bootstrap

Installs **OpenShift GitOps** plus the OLM baseline from [validated-pattern-aro-classic](https://github.com/rh-mobb/validated-pattern-aro-classic): Web Terminal, Compliance Operator, and External Secrets Operator with GCP Secret Manager wiring.

## Prerequisites (Terraform)

| Input / output | Purpose |
|----------------|---------|
| `pull_secret_path` in tfvars | Stores Red Hat pull secret in Secret Manager on apply |
| `pull_secret_secret_name` | Secret Manager id (default `redhat-pull-secret`) |
| `eso_gcp_service_account_email` | ESO GCP SA (WIF impersonation target) |
| `wif_kubernetes_token_audience` | SA token `aud` for ESO ClusterSecretStore (default `openshift`) |
| `eso_wif_principal_member` | Debug: WIF binding on the ESO GCP SA |

Set `pull_secret_path` before `make cluster.<profile>.apply` so bootstrap can read the pull secret from Secret Manager (or pass `PULL_SECRET_PATH` for a local file).

## Commands

```bash
make cluster.public.login
make cluster.public.bootstrap
```

## Environment

| Variable | Default | Purpose |
|----------|---------|---------|
| `GITOPS_REPO` | This repo on GitHub | Argo `Application` source |
| `GITOPS_REVISION` | `main` | Branch or tag |
| `GITOPS_LOCAL_ONLY` | `0` | Skip root Application when testing locally |
| `PULL_SECRET_PATH` | unset | Overrides Secret Manager for `additional-pull-secret` |

Dry-run without a cluster:

```bash
GITOPS_DRY_RUN=1 bash scripts/gitops-bootstrap.sh bootstrap
```

Subcommands:

```bash
bash scripts/gitops-bootstrap.sh ensure-pull-secret
```

## Layout

| Path | Contents |
|------|----------|
| `gitops/bootstrap/` | OpenShift GitOps OLM install |
| `gitops/operators/*` | Web Terminal, Compliance, ESO (+ metadata Job) |
| `gitops/base/` | Composes bootstrap + operators |
| `gitops/overlays/<profile>/` | Profile pointer to `../../base` |

Bootstrap publishes `openshift-gitops/osd-platform-metadata`. The ESO Job applies `ClusterSecretStore` `customer-secret-manager` (GCP Secret Manager) and syncs `kube-system/additional-pull-secret`.

## ESO auth on OSD

ESO uses the **OCM workload identity pool** (same model as [osd-gcp-cudn-routing](https://github.com/rh-mobb/osd-gcp-cudn-routing) `controller_gcp_iam`): Terraform binds `external-secrets-sa` to a dedicated GCP SA; bootstrap metadata drives `gcpsm` **workloadIdentityFederation** (no SA key Secret). See [Architecture](../architecture.md#eso-identity-on-osd-gcp-wif-same-model-as-osd-gcp-cudn-routing).

If Secret Manager sync fails with STS / audience errors, compare `wif_kubernetes_token_audience` with `gcloud iam workload-identity-pools providers describe` on the cluster WIF provider.

## Troubleshooting

**CSV `Failed` with `UnsupportedOperatorGroup`**

Re-run `make cluster.<profile>.bootstrap`; GitOps OperatorGroup must use `upgradeStrategy: Default` only (no `targetNamespaces`).

**Bootstrap fails on pull secret**

Set `pull_secret_path` and re-apply phase 2, or export `PULL_SECRET_PATH` to a local dockerconfigjson file.
