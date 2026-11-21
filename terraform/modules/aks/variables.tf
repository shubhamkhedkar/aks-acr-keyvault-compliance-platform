variable "name" {
  description = "Name prefix."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the cluster."
  type        = string
}

variable "tenant_id" {
  description = "Entra ID tenant for Kubernetes RBAC."
  type        = string
}

variable "kubernetes_version" {
  description = "Minor version (patches are applied by the auto-upgrade channel)."
  type        = string
  default     = "1.34"
}

variable "nodes_subnet_id" {
  description = "Subnet for node NICs."
  type        = string
}

variable "vnet_id" {
  description = "VNet ID (control-plane identity needs Network Contributor on it for the custom VNet)."
  type        = string
}

variable "admin_group_object_ids" {
  description = "Entra ID groups that become cluster admins (Azure RBAC Cluster Admin)."
  type        = list(string)

  validation {
    condition     = length(var.admin_group_object_ids) > 0
    error_message = "At least one admin group is required because local accounts are disabled."
  }
}

variable "log_analytics_workspace_id" {
  description = "Workspace for Container Insights and Defender."
  type        = string
}

variable "acr_id" {
  description = "Registry the kubelet identity may pull from."
  type        = string
}

variable "system_vm_size" {
  description = "VM size for the system pool."
  type        = string
  default     = "Standard_D4ds_v5"
}

variable "apps_vm_size" {
  description = "VM size for the workload pool."
  type        = string
  default     = "Standard_D4ds_v5"
}

variable "system_pool" {
  description = "Autoscaler bounds for the system pool."
  type        = object({ min = number, max = number })
  default     = { min = 2, max = 4 }
}

variable "apps_pool" {
  description = "Autoscaler bounds for the workload pool."
  type        = object({ min = number, max = number })
  default     = { min = 2, max = 6 }

  validation {
    condition     = var.apps_pool.min >= 2 && var.apps_pool.max >= var.apps_pool.min
    error_message = "apps_pool needs min >= 2 (zone spread + PDB) and max >= min."
  }
}

variable "zones" {
  description = "Availability zones for the node pools."
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "service_cidr" {
  description = "Kubernetes service CIDR (must not overlap the VNet)."
  type        = string
  default     = "172.16.0.0/16"
}

variable "dns_service_ip" {
  description = "CoreDNS service IP inside service_cidr."
  type        = string
  default     = "172.16.0.10"
}

variable "pod_cidr" {
  description = "CNI overlay pod CIDR."
  type        = string
  default     = "192.168.0.0/16"
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
