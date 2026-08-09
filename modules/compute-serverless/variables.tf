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

variable "integracion_subnet_id" {
  description = "ID de la subred integracion, delegada a Microsoft.Web/serverFarms (contrato recibido del módulo networking)."
  type        = string
}

variable "function_plan_sku" {
  description = "SKU del Service Plan del Function App. Y1 = Consumo (escala a cero). EP1 = Elastic Premium, alternativa si la región elegida en el despliegue real no soporta integración VNet regional en Consumo Linux (documento de diseño, sección 9)."
  type        = string
  default     = "Y1"
}

variable "servicebus_namespace_fqdn" {
  description = "FQDN del namespace de Service Bus (salida de messaging-servicebus), usado para la conexión por identidad administrada."
  type        = string
}

variable "appinsights_connection_string" {
  description = "Connection string de Application Insights (salida de observability), usado para trazas distribuidas."
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "Etiquetas obligatorias."
  type        = map(string)
}
