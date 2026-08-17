output "server_id" {
  description = "ID del servidor SQL secundario, consumido por el Auto-Failover Group (partner_server, envs/{prod,dev}/main.tf)."
  value       = azurerm_mssql_server.secondary.id
}

output "server_name" {
  description = "Nombre del servidor SQL secundario."
  value       = azurerm_mssql_server.secondary.name
}
