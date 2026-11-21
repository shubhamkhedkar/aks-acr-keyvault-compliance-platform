# Root-module plan tests against a mocked azurerm provider.
# No credentials, no API calls, nothing is created.

mock_provider "azurerm" {
  override_during = plan

  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id       = "22222222-2222-2222-2222-222222222222"
      subscription_id = "00000000-0000-0000-0000-000000000000"
      object_id       = "33333333-3333-3333-3333-333333333333"
    }
  }

}

variables {
  subscription_id            = "00000000-0000-0000-0000-000000000000"
  unique_suffix              = "sk07"
  aks_admin_group_object_ids = ["11111111-1111-1111-1111-111111111111"]
  alert_email                = "platform-oncall@example.com"
}

run "resource_group_naming_tags_and_lock" {
  command = plan

  assert {
    condition     = azurerm_resource_group.this.name == "rg-flagpost-prod" && azurerm_resource_group.this.location == "centralindia"
    error_message = "Resource group must be rg-<workload>-<env> in centralindia by default."
  }

  assert {
    condition     = azurerm_resource_group.this.tags["managed_by"] == "terraform" && azurerm_resource_group.this.tags["environment"] == "prod"
    error_message = "Default tags must be applied."
  }

  assert {
    condition     = azurerm_management_lock.rg.lock_level == "CanNotDelete"
    error_message = "Production resource group must carry a CanNotDelete lock."
  }
}

run "extra_tags_merge" {
  command = plan

  variables {
    tags = { cost_center = "cc-1234" }
  }

  assert {
    condition     = azurerm_resource_group.this.tags["cost_center"] == "cc-1234" && azurerm_resource_group.this.tags["workload"] == "flagpost"
    error_message = "Caller tags must merge with, not replace, the defaults."
  }
}

run "rejects_bad_suffix" {
  command = plan

  variables {
    unique_suffix = "Not_Valid!"
  }

  expect_failures = [var.unique_suffix]
}

run "rejects_bad_subscription_id" {
  command = plan

  variables {
    subscription_id = "my-subscription"
  }

  expect_failures = [var.subscription_id]
}

run "rejects_unknown_environment" {
  command = plan

  variables {
    environment = "qa"
  }

  expect_failures = [var.environment]
}

run "requires_an_admin_group" {
  command = plan

  variables {
    aks_admin_group_object_ids = []
  }

  expect_failures = [var.aks_admin_group_object_ids]
}

run "rejects_non_guid_admin_group" {
  command = plan

  variables {
    aks_admin_group_object_ids = ["platform-admins"]
  }

  expect_failures = [var.aks_admin_group_object_ids]
}

run "outputs_wire_through" {
  command = plan

  assert {
    condition     = output.resource_group_name == "rg-flagpost-prod" && output.tenant_id == "22222222-2222-2222-2222-222222222222"
    error_message = "Outputs must expose the resource group and tenant used by the SecretProviderClass."
  }
}
