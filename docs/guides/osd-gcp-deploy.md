# OSD GCP deploy — `public` profile

Operator command path for the **`public`** example: basic public API, BYO VPC, no PSC. Agents use [`clusters/public/AGENTS.md`](../../clusters/public/AGENTS.md) for done-when gates.

## 0. Environment variables

```bash
env | grep -E '^(OSDGOOGLE_TOKEN|OCM_TOKEN|TF_VAR_)' || true
```

`make cluster.*.apply` passes `-var-file=clusters/<profile>/terraform.tfvars`, so values **in that file** win over conflicting `TF_VAR_*` in the shell ([Terraform precedence](https://developer.hashicorp.com/terraform/language/values/variables)). Set `gcp_project_id` in tfvars; unset stray `TF_VAR_*` from other projects to reduce noise.

## 1. Authenticate

```bash
export OSDGOOGLE_TOKEN="<offline-token>"
gcloud auth application-default login
gcloud config set project YOUR_PROJECT_ID
```

## 2. Plan and apply

```bash
make setup
# Set pull_secret_path in clusters/public/terraform.tfvars before apply (stores pull secret in Secret Manager)
# Edit clusters/public/terraform.tfvars — gcp_project_id (not replace-me)

make cluster.public.plan
make cluster.public.apply
```

Apply runs **two Terraform phases** automatically:

1. `terraform/wif/` — OCM WIF config (`{cluster_name}-wif`)
2. `terraform/` — BYO VPC + OSD cluster + optional machine pools

## 3. Cluster access

```bash
make cluster.public.show-credentials
make cluster.public.login
```

Uses HTPasswd cluster-admin from Terraform (`create_admin = true`), not kubeadmin.

## 4. GitOps and platform contract

```bash
make cluster.public.bootstrap
make cluster.public.platform
```

`platform.json` is gitignored under `clusters/public/`. It uses **contract_version 1** with GCP-specific fields (no Azure `machine_api_client_id`).

Optional OperatorHub pull secret during bootstrap (overrides Secret Manager):

```bash
PULL_SECRET_PATH=~/pull-secret.txt make cluster.public.bootstrap
```

If `pull_secret_path` was set before apply, bootstrap reads from Secret Manager automatically.

## 5. Private clusters (PSC)

Set `enable_psc = true` in tfvars (OpenShift 4.17+). Requires PSC subnet and secure boot wiring documented in the provider BYO VPC guide.

## 6. Destroy

```bash
DESTROY_CONFIRM=yes make cluster.public.destroy
```

Destroys the cluster stack first (including GCP WIF IAM inside `osd-cluster`), then the OCM WIF config in phase 1.

### Known limitation — repeat deploy in the same project

Destroy is appropriate for a clean teardown, but **re-applying the same `cluster_name` in one GCP project after destroy** can fail when GCP has **soft-deleted or tombstoned** WIF **custom IAM role** ids from `osd-wif-gcp`. Typical error: `role_id … marked for deletion`.

```bash
make cluster.public.wif-undelete-roles
make cluster.public.apply
```

Full recovery, tombstone workarounds, and manual `gcloud` steps: [WIF GCP IAM after destroy](wif-iam-after-destroy.md). Summary: [Architecture](../architecture.md#known-limitations-wif-gcp-iam-after-destroy).

## Future virt

OpenShift Virtualization on GCP is **not** implemented in this repository. Do not point the Azure [validated-pattern-openshift-virt](https://github.com/rh-mobb/validated-pattern-openshift-virt) sibling at this installer until a GCP slice exists.
