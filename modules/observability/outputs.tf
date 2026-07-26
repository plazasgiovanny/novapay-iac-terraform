output "log_analytics_workspace_id" {
  description = "ID del workspace centralizado de Log Analytics."
  value       = azurerm_log_analytics_workspace.this.id
}

output "action_group_id" {
  description = "ID del grupo de acción usado por las reglas de alerta."
  value       = azurerm_monitor_action_group.sre.id
}
