output "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID."
  value       = azurerm_log_analytics_workspace.this.id
}

output "application_insights_id" {
  description = "Application Insights component ID."
  value       = azurerm_application_insights.this.id
}

output "application_insights_connection_string" {
  description = "Connection string (no instrumentation secret when local auth is disabled; still treat as sensitive)."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}

output "action_group_id" {
  description = "On-call action group ID."
  value       = azurerm_monitor_action_group.oncall.id
}
