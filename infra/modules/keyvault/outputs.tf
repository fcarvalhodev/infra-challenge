output "key_vault_id" {
  value = azurerm_key_vault.app.id
}

output "key_vault_uri" {
  value = azurerm_key_vault.app.vault_uri
}

output "key_vault_name" {
  value = azurerm_key_vault.app.name
}

# Exposed only for local testing convenience (make test-api).
# Value is stored in Terraform state which is encrypted at rest in Azure Storage.
output "api_key_value" {
  value     = random_password.api_key.result
  sensitive = true
}
