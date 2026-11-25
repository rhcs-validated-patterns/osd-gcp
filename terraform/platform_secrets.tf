locals {
  pull_secret_content = (
    trimspace(var.pull_secret) != "" ? var.pull_secret :
    (trimspace(var.pull_secret_path) != "" ? file(pathexpand(var.pull_secret_path)) : "")
  )
  have_pull_secret = length(trimspace(local.pull_secret_content)) > 0
  wif_display_name = "${var.cluster_name}-wif"
}

data "google_project" "project" {
  project_id = var.gcp_project_id
}

data "osdgoogle_wif_config" "wif" {
  display_name = local.wif_display_name
}

locals {
  workload_pool_id     = data.osdgoogle_wif_config.wif.gcp.workload_identity_pool.pool_id
  workload_provider_id = data.osdgoogle_wif_config.wif.gcp.workload_identity_pool.identity_provider.identity_provider_id
  project_number_for_wif = (
    try(data.osdgoogle_wif_config.wif.gcp.federated_project_number, "") != ""
    ? data.osdgoogle_wif_config.wif.gcp.federated_project_number
    : tostring(data.google_project.project.number)
  )
}

module "eso_iam" {
  source = "../modules/osd-eso-iam"

  project_id                       = var.gcp_project_id
  project_number_for_wif_principal = local.project_number_for_wif
  workload_identity_pool_id        = local.workload_pool_id
  workload_identity_provider_id    = local.workload_provider_id

  service_account_id              = "${var.cluster_name}-eso"
  service_account_display_name    = "External Secrets Operator (${var.cluster_name})"
  kubernetes_namespace            = "external-secrets-operator"
  kubernetes_service_account_name = "external-secrets-sa"
}

resource "google_secret_manager_secret" "pull_secret" {
  count = local.have_pull_secret ? 1 : 0

  project   = var.gcp_project_id
  secret_id = var.pull_secret_secret_name

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "pull_secret" {
  count = local.have_pull_secret ? 1 : 0

  secret      = google_secret_manager_secret.pull_secret[0].id
  secret_data = local.pull_secret_content
}

resource "google_secret_manager_secret_iam_member" "eso_pull_secret" {
  count = local.have_pull_secret ? 1 : 0

  project   = var.gcp_project_id
  secret_id = google_secret_manager_secret.pull_secret[0].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${module.eso_iam.gcp_service_account_email}"
}
