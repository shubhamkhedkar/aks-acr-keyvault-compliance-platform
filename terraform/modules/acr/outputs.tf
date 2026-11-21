output "id" {
  description = "Registry resource ID."
  value       = azurerm_container_registry.this.id
}

output "login_server" {
  description = "Registry login server (<name>.azurecr.io)."
  value       = azurerm_container_registry.this.login_server
}
