# ---------------------------------------------------------------------------
# keyvault/main.tf
# Creates:
#   • Application Key Vault with RBAC authorization model
#   • Random 32-char API key stored under secret name "api-key"
#   • Grants id-manager "Key Vault Secrets Officer" (provisioning-time only,
#     via access-manager / azurerm.rbac) so Terraform can write the secret
#
# Runtime access (vm-mi → Key Vault Secrets User) lives in the rbac module.
# ---------------------------------------------------------------------------

data "azurerm_client_config" "current" {}

resource "random_id" "kv_suffix" {
  byte_length = 3
}

resource "random_password" "api_key" {
  length  = 32
  special = false # alphanumeric only — safe in HTTP headers
}

locals {
  kv_name = "kv-fabio-${var.environment}-${random_id.kv_suffix.hex}"
}

resource "azurerm_key_vault" "app" {
  name                       = local.kv_name
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = var.tenant_id
  sku_name                   = "standard" # standard is sufficient; premium (HSM) not needed
  enable_rbac_authorization  = true       # use RBAC, not legacy access policies
  purge_protection_enabled   = false      # lab env: allow immediate purge after delete
  soft_delete_retention_days = 7          # minimum value; keeps cost/complexity low
  tags                       = var.tags
}

# ── Provisioning-time role assignment ────────────────────────────────────────
# id-manager needs "Key Vault Secrets Officer" to write the api-key secret.
# This is performed by access-manager (azurerm.rbac) and is a provisioning-only
# assignment — it is NOT used by the running API.
resource "azurerm_role_assignment" "id_manager_kv_officer" {
  provider             = azurerm.rbac
  scope                = azurerm_key_vault.app.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = var.id_manager_principal_id
  description          = "Provisioning-time: allows Terraform (id-manager) to write the api-key secret"
}

# ── API key secret ────────────────────────────────────────────────────────────
resource "azurerm_key_vault_secret" "api_key" {
  name         = "api-key"
  value        = random_password.api_key.result
  key_vault_id = azurerm_key_vault.app.id

  # Must wait for the role assignment to propagate before writing the secret
  depends_on = [azurerm_role_assignment.id_manager_kv_officer]
}
