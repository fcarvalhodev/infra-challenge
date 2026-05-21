variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "environment" { type = string }
variable "storage_subnet_id" { type = string }
variable "private_dns_zone_id" { type = string }

variable "replication_type" {
  type        = string
  default     = "LRS"
  description = "LRS for dev, ZRS for prod"
}

variable "tags" {
  type    = map(string)
  default = {}
}
