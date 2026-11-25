# Agent playbook — `clusters/public`

Step-by-step **done-when** gates for AI operators. Human runbook: [OSD GCP deploy](../../docs/guides/osd-gcp-deploy.md). Generic Live GCP: root [`AGENTS.md`](../../AGENTS.md#live-gcp-deployments).

If this file and osd-gcp-deploy.md disagree on a `make` target, **the guide wins for commands**; **this file wins for stop-and-ask**.

## When to run

- User asks to deploy, verify, or destroy the **public** OSD GCP example profile.
- PR changes this profile, Terraform roots, GitOps bootstrap, or destroy order.

Skip live E2E for refactors with no operator-facing behavior (note in the PR).

Do **not** claim deploy done without `login`, `bootstrap`, and `platform` when the user asked for full installer parity.

## Recipe facts

| Item | Value |
|------|--------|
| Profile / `cluster_name` | `public` |
| Cluster type | Public API, module-managed BYO VPC, no PSC (`enable_psc = false`) |
| GCP project | from profile tfvars (`-var-file`; not overridden by stray `TF_VAR_*`) |
| Region | default `us-central1` in example tfvars |
| WIF display name | `public-wif` |
| Default workers | 3 × `n2-standard-4` via cluster module |
| Extra pools | `machine_pools` in tfvars → `osdgoogle_machine_pool` |
| Virt sibling | **Not wired** |

## Steps 0–5 (installer)

Use tmux ([root AGENTS.md](../../AGENTS.md#long-running-operations-tmux)).

### Step 0 — Preflight

Follow root Live GCP preflight. Also:

- `OSDGOOGLE_TOKEN` (or `OCM_TOKEN`) / client credentials in the shell running Make.
- `gcp_project_id` in tfvars is not `replace-me`.

**Done when:** GCP project matches intent; `make cluster.public.plan` summarized.

### Step 1 — Plan

```bash
make cluster.public.plan
```

**Done when:** Plan shows WIF config (phase 1) and VPC + cluster + pools (phase 2) consistent with tfvars.

### Step 2 — Apply

```bash
make cluster.public.apply
```

**Done when:** Both phases complete without error; `terraform output -raw api_url` returns a URL; OCM reports cluster ready.

### Step 3 — Cluster access

```bash
make cluster.public.login
```

**Done when:** `.kube/config-public` exists (default per-profile kubeconfig); `oc whoami` works; nodes are Ready.

### Step 4 — GitOps bootstrap

```bash
make cluster.public.bootstrap
```

Requires `pull_secret_path` in tfvars (or `PULL_SECRET_PATH`) and a successful phase-2 apply that stored the pull secret in Secret Manager.

**Done when:** OpenShift GitOps CSV **Succeeded**; Web Terminal, Compliance, and ESO CSVs **Succeeded**; Argo CD server available; `openshift-gitops/osd-platform-metadata` ConfigMap present; root Application present unless `GITOPS_LOCAL_ONLY=1`.

### Step 5 — Platform

```bash
make cluster.public.platform
```

**Done when:** `platform.json` has `contract_version == 1`, non-empty `cluster_id`, `wif_config_id`, and `api_url`.

## Destroy

```bash
DESTROY_CONFIRM=yes make cluster.public.destroy
# Long destroy: make cluster.public.longrun.destroy
```

**Done when:** Both state files empty or removed; OCM no longer lists the cluster; WIF config removed when destroy succeeded.

## Out of scope

- Helm MachineSets
- Azure virt / ANF / Route Server / BGP
- Private cluster / PSC (use a future profile with `enable_psc = true`)
