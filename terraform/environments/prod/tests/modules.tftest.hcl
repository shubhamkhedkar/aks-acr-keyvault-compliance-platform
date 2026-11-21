# Module-level guardrail tests (mocked azurerm, plan only). Each run targets one module
# and asserts the security settings the InSpec profile later verifies on the live resources.

mock_provider "azurerm" {
  override_during = plan
}

variables {
  location            = "centralindia"
  resource_group_name = "rg-flagpost-prod"
  sub                 = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-flagpost-prod/providers"
}

run "network_subnets_nsgs_and_egress" {
  command = plan
  module {
    source = "../../modules/network"
  }

  variables {
    name = "flagpost-prod"
  }

  assert {
    condition     = azurerm_subnet.aks_nodes.default_outbound_access_enabled == false && azurerm_subnet.private_endpoints.default_outbound_access_enabled == false
    error_message = "Subnets must not rely on implicit default outbound access."
  }

  assert {
    condition     = azurerm_network_security_rule.aks_deny_internet_inbound.access == "Deny" && azurerm_network_security_rule.aks_deny_internet_inbound.source_address_prefix == "Internet"
    error_message = "Node subnet NSG must deny inbound from the Internet."
  }

  assert {
    condition     = azurerm_network_security_rule.pe_allow_https_from_vnet.destination_port_range == "443" && azurerm_network_security_rule.pe_deny_all_inbound.priority == 4096
    error_message = "Private endpoint subnet allows only HTTPS from the VNet."
  }

  assert {
    condition     = toset(keys(azurerm_private_dns_zone.this)) == toset(["acr", "keyvault"]) && azurerm_private_dns_zone.this["keyvault"].name == "privatelink.vaultcore.azure.net"
    error_message = "Private DNS zones for ACR and Key Vault are required."
  }

  assert {
    condition     = azurerm_nat_gateway.this.sku_name == "Standard" && azurerm_public_ip.nat.sku == "Standard"
    error_message = "Egress goes through a Standard NAT gateway."
  }
}

run "network_rejects_tiny_node_subnet" {
  command = plan
  module {
    source = "../../modules/network"
  }

  variables {
    name           = "flagpost-prod"
    aks_nodes_cidr = "10.40.0.0/27"
  }

  expect_failures = [var.aks_nodes_cidr]
}

run "acr_private_keyless_premium" {
  command = plan
  module {
    source = "../../modules/acr"
  }

  variables {
    name                       = "acrflagpostprodsk07"
    private_endpoint_subnet_id = "${var.sub}/Microsoft.Network/virtualNetworks/vnet/subnets/pe"
    private_dns_zone_id        = "${var.sub}/Microsoft.Network/privateDnsZones/privatelink.azurecr.io"
    log_analytics_workspace_id = "${var.sub}/Microsoft.OperationalInsights/workspaces/log"
    georeplication_locations   = ["southindia"]
  }

  assert {
    condition     = azurerm_container_registry.this.admin_enabled == false && azurerm_container_registry.this.anonymous_pull_enabled == false
    error_message = "ACR admin user and anonymous pull must be disabled."
  }

  assert {
    condition     = azurerm_container_registry.this.public_network_access_enabled == false && azurerm_container_registry.this.network_rule_bypass_option == "None"
    error_message = "ACR must not be reachable from public networks."
  }

  assert {
    condition     = azurerm_container_registry.this.sku == "Premium" && azurerm_container_registry.this.export_policy_enabled == false && azurerm_container_registry.this.zone_redundancy_enabled
    error_message = "ACR must be zone-redundant Premium with export disabled."
  }

  assert {
    condition     = one(azurerm_private_endpoint.acr.private_service_connection).subresource_names == tolist(["registry"])
    error_message = "ACR private endpoint must target the registry sub-resource."
  }

  assert {
    condition     = length(azurerm_container_registry.this.georeplications) == 1
    error_message = "Each geo-replication location must render one georeplications block."
  }
}

run "acr_rejects_bad_name" {
  command = plan
  module {
    source = "../../modules/acr"
  }

  variables {
    name                       = "ACR-With-Dashes"
    private_endpoint_subnet_id = "${var.sub}/Microsoft.Network/virtualNetworks/vnet/subnets/pe"
    private_dns_zone_id        = "${var.sub}/Microsoft.Network/privateDnsZones/privatelink.azurecr.io"
    log_analytics_workspace_id = "${var.sub}/Microsoft.OperationalInsights/workspaces/log"
  }

  expect_failures = [var.name]
}

