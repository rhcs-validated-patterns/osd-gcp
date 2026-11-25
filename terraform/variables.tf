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
  description = "GCP project ID for VPC, WIF, and the cluster."
}

variable "gcp_region" {
  type        = string
  description = "GCP region (e.g. us-central1)."
}

variable "availability_zones" {
  type        = list(string)
  default     = null
  description = "GCP zones for the default worker pool (1 = single-AZ, 3 = multi-AZ). Required when machine_pools set availability_zones (see osd-gcp-cudn-routing baremetal_availability_zones)."
}

variable "openshift_version" {
  type        = string
  description = "OpenShift version (x.y.z)."
}

variable "enable_psc" {
  type        = bool
  default     = false
  description = "Enable Private Service Connect (private cluster path)."
}

variable "compute_nodes" {
  type        = number
  default     = 3
  description = "Default worker count for the cluster module."
}

variable "compute_machine_type" {
  type        = string
  default     = "n2-standard-4"
  description = "GCP machine type for the default worker pool."
}

variable "create_admin" {
  type        = bool
  default     = true
  description = "Create HTPasswd cluster-admin via osdgoogle_cluster_admin."
}

variable "admin_password" {
  type        = string
  default     = null
  nullable    = true
  sensitive   = true
  description = "Optional admin password; auto-generated when null and create_admin is true."
}

variable "pull_secret_path" {
  type        = string
  default     = ""
  description = "Path to Red Hat pull secret JSON file (stored in Secret Manager on apply)."
}

variable "pull_secret" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Inline pull secret for tests; live deploys use pull_secret_path."
}

variable "pull_secret_secret_name" {
  type        = string
  default     = "redhat-pull-secret"
  description = "Secret Manager secret id for the Red Hat pull secret (bootstrap / ESO)."

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,255}$", var.pull_secret_secret_name))
    error_message = "pull_secret_secret_name must be a valid Secret Manager secret id."
  }
}

variable "wif_kubernetes_token_audience" {
  type        = string
  default     = "openshift"
  description = <<-EOT
    Projected ServiceAccount token `aud` for ESO→GCP WIF (must match OCM WIF OIDC provider allowedAudiences).
    See osd-gcp-cudn-routing controller_gcp_iam (typically the literal "openshift", not the iam.googleapis.com provider URL).
  EOT
}

variable "machine_pools" {
  type = list(object({
    name                = string
    instance_type       = string
    autoscaling_enabled = optional(bool, true)
    min_replicas        = optional(number)
    max_replicas        = optional(number)
    replicas            = optional(number)
    availability_zones  = optional(list(string))
    labels              = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
    root_volume_size = optional(number)
    secure_boot      = optional(bool, false)
  }))
  default     = []
  description = "Additional osdgoogle_machine_pool resources. Names worker and workers-* are reserved."

  validation {
    condition = alltrue([
      for mp in var.machine_pools :
      mp.name != "worker" && !startswith(mp.name, "workers-")
    ])
    error_message = "machine_pools must not use reserved names worker or workers-* (default pool is compute_nodes on the cluster module)."
  }
}
