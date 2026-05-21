include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

locals {
  env_vars = read_terragrunt_config(find_in_parent_folders("terragrunt.hcl", "dev/terragrunt.hcl"))
  env      = local.env_vars.locals.environment
  tags     = local.env_vars.locals.common_tags
}

terraform {
  source = "../../../modules/networking"
}

inputs = {
  resource_group_name = "rg-devtest-lab-interviews"
  location            = "japaneast"
  environment         = "dev"
  vnet_a_name         = "vnet-lab-interviews"
  vnet_a_cidr         = "10.0.0.0/16"
  vnet_b_cidr         = "10.1.0.0/16"
  storage_subnet_cidr = "10.1.0.0/24"
  tags = {
    Owner        = "fabio"
    Environment  = "dev"
    CostCenter   = "interview-lab"
    AssignmentId = "fabio-001"
  }
}
