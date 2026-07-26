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

variable "data_subnet_id" {
  description = "ID de la subred de datos (contrato recibido del módulo networking)."
  type        = string
}

variable "sku_name" {
  description = "SKU de Azure SQL Database. GP_Gen5_2 en dev, BC_Gen5_4 (Business Critical, zone-redundant) en prod (sección 3.4)."
  type        = string
}

variable "zone_redundant" {
  description = "Redundancia zonal. false en dev, true en prod para sostener el SLA >= 99.95% (sección 1.5)."
  type        = bool
}

variable "aad_admin_login" {
  description = "Nombre del grupo o identidad de Microsoft Entra ID designado como administrador de Azure SQL. Reemplaza la autenticación SQL con usuario/contraseña por defecto (sección 4.5)."
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
