# Lab cluster profile (`virt`)

OSD-on-GCP profile for **nested-GCE / BGP lab** work: default **`n2-standard-4`** workers plus a **`np-nested-lab`** pool (**2** × **`n2-standard-8`**, label `workload=nested-lab`).

This profile provisions **OSD GCP + a nested-lab worker pool** only. After **`make cluster.virt.platform`**, install/configure the virt stack from the sibling **[validated-pattern-openshift-virt](https://github.com/rh-mobb/validated-pattern-openshift-virt)** checkout (use its GCP slice when documented there; consume this repo’s `platform.json`). Hub/spoke BGP/CUDN patterns: local **`references/osd-gcp-cudn-routing`** (reference only).

## Layout

| Path | Purpose |
|------|---------|
| [`clusters/virt/terraform.tfvars`](../../clusters/virt/terraform.tfvars) | `cluster_name = virt`, pool `np-nested-lab` |
| [`clusters/virt/AGENTS.md`](../../clusters/virt/AGENTS.md) | Agent done-when gates |
| [`scripts/enable-nested-virt.sh`](../../scripts/enable-nested-virt.sh) | Lab GCE nested virt (instance restart) |

## Deploy (this repo — BYO VPC)

Same flow as [OSD GCP deploy](osd-gcp-deploy.md), with `virt` instead of `public`:

```bash
export OSDGOOGLE_TOKEN="$(ocm token)"
make setup
make cluster.virt.plan
make cluster.virt.apply
make cluster.virt.login
make cluster.virt.bootstrap
make cluster.virt.platform
```

Enable nested virtualization on the lab pool (optional, **unsupported** on OSD):

```bash
CLUSTER=virt ./scripts/enable-nested-virt.sh --label workload=nested-lab
```

## Teardown (virt stack + cluster)

Order is reverse of deploy: sibling **validated-pattern-openshift-virt** (`osd-gcp-virt` profile), then this repo.

```bash
export OSD_GCP_ROOT="$(pwd)"   # this installer checkout
export OSD_GCP_PROFILE=virt
make -C ../validated-pattern-openshift-virt cluster.osd-gcp-virt.destroy

DESTROY_CONFIRM=yes make cluster.virt.destroy
# Long apply/destroy: make cluster.virt.longrun.destroy
```

## Related

- [Machine pools](machine-pools.md)
- [Architecture](../architecture.md)