module "wif_config" {
  source = "git::https://github.com/rh-mobb/terraform-provider-osd-google.git//modules/osd-wif-config?ref=v0.1.5"

  gcp_project_id    = var.gcp_project_id
  cluster_name      = var.cluster_name
  openshift_version = var.openshift_version
  role_prefix       = var.role_prefix
}
