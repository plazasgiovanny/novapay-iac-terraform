output "namespace_id" {
  description = "ID del namespace de Service Bus, consumido por observability (diagnostic settings)."
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

output "topic_id" {
  description = "ID del Topic sbt-novapay-pagos-pendientes, usado como scope de los role assignments Data Sender en la raíz (ambas instancias envían al mismo Topic)."
  value       = azurerm_servicebus_topic.pagos_pendientes.id
}

output "topic_name" {
  description = "Nombre del Topic sbt-novapay-pagos-pendientes, consumido por compute-serverless para el app setting ServiceBusTopicName."
  value       = azurerm_servicebus_topic.pagos_pendientes.name
}

output "subscription_ids" {
  description = "IDs de las Subscriptions del Topic, por clave de instancia (estable/canary) — usados como scope de los role assignments Data Receiver en la raíz. Cada instancia recibe acceso únicamente a la suya, nunca a la del otro slot."
  value       = { for k, v in azurerm_servicebus_subscription.func : k => v.id }
}

output "subscription_names" {
  description = "Nombres de las Subscriptions del Topic, por clave de instancia (estable/canary) — consumidos por compute-serverless para el app setting ServiceBusSubscriptionName."
  value       = { for k, v in azurerm_servicebus_subscription.func : k => v.name }
}
