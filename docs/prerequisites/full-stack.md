# Full-stack deployment

High-level permissions and order of operations for the example profile `public`.

| Step | Make target | GCP / OCM needs |
|------|-------------|-----------------|
| Preflight | `setup`, edit tfvars | Read project; OCM token |
| Plan | `cluster.public.plan` | Same (read-only Terraform) |
| Phase 1 WIF | part of `.apply` | OCM WIF config; IAM WIF admin on project |
| Phase 2 cluster | part of `.apply` | Compute network admin; OSD create via OCM |
| Login | `cluster.public.login` | Cluster API reachable |
| GitOps | `cluster.public.bootstrap` | Cluster admin; OperatorHub pull if using `PULL_SECRET_PATH` |
| Contract | `cluster.public.platform` | Terraform state with cluster outputs |

Detailed IAM for WIF and BYO VPC follows the [terraform-provider-osd-google BYO VPC guide](https://github.com/rh-mobb/terraform-provider-osd-google/blob/main/docs/guides/deploy-byo-vpc-cluster.md).

Apply is long-running (often 45–90+ minutes). Prefer tmux and log under `clusters/public/logs/` (gitignored).

Stray `TF_VAR_*` from other stacks do not override keys in `clusters/<profile>/terraform.tfvars` during `make cluster.*.apply` (Terraform `-var-file` precedence). Unset them only to keep the shell clean.

See [OSD GCP deploy](../guides/osd-gcp-deploy.md) for commands.
