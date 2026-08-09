variable "environment" {
  description = "Nombre del ambiente (dev, prod). Se usa como sufijo de nombres de recursos."
  type        = string
}

variable "location" {
  description = "Región de Azure donde se aprovisiona la red spoke."
  type        = string
}

variable "resource_group_name" {
  description = "Nombre del grupo de recursos donde vive la red spoke de este ambiente."
  type        = string
}

variable "vnet_cidr" {
  description = "Bloque CIDR de la VNet spoke."
  type        = string
}

variable "hub_vnet_id" {
  description = "ID de la VNet hub, usada para establecer el peering hub-spoke."
  type        = string
}

variable "subnets" {
  description = <<-EOT
    Mapa de subredes a crear. La clave es el nombre lógico de la subred
    (aplicacion, integracion, datos, publica) y el valor define su CIDR,
    las reglas de entrada explícitamente permitidas (deny-by-default), y
    opcionalmente una delegación de servicio (p. ej. Microsoft.Web/serverFarms
    para integración VNet regional de un plan de Consumo de Azure Functions).
    `delegation = null` (el default) deja la subred sin delegar, igual que
    hoy — una subred delegada queda exclusiva para ese tipo de servicio.
  EOT
  type = map(object({
    cidr = string
    allowed_rules = list(object({
      name     = string
      priority = number
      protocol = string
      port     = string
      source   = string
    }))
    delegation = optional(object({
      name                    = string
      service_delegation_name = string
    }))
  }))
}

variable "tags" {
  description = "Etiquetas obligatorias aplicadas a todos los recursos de este módulo."
  type        = map(string)
}
