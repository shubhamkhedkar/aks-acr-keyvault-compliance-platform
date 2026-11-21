variable "name" {
  description = "Vault name: 3-24 chars, globally unique."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]$", var.name))
    error_message = "Key Vault names are 3-24 alphanumerics or dashes, starting with a letter."
  }
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the vault."
  type        = string
}

variable "tenant_id" {
  description = "Entra ID tenant that owns the vault."
  type        = string
}

variable "private_endpoint_subnet_id" {
  description = "Subnet for the vault private endpoint."
  type        = string
}

variable "private_dns_zone_id" {
  description = "privatelink.vaultcore.azure.net zone ID."
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "Destination for vault audit logs."
  type        = string
}

variable "soft_delete_retention_days" {
  description = "Soft-delete retention (7-90)."
  type        = number
  default     = 90

  validation {
    condition     = var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90
    error_message = "soft_delete_retention_days must be 7-90."
  }
}

variable "secret_officer_principal_ids" {
  description = "Principals (e.g. the platform admin group) that may write secrets. Workloads only get read access."
  type        = set(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
