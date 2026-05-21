include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

dependency "networking" {
  config_path = "../networking"
  mock_outputs = {
    storage_subnet_id   = "/subscriptions/mock/resourceGroups/mock/providers/Microsoft.Network/virtualNetworks/mock/subnets/mock"
    private_dns_zone_id = "/subscriptions/mock/resourceGroups/mock/providers/Microsoft.Network/privateDnsZones/mock"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init", "run-all init"]
}

terraform {
  source = "../../../modules/storage"
}

inputs = {
  resource_group_name = "rg-devtest-lab-interviews"
  location            = "japaneast"
  environment         = "dev"
  replication_type    = "LRS"  # dev: LRS (cheapest); prod uses ZRS
  storage_subnet_id   = dependency.networking.outputs.storage_subnet_id
  private_dns_zone_id = dependency.networking.outputs.private_dns_zone_id
  tags = {
    Owner        = "fabio"
    Environment  = "dev"
    CostCenter   = "interview-lab"
    AssignmentId = "fabio-001"
  }
}
