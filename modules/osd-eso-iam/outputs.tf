output "gcp_service_account_email" {
  value       = google_service_account.eso.email
  description = "GCP SA email impersonated by ESO via WIF."
}

output "gcp_service_account_id" {
  value       = google_service_account.eso.id
  description = "Resource ID of the GCP service account."
}

output "workload_identity_provider_resource_name" {
  value = format(
    "projects/%s/locations/global/workloadIdentityPools/%s/providers/%s",
    var.project_number_for_wif_principal,
    var.workload_identity_pool_id,
    var.workload_identity_provider_id,
  )
  description = "Provider resource path (debug / gcloud describe)."
}

output "workload_identity_principal_member" {
  value       = local.workload_identity_impersonation_member
  description = "principal://… bound with roles/iam.workloadIdentityUser."
}
