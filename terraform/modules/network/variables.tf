variable "name" {
  description = "Name prefix, e.g. flagpost-prod."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group that owns the network."
  type        = string
}

variable "address_space" {
  description = "VNet address space."
  type        = list(string)
  default     = ["10.40.0.0/16"]
}

variable "aks_nodes_cidr" {
  description = "Subnet for AKS node NICs (pods use the CNI overlay range, not this subnet)."
  type        = string
  default     = "10.40.0.0/22"

  validation {
    condition     = can(cidrnetmask(var.aks_nodes_cidr)) && tonumber(split("/", var.aks_nodes_cidr)[1]) <= 24
    error_message = "aks_nodes_cidr must be a valid CIDR of /24 or larger so the node pools can scale."
  }
}

variable "private_endpoints_cidr" {
  description = "Subnet for ACR and Key Vault private endpoints."
  type        = string
  default     = "10.40.8.0/24"
}

variable "zones" {
  description = "Availability zone for the NAT gateway (NAT gateway is zonal)."
  type        = list(string)
  default     = ["1"]
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
