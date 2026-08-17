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

output "verify_key" {
  description = "Secreto que gatea la ruta directa de verificación post-despliegue (bypassa el backend pool ponderado, ver HALLAZGO REAL en azurerm_api_management_api_policy.confirmaciones) — se configura como secret de GitHub (novapay-functions, APIM_VERIFY_KEY) para que cd.yml pueda verificar la instancia recién desplegada aunque esté al 0% de peso. Se lee directamente de random_id, no del Named Value: un Named Value marcado como secreto no garantiza devolver su valor vía GET en todos los providers/versiones, y random_id ya conoce el valor desde el propio state, sin depender de eso."
  value       = random_id.verify_key.hex
  sensitive   = true
}
