include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

terraform {
  source = "../../../modules/networking"
}

inputs = {
  resource_group_name = "rg-devtest-lab-interviews"
  location            = "japaneast"
  environment         = "prod"
  vnet_a_name         = "vnet-lab-interviews"
  vnet_a_cidr         = "10.0.0.0/16"
  vnet_b_cidr         = "10.2.0.0/16"   # prod uses different /16 from dev
  storage_subnet_cidr = "10.2.0.0/24"
  tags = {
    Owner        = "fabio"
    Environment  = "prod"
    CostCenter   = "interview-lab"
    AssignmentId = "fabio-001"
  }
}
