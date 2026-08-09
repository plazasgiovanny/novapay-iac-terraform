output "principal_id" {
  description = "Principal ID de la identidad SystemAssigned del Function App — compartida por ValidarPago y ProcesarPago (documento de diseño, sección 5). Usado en la raíz para los role assignments de Service Bus y en el script SQL para el usuario contenido AAD."
  value       = azurerm_linux_function_app.this.identity[0].principal_id
}

output "default_hostname" {
  description = "Hostname público del Function App, consumido por api-management como backend."
  value       = azurerm_linux_function_app.this.default_hostname
}

output "function_app_id" {
  description = "ID del Function App, consumido por observability (diagnostic settings) y api-management (data source de host keys)."
  value       = azurerm_linux_function_app.this.id
}

output "function_app_name" {
  description = "Nombre del Function App."
  value       = azurerm_linux_function_app.this.name
}