run "keyvault_rbac_purge_protected_private" {
  command = plan
  module {
    source = "../../modules/keyvault"
  }

  variables {
    name                         = "kv-flagpost-prod-sk07"
    tenant_id                    = "22222222-2222-2222-2222-222222222222"
    private_endpoint_subnet_id   = "${var.sub}/Microsoft.Network/virtualNetworks/vnet/subnets/pe"
    private_dns_zone_id          = "${var.sub}/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
    log_analytics_workspace_id   = "${var.sub}/Microsoft.OperationalInsights/workspaces/log"
    secret_officer_principal_ids = ["11111111-1111-1111-1111-111111111111"]
  }

  assert {
    condition     = azurerm_key_vault.this.rbac_authorization_enabled && azurerm_key_vault.this.purge_protection_enabled
    error_message = "Key Vault must use RBAC and purge protection."
  }

  assert {
    condition     = azurerm_key_vault.this.soft_delete_retention_days == 90 && azurerm_key_vault.this.public_network_access_enabled == false
    error_message = "Key Vault keeps 90-day soft delete and no public access."
  }

  assert {
    condition     = one(azurerm_key_vault.this.network_acls).default_action == "Deny"
    error_message = "Key Vault firewall must default to Deny."
  }

  assert {
    condition     = azurerm_role_assignment.secret_officers["11111111-1111-1111-1111-111111111111"].role_definition_name == "Key Vault Secrets Officer"
    error_message = "Admin group gets Secrets Officer (write), not Administrator."
  }

  assert {
    condition     = [for l in azurerm_monitor_diagnostic_setting.vault.enabled_log : l.category] == ["AuditEvent"]
    error_message = "Key Vault AuditEvent logs must go to Log Analytics."
  }
}

run "keyvault_rejects_short_soft_delete" {
  command = plan
  module {
    source = "../../modules/keyvault"
  }

  variables {
    name                       = "kv-flagpost-prod-sk07"
    tenant_id                  = "22222222-2222-2222-2222-222222222222"
    private_endpoint_subnet_id = "${var.sub}/Microsoft.Network/virtualNetworks/vnet/subnets/pe"
    private_dns_zone_id        = "${var.sub}/Microsoft.Network/privateDnsZones/privatelink.azurecr.io"
    log_analytics_workspace_id = "${var.sub}/Microsoft.OperationalInsights/workspaces/log"
    soft_delete_retention_days = 3
  }

  expect_failures = [var.soft_delete_retention_days]
}

run "aks_private_entra_workload_identity" {
  command = plan
  module {
    source = "../../modules/aks"
  }

  variables {
    name                       = "flagpost-prod"
    tenant_id                  = "22222222-2222-2222-2222-222222222222"
    vnet_id                    = "${var.sub}/Microsoft.Network/virtualNetworks/vnet"
    nodes_subnet_id            = "${var.sub}/Microsoft.Network/virtualNetworks/vnet/subnets/aks"
    admin_group_object_ids     = ["11111111-1111-1111-1111-111111111111"]
    log_analytics_workspace_id = "${var.sub}/Microsoft.OperationalInsights/workspaces/log"
    acr_id                     = "${var.sub}/Microsoft.ContainerRegistry/registries/acrflagpostprodsk07"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.private_cluster_enabled && azurerm_kubernetes_cluster.this.private_cluster_public_fqdn_enabled == false
    error_message = "API server must be private with no public FQDN."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.local_account_disabled && one(azurerm_kubernetes_cluster.this.azure_active_directory_role_based_access_control).azure_rbac_enabled
    error_message = "Only Entra ID identities with Azure RBAC may access the cluster."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.oidc_issuer_enabled && azurerm_kubernetes_cluster.this.workload_identity_enabled
    error_message = "OIDC issuer and Workload Identity must be on."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.azure_policy_enabled && one(azurerm_kubernetes_cluster.this.key_vault_secrets_provider).secret_rotation_enabled
    error_message = "Azure Policy and Key Vault CSI rotation must be on."
  }

  assert {
    condition     = one(azurerm_kubernetes_cluster.this.network_profile).network_policy == "cilium" && one(azurerm_kubernetes_cluster.this.network_profile).outbound_type == "userAssignedNATGateway"
    error_message = "Cilium network policy and NAT gateway egress expected."
  }

  assert {
    condition     = one(azurerm_kubernetes_cluster.this.default_node_pool).only_critical_addons_enabled && one(azurerm_kubernetes_cluster.this.default_node_pool).host_encryption_enabled
    error_message = "System pool is tainted for critical add-ons and uses host encryption."
  }

  assert {
    condition     = length(one(azurerm_kubernetes_cluster.this.default_node_pool).zones) == 3 && length(azurerm_kubernetes_cluster_node_pool.apps.zones) == 3
    error_message = "Both pools must span three zones."
  }

  assert {
    condition     = azurerm_role_assignment.kubelet_acr_pull.role_definition_name == "AcrPull"
    error_message = "Kubelet identity pulls from ACR with AcrPull only."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.run_command_enabled == false && azurerm_kubernetes_cluster.this.sku_tier == "Standard"
    error_message = "Run command is off and the uptime-SLA tier is used."
  }
}

