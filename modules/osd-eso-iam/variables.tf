variable "project_id" {
  type        = string
  description = "GCP project ID where the ESO service account is created."
}

variable "project_number_for_wif_principal" {
  type        = string
  description = "GCP project number in WIF principal paths (federated project number from osdgoogle_wif_config when set)."
}

variable "workload_identity_pool_id" {
  type        = string
  description = "Workload identity pool ID from osdgoogle_wif_config."
}

variable "workload_identity_provider_id" {
  type        = string
  description = "OIDC provider ID from osdgoogle_wif_config."
}

variable "kubernetes_namespace" {
  type        = string
  default     = "external-secrets-operator"
  description = "Namespace of the ESO ServiceAccount referenced by ClusterSecretStore."
}

variable "kubernetes_service_account_name" {
  type        = string
  default     = "external-secrets-sa"
  description = "Kubernetes ServiceAccount name for WIF impersonation binding."
}

variable "service_account_id" {
  type        = string
  description = "GCP service account_id (short name)."
}

variable "service_account_display_name" {
  type        = string
  default     = "External Secrets Operator"
  description = "Display name for the GCP service account."
}
