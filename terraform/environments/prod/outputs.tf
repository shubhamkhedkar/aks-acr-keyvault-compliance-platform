output "resource_group_name" {
  description = "Platform resource group."
  value       = azurerm_resource_group.this.name
}

output "aks_name" {
  description = "AKS cluster name."
  value       = module.aks.name
}

output "aks_private_fqdn" {
  description = "Private API server FQDN (reachable from inside the VNet only)."
  value       = module.aks.private_fqdn
}

output "acr_login_server" {
  description = "ACR login server used by the pipeline and the kustomize image override."
  value       = module.acr.login_server
}

output "key_vault_name" {
  description = "Key Vault referenced by the SecretProviderClass."
  value       = module.keyvault.name
}

output "workload_identity_client_id" {
  description = "Goes on the flagpost service account annotation."
  value       = module.flagpost_identity.client_id
}

output "tenant_id" {
  description = "Tenant ID for the SecretProviderClass."
  value       = data.azurerm_client_config.current.tenant_id
}

output "log_analytics_workspace_id" {
  description = "Workspace for Container Insights queries."
  value       = module.monitoring.log_analytics_workspace_id
}
