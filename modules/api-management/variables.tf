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

variable "publisher_name" {
  description = "Nombre del publicador de la instancia de APIM (requerido por Azure, no es una preferencia de diseño)."
  type        = string
}

variable "publisher_email" {
  description = "Correo del publicador de la instancia de APIM (requerido por Azure)."
  type        = string
}

variable "function_app_name" {
  description = "Nombre del Function App backend (salida de compute-serverless), usado para leer sus host keys."
  type        = string
}

variable "function_app_id" {
  description = "ID del Function App backend (salida de compute-serverless). Se usa solo como disparador de dependencia (depends_on) para que el data source de host keys se resuelva después de crear el Function App."
  type        = string
}

variable "function_default_hostname" {
  description = "Hostname público del Function App backend (salida de compute-serverless), usado para construir la URL del backend de APIM."
  type        = string
}

variable "rate_limit_calls_per_minute" {
  description = "Límite de llamadas por minuto por subscription key (protección ante abuso)."
  type        = number
  default     = 60
}

variable "quota_calls_per_day" {
  description = "Cuota de llamadas por día por subscription key."
  type        = number
  default     = 5000
}

variable "tags" {
  description = "Etiquetas obligatorias."
  type        = map(string)
}
