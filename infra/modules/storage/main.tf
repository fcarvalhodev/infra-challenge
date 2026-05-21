resource "random_id" "storage_suffix" {
  byte_length = 4
}

locals {
  storage_account_name = "stfabio${var.environment}${random_id.storage_suffix.hex}"
}

resource "azurerm_storage_account" "main" {
  name                     = local.storage_account_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = var.replication_type
  account_kind             = "StorageV2"

  public_network_access_enabled   = false
  allow_nested_items_to_be_public = false
  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = true

  blob_properties {
    delete_retention_policy {
      days = 7
    }
  }

  tags = var.tags
}

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

  private_dns_zone_group {
    name                 = "dns-group-blob-${var.environment}"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }
}

# Create container and upload ping.txt using account key via az CLI.
# azurerm v4 dropped storage_use_azuread=false; id-manager has no data-plane
# role so we fall back to key-based auth. The VM reaches the SA over the
# private endpoint (VNet A peered to VNet B, DNS zone linked to both).
resource "null_resource" "healthcheck_blob" {
  triggers = {
    storage_account_id = azurerm_storage_account.main.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "Waiting for private endpoint DNS to propagate..."
      sleep 30
      KEY=$(az storage account keys list \
        --account-name ${azurerm_storage_account.main.name} \
        --resource-group ${var.resource_group_name} \
        --query '[0].value' -o tsv)
      az storage container create \
        --name healthcheck \
        --account-name ${azurerm_storage_account.main.name} \
        --account-key "$KEY"
      echo "pong" | az storage blob upload \
        --account-name ${azurerm_storage_account.main.name} \
        --container-name healthcheck \
        --name ping.txt \
        --data "pong" \
        --account-key "$KEY" \
        --overwrite
      echo "healthcheck/ping.txt uploaded successfully"
    EOT
  }

  depends_on = [azurerm_private_endpoint.blob]
}
