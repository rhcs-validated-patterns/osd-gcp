cluster_name      = "virt"
# gcp_project_id    = ""
gcp_region        = "us-central1"
openshift_version = "4.21.3"

compute_nodes        = 3
compute_machine_type = "n2-standard-4"
create_admin         = true
enable_psc           = false

# Lab pool: regular GCE workers for nested KVM (GCE advancedMachineFeatures) and BGP/CUDN
# testing without bare metal. After apply + login:
#   CLUSTER=virt ./scripts/enable-nested-virt.sh --label workload=nested-lab
machine_pools = [
  {
    name                = "np-nested-lab"
    instance_type       = "n2-standard-8"
    autoscaling_enabled = false
    replicas            = 2
    secure_boot         = false
    labels = {
      workload = "nested-lab"
    }
  },
]