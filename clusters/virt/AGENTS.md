# Agent playbook — `clusters/virt`

**Lab profile** (same installer as `public`): default workers plus an optional **regular-compute** pool for nested-GCE and BGP/CUDN experiments — **not** product OpenShift Virt on bare metal. Human runbook: [Virt / lab cluster](../../docs/guides/virt-cluster.md).

## Recipe facts

| Item | Value |
|------|--------|
| Profile / `cluster_name` | `virt` |
| Default workers | 3 × `n2-standard-4` |
| Lab pool | `np-nested-lab`: **2** × `n2-standard-8`, label `workload=nested-lab` |
| WIF display name | `virt-wif` |
| Nested GCE KVM | `scripts/enable-nested-virt.sh` after login (lab-only, instance **RESTART**) |
| Virt stack after platform | Sibling **`validated-pattern-openshift-virt`** (not this repo) |
| BGP/CUDN reference | Local `references/osd-gcp-cudn-routing/` (gitignored); not a deploy dependency |

## When to run

Same as root Live GCP rules. Preflight and apply/destroy commands use **`make cluster.virt.*`** instead of `public`.

## Steps 0–5

Mirror [`clusters/public/AGENTS.md`](../public/AGENTS.md) with `virt` substituted. After apply:

```bash
oc get machineset -n openshift-machine-api | rg nested-lab
oc get nodes -l workload=nested-lab
CLUSTER=virt ./scripts/enable-nested-virt.sh --label workload=nested-lab --dry-run
```

**Done when (apply):** OCM cluster ready; machine pool `np-nested-lab` with 2 replicas; Ready nodes with `workload=nested-lab` when machines have joined.

**Done when (platform):** `platform.json` lists `machine_pools.np-nested-lab` with `n2-standard-8`.

## Destroy

Destroy **virt stack first**, then this installer cluster (reverse of deploy).

```bash
export OSD_GCP_ROOT=/path/to/validated-pattern-osd-gcp
export OSD_GCP_PROFILE=virt
# Sibling: drains Hyperdisk PVCs + BGP CRs, then terraform (kubeconfig auto: .kube/config-virt)
OSD_GCP_ROOT="$OSD_GCP_ROOT" make -C /path/to/validated-pattern-openshift-virt cluster.osd-gcp-virt.destroy

DESTROY_CONFIRM=yes make cluster.virt.destroy
# Or tmux with env wired: make cluster.virt.longrun.destroy
```

Repeat deploy with the same `cluster_name` may need `make cluster.virt.wif-undelete-roles` if WIF custom roles are tombstoned.

## Notes

- For **hub/spoke NCC BGP + CUDN + optional `make virt.deploy`**, use the sibling repo — not this BYO-VPC root alone.
- Bare metal (`c3-standard-192-metal`) remains documented in git history for product Virt when metal supply and MHC are resolved.