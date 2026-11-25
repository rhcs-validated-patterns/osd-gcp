output "cluster_name" {
  value = var.cluster_name
}

output "gcp_project_id" {
  value = var.gcp_project_id
}

output "gcp_region" {
  value = var.gcp_region
}

output "api_url" {
  value = module.cluster.api_url
}

output "console_url" {
  value = module.cluster.console_url
}

output "cluster_id" {
  value = module.cluster.cluster_id
}

output "wif_config_id" {
  value = module.cluster.wif_config_id
}

output "admin_username" {
  value = module.cluster.admin_username
}

output "admin_password" {
  value     = module.cluster.admin_password
  sensitive = true
}

output "vpc_name" {
  value = module.osd_vpc.vpc_name
}

output "control_plane_subnet" {
  value = module.osd_vpc.control_plane_subnet
}

output "compute_subnet" {
  value = module.osd_vpc.compute_subnet
}

output "eso_gcp_service_account_email" {
  value       = module.eso_iam.gcp_service_account_email
  description = "GCP service account impersonated by ESO via OCM WIF."
}

output "pull_secret_secret_name" {
  value       = var.pull_secret_secret_name
  description = "Secret Manager secret id for the Red Hat pull secret."
}

output "eso_auth_method" {
  value       = "workload_identity_federation"
  description = "ESO authenticates to Secret Manager via OCM WIF pool + Kubernetes SA federation."
}

output "wif_kubernetes_token_audience" {
  value       = var.wif_kubernetes_token_audience
  description = "Kubernetes SA token aud claim for GCP STS (ClusterSecretStore / debugging)."
}

output "eso_wif_audience" {
  value       = var.wif_kubernetes_token_audience
  description = "Kubernetes SA token aud for bound tokens (serviceAccountRef.audiences)."
}

output "eso_wif_sts_audience" {
  value       = "//iam.googleapis.com/${module.eso_iam.workload_identity_provider_resource_name}"
  description = "GCP STS audience for ESO ClusterSecretStore workloadIdentityFederation.audience."
}

output "eso_wif_provider_resource_name" {
  value       = module.eso_iam.workload_identity_provider_resource_name
  description = "Full WIF provider resource name (gcloud providers describe)."
}

output "eso_wif_principal_member" {
  value       = module.eso_iam.workload_identity_principal_member
  description = "WIF impersonation principal bound to the ESO GCP SA."
}

output "platform" {
  description = "Versioned contract for downstream automation (terraform output -json platform)."
  value = nonsensitive({
    contract_version  = 1
    installer         = "osd-gcp"
    cluster_name      = var.cluster_name
    cluster_id        = module.cluster.cluster_id
    gcp_project_id    = var.gcp_project_id
    gcp_region        = var.gcp_region
    openshift_version = var.openshift_version
    wif_config_id     = module.cluster.wif_config_id
    api_url           = module.cluster.api_url
    console_url       = module.cluster.console_url
    network = {
      vpc_name             = module.osd_vpc.vpc_name
      control_plane_subnet = module.osd_vpc.control_plane_subnet
      compute_subnet       = module.osd_vpc.compute_subnet
      psc_enabled          = var.enable_psc
    }
    default_workers = {
      replicas      = var.compute_nodes
      instance_type = var.compute_machine_type
    }
    machine_pools = {
      for mp in var.machine_pools : mp.name => {
        instance_type       = mp.instance_type
        autoscaling_enabled = mp.autoscaling_enabled
        min_replicas        = try(mp.min_replicas, null)
        max_replicas        = try(mp.max_replicas, null)
        replicas            = try(mp.replicas, null)
        availability_zones  = try(mp.availability_zones, null)
        labels              = coalesce(mp.labels, {})
        taints              = coalesce(mp.taints, [])
      }
    }
    eso = {
      auth_method                        = "workload_identity_federation"
      gcp_service_account_email          = module.eso_iam.gcp_service_account_email
      pull_secret_secret_name            = var.pull_secret_secret_name
      pull_secret_stored                 = length(google_secret_manager_secret.pull_secret) > 0
      wif_kubernetes_token_audience      = var.wif_kubernetes_token_audience
      wif_sts_audience                   = "//iam.googleapis.com/${module.eso_iam.workload_identity_provider_resource_name}"
      wif_provider_resource_name         = module.eso_iam.workload_identity_provider_resource_name
      workload_identity_principal_member = module.eso_iam.workload_identity_principal_member
    }
  })
}
