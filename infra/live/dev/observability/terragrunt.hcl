include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependency "keyvault" {
  config_path = "../keyvault"
  mock_outputs = {
    key_vault_id = "/subscriptions/mock/resourceGroups/mock/providers/Microsoft.KeyVault/vaults/mock"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init", "run-all init"]
}

dependency "storage" {
  config_path = "../storage"
  mock_outputs = {
    storage_account_id = "/subscriptions/mock/resourceGroups/mock/providers/Microsoft.Storage/storageAccounts/mock"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init", "run-all init"]
}

terraform {
  source = "../../../modules/observability"
}

inputs = {
  resource_group_name = "rg-devtest-lab-interviews"
  location            = "japaneast"
  environment         = "dev"
  key_vault_id        = dependency.keyvault.outputs.key_vault_id
  storage_account_id  = dependency.storage.outputs.storage_account_id
  daily_quota_gb      = 0.5   # dev: 500MB/day cap — sufficient for lab diagnostics
  alert_severity      = 2     # dev: Warning
  tags = {
    Owner        = "fabio"
    Environment  = "dev"
    CostCenter   = "interview-lab"
    AssignmentId = "fabio-001"
  }
}
