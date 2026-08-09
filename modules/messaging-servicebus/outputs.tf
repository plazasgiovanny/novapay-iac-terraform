output "namespace_id" {
  description = "ID del namespace de Service Bus, consumido por observability (diagnostic settings) y por los role assignments de la raíz."
  value       = azurerm_servicebus_namespace.this.id
}

output "namespace_name" {
  description = "Nombre del namespace de Service Bus."
  value       = azurerm_servicebus_namespace.this.name
}

output "namespace_fqdn" {
  description = "FQDN del namespace (<namespace>.servicebus.windows.net), consumido por compute-serverless para el app setting serviceBusConnection__fullyQualifiedNamespace (sin cadena de conexión con clave)."
  value       = "${azurerm_servicebus_namespace.this.name}.servicebus.windows.net"
}

output "queue_id" {
  description = "ID de la cola sbq-novapay-pagos-pendientes, usado como scope de los role assignments Data Sender / Data Receiver en la raíz."
  value       = azurerm_servicebus_queue.pagos_pendientes.id
}

output "queue_name" {
  description = "Nombre de la cola sbq-novapay-pagos-pendientes."
  value       = azurerm_servicebus_queue.pagos_pendientes.name
}
