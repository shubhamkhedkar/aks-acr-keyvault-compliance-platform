output "vnet_id" {
  description = "VNet resource ID."
  value       = azurerm_virtual_network.this.id
}

output "aks_nodes_subnet_id" {
  description = "Subnet ID for AKS node pools."
  value       = azurerm_subnet.aks_nodes.id
}

output "private_endpoints_subnet_id" {
  description = "Subnet ID for private endpoints."
  value       = azurerm_subnet.private_endpoints.id
}

output "private_dns_zone_ids" {
  description = "Private DNS zone IDs keyed by service (acr, keyvault)."
  value       = { for k, z in azurerm_private_dns_zone.this : k => z.id }
}

output "nat_gateway_id" {
  description = "NAT gateway that provides AKS egress."
  value       = azurerm_nat_gateway.this.id
}
