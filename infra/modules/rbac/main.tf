# ---------------------------------------------------------------------------
# rbac/main.tf
# ALL resources in this module use provider = azurerm.rbac (access-manager).
# access-manager has "Role Based Access Control Administrator" on the RG.
# No resource creation here — pure role assignments.
#
# Required assignments per challenge spec:
#   vm-mi  Reader                   → provided resource group
#   vm-mi  Key Vault Secrets User   → application Key Vault
#   vm-mi  Storage Blob Data Reader → application Storage Account
# ---------------------------------------------------------------------------

# Reader on the provided resource group
# Allows vm-mi to list resources via ARM API (used by /resources endpoint)
resource "azurerm_role_assignment" "vm_mi_reader_rg" {
  provider             = azurerm.rbac
  scope                = var.resource_group_id
  role_definition_name = "Reader"
  principal_id         = var.vm_mi_principal_id
  description          = "vm-mi: list resources in the provided resource group for /resources endpoint"
}

# Key Vault Secrets User on the application Key Vault
# Allows vm-mi to GET secrets (not list, not set) — minimum permission for api-key fetch
resource "azurerm_role_assignment" "vm_mi_kv_secrets_user" {
  provider             = azurerm.rbac
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.vm_mi_principal_id
  description          = "vm-mi: read api-key secret from application Key Vault at startup"
}

# Storage Blob Data Reader on the application Storage Account
# Allows vm-mi to download ping.txt for /storage/ping endpoint
resource "azurerm_role_assignment" "vm_mi_storage_reader" {
  provider             = azurerm.rbac
  scope                = var.storage_account_id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = var.vm_mi_principal_id
  description          = "vm-mi: read ping.txt blob from healthcheck container for /storage/ping"
}
