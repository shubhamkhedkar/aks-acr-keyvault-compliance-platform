variable "subscription_id" {
  description = "Target subscription ID."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.subscription_id))
    error_message = "subscription_id must be a GUID."
  }
}

variable "environment" {
  description = "Environment name used in resource names and tags."
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging or prod."
  }
}

variable "location" {
  description = "Primary Azure region."
  type        = string
  default     = "centralindia"
}

variable "workload" {
  description = "Workload short name."
  type        = string
  default     = "flagpost"
}

variable "unique_suffix" {
  description = "Short lowercase suffix that makes ACR / Key Vault names globally unique."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,6}$", var.unique_suffix))
    error_message = "unique_suffix must be 3-6 lowercase letters or digits."
  }
}

variable "aks_admin_group_object_ids" {
  description = "Entra ID group(s) that administer the cluster and write Key Vault secrets."
  type        = list(string)

  validation {
    condition = length(var.aks_admin_group_object_ids) > 0 && alltrue([
      for id in var.aks_admin_group_object_ids : can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", id))
    ])
    error_message = "Provide at least one Entra ID group object ID (GUID); local accounts are disabled."
  }
}

variable "kubernetes_version" {
  description = "AKS minor version."
  type        = string
  default     = "1.34"
}

variable "alert_email" {
  description = "On-call email for alerts."
  type        = string
}

variable "availability_test_url" {
  description = "Public health URL for the synthetic test (empty while the app is internal-only)."
  type        = string
  default     = ""
}

variable "acr_georeplication_locations" {
  description = "Extra regions for ACR geo-replication."
  type        = list(string)
  default     = ["southindia"]
}

variable "app_namespace" {
  description = "Namespace the app runs in."
  type        = string
  default     = "flagpost"
}

variable "app_service_account" {
  description = "Service account federated to the workload identity."
  type        = string
  default     = "flagpost"
}

variable "tags" {
  description = "Extra tags merged onto the defaults."
  type        = map(string)
  default     = {}
}
