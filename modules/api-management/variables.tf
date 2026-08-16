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
  description = "Límite de llamadas por minuto por subscription (protección ante abuso) — política 'rate-limit', la única disponible en el tier Consumption de APIM."
  type        = number
  default     = 60
}

variable "tags" {
  description = "Etiquetas obligatorias."
  type        = map(string)
}

variable "wire_backend" {
  description = <<-EOT
    Si es false, omite el named_value de host key, el backend hacia el
    Function App y la policy que lo referencia. Necesario para el apply
    inicial de bootstrap: el data source de host keys requiere que el
    Function App ya tenga código desplegado y su runtime esté sano, algo
    que no existe todavía en un ambiente recién creado (el código se
    despliega por un pipeline aparte, ver ADR-01/02). Poner en true y
    reaplicar una vez confirmado el primer despliegue de código exitoso.
  EOT
  type        = bool
  default     = true
}
