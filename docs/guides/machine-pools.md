# Machine pools

Day-0 default workers are configured on the cluster module:

- `compute_nodes` — replica count (default `3`)
- `compute_machine_type` — GCP machine type (default `n2-standard-4`)

Additional pools use Terraform `machine_pools` in [`clusters/public/terraform.tfvars`](../../clusters/public/terraform.tfvars). They map to `osdgoogle_machine_pool` resources in the [osd-cluster module](https://github.com/rh-mobb/terraform-provider-osd-google/tree/main/modules/osd-cluster).

## Reserved names

Do **not** name pools `worker` or `workers-*`. Those names are reserved for the default worker pool.

## Example (VM workers)

```hcl
machine_pools = [
  {
    name                = "np-virt"
    instance_type       = "n2-standard-8"
    autoscaling_enabled = false
    replicas            = 2
    labels = {
      workload = "virtualization"
    }
  },
]
```

## Bare metal pool (OpenShift Virtualization prep)

OSD on GCP supports **`c3-standard-192-metal`** for bare-metal workers. Pin **`availability_zones`** to a single zone where the type exists; set **`secure_boot = false`** on the pool.

Committed example: [`clusters/virt/terraform.tfvars`](../../clusters/virt/terraform.tfvars) and [Virt example cluster](virt-cluster.md) (`make cluster.virt.apply`).

After changing pools, run:

```bash
make cluster.public.plan
make cluster.public.apply
```

There is **no** Helm MachineSets chart in this repo (contrast with [validated-pattern-aro-classic](https://github.com/rh-mobb/validated-pattern-aro-classic)).

Autoscaling pools require `min_replicas` and `max_replicas` with `autoscaling_enabled = true`. Fixed-size pools require `replicas` with `autoscaling_enabled = false`.

Pool intent is recorded in `platform.json` under `machine_pools` when you run `make cluster.public.platform`.
