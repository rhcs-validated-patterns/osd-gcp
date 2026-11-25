# AGENTS.md

Instructions for AI agents working in this repository.

## What this repo is

Customer-side **OpenShift Dedicated (OSD) on Google Cloud** reference deployment. Terraform provisions OCM WIF config, GCP IAM from the WIF blueprint, a BYO VPC, the OSD cluster, optional **osdgoogle_machine_pool** resources, GitOps bootstrap, and `platform.json`.

This is **not** ARO Classic/HCP, ROSA, or the Azure virt/BGP stack. Do not use `az aro`, `rosa`, or assume ANF/Route Server resources exist here.

## Human docs vs agent docs

Operators follow MkDocs (`docs/`). Agents follow this file plus [`clusters/<name>/AGENTS.md`](clusters/) when it exists.

| Topic | Human | Agent |
|-------|--------|--------|
| Deploy commands | [OSD GCP deploy](docs/guides/osd-gcp-deploy.md), `README.md` | Step **done-when** in `clusters/public/AGENTS.md` |
| Live GCP / OCM | Short warnings in guides | This file, [Live GCP](#live-gcp-deployments) |
| WIF / VPC / pools | [Architecture](docs/architecture.md) | Provider module READMEs via pinned Git tag |
| Virt | One paragraph in architecture | **Out of scope** until a GCP sibling exists |

If agent and human instructions disagree: **the operator guide wins for command names**; **this file / `clusters/*/AGENTS.md` wins for stop-and-ask**.

## Source precedence

1. **This repo** — `AGENTS.md`, `Makefile`, `scripts/`, committed example tfvars.
2. **[validated-pattern-aro-classic](https://github.com/rh-mobb/validated-pattern-aro-classic)** — local `references/validated-pattern-aro-classic/`. Shape for Make interface, MkDocs, per-cluster state, GitOps bootstrap flow, and tests. **Do not** port Azure resources, Helm MachineSets, or kubeadmin flows. **Do** port GitOps `base` composition, bootstrap script behavior (metadata ConfigMap, pull secret, operator CSV waits), and platform secrets **using GCP equivalents** (Secret Manager, ESO SA key or WI when issuer is public).
3. **[terraform-provider-osd-google](https://github.com/rh-mobb/terraform-provider-osd-google)** — local `references/terraform-provider-osd-google/`. Authority for WIF two-phase apply, `modules/osd-vpc`, `modules/osd-cluster`, and machine pools. Live modules pin **`ref=v0.1.5`** on GitHub; never `source = "../references/..."`.

`references/` is gitignored local checkout space, not a deployment dependency.

## Hard rules

- **`make` is the interface:** run `make fmt lint test` before claiming work is done.
- **Two-phase apply:** WIF root then cluster root; both wrapped in `make cluster.<name>.apply`.
- **OCM auth:** `OSDGOOGLE_TOKEN` or client credentials via env — **never** commit tokens in tfvars.
- **`TF_VAR_*`:** ignored for keys set in profile tfvars when using `make cluster.*` (`-var-file` outranks env per [Terraform variable precedence](https://developer.hashicorp.com/terraform/language/values/variables)). Preflight logs a note if env and tfvars disagree; edit tfvars (not only `TF_VAR_*`) for `gcp_project_id`.
- **Placeholder project:** refuse apply when `gcp_project_id = replace-me`.
- **No Helm MachineSets:** worker shape is `compute_*` + `machine_pools` only.
- **Reserved pool names:** no `worker` or `workers-*` in `machine_pools`.
- **Never commit:** operator tfvars except the committed example, state, `platform.json`, `clusters/*/logs/`, kubeconfig, tokens.
- **Live GCP:** do not `apply` / `destroy` unless the user asked. Follow [Live GCP deployments](#live-gcp-deployments).
- **Git:** feature branches; Conventional Commits; no `Co-authored-by: Cursor` or AI trailers.

## Layout

| Path | Purpose |
|------|---------|
| `terraform/wif/` | Phase 1 OCM WIF config |
| `terraform/` | Phase 2 VPC + osd-cluster module |
| `clusters/<name>/` | Per-cluster tfvars + local state |
| `scripts/` | credentials, destroy, GitOps, platform.json |
| `gitops/` | OpenShift GitOps bootstrap + overlays (match ARO Classic `gitops/base`) |
| `docs/` | MkDocs operator guides |
| `tests/` | `terraform test` + bats |

## Deploy path

```bash
make setup
make cluster.public.plan
make cluster.public.apply
make cluster.public.login
make cluster.public.bootstrap
make cluster.public.platform
```

Agent done-when: [`clusters/public/AGENTS.md`](clusters/public/AGENTS.md). Virt bare-metal profile: [`clusters/virt/AGENTS.md`](clusters/virt/AGENTS.md).

A **deploy / create cluster** request means: preflight → apply → login → bootstrap → platform. **No** MachineSets step. Virt sibling is **not** part of full parity today.

## Live GCP deployments

Apply is **45–90+ minutes**. Destroy removes OCM cluster and WIF config.

### Long-running operations (tmux)

1. Prefer **`make cluster.<name>.longrun.apply`** / **`.longrun.destroy`** (wraps `scripts/cluster-longrun.sh`) so tmux gets **`DESTROY_CONFIRM`**, OCM tokens, and log tee under `clusters/<name>/logs/`.
2. Raw tmux is fine if you `source` the same env file pattern as `cluster-longrun.sh` — do not start destroy in tmux without **`DESTROY_CONFIRM=yes`** in that session.
3. Fallback: background shell via `cluster-longrun.sh` when tmux is unavailable.

### Halt vs continue

One **mutating** Terraform apply/destroy at a time.

**Halt and ask:**

- Apply/destroy hung with no terminal progress in OCM/GCP for an extended period.
- Second apply/destroy while the first is in flight.
- Existing cluster state or non-empty tfstate when the user did not ask to adopt or destroy.

**OK without asking:**

- Read-only: `terraform plan`, `gcloud` describe, `ocm get cluster`.
- Docs or tests that do not touch the project.

### Preflight (every apply or destroy)

1. **`gcloud config get-value project`** — must match `gcp_project_id` in tfvars (or stop).
2. **`clusters/<name>/terraform.tfvars`** — must exist; `gcp_project_id` not `replace-me`.
3. **`env | grep '^TF_VAR_'`** — stray vars from other stacks are ignored on apply when the same key is in tfvars (warning only). Keys not in tfvars still use `TF_VAR_*`.
4. **OCM token** — `OSDGOOGLE_TOKEN` or client credential env vars present.
5. **Existing state** — if `infrastructure.tfstate` or live OCM cluster exists, stop and ask.
6. **Plan first** — `make cluster.<name>.plan`; summarize create/change/destroy.

### After apply

- OCM cluster state **ready**; `terraform output api_url` non-empty.
- After login: `oc get nodes` shows Ready workers.

### Destroy

`DESTROY_CONFIRM=yes make cluster.<name>.destroy` — confirm project, cluster name, and region with the user first.

Repeat deploy with the **same `cluster_name` in one GCP project** after full destroy may hit GCP **WIF custom role** soft-delete/tombstone (`osd-wif-gcp` in phase 2). See [docs/guides/wif-iam-after-destroy.md](docs/guides/wif-iam-after-destroy.md); run `make cluster.<name>.wif-undelete-roles` before re-apply when roles are soft-deleted. New `cluster_name` if tombstoned—not skipping phase-1 WIF destroy alone.

### Do not

- Call `terraform apply` outside Make (skips two-phase ordering and `-var-file`).
- Add Helm MachineSets or Azure virt modules to this root without an explicit user request.

## Documentation

When behavior changes: update `docs/architecture.md` and the operator guide in the same work. Update profile `AGENTS.md` when done-when gates change.

## Changelog

Update [`CHANGELOG.md`](CHANGELOG.md) only at commit time from `git diff --cached`.

## Testing (agents)

| Tier | Command | When |
|------|---------|------|
| CI / local | `make fmt lint test` | Every PR; before claiming implementation done |
| Docs | `make docs-build` | Doc or nav changes |
| Live GCP E2E | Profile `AGENTS.md` | Only when user explicitly requests deploy in a project |

Do not claim live E2E without evidence (OCM cluster ready, `platform.json`, successful login).
