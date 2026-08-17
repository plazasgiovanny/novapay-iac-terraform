output "function_app_id" {
  description = "ID del Function App de rollback-canary, consumido por observability (diagnostic settings)."
  value       = azurerm_linux_function_app.this.id
}

output "action_group_id" {
  description = "ID del Action Group de rollback, por si otra alerta necesita referenciarlo en el futuro."
  value       = azurerm_monitor_action_group.this.id
}
