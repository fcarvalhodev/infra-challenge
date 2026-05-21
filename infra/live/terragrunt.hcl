locals {
  subscription_id = "128100a8-3b59-40af-882c-7c6c91a676a2"
  tenant_id       = "764704c3-6b1b-4f4e-8c84-0535d564ec86"
  location        = "japaneast"
  resource_group  = "rg-devtest-lab-interviews"

  # Provisioning identity (Contributor on RG, no RBAC write)
  id_manager_client_id = "297f855a-c1c3-4a2a-94c8-04e9b4557c62"
  # RBAC assignment identity (RBAC Admin on RG, no resource write)
  access_manager_client_id = "1c984177-182e-4d71-8fd0-99989661976e"

  # Derive environment name from the directory path: live/dev/... -> "dev"
  env = element(compact(split("/", path_relative_to_include())), 0)
}

# ---------------------------------------------------------------------------
# Remote state — backend already exists, only the key differs per module/env
# ---------------------------------------------------------------------------
remote_state {
  backend = "azurerm"
  config = {
    subscription_id      = local.subscription_id
    resource_group_name  = local.resource_group
    storage_account_name = "stinterviewtfstate001"
    container_name       = "tfstate"
    key                  = "${path_relative_to_include()}/terraform.tfstate"
  }
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

# ---------------------------------------------------------------------------
# Provider injection
# Every leaf module gets both providers.
# Modules that create resources use the default `azurerm` (id-manager).
# Modules that create role assignments use `azurerm.rbac` (access-manager).
# storage_use_azuread = false on the default provider so azurerm_storage_blob
# falls back to account-key auth (Contributor can list keys); no extra RBAC needed.
# ---------------------------------------------------------------------------
generate "providers" {
  path      = "providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    terraform {
      required_version = ">= 1.5"
      required_providers {
        azurerm = {
          source  = "hashicorp/azurerm"
          version = "~> 4.0"
        }
        random = {
          source  = "hashicorp/random"
          version = "~> 3.6"
        }
      }
    }

    # id-manager: creates/updates/deletes resources; cannot assign RBAC
    provider "azurerm" {
      features {}
      subscription_id     = "${local.subscription_id}"
      tenant_id           = "${local.tenant_id}"
      client_id           = "${local.id_manager_client_id}"
      use_msi             = true
      storage_use_azuread = false
    }

    # access-manager: creates/deletes role assignments; cannot mutate resources
    provider "azurerm" {
      alias           = "rbac"
      features {}
      subscription_id = "${local.subscription_id}"
      tenant_id       = "${local.tenant_id}"
      client_id       = "${local.access_manager_client_id}"
      use_msi         = true
    }

    provider "random" {}
  EOF
}
