# OSD on GCP reference deployment

Terraform and scripts for **OpenShift Dedicated (OSD) on Google Cloud** with Workload Identity Federation (WIF), a module-managed BYO VPC, **osdgoogle** machine pools (no Helm MachineSets), GitOps bootstrap, and a `platform.json` contract for future downstream automation.

Provisioning uses modules from [terraform-provider-osd-google](https://github.com/rh-mobb/terraform-provider-osd-google) (`v0.1.5`). This is **not** ARO, ROSA, or the Azure virt stack.

## Quick path

```bash
export OSDGOOGLE_TOKEN="$(ocm token)"   # or console.redhat.com/openshift/token
make setup
# Edit clusters/public/terraform.tfvars (gcp_project_id, region, version)
make cluster.public.plan
make cluster.public.apply
make cluster.public.login
make cluster.public.bootstrap
make cluster.public.platform
```

Operator guide: [OSD GCP deploy](docs/guides/osd-gcp-deploy.md). **Virt prep profile:** [Virt example cluster](docs/guides/virt-cluster.md) (`make cluster.virt.*`). Agents: [`AGENTS.md`](AGENTS.md), [`clusters/public/AGENTS.md`](clusters/public/AGENTS.md), [`clusters/virt/AGENTS.md`](clusters/virt/AGENTS.md).

OpenShift Virtualization/GCP storage lives in sibling **[validated-pattern-openshift-virt](https://github.com/rh-mobb/validated-pattern-openshift-virt)**; the `virt` profile here adds a **nested-lab** machine pool for lab work.

## Development

```bash
make fmt lint test
make docs-build
```

Prior art: [validated-pattern-aro-classic](https://github.com/rh-mobb/validated-pattern-aro-classic) (Make + docs shape), [terraform-provider-osd-google](https://github.com/rh-mobb/terraform-provider-osd-google) (WIF, VPC, cluster, machine pools).
