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

variable "retention_in_days" {
  description = "Retención de logs en Log Analytics. 30 días en dev, >= 5 años (1826 días) en prod para la bitácora inmutable exigida por cumplimiento (sección 1.5)."
  type        = number
}

variable "monitored_resource_ids" {
  description = "Mapa nombre_recurso -> ID, de todos los recursos de las capas 1 y 2 a los que se les configura diagnostic settings hacia este workspace."
  type        = map(string)
  default     = {}
}

variable "alert_email" {
  description = "Correo del equipo SRE/DevOps que recibe alertas del grupo de acción."
  type        = string
}

variable "tags" {
  description = "Etiquetas obligatorias."
  type        = map(string)
}
