# dev/terragrunt.hcl — common inputs shared by all dev modules
# This file is NOT a leaf; it's included by leaf modules via find_in_parent_folders()
# to pick up the root remote_state and provider generate blocks.
# Leaf modules re-include the root with an explicit path.
locals {
  environment  = "dev"
  cost_center  = "FILL_ME"   # TODO: replace with value from assignment email
  assignment_id = "FILL_ME"  # TODO: replace with value from assignment email

  common_tags = {
    Owner        = "fabio"
    Environment  = local.environment
    CostCenter   = local.cost_center
    AssignmentId = local.assignment_id
  }
}
