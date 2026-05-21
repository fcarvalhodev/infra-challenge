variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "environment" { type = string }
variable "tenant_id" { type = string }

variable "id_manager_principal_id" {
  type        = string
  description = "Object ID of id-manager; needs Secrets Officer at provisioning time"
}

variable "tags" {
  type    = map(string)
  default = {}
}
