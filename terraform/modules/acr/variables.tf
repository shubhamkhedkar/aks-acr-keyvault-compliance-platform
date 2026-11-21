variable "name" {
  description = "Registry name: 5-50 lowercase alphanumerics, globally unique."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{5,50}$", var.name))
    error_message = "ACR names are 5-50 lowercase letters and digits."
  }
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the registry."
  type        = string
}

variable "private_endpoint_subnet_id" {
  description = "Subnet for the registry private endpoint."
  type        = string
}

variable "private_dns_zone_id" {
  description = "privatelink.azurecr.io zone ID."
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "Destination for registry diagnostics."
  type        = string
}

variable "untagged_retention_days" {
  description = "Days before untagged manifests are purged."
  type        = number
  default     = 7
}

variable "georeplication_locations" {
  description = "Extra regions to replicate the registry to (Premium)."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
