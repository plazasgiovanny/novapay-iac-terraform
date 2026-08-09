# Módulo: messaging-servicebus
# Cola de mensajería asíncrona del flujo de confirmación y notificación
# de pagos (Entrega 2, documento de diseño sección 2 y 4). Desacopla
# la función ValidarPago (publica) de ProcesarPago (consume), con
# reintentos automáticos y dead-lettering nativos del propio servicio.

resource "azurerm_servicebus_namespace" "this" {
  name                = "sb-novapay-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"

  # Sin claves compartidas: la autenticación es exclusivamente por
  # Azure AD/RBAC (documento de diseño, sección 5 y 7 — misma
  # jerarquía "eliminar el secreto" ya aplicada en toda la Entrega 1).
  local_auth_enabled = false

  tags = var.tags
}

# Cola dedicada del evento PagoValidado. La deduplicación nativa usa
# el MessageId del mensaje (igual al transactionId, por contrato con
# Johan) como primera capa de idempotencia — la segunda capa es la
# restricción UNIQUE de la tabla NotificacionesTransaccionales en
# Azure SQL (documento de diseño, sección 6).
resource "azurerm_servicebus_queue" "pagos_pendientes" {
  name         = "sbq-novapay-pagos-pendientes-${var.environment}"
  namespace_id = azurerm_servicebus_namespace.this.id

  requires_duplicate_detection            = true
  duplicate_detection_history_time_window = "PT10M"
  lock_duration                           = "PT1M"

  # Tras 5 intentos fallidos de ProcesarPago, el mensaje se mueve a la
  # dead-letter queue nativa de la cola en vez de perderse o
  # reintentar indefinidamente (documento de diseño, sección 2, paso 6).
  max_delivery_count                   = var.max_delivery_count
  dead_lettering_on_message_expiration = true
}
