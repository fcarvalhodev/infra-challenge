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
  source = "../../../modules/observability"
}

inputs = {
  resource_group_name = "rg-devtest-lab-interviews"
  location            = "japaneast"
  environment         = "prod"
  key_vault_id        = dependency.keyvault.outputs.key_vault_id
  storage_account_id  = dependency.storage.outputs.storage_account_id
  daily_quota_gb      = 1     # prod: 1GB/day (still capped, higher than dev)
  alert_severity      = 1     # prod: Error severity
  tags = {
    Owner        = "fabio"
    Environment  = "prod"
    CostCenter   = "FILL_ME"
    AssignmentId = "FILL_ME"
  }
}
