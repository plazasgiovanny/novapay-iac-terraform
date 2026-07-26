variable "environment" {
  description = "Nombre del ambiente (dev, prod)."
  type        = string
}

variable "location" {
  description = "Región de Azure."
  type        = string
}

variable "resource_group_name" {
  description = "Grupo de recursos del ambiente."
  type        = string
}

variable "app_subnet_id" {
  description = "ID de la subred de aplicación (contrato recibido del módulo networking)."
  type        = string
}

variable "sku_name" {
  description = "SKU del App Service Plan. Difiere entre dev y prod (sección 3.4)."
  type        = string
}

variable "worker_count" {
  description = "Número mínimo de instancias del plan. 1 en dev, 3 en prod para sostener el autoescalado 5-8x (sección 1.5 de requerimientos no funcionales)."
  type        = number
}

variable "key_vault_uri" {
  description = "URI del Key Vault desde donde la aplicación resuelve sus secretos en tiempo de ejecución (sección 4.5)."
  type        = string
}

variable "functions_storage_account_name" {
  description = "Nombre de la cuenta de almacenamiento requerida por Azure Functions (runtime), no de datos de negocio."
  type        = string
}

variable "functions_storage_account_id" {
  description = "ID de recurso de esa cuenta de almacenamiento, usado para asignar el rol mínimo necesario a la identidad administrada del Function App."
  type        = string
}

variable "tags" {
  description = "Etiquetas obligatorias."
  type        = map(string)
}
