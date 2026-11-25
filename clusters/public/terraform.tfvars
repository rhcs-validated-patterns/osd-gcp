cluster_name      = "public"
# gcp_project_id    = ""
gcp_region        = "us-central1"
openshift_version = "4.21.3"

compute_nodes        = 3
compute_machine_type = "n2-standard-4"
create_admin         = true
enable_psc           = false

# machine_pools = [
#   {
#     name                = "np-virt"
#     instance_type       = "n2-standard-8"
#     autoscaling_enabled = false
#     replicas            = 2
#     labels = {
#       workload = "virtualization"
#     }
#   },
# ]
