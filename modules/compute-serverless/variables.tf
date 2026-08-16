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

variable "instance_suffix" {
  description = "Sufijo de nombre de esta instancia física: \"\" para la estable (func-novapay-pagos-{env}), \"-canary\" para la candidata (func-novapay-pagos-canary-{env}) — ADR-03 U4. Debe coincidir literalmente con el sufijo usado en la Subscription de Service Bus correspondiente, porque sourceInstance compara contra WEBSITE_SITE_NAME (= el nombre real de este recurso)."
  type        = string
  default     = ""
}

variable "storage_account_name" {
  description = "Nombre de la cuenta de almacenamiento dedicada de esta instancia. Explícito (no derivado de instance_suffix dentro del módulo) porque el límite de 24 caracteres de Storage Account exige un nombre abreviado propio para la instancia canary, no una simple concatenación de sufijo."
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

variable "servicebus_topic_name" {
  description = "Nombre del Topic sbt-novapay-pagos-pendientes (salida de messaging-servicebus), inyectado como app setting ServiceBusTopicName. Mismo Topic para ambas instancias — el aislamiento ocurre en la Subscription, no en el Topic."
  type        = string
}

variable "servicebus_subscription_name" {
  description = "Nombre de la Subscription propia de esta instancia (salida de messaging-servicebus, mapa por clave estable/canary), inyectado como app setting ServiceBusSubscriptionName. Específico de cada instancia — nunca la Subscription del otro slot."
  type        = string
}

variable "apim_service_tag" {
  description = "Service tag de Azure usado en ip_restriction del site_config, para que el Function App solo acepte tráfico del gateway de APIM (nunca directo de Internet) — el function key es defensa en profundidad, no la única barrera."
  type        = string
  default     = "ApiManagement"
}

variable "sql_server_fqdn" {
  description = "FQDN del servidor Azure SQL (salida de data-sql), inyectado como app setting SqlServer__Fqdn."
  type        = string
}

variable "sql_database_name" {
  description = "Nombre de la base de datos Azure SQL (salida de data-sql), inyectado como app setting SqlServer__Database."
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
