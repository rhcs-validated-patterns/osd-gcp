variable "ocm_token" {
  type        = string
  sensitive   = true
  default     = ""
  description = "OCM offline token (optional; use OSDGOOGLE_TOKEN env var instead)."
}

variable "cluster_name" {
  type        = string
  description = "OSD cluster name. WIF display name is {cluster_name}-wif."
}

variable "gcp_project_id" {
  type        = string
  description = "GCP project ID for WIF resources."
}

variable "openshift_version" {
  type        = string
  description = "OpenShift version (x.y.z)."
}

variable "role_prefix" {
  type        = string
  default     = null
  nullable    = true
  description = "Optional WIF IAM role prefix."
}

# Declared so clusters/*/terraform.tfvars can be shared with the cluster root without errors.
variable "gcp_region" {
  type    = string
  default = null
}

variable "availability_zones" {
  type    = list(string)
  default = null
}

variable "enable_psc" {
  type    = bool
  default = false
}

variable "compute_nodes" {
  type    = number
  default = 3
}

variable "compute_machine_type" {
  type    = string
  default = "n2-standard-4"
}

variable "create_admin" {
  type    = bool
  default = true
}

variable "admin_password" {
  type      = string
  default   = null
  nullable  = true
  sensitive = true
}

variable "machine_pools" {
  type    = list(any)
  default = []
}
