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

variable "max_instance_count" {
  description = "Techo de instancias del Function App, reconciliado contra el límite real de concurrent workers de la Azure SQL Database reutilizada. Distinto por ambiente porque el SKU de SQL también lo es — sin default deliberado, para forzar una decisión explícita por ambiente en dev.tfvars/prod.tfvars."
  type        = number
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
