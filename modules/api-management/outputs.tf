output "id" {
  description = "ID de la instancia de APIM, consumido por observability (diagnostic settings)."
  value       = azurerm_api_management.this.id
}

output "gateway_url" {
  description = "URL pública del gateway de APIM — punto de entrada real de esta superficie mientras Azure Front Door no esté provisionado."
  value       = azurerm_api_management.this.gateway_url
}

output "subscription_primary_key" {
  description = "Subscription key de la suscripción por defecto — enviada como header Ocp-Apim-Subscription-Key."
  value       = azurerm_api_management_subscription.default.primary_key
  sensitive   = true
}

output "backend_pool_id" {
  description = "ID ARM del backend pool ponderado (azapi_resource, gateado por wire_backend), consumido por observability para el panel 1 del Workbook (peso actual, fuente ARM en tiempo real, ADR-07 U4). Null mientras wire_backend = false — el panel de peso no tiene sentido antes de que el pool exista."
  value       = var.wire_backend ? azapi_resource.backend_pool[0].id : null
}
