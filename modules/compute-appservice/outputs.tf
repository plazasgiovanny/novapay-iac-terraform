output "api_principal_id" {
  description = "Object ID de la identidad administrada del App Service. Se usa para autorizarla en Key Vault y Azure SQL (mínimo privilegio, sección 4.3)."
  value       = azurerm_linux_web_app.api.identity[0].principal_id
}

output "functions_principal_id" {
  description = "Object ID de la identidad administrada del Function App."
  value       = azurerm_linux_function_app.async_workers.identity[0].principal_id
}

output "api_default_hostname" {
  description = "Hostname por defecto del App Service, consumido por Application Gateway como backend."
  value       = azurerm_linux_web_app.api.default_hostname
}
