output "server_id" {
  description = "ID del servidor Azure SQL, consumido por security-keyvault y observability."
  value       = azurerm_mssql_server.this.id
}

output "database_id" {
  description = "ID de la base de datos, consumido por observability para diagnostic settings."
  value       = azurerm_mssql_database.core.id
}

output "fully_qualified_domain_name" {
  description = "FQDN privado del servidor, resuelto internamente vía el Private Endpoint."
  value       = azurerm_mssql_server.this.fully_qualified_domain_name
}

output "database_name" {
  description = "Nombre de la base de datos, consumido por compute-serverless (app setting SqlServer__Database) para que ValidatePayment/ProcessPayment abran conexión sin hardcodear el nombre en el código de la función."
  value       = azurerm_mssql_database.core.name
}
