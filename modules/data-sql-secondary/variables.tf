variable "environment" {
  description = "Nombre del ambiente (dev, prod)."
  type        = string
}

variable "location" {
  description = "Región secundaria de Azure, distinta de la región del servidor primario (modules/data-sql). Sin precedente empírico en esta suscripción — es el propio propósito de esta etapa validarla."
  type        = string
}

variable "resource_group_name" {
  description = "Grupo de recursos del ambiente (el mismo del resto del diseño — el aislamiento de esta etapa es funcional, no de resource group)."
  type        = string
}

variable "data_subnet_id" {
  description = "ID de la subred de datos de la región PRIMARIA (contrato recibido del módulo networking, mismo que usa modules/data-sql) — el Private Endpoint del servidor secundario vive ahí, no en una VNet nueva en la región secundaria (Azure SQL soporta Private Endpoint cross-región, verificado antes de asumirlo)."
  type        = string
}

variable "primary_location" {
  description = "Región PRIMARIA (var.location del ambiente, no de este módulo) — el recurso Private Endpoint en sí debe estar en la misma región que la VNet/subred que lo contiene (azurerm_private_endpoint.secondary), aunque el servidor SQL al que apunta esté en la región secundaria (var.location de este módulo). Distinta de var.location a propósito — confundirlas causó un apply real fallido (400 InvalidResourceReference), ver HALLAZGO REAL en main.tf."
  type        = string
}

variable "private_dns_zone_id" {
  description = "ID de la zona DNS privada privatelink.database.windows.net ya creada por modules/data-sql (salida private_dns_zone_id) — se reutiliza la MISMA zona, no una nueva, para que el listener del failover group resuelva correctamente hacia el lado vigente tras una conmutación."
  type        = string
}

variable "aad_admin_login" {
  description = "Mismo administrador de Microsoft Entra ID que el servidor primario (modules/data-sql)."
  type        = string
}

variable "aad_admin_object_id" {
  description = "Object ID de Microsoft Entra ID del administrador anterior."
  type        = string
}

variable "tenant_id" {
  description = "ID del tenant de Microsoft Entra ID."
  type        = string
}

variable "tags" {
  description = "Etiquetas obligatorias."
  type        = map(string)
}
