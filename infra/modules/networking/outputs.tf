output "vnet_b_id" {
  value = azurerm_virtual_network.vnet_b.id
}

output "vnet_b_name" {
  value = azurerm_virtual_network.vnet_b.name
}

output "storage_subnet_id" {
  value = azurerm_subnet.storage.id
}

output "private_dns_zone_id" {
  value = azurerm_private_dns_zone.blob.id
}

output "private_dns_zone_name" {
  value = azurerm_private_dns_zone.blob.name
}