run "aks_rejects_single_node_apps_pool" {
  command = plan
  module {
    source = "../../modules/aks"
  }

  variables {
    name                       = "flagpost-prod"
    tenant_id                  = "22222222-2222-2222-2222-222222222222"
    vnet_id                    = "${var.sub}/Microsoft.Network/virtualNetworks/vnet"
    nodes_subnet_id            = "${var.sub}/Microsoft.Network/virtualNetworks/vnet/subnets/aks"
    admin_group_object_ids     = ["11111111-1111-1111-1111-111111111111"]
    log_analytics_workspace_id = "${var.sub}/Microsoft.OperationalInsights/workspaces/log"
    acr_id                     = "${var.sub}/Microsoft.ContainerRegistry/registries/acrflagpostprodsk07"
    apps_pool                  = { min = 1, max = 3 }
  }

  expect_failures = [var.apps_pool]
}

run "workload_identity_federation" {
  command = plan
  module {
    source = "../../modules/workload-identity"
  }

  variables {
    name            = "id-flagpost-prod-workload"
    oidc_issuer_url = "https://centralindia.oic.prod-aks.azure.com/tenant/issuer/"
    namespace       = "flagpost"
    service_account = "flagpost"
    key_vault_id    = "${var.sub}/Microsoft.KeyVault/vaults/kv-flagpost-prod-sk07"
  }

  assert {
    condition     = azurerm_federated_identity_credential.this.subject == "system:serviceaccount:flagpost:flagpost"
    error_message = "Federated subject must pin one namespace/service account."
  }

  assert {
    condition     = azurerm_federated_identity_credential.this.audience == tolist(["api://AzureADTokenExchange"])
    error_message = "Audience must be the AKS token exchange audience."
  }

  assert {
    condition     = azurerm_role_assignment.secrets_user.role_definition_name == "Key Vault Secrets User"
    error_message = "Workload gets read-only secret access."
  }
}

run "monitoring_without_public_url" {
  command = plan
  module {
    source = "../../modules/monitoring"
  }

  variables {
    name        = "flagpost-prod"
    alert_email = "platform-oncall@example.com"
  }

  assert {
    condition     = length(azurerm_application_insights_standard_web_test.health) == 0 && length(azurerm_monitor_metric_alert.availability) == 0
    error_message = "No availability test while the app is internal-only."
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.local_authentication_enabled == false && azurerm_application_insights.this.local_authentication_enabled == false
    error_message = "Monitoring ingestion must use Entra ID auth only."
  }
}

run "monitoring_with_availability_test" {
  command = plan
  module {
    source = "../../modules/monitoring"
  }

  variables {
    name                  = "flagpost-prod"
    alert_email           = "platform-oncall@example.com"
    availability_test_url = "https://flagpost.example.com/healthz"
  }

  assert {
    condition     = length(azurerm_application_insights_standard_web_test.health) == 1 && length(azurerm_monitor_metric_alert.availability) == 1
    error_message = "A public URL enables the synthetic test and its alert."
  }
}

run "monitoring_rejects_http_url_and_bad_email" {
  command = plan
  module {
    source = "../../modules/monitoring"
  }

  variables {
    name                  = "flagpost-prod"
    alert_email           = "not-an-email"
    availability_test_url = "http://flagpost.example.com/healthz"
  }

  expect_failures = [var.alert_email, var.availability_test_url]
}
