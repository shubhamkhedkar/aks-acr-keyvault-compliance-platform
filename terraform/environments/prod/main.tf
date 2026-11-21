data "azurerm_client_config" "current" {}

locals {
  name = "${var.workload}-${var.environment}"
  tags = merge({
    workload    = var.workload
    environment = var.environment
    owner       = "platform-team"
    managed_by  = "terraform"
    repo        = "shubhamkhedkar/aks-acr-keyvault-compliance-platform"
  }, var.tags)
}

resource "azurerm_resource_group" "this" {
  name     = "rg-${local.name}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_management_lock" "rg" {
  name       = "lock-${local.name}"
  scope      = azurerm_resource_group.this.id
  lock_level = "CanNotDelete"
  notes      = "Production platform: remove deliberately before teardown."
}

module "monitoring" {
  source                = "../../modules/monitoring"
  name                  = local.name
  location              = var.location
  resource_group_name   = azurerm_resource_group.this.name
  alert_email           = var.alert_email
  availability_test_url = var.availability_test_url
  tags                  = local.tags
}

module "network" {
  source              = "../../modules/network"
  name                = local.name
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

module "acr" {
  source                     = "../../modules/acr"
  name                       = "acr${var.workload}${var.environment}${var.unique_suffix}"
  location                   = var.location
  resource_group_name        = azurerm_resource_group.this.name
  private_endpoint_subnet_id = module.network.private_endpoints_subnet_id
  private_dns_zone_id        = module.network.private_dns_zone_ids["acr"]
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id
  georeplication_locations   = var.acr_georeplication_locations
  tags                       = local.tags
}

module "keyvault" {
  source                       = "../../modules/keyvault"
  name                         = "kv-${var.workload}-${var.environment}-${var.unique_suffix}"
  location                     = var.location
  resource_group_name          = azurerm_resource_group.this.name
  tenant_id                    = data.azurerm_client_config.current.tenant_id
  private_endpoint_subnet_id   = module.network.private_endpoints_subnet_id
  private_dns_zone_id          = module.network.private_dns_zone_ids["keyvault"]
  log_analytics_workspace_id   = module.monitoring.log_analytics_workspace_id
  secret_officer_principal_ids = toset(var.aks_admin_group_object_ids)
  tags                         = local.tags
}

module "aks" {
  source                     = "../../modules/aks"
  name                       = local.name
  location                   = var.location
  resource_group_name        = azurerm_resource_group.this.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  kubernetes_version         = var.kubernetes_version
  vnet_id                    = module.network.vnet_id
  nodes_subnet_id            = module.network.aks_nodes_subnet_id
  admin_group_object_ids     = var.aks_admin_group_object_ids
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id
  acr_id                     = module.acr.id
  tags                       = local.tags

  depends_on = [module.network]
}

module "flagpost_identity" {
  source              = "../../modules/workload-identity"
  name                = "id-${local.name}-workload"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  oidc_issuer_url     = module.aks.oidc_issuer_url
  namespace           = var.app_namespace
  service_account     = var.app_service_account
  key_vault_id        = module.keyvault.id
  tags                = local.tags
}
