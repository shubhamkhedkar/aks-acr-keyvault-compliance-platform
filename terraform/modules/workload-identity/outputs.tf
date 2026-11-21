output "client_id" {
  description = "Client ID to put on the service account annotation azure.workload.identity/client-id."
  value       = azurerm_user_assigned_identity.this.client_id
}

output "principal_id" {
  description = "Principal (object) ID of the identity."
  value       = azurerm_user_assigned_identity.this.principal_id
}

output "subject" {
  description = "Federated subject."
  value       = azurerm_federated_identity_credential.this.subject
}
