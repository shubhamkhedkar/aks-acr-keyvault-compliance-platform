# Log Analytics (Container Insights + diagnostics), workspace-based Application Insights,
# an on-call action group and an optional synthetic availability test.

resource "azurerm_log_analytics_workspace" "this" {
  name                         = "log-${var.name}"
  location                     = var.location
  resource_group_name          = var.resource_group_name
  sku                          = "PerGB2018"
  retention_in_days            = var.retention_in_days
  daily_quota_gb               = var.daily_quota_gb
  local_authentication_enabled = false
  tags                         = var.tags
}

resource "azurerm_application_insights" "this" {
  name                         = "appi-${var.name}"
  location                     = var.location
  resource_group_name          = var.resource_group_name
  workspace_id                 = azurerm_log_analytics_workspace.this.id
  application_type             = "web"
  local_authentication_enabled = false
  sampling_percentage          = 100
  tags                         = var.tags
}

resource "azurerm_monitor_action_group" "oncall" {
  name                = "ag-${var.name}-oncall"
  resource_group_name = var.resource_group_name
  short_name          = "oncall"
  tags                = var.tags

  email_receiver {
    name                    = "platform-oncall"
    email_address           = var.alert_email
    use_common_alert_schema = true
  }
}

resource "azurerm_application_insights_standard_web_test" "health" {
  count                   = var.availability_test_url == "" ? 0 : 1
  name                    = "webtest-${var.name}-healthz"
  location                = var.location
  resource_group_name     = var.resource_group_name
  application_insights_id = azurerm_application_insights.this.id
  geo_locations           = ["emea-au-syd-edge", "apac-sg-sin-azr", "us-va-ash-azr"]
  frequency               = 300
  timeout                 = 30
  retry_enabled           = true
  enabled                 = true
  tags                    = var.tags

  request {
    url       = var.availability_test_url
    http_verb = "GET"
  }

  validation_rules {
    expected_status_code        = 200
    ssl_check_enabled           = true
    ssl_cert_remaining_lifetime = 14
  }
}

resource "azurerm_monitor_metric_alert" "availability" {
  count               = var.availability_test_url == "" ? 0 : 1
  name                = "alert-${var.name}-availability"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_application_insights_standard_web_test.health[0].id, azurerm_application_insights.this.id]
  description         = "Health endpoint failing from 2 or more test locations."
  severity            = 1
  tags                = var.tags

  application_insights_web_test_location_availability_criteria {
    web_test_id           = azurerm_application_insights_standard_web_test.health[0].id
    component_id          = azurerm_application_insights.this.id
    failed_location_count = 2
  }

  action {
    action_group_id = azurerm_monitor_action_group.oncall.id
  }
}
