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
  description = "Retención de logs en Log Analytics. 30 días en dev, >= 5 años (1826 días) en prod para la bitácora inmutable exigida por cumplimiento normativo."
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

variable "apim_backend_pool_id" {
  description = "ID ARM completo del backend pool ponderado de APIM (salida backend_pool_id de api-management), consumido por el panel 1 del Workbook (peso actual, fuente ARM en tiempo real — ADR-07 U4, deliberadamente independiente del evento PesoActualizado para no depender de que el job de CD lo emita con éxito). Null mientras wire_backend = false en el módulo api-management."
  type        = string
  default     = null
}

variable "novapay_functions_sp_principal_id" {
  description = "Object ID del service principal OIDC de novapay-functions (app registration creada fuera de Terraform, Bloque 3.1), recibe 'Monitoring Metrics Publisher' acotado a la Data Collection Rule del evento PesoActualizado (ADR-07 U4). Vacío por defecto (nadie recibe el rol)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "tags" {
  description = "Etiquetas obligatorias."
  type        = map(string)
}
