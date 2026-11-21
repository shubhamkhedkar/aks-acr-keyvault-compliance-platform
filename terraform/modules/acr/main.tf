# Premium ACR: no admin user, no anonymous pull, no public network access,
# reachable only through a private endpoint. Pull/push is Entra ID + RBAC only.

resource "azurerm_container_registry" "this" {
  #checkov:skip=CKV_AZURE_164:Image signing is enforced at admission (Ratify/Notation) rather than with legacy Docker Content Trust.
  #checkov:skip=CKV_AZURE_166:Quarantine would block pulls until an external scanner releases images; scanning gates run in the pipeline and Defender for Containers.
  name                          = var.name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  sku                           = "Premium"
  admin_enabled                 = false
  anonymous_pull_enabled        = false
  public_network_access_enabled = false
  export_policy_enabled         = false
  data_endpoint_enabled         = true
  zone_redundancy_enabled       = true
  network_rule_bypass_option    = "None"
  retention_policy_in_days      = var.untagged_retention_days
  tags                          = var.tags

  dynamic "georeplications" {
    for_each = toset(var.georeplication_locations)
    content {
      location                        = georeplications.value
      zone_redundancy_enabled         = true
      global_endpoint_routing_enabled = true
      tags                            = var.tags
    }
  }
}

resource "azurerm_private_endpoint" "acr" {
  name                = "pe-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${var.name}"
    private_connection_resource_id = azurerm_container_registry.this.id
    subresource_names              = ["registry"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "acr"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }
}

resource "azurerm_monitor_diagnostic_setting" "acr" {
  name                       = "diag-to-log-analytics"
  target_resource_id         = azurerm_container_registry.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
