variable "vm_mi_principal_id" {
  type        = string
  description = "Object ID of the VM system-assigned managed identity (vm-mi)"
}

variable "resource_group_id" {
  type        = string
  description = "Resource ID of the provided resource group"
}

variable "key_vault_id" {
  type        = string
  description = "Resource ID of the application Key Vault"
}

variable "storage_account_id" {
  type        = string
  description = "Resource ID of the application Storage Account"
}
