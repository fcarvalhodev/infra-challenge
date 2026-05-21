# ---------------------------------------------------------------------------
# networking/main.tf
# Creates:
#   • VNet B (10.1.0.0/16) with a dedicated storage subnet
#   • NSG on the storage subnet — no 0.0.0.0/0 ingress, only VNet-A traffic
#   • Bidirectional VNet peering A <-> B
#   • Private DNS zone privatelink.blob.core.windows.net linked to both VNets
# ---------------------------------------------------------------------------

data "azurerm_virtual_network" "vnet_a" {
  name                = var.vnet_a_name
  resource_group_name = var.resource_group_name
}

# ── VNet B ──────────────────────────────────────────────────────────────────
resource "azurerm_virtual_network" "vnet_b" {
  name                = "vnet-b-fabio-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.vnet_b_cidr]
  tags                = var.tags
}

# ── Storage subnet NSG ──────────────────────────────────────────────────────
resource "azurerm_network_security_group" "storage" {
  name                = "nsg-storage-fabio-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  # Allow HTTPS from VNet A (bootstrap VM) to reach the private endpoint
  security_rule {
    name                       = "Allow-VnetA-Inbound-HTTPS"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = var.vnet_a_cidr
    source_port_range          = "*"
    destination_address_prefix = "*"
    destination_port_range     = "443"
  }

  # Allow intra-VNet-B traffic (health probes, etc.)
  security_rule {
    name                       = "Allow-VnetB-Inbound"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = "VirtualNetwork"
    source_port_range          = "*"
    destination_address_prefix = "*"
    destination_port_range     = "*"
  }

  # Deny everything else inbound — no 0.0.0.0/0 ingress
  security_rule {
    name                       = "Deny-All-Inbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_address_prefix      = "*"
    source_port_range          = "*"
    destination_address_prefix = "*"
    destination_port_range     = "*"
  }

  # Allow outbound to VNet A (return traffic, DNS)
  security_rule {
    name                       = "Allow-VnetA-Outbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = "*"
    source_port_range          = "*"
    destination_address_prefix = var.vnet_a_cidr
    destination_port_range     = "*"
  }

  # Allow outbound within VNet B
  security_rule {
    name                       = "Allow-VnetB-Outbound"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = "*"
    source_port_range          = "*"
    destination_address_prefix = "VirtualNetwork"
    destination_port_range     = "*"
  }

  # Deny everything else outbound
  security_rule {
    name                       = "Deny-All-Outbound"
    priority                   = 4000
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "*"
    source_address_prefix      = "*"
    source_port_range          = "*"
    destination_address_prefix = "*"
    destination_port_range     = "*"
  }
}

# ── Storage subnet ───────────────────────────────────────────────────────────
resource "azurerm_subnet" "storage" {
  name                 = "snet-storage-fabio-${var.environment}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet_b.name
  address_prefixes     = [var.storage_subnet_cidr]

  # Required to enforce NSG on PE subnets (Azure default is to bypass NSG on PE subnets)
  private_endpoint_network_policies = "Enabled"
}

resource "azurerm_subnet_network_security_group_association" "storage" {
  subnet_id                 = azurerm_subnet.storage.id
  network_security_group_id = azurerm_network_security_group.storage.id
}

# ── VNet Peering A -> B ──────────────────────────────────────────────────────
resource "azurerm_virtual_network_peering" "a_to_b" {
  name                         = "peer-vneta-to-vnetb-${var.environment}"
  resource_group_name          = var.resource_group_name
  virtual_network_name         = data.azurerm_virtual_network.vnet_a.name
  remote_virtual_network_id    = azurerm_virtual_network.vnet_b.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

# ── VNet Peering B -> A ──────────────────────────────────────────────────────
resource "azurerm_virtual_network_peering" "b_to_a" {
  name                         = "peer-vnetb-to-vneta-${var.environment}"
  resource_group_name          = var.resource_group_name
  virtual_network_name         = azurerm_virtual_network.vnet_b.name
  remote_virtual_network_id    = data.azurerm_virtual_network.vnet_a.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

# ── Private DNS Zone for Blob Storage ────────────────────────────────────────
resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob_to_vnet_a" {
  name                  = "dns-link-vneta-${var.environment}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = data.azurerm_virtual_network.vnet_a.id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob_to_vnet_b" {
  name                  = "dns-link-vnetb-${var.environment}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = azurerm_virtual_network.vnet_b.id
  registration_enabled  = false
  tags                  = var.tags
}
