output "server_id" {
  description = "ID del servidor SQL secundario. Consumido en la Etapa 2 (failover group) — no usado en esta etapa."
  value       = azurerm_mssql_server.secondary.id
}

output "server_name" {
  description = "Nombre del servidor SQL secundario, requerido por azurerm_mssql_failover_group en la Etapa 2."
  value       = azurerm_mssql_server.secondary.name
}
