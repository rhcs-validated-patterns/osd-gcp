mock_provider "google" {}
mock_provider "osdgoogle" {}

variables {
  cluster_name         = "public"
  gcp_project_id       = "test-project"
  gcp_region           = "us-central1"
  openshift_version    = "4.21.3"
  compute_nodes        = 3
  compute_machine_type = "n2-standard-4"
  enable_psc           = false
  create_admin         = true
  machine_pools        = []
}

run "platform_contract" {
  command = plan

  assert {
    condition     = output.platform.contract_version == 1
    error_message = "platform.contract_version must be 1."
  }

  assert {
    condition     = output.platform.installer == "osd-gcp"
    error_message = "platform.installer must identify osd-gcp."
  }

  assert {
    condition     = output.platform.wif_config_id != ""
    error_message = "platform must include wif_config_id from the cluster module."
  }

  assert {
    condition     = output.platform.eso.auth_method == "workload_identity_federation"
    error_message = "platform.eso.auth_method must be workload_identity_federation (OCM WIF)."
  }

  assert {
    condition     = module.osd_vpc.vpc_name != ""
    error_message = "BYO VPC module must be wired for osd-cluster gcp_network."
  }
}

run "virt_baremetal_pool_plan" {
  command = plan

  variables {
    cluster_name = "virt"
    machine_pools = [{
      name                = "np-virt-metal"
      instance_type       = "c3-standard-192-metal"
      autoscaling_enabled = false
      replicas            = 2
      availability_zones  = ["us-central1-a"]
      secure_boot         = false
      labels              = { workload = "virtualization" }
    }]
  }

  assert {
    condition     = length(var.machine_pools) == 1 && var.machine_pools[0].replicas == 2
    error_message = "virt profile expects a fixed 2-replica bare-metal pool."
  }
}

run "reject_worker_machine_pool_name" {
  command = plan

  variables {
    machine_pools = [{
      name                = "worker"
      instance_type       = "n2-standard-4"
      autoscaling_enabled = false
      replicas            = 1
    }]
  }

  expect_failures = [
    var.machine_pools,
  ]
}
