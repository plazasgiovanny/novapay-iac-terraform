output "log_analytics_workspace_id" {
  description = "ID del workspace centralizado de Log Analytics."
  value       = azurerm_log_analytics_workspace.this.id
}

output "action_group_id" {
  description = "ID del grupo de acción usado por las reglas de alerta."
  value       = azurerm_monitor_action_group.sre.id
}

output "appinsights_id" {
  description = "ID de Application Insights, consumido por este mismo módulo (diagnostic settings, vía monitored_resource_ids en la raíz)."
  value       = azurerm_application_insights.this.id
}

output "appinsights_connection_string" {
  description = "Connection string de Application Insights, consumido por compute-serverless (APPLICATIONINSIGHTS_CONNECTION_STRING)."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}

output "appinsights_instrumentation_key" {
  description = "Instrumentation key de Application Insights, expuesta por compatibilidad con SDKs legacy que aún no soportan connection string."
  value       = azurerm_application_insights.this.instrumentation_key
  sensitive   = true
}
