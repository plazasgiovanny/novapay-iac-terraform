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
