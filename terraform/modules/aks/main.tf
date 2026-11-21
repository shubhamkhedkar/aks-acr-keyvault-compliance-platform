# Private AKS: no public API endpoint, Entra ID + Azure RBAC only (local accounts off),
# OIDC issuer + Workload Identity, Azure Policy, Key Vault CSI driver with rotation,
# Container Insights, Defender, Azure CNI overlay with Cilium network policy,
# NAT-gateway egress, zone-spread autoscaling pools and planned maintenance windows.

resource "azurerm_user_assigned_identity" "control_plane" {
  name                = "id-${var.name}-aks-control-plane"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# Bring-your-own kubelet identity: its principal is known before the cluster exists,
# survives cluster rebuilds, and is the only identity that holds AcrPull.
resource "azurerm_user_assigned_identity" "kubelet" {
  name                = "id-${var.name}-aks-kubelet"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# The control plane must be allowed to assign the kubelet identity to the node VMSS.
resource "azurerm_role_assignment" "control_plane_kubelet_operator" {
  scope                = azurerm_user_assigned_identity.kubelet.id
  role_definition_name = "Managed Identity Operator"
  principal_id         = azurerm_user_assigned_identity.control_plane.principal_id
  principal_type       = "ServicePrincipal"
}

# Required for a custom VNet: the control plane manages NICs/LB rules in the node subnet.
resource "azurerm_role_assignment" "control_plane_network" {
  scope                = var.vnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.control_plane.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_kubernetes_cluster" "this" {
  #checkov:skip=CKV_AZURE_117:Nodes use ephemeral OS disks with encryption at host, so there is no managed OS disk for a Disk Encryption Set to cover; the workload is stateless (no persistent volumes).
  name                                = "aks-${var.name}"
  location                            = var.location
  resource_group_name                 = var.resource_group_name
  dns_prefix_private_cluster          = "aks-${var.name}"
  kubernetes_version                  = var.kubernetes_version
  sku_tier                            = "Standard"
  node_resource_group                 = "rg-${var.name}-aks-nodes"
  private_cluster_enabled             = true
  private_cluster_public_fqdn_enabled = false
  private_dns_zone_id                 = "System"
  local_account_disabled              = true
  role_based_access_control_enabled   = true
  oidc_issuer_enabled                 = true
  workload_identity_enabled           = true
  azure_policy_enabled                = true
  run_command_enabled                 = false
  image_cleaner_enabled               = true
  image_cleaner_interval_hours        = 48
  automatic_upgrade_channel           = "patch"
  node_os_upgrade_channel             = "NodeImage"
  cost_analysis_enabled               = true
  tags                                = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.control_plane.id]
  }

  kubelet_identity {
    client_id                 = azurerm_user_assigned_identity.kubelet.client_id
    object_id                 = azurerm_user_assigned_identity.kubelet.principal_id
    user_assigned_identity_id = azurerm_user_assigned_identity.kubelet.id
  }

  azure_active_directory_role_based_access_control {
    tenant_id              = var.tenant_id
    azure_rbac_enabled     = true
    admin_group_object_ids = var.admin_group_object_ids
  }

  default_node_pool {
    name                         = "system"
    vm_size                      = var.system_vm_size
    vnet_subnet_id               = var.nodes_subnet_id
    zones                        = var.zones
    auto_scaling_enabled         = true
    min_count                    = var.system_pool.min
    max_count                    = var.system_pool.max
    max_pods                     = 50
    os_sku                       = "AzureLinux"
    os_disk_type                 = "Ephemeral"
    os_disk_size_gb              = 128
    host_encryption_enabled      = true
    node_public_ip_enabled       = false
    only_critical_addons_enabled = true
    temporary_name_for_rotation  = "systemtmp"
    tags                         = var.tags

    upgrade_settings {
      max_surge                     = "33%"
      drain_timeout_in_minutes      = 30
      node_soak_duration_in_minutes = 5
    }
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    load_balancer_sku   = "standard"
    outbound_type       = "userAssignedNATGateway"
    pod_cidr            = var.pod_cidr
    service_cidr        = var.service_cidr
    dns_service_ip      = var.dns_service_ip
  }

  # Node auto-provisioning (Karpenter) stays off; the pools below are explicit and autoscaled.
  node_provisioning_profile {
    mode = "Manual"
  }

  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }

  oms_agent {
    log_analytics_workspace_id      = var.log_analytics_workspace_id
    msi_auth_for_monitoring_enabled = true
  }

  microsoft_defender {
    log_analytics_workspace_id = var.log_analytics_workspace_id
  }

  maintenance_window_auto_upgrade {
    frequency   = "Weekly"
    interval    = 1
    day_of_week = "Sunday"
    start_time  = "02:00"
    utc_offset  = "+05:30"
    duration    = 4
  }

  maintenance_window_node_os {
    frequency   = "Weekly"
    interval    = 1
    day_of_week = "Saturday"
    start_time  = "02:00"
    utc_offset  = "+05:30"
    duration    = 4
  }

  depends_on = [
    azurerm_role_assignment.control_plane_network,
    azurerm_role_assignment.control_plane_kubelet_operator,
  ]

  lifecycle {
    ignore_changes = [default_node_pool[0].node_count]
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "apps" {
  name                        = "apps"
  kubernetes_cluster_id       = azurerm_kubernetes_cluster.this.id
  mode                        = "User"
  vm_size                     = var.apps_vm_size
  vnet_subnet_id              = var.nodes_subnet_id
  zones                       = var.zones
  auto_scaling_enabled        = true
  min_count                   = var.apps_pool.min
  max_count                   = var.apps_pool.max
  max_pods                    = 50
  os_sku                      = "AzureLinux"
  os_disk_type                = "Ephemeral"
  os_disk_size_gb             = 128
  host_encryption_enabled     = true
  node_public_ip_enabled      = false
  temporary_name_for_rotation = "appstmp"
  node_labels                 = { "workload" = "apps" }
  tags                        = var.tags

  upgrade_settings {
    max_surge                     = "33%"
    drain_timeout_in_minutes      = 30
    node_soak_duration_in_minutes = 5
  }

  lifecycle {
    ignore_changes = [node_count]
  }
}

# Kubelet pulls from the private ACR with its managed identity - no image pull secrets.
resource "azurerm_role_assignment" "kubelet_acr_pull" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.kubelet.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_monitor_diagnostic_setting" "aks" {
  name                           = "diag-to-log-analytics"
  target_resource_id             = azurerm_kubernetes_cluster.this.id
  log_analytics_workspace_id     = var.log_analytics_workspace_id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category = "kube-audit-admin"
  }

  enabled_log {
    category = "guard"
  }

  enabled_log {
    category = "kube-apiserver"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
