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

# Alerta real, no solo una frase en el documento de diseño: "alguien se
# entera" cuando un mensaje cae en la dead-letter queue. Sin esto, un
# pago que agotó sus reintentos podría quedar silenciosamente varado
# (documento de diseño, sección 2/11 — manejo de errores). Se escucha
# a nivel de namespace (no de la cola directamente: azurerm/Azure no
# soportan de forma confiable un scope de cola individual para este
# tipo de alerta) con un filtro por EntityName.
resource "azurerm_monitor_metric_alert" "dlq" {
  name                = "alert-dlq-sbq-novapay-pagos-pendientes-${var.environment}"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_servicebus_namespace.this.id]
  description         = "Se dispara cuando llega al menos un mensaje a la dead-letter queue de sbq-novapay-pagos-pendientes-${var.environment} — un pago agotó sus reintentos y necesita revisión manual."
  frequency           = "PT1M"
  window_size         = "PT5M"
  severity            = 1

  criteria {
    metric_namespace = "Microsoft.ServiceBus/namespaces"
    metric_name      = "DeadletteredMessages"
    aggregation      = "Maximum"
    operator         = "GreaterThan"
    threshold        = 0

    dimension {
      name     = "EntityName"
      operator = "Include"
      values   = [azurerm_servicebus_queue.pagos_pendientes.name]
    }
  }

  action {
    action_group_id = var.action_group_id
  }

  tags = var.tags
}
