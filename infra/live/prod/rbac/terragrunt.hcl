include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

dependency "keyvault" {
  config_path = "../keyvault"
  mock_outputs = {
    key_vault_id = "/subscriptions/mock/resourceGroups/mock/providers/Microsoft.KeyVault/vaults/mock"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "storage" {
  config_path = "../storage"
  mock_outputs = {
    storage_account_id = "/subscriptions/mock/resourceGroups/mock/providers/Microsoft.Storage/storageAccounts/mock"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

terraform {
  source = "../../../modules/rbac"
}

inputs = {
  vm_mi_principal_id = "fc77b65c-f439-44d6-b674-9beb9a5ca81a"
  resource_group_id  = "/subscriptions/128100a8-3b59-40af-882c-7c6c91a676a2/resourceGroups/rg-devtest-lab-interviews"
  key_vault_id       = dependency.keyvault.outputs.key_vault_id
  storage_account_id = dependency.storage.outputs.storage_account_id
}
