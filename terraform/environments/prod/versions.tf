terraform {
  required_version = ">= 1.11.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.14"
    }
  }

  # Partial configuration: values live in backend.hcl (see backend.hcl.example) and
  # the state container is created once with scripts/bootstrap-tfstate.sh.
  backend "azurerm" {}
}
