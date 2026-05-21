include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../modules/keyvault"
}

inputs = {
  resource_group_name     = "rg-devtest-lab-interviews"
  location                = "japaneast"
  environment             = "dev"
  tenant_id               = "764704c3-6b1b-4f4e-8c84-0535d564ec86"
  # id-manager principal ID — needs Secrets Officer at provisioning time
  id_manager_principal_id = "bc771b3f-bd20-404b-ac9c-7a0d1a5601da"
  tags = {
    Owner        = "fabio"
    Environment  = "dev"
    CostCenter   = "interview-lab"
    AssignmentId = "fabio-001"
  }
}
