output "vm_mi_reader_assignment_id" {
  value = azurerm_role_assignment.vm_mi_reader_rg.id
}

output "vm_mi_kv_secrets_user_assignment_id" {
  value = azurerm_role_assignment.vm_mi_kv_secrets_user.id
}

output "vm_mi_storage_reader_assignment_id" {
  value = azurerm_role_assignment.vm_mi_storage_reader.id
}
