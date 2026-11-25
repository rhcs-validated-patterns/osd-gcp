# ESO GCP identity via OCM WIF pool (same pattern as osd-gcp-cudn-routing modules/osd-bgp-controller-iam).
resource "google_service_account" "eso" {
  project      = var.project_id
  account_id   = var.service_account_id
  display_name = var.service_account_display_name
}

locals {
  workload_identity_impersonation_member = format(
    "principal://iam.googleapis.com/projects/%s/locations/global/workloadIdentityPools/%s/subject/system:serviceaccount:%s:%s",
    var.project_number_for_wif_principal,
    var.workload_identity_pool_id,
    var.kubernetes_namespace,
    var.kubernetes_service_account_name,
  )
}

resource "google_service_account_iam_member" "wif_impersonation" {
  service_account_id = google_service_account.eso.name
  role               = "roles/iam.workloadIdentityUser"
  member             = local.workload_identity_impersonation_member
}
