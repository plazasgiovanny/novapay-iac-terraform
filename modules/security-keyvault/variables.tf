variable "environment" {
  description = "Nombre del ambiente (dev, prod)."
  type        = string
}

variable "location" {
  description = "Región de Azure donde se aprovisiona Key Vault."
  type        = string
}

variable "resource_group_name" {
  description = "Grupo de recursos del ambiente."
  type        = string
}

variable "tenant_id" {
  description = "ID del tenant de Microsoft Entra ID."
  type        = string
}

variable "data_subnet_id" {
  description = "ID de la subred de datos, usada para el Private Endpoint de Key Vault."
  type        = string
}

variable "tags" {
  description = "Etiquetas obligatorias."
  type        = map(string)
}

variable "name_suffix" {
  description = "Sufijo opcional para el nombre del Key Vault. Los nombres de Key Vault son únicos globalmente en Azure y, con purge_protection_enabled = true, un vault destruido queda en soft-delete sin poder purgarse hasta que expire su retención — este sufijo permite reusar el módulo con un nombre distinto mientras tanto, en vez de bloquear el despliegue."
  type        = string
  default     = ""
}
