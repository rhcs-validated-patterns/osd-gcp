# Architecture

## Scope

This repository is the **OSD on GCP installer**: WIF registration in OCM, GCP IAM from the WIF blueprint, customer VPC, OSD cluster creation, optional extra machine pools, GitOps bootstrap, and `platform.json`.

It does **not** contain OpenShift Virtualization, File storage, or BGP routing resources.

## Terraform layout

| Path | State file | Purpose |
|------|------------|---------|
| `terraform/wif/` | `clusters/<profile>/wif.tfstate` | Phase 1: `osd-wif-config` in OCM |
| `terraform/` | `clusters/<profile>/infrastructure.tfstate` | Phase 2: `osd-vpc` + `osd-cluster` |

Modules are sourced from Git tag **`v0.1.5`** on [terraform-provider-osd-google](https://github.com/rh-mobb/terraform-provider-osd-google):

- `modules/osd-wif-config`
- `modules/osd-vpc`
- `modules/osd-cluster` (includes nested `osd-wif-gcp`, `osdgoogle_cluster`, `osdgoogle_cluster_admin`, `osdgoogle_machine_pool`)

Phase 2 also provisions **platform secrets** in [`terraform/platform_secrets.tf`](../terraform/platform_secrets.tf) (ARO Classic `platform-secrets` equivalent):

- Red Hat **pull secret** in **Secret Manager** (when `pull_secret_path` / `pull_secret` is set on apply)
- [`modules/osd-eso-iam`](../modules/osd-eso-iam): ESO GCP SA + **OCM WIF pool** impersonation (no JSON keys)
- `secretAccessor` on the pull secret for the ESO GCP SA

## GitOps parity (ARO Classic)

`gitops/base` composes OpenShift GitOps, Web Terminal, Compliance, and External Secrets (same subscriptions as [validated-pattern-aro-classic](https://github.com/rh-mobb/validated-pattern-aro-classic)). Bootstrap publishes `openshift-gitops/osd-platform-metadata`; the `eso-from-metadata` Job applies `ClusterSecretStore` + `ExternalSecret` for `kube-system/additional-pull-secret`.

## ESO identity on OSD (GCP WIF, same model as osd-gcp-cudn-routing)

ARO Classic federates ESO to **Azure Key Vault** using a **public cluster OIDC issuer** and user-assigned identity.

On OSD GCP, platform workloads (including ESO) use the **existing OCM WIF pool** from `osdgoogle_wif_config` — the same pool `osd-wif-gcp` provisions for cluster operators. The [`modules/osd-eso-iam`](../modules/osd-eso-iam) module (pattern from [osd-gcp-cudn-routing `osd-bgp-controller-iam`](https://github.com/rh-mobb/osd-gcp-cudn-routing)) creates a dedicated GCP SA and binds:

`principal://…/workloadIdentityPools/<pool>/subject/system:serviceaccount:external-secrets-operator:external-secrets-sa`

Bootstrap publishes **`esoWifKubernetesTokenAudience`** (default **`openshift`**, OIDC provider `allowedAudiences`) and **`esoWifStsAudience`** (`//iam.googleapis.com/…/providers/…` for ESO STS) in `osd-platform-metadata`. The `eso-from-metadata` Job configures `gcpsm` **workloadIdentityFederation** on the ClusterSecretStore — **no** JSON service account keys in Secret Manager for ESO.

| ARO Classic | OSD GCP |
|-------------|---------|
| Key Vault + pull secret | Secret Manager + `pull_secret_secret_name` |
| UAMI + federated credential (cluster OIDC issuer) | ESO GCP SA + **OCM WIF pool** impersonation binding |
| `aro-platform-metadata` | `osd-platform-metadata` |
| ESO `azurekv` WorkloadIdentity | ESO `gcpsm` workloadIdentityFederation |

Tune `wif_kubernetes_token_audience` if `gcloud iam workload-identity-pools providers describe` shows different `allowedAudiences` (see cudn-routing `controller_gcp_iam` troubleshooting).

## WIF naming

WIF display name defaults to `{cluster_name}-wif`.

## Known limitations: WIF GCP IAM after destroy

Full `make cluster.<profile>.destroy` removes **both** Terraform phases: phase 2 (cluster stack) **then** phase 1 (OCM WIF config). The tombstone risk for repeat deploys in the **same GCP project** comes mainly from phase 2, not from skipping phase 1 alone.

| Phase | What runs | What gets deleted |
|-------|-----------|-------------------|
| Phase 2 `terraform/` | `module.cluster` → **`osd-wif-gcp`** | GCP workload identity resources, **project custom IAM roles** (from `role_prefix` / `cluster_name`), service accounts, bindings; plus VPC and OCM cluster |
| Phase 1 `terraform/wif/` | `osd-wif-config` | OCM WIF config `{cluster_name}-wif` |

GCP **soft-deletes** those custom roles when Terraform destroys them. A quick re-apply may fail with **marked for deletion** / `failedPrecondition`. Recovery and mitigations are documented in [WIF GCP IAM after destroy](guides/wif-iam-after-destroy.md), including **`make cluster.<profile>.wif-undelete-roles`** and [`scripts/gcp-undelete-wif-custom-roles.sh`](../scripts/gcp-undelete-wif-custom-roles.sh).

Skipping destroy of **only** the OCM WIF config does **not** bypass role tombstoning—the cluster stack destroy still tears down `osd-wif-gcp`.

## Network

The `osd-vpc` module creates a custom VPC, control plane and worker subnets, Cloud NAT, and optional PSC objects when `enable_psc = true`.

Default CIDRs are defined in the module; override via module variables only if you vendor or fork modules—this pattern uses module defaults from the pinned tag.

## Authentication to the cluster

When `create_admin = true`, Terraform creates an HTPasswd identity provider and cluster-admin user via `osdgoogle_cluster_admin`. Scripts use `terraform output` for login—not GCP service account keys.

## platform.json

`terraform output -json platform` (written by `make cluster.<profile>.platform`) uses `contract_version = 1` and `installer = "osd-gcp"`. Fields include cluster and WIF IDs, API URLs, VPC subnet names, default worker sizing, declared `machine_pools`, and an **`eso`** object (Secret Manager secret names, auth method).

There is no Azure-style `machine_api_client_id` or reserved ANF/Route Server CIDR block.

Before writing `platform.json`, [`scripts/platform.sh`](../scripts/platform.sh) verifies labeled `machine_pools` have matching Ready nodes when you use the cluster API (same gate as ARO Classic for labeled pools).

## Future virt

The **`virt`** cluster profile ([guide](guides/virt-cluster.md)) provisions a **`np-virt-metal`** pool: 2 × `c3-standard-192-metal` in one AZ on top of the default `n2-standard-4` workers. `platform.json` records pool labels and `availability_zones` for a downstream virt installer.

A GCP virt sibling may consume that contract once operator/storage automation exists. The existing [validated-pattern-openshift-virt](https://github.com/rh-mobb/validated-pattern-openshift-virt) repository targets Azure (ANF, Route Server). Treat it as prior art only for GitOps structure, not as a drop-in second phase for OSD GCP today.

## Reference map (local)

Gitignored checkouts under `references/`:

- `validated-pattern-aro-classic` — Make, docs, tests, per-cluster state
- `terraform-provider-osd-google` — provider and modules authority
- `validated-pattern-openshift-virt` — future virt integration (Azure today)

Never use `references/` as a Terraform module source in live configs.
