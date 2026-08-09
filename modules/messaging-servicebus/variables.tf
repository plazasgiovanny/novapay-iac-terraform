variable "environment" {
  description = "Nombre del ambiente (dev, prod). Se usa como sufijo de nombres de recursos."
  type        = string
}

variable "location" {
  description = "Región de Azure donde se aprovisiona el namespace de Service Bus."
  type        = string
}

variable "resource_group_name" {
  description = "Nombre del grupo de recursos donde vive el namespace de este ambiente."
  type        = string
}

variable "max_delivery_count" {
  description = "Número de intentos de entrega antes de mover el mensaje a la dead-letter queue."
  type        = number
  default     = 5
}

variable "action_group_id" {
  description = "ID del grupo de acción de Azure Monitor (salida de observability), usado por la alerta de mensajes en la dead-letter queue."
  type        = string
}

variable "tags" {
  description = "Etiquetas obligatorias aplicadas a todos los recursos de este módulo."
  type        = map(string)
}
