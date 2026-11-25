locals {
  osd_module_ref = "v0.1.5"
}

module "osd_vpc" {
  source = "git::https://github.com/rh-mobb/terraform-provider-osd-google.git//modules/osd-vpc?ref=${local.osd_module_ref}"

  project_id             = var.gcp_project_id
  region                 = var.gcp_region
  cluster_name           = var.cluster_name
  enable_psc             = var.enable_psc
  enable_private_cluster = var.enable_psc
}

module "cluster" {
  source = "git::https://github.com/rh-mobb/terraform-provider-osd-google.git//modules/osd-cluster?ref=${local.osd_module_ref}"

  name           = var.cluster_name
  cloud_region   = var.gcp_region
  gcp_project_id = var.gcp_project_id

  openshift_version    = var.openshift_version
  compute_nodes        = var.compute_nodes
  compute_machine_type = var.compute_machine_type
  availability_zones   = var.availability_zones
  multi_az             = var.availability_zones != null ? length(var.availability_zones) > 1 : null
  ccs_enabled          = true

  create_admin   = var.create_admin
  admin_password = var.admin_password

  gcp_network = {
    vpc_name             = module.osd_vpc.vpc_name
    control_plane_subnet = module.osd_vpc.control_plane_subnet
    compute_subnet       = module.osd_vpc.compute_subnet
  }

  private_service_connect = var.enable_psc ? {
    service_attachment_subnet = module.osd_vpc.psc_subnet
  } : null

  security = var.enable_psc ? {
    secure_boot = true
  } : null

  machine_pools = var.machine_pools
}
