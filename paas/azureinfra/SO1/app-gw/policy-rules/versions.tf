terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tfstate-mgmt-uks"
    storage_account_name = "tfstatepredmgmt"
    container_name       = "terraform-backend"
    key                  = ""
  }
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "3.31.0"
    }
    template = {
      source  = "hashicorp/template"
      version = "2.2.0"
    }
  }
}

provider "azurerm" {
  # Default
  subscription_id = var.infra_sub_id
  features {}
}
provider "azurerm" {
  # Management / Shared Services
  alias           = "mgmt"
  subscription_id = var.mgmt_sub_id
  features {}
}

provider "azurerm" {
  # Infrasturcture / Spoke
  alias           = "infra"
  subscription_id = var.infra_sub_id
  features {}
}
