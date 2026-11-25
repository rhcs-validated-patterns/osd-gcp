# OSD on GCP reference deployment

Terraform reference for **OpenShift Dedicated on Google Cloud** with Workload Identity Federation, BYO VPC, Terraform-managed machine pools, GitOps baseline, and `platform.json` for future integrations.

| I want to… | Start here |
|------------|------------|
| Deploy my first cluster | [Quick start](getting-started/quick-start.md) |
| Verify GCP and OCM access | [Account prerequisites](prerequisites/account.md) |
| Permissions per `make` step | [Full-stack deployment](prerequisites/full-stack.md) |
| Deploy the example profile | [OSD GCP deploy](guides/osd-gcp-deploy.md) |
| Add worker machine pools | [Machine pools](guides/machine-pools.md) |
| Inspect WIF, VPC, and modules | [Architecture](architecture.md) |
| Run an agent E2E (done-when) | [`AGENTS.md`](../AGENTS.md) → [`clusters/public/AGENTS.md`](../clusters/public/AGENTS.md) |

Sister pattern (Azure Classic): [validated-pattern-aro-classic](https://github.com/rh-mobb/validated-pattern-aro-classic).

OpenShift Virtualization on GCP is not part of this repo yet; see [Architecture](architecture.md#future-virt).
