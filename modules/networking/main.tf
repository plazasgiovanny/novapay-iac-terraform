# Módulo: networking
# Aprovisiona la VNet spoke de NovaPay, sus subredes y el NSG de cada
# una en modo "deny-by-default": solo se permite explícitamente el
# tráfico declarado en var.subnets[*].allowed_rules.

resource "azurerm_virtual_network" "spoke" {
  name                = "vnet-novapay-spoke-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.vnet_cidr]
  tags                = var.tags
}

# El mapa de subredes es el contrato de entrada del módulo: quien lo
# consume decide cuántas subredes crear y con qué propósito, sin
# tocar la lógica interna.
resource "azurerm_subnet" "this" {
  for_each             = var.subnets
  name                 = "snet-${each.key}-${var.environment}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [each.value.cidr]

  # Delegación opcional: convierte la subred en exclusiva para el
  # servicio delegado (p. ej. Microsoft.Web/serverFarms, requerido por
  # la integración VNet regional de un Function App).
  dynamic "delegation" {
    for_each = each.value.delegation != null ? [each.value.delegation] : []
    content {
      name = delegation.value.name
      service_delegation {
        name    = delegation.value.service_delegation_name
        actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
      }
    }
  }
}

# Cada subred nace con un NSG propio en modo deny-by-default: el motor
# de Azure deniega implícitamente todo lo no declarado explícitamente
# en las reglas dinámicas de abajo.
resource "azurerm_network_security_group" "this" {
  for_each            = var.subnets
  name                = "nsg-${each.key}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  dynamic "security_rule" {
    for_each = each.value.allowed_rules
    content {
      name                       = security_rule.value.name
      priority                   = security_rule.value.priority
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = security_rule.value.protocol
      source_port_range          = "*"
      destination_port_range     = security_rule.value.port
      source_address_prefix      = security_rule.value.source
      destination_address_prefix = each.value.cidr
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "this" {
  for_each                  = var.subnets
  subnet_id                 = azurerm_subnet.this[each.key].id
  network_security_group_id = azurerm_network_security_group.this[each.key].id
}

# Peering hacia la VNet hub: habilita el acceso administrativo vía
# Azure Bastion y la inspección de tráfico norte-sur por Azure
# Firewall, sin exponer la spoke directamente a Internet.
resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                      = "peer-spoke-to-hub-${var.environment}"
  resource_group_name       = var.resource_group_name
  virtual_network_name      = azurerm_virtual_network.spoke.name
  remote_virtual_network_id = var.hub_vnet_id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}
