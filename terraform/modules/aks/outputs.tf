output "id" {
  description = "Cluster resource ID."
  value       = azurerm_kubernetes_cluster.this.id
}

output "name" {
  description = "Cluster name."
  value       = azurerm_kubernetes_cluster.this.name
}

output "oidc_issuer_url" {
  description = "OIDC issuer used by Workload Identity federation."
  value       = azurerm_kubernetes_cluster.this.oidc_issuer_url
}

output "kubelet_object_id" {
  description = "Kubelet managed identity object ID (holds AcrPull)."
  value       = azurerm_user_assigned_identity.kubelet.principal_id
}

output "private_fqdn" {
  description = "Private API server FQDN."
  value       = azurerm_kubernetes_cluster.this.private_fqdn
}
