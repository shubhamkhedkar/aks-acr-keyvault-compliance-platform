output "id" {
  description = "Vault resource ID."
  value       = azurerm_key_vault.this.id
}

output "name" {
  description = "Vault name."
  value       = azurerm_key_vault.this.name
}

output "vault_uri" {
  description = "Vault URI."
  value       = azurerm_key_vault.this.vault_uri
}
