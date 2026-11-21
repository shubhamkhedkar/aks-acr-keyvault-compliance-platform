provider "azurerm" {
  # Credentials come from the Azure Pipelines service connection (workload identity
  # federation, ARM_USE_OIDC=true) - no client secret is stored anywhere.
  subscription_id     = var.subscription_id
  storage_use_azuread = true

  features {
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }

    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
}
