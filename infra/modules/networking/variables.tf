variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "environment" {
  type = string
}

variable "vnet_a_name" {
  type    = string
  default = "vnet-lab-interviews"
}

variable "vnet_a_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "vnet_b_cidr" {
  type    = string
  default = "10.1.0.0/16"
}

variable "storage_subnet_cidr" {
  type    = string
  default = "10.1.0.0/24"
}

variable "tags" {
  type    = map(string)
  default = {}
}
