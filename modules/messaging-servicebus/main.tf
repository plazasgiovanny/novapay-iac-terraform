# Módulo: messaging-servicebus
# Cola de mensajería asíncrona del flujo de confirmación y notificación
# de pagos. Desacopla la función ValidatePayment (publica) de
# ProcessPayment (consume), con reintentos automáticos y
# dead-lettering nativos del propio servicio.

resource "azurerm_servicebus_namespace" "this" {
  name                = "sb-novapay-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"

  # Sin claves compartidas: la autenticación es exclusivamente por
  # Azure AD/RBAC, mismo criterio que el resto del repositorio.
  local_auth_enabled = false

  tags = var.tags
}

# Cola dedicada del evento PaymentValidated. La deduplicación nativa usa
# el MessageId del mensaje (igual al transactionId del contrato del
# evento) como primera capa de idempotencia — la segunda capa es la
# restricción UNIQUE de la tabla TransactionalNotifications en
# Azure SQL.
resource "azurerm_servicebus_queue" "pagos_pendientes" {
  name         = "sbq-novapay-pagos-pendientes-${var.environment}"
  namespace_id = azurerm_servicebus_namespace.this.id

  requires_duplicate_detection            = true
  duplicate_detection_history_time_window = "PT10M"
  lock_duration                           = "PT1M"

  # Tras 5 intentos fallidos de ProcessPayment, el mensaje se mueve a la
  # dead-letter queue nativa de la cola en vez de perderse o
  # reintentar indefinidamente.
  max_delivery_count                   = var.max_delivery_count
  dead_lettering_on_message_expiration = true
}

# Alerta real: sin esto, un pago que agotó sus reintentos podría quedar
# silenciosamente varado en la dead-letter queue. Se escucha a nivel
# de namespace (no de la cola directamente: azurerm/Azure no soportan
# de forma confiable un scope de cola individual para este tipo de
# alerta) con un filtro por EntityName.
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
