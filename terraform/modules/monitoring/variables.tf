variable "name" {
  description = "Name prefix."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for monitoring resources."
  type        = string
}

variable "retention_in_days" {
  description = "Log Analytics retention."
  type        = number
  default     = 90

  validation {
    condition     = var.retention_in_days >= 30 && var.retention_in_days <= 730
    error_message = "retention_in_days must be between 30 and 730."
  }
}

variable "daily_quota_gb" {
  description = "Daily ingestion cap for Log Analytics (-1 = unlimited)."
  type        = number
  default     = 5
}

variable "alert_email" {
  description = "On-call address for the action group."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "alert_email must be an email address."
  }
}

variable "availability_test_url" {
  description = "Public HTTPS health URL for the synthetic availability test. Empty disables the test."
  type        = string
  default     = ""

  validation {
    condition     = var.availability_test_url == "" || startswith(var.availability_test_url, "https://")
    error_message = "availability_test_url must be empty or an https:// URL."
  }
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
