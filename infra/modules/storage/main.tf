# ---------------------------------------------------------------------------
# storage/main.tf
# Creates:
#   • Storage account — public blob access disabled; LRS (dev) or ZRS (prod)
#   • Container "healthcheck" and blob "ping.txt" for /storage/ping endpoint
#   • Private endpoint in VNet B storage subnet
#   • Private DNS zone group wires the PE into the blob private DNS zone
#
# Auth for provisioning: azurerm_storage_blob uses account-key auth
# (storage_use_azuread = false in provider) so id-manager's Contributor role
# on the RG is sufficient — no extra data-plane RBAC assignment required.
# ---------------------------------------------------------------------------

resource "random_id" "storage_suffix" {
  byte_length = 4
}

locals {
  # 3-24 chars, lowercase alphanumeric only
  storage_account_name = "stfabio${var.environment}${random_id.storage_suffix.hex}"
}

resource "azurerm_storage_account" "main" {
  name                     = local.storage_account_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = var.replication_type # LRS (dev) or ZRS (prod)
  account_kind             = "StorageV2"

  # Disable all public blob access — only private endpoint is valid
  public_network_access_enabled   = false
  allow_nested_items_to_be_public = false

  # Require HTTPS; TLS 1.2 minimum
  https_traffic_only_enabled = true
  min_tls_version           = "TLS1_2"

  blob_properties {
    delete_retention_policy {
      days = 7
    }
  }

  tags = var.tags
}

resource "azurerm_storage_container" "healthcheck" {
  name                  = "healthcheck"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

resource "azurerm_storage_blob" "ping" {
  name                   = "ping.txt"
  storage_account_name   = azurerm_storage_account.main.name
  storage_container_name = azurerm_storage_container.healthcheck.name
  type                   = "Block"
  source_content         = "pong"
}

# ── Private Endpoint ─────────────────────────────────────────────────────────
resource "azurerm_private_endpoint" "blob" {
  name                = "pe-storage-fabio-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.storage_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-blob-fabio-${var.environment}"
    private_connection_resource_id = azurerm_storage_account.main.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  # Wire the PE NIC into the private DNS zone so the FQDN resolves to a private IP
  private_dns_zone_group {
    name                 = "dns-group-blob-${var.environment}"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }
}
