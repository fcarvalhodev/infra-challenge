locals {
  environment   = "prod"
  cost_center   = "FILL_ME"   # TODO: replace with value from assignment email
  assignment_id = "FILL_ME"   # TODO: replace with value from assignment email

  common_tags = {
    Owner        = "fabio"
    Environment  = local.environment
    CostCenter   = local.cost_center
    AssignmentId = local.assignment_id
  }
}
