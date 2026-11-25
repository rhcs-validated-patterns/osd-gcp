# WIF GCP IAM after destroy

Operator reference for **repeat deploy** in the same GCP project after `make cluster.<profile>.destroy`.

## What breaks and why

Full destroy runs **phase 2** (cluster stack), then **phase 1** (OCM WIF config). Custom IAM roles for WIF are created by **`osd-wif-gcp`** inside `module.cluster` during phase 2 apply. Phase 2 destroy **deletes** those `google_project_iam_custom_role` resources.

GCP then **soft-deletes** the roles. Symptoms on the next apply:

- `role_id (...) which has been marked for deletion, failedPrecondition`

While the role is still in the soft-delete window, **`gcloud iam roles undelete`** can restore it. Later, GCP may **tombstone** the `role_id`: undelete and describe return `NOT_FOUND`, but create with the same id still fails. Timelines are Google-defined and not fixed in this repository; plan for **days to weeks**.

Skipping destroy of **only** the OCM WIF config does **not** avoid this—cluster destroy still removes `osd-wif-gcp` roles.

See also [Architecture — WIF GCP IAM after destroy](../architecture.md#known-limitations-wif-gcp-iam-after-destroy).

## Recover soft-deleted roles (same cluster name)

1. Confirm project and prefix match `clusters/<profile>/terraform.tfvars` (`gcp_project_id`, `cluster_name`, optional `role_prefix`).

2. Run undelete (discovers roles by prefix):

```bash
make cluster.public.wif-undelete-roles
# Preview:
make cluster.public.wif-undelete-roles WIF_UNDELETE_ARGS='--dry-run'
```

Or run the script directly:

```bash
TFVARS=clusters/public/terraform.tfvars ./scripts/gcp-undelete-wif-custom-roles.sh
```

3. Re-apply:

```bash
make cluster.public.apply
```

4. If Terraform still wants to **create** roles that now exist in GCP, refresh or import `module.cluster.module.wif_gcp` custom role resources in phase 2 state (`clusters/<profile>/infrastructure.tfstate`).

### Manual undelete (one role)

From the apply error, note `projects/PROJECT/roles/ROLE_ID`:

```bash
gcloud iam roles undelete ROLE_ID --project=PROJECT
```

Parse a saved apply log:

```bash
./scripts/gcp-undelete-wif-custom-roles.sh --from-log clusters/public/logs/your-apply.log
```

### Diagnose list vs tombstone

```bash
PROJECT=your-gcp-project
gcloud iam roles list --project="${PROJECT}" --format='value(name)' | wc -l
gcloud iam roles list --project="${PROJECT}" --show-deleted --format='value(name)' | wc -l
```

If counts are equal but apply still says **marked for deletion**, the id is likely **tombstoned**. Undelete will not help.

## When undelete does not work

| Approach | When to use |
|----------|-------------|
| **New `cluster_name`** in tfvars | Tombstoned ids; generates new `role_prefix` and OCM `{name}-wif` |
| **Wait** | Same `cluster_name`; GCP eventually releases reserved `role_id`s |
| **Avoid full destroy** between lab cycles | Keep GCP WIF IAM; destroy only the OCM cluster and VPC (not supported as a first-class Make target here today) |

Optional `role_prefix` in tfvars (phase 1 WIF module) overrides the default prefix derived from `cluster_name`.

## Permissions

Undelete requires permission to list and undelete project custom roles (for example `roles/iam.roleAdmin` on the project).
