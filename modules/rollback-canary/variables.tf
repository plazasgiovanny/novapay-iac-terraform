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

variable "subscription_id" {
  description = "ID de la suscripción — inyectado como app setting para que run.ps1 construya la URL ARM del backend pool sin depender de metadata implícita."
  type        = string
}

variable "apim_name" {
  description = "Nombre de la instancia de APIM (apim-novapay-{env}) cuyo backend pool administra esta función."
  type        = string
}

variable "backend_pool_name" {
  description = "Nombre del backend pool ponderado (pool-novapay-pagos-{env}, salida de api-management)."
  type        = string
}

variable "apim_id" {
  description = "ID ARM de la instancia de APIM, para acotar el rol API Management Service Contributor (ADR-03 §2.6) — nunca sobre el resource group completo."
  type        = string
}

variable "action_group_alert_scopes" {
  description = "IDs de los Log Analytics Workspace/Application Insights sobre los que corre la alerta de error rate en rampa (scopes del azurerm_monitor_scheduled_query_rules_alert_v2)."
  type        = list(string)
}

variable "role_names_in_ramp" {
  description = "Nombres exactos de los dos Function Apps de pagos (AppRoleName en Application Insights), para la query KQL de la alerta de error rate en rampa."
  type        = list(string)
}

variable "tags" {
  description = "Etiquetas obligatorias."
  type        = map(string)
}
