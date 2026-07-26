output "vnet_id" {
  description = "ID de la VNet spoke, consumido por el módulo de observabilidad para diagnostic settings."
  value       = azurerm_virtual_network.spoke.id
}

output "subnet_ids" {
  description = "Mapa nombre_subred -> ID de subred. Contrato consumido por compute-appservice y data-sql."
  value       = { for k, s in azurerm_subnet.this : k => s.id }
}

output "nsg_ids" {
  description = "Mapa nombre_subred -> ID del NSG asociado, consumido por observability para diagnostic settings."
  value       = { for k, n in azurerm_network_security_group.this : k => n.id }
}
