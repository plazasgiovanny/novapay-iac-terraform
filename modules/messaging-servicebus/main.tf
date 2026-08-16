# Módulo: messaging-servicebus
# Topic de mensajería asíncrona del flujo de confirmación y notificación
# de pagos, con una Subscription por instancia física del Function App
# serverless (estable/canary — ver compute-serverless). Reemplaza la
# cola única de Entrega 2 (ADR-03, U4): con dos instancias competiendo
# por la misma cola, el % de canary no protegía la mitad asíncrona del
# flujo. Cada Subscription filtra por la propiedad sourceInstance
# (estampada por ValidatePayment desde WEBSITE_SITE_NAME), así que cada
# ProcessPayment consume únicamente los mensajes publicados por su
# propia instancia.

resource "azurerm_servicebus_namespace" "this" {
  name                = "sb-novapay-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard" # Topics/Subscriptions con filtro SQL: soportado desde Standard, no requiere Premium.

  # Sin claves compartidas: la autenticación es exclusivamente por
  # Azure AD/RBAC, mismo criterio que el resto del repositorio.
  local_auth_enabled = false

  tags = var.tags
}

# Una instancia por clave: "" = estable (func-novapay-pagos-{env}), "-canary"
# = candidata (func-novapay-pagos-canary-{env}). Mismo sufijo que usa
# compute-serverless (var.instance_suffix) — deben coincidir literalmente,
# porque sourceInstance se compara contra el nombre real del recurso.
locals {
  instance_suffixes = {
    estable = ""
    canary  = "-canary"
  }
}

# Topic dedicado del evento PaymentValidated. La deduplicación nativa usa
# el MessageId del mensaje (igual al transactionId del contrato del
# evento) como primera capa de idempotencia — la segunda capa es la
# restricción UNIQUE de la tabla TransactionalNotifications en
# Azure SQL. La deduplicación es una propiedad del Topic (punto de
# ingreso), no de cada Subscription.
resource "azurerm_servicebus_topic" "pagos_pendientes" {
  name         = "sbt-novapay-pagos-pendientes-${var.environment}"
  namespace_id = azurerm_servicebus_namespace.this.id

  requires_duplicate_detection            = true
  duplicate_detection_history_time_window = "PT10M"
}

# Cola de aterrizaje del dead-letter de cada Subscription (una por
# instancia). No es un mecanismo nuevo de negocio: es el vehículo que
# permite alertar por instancia, ver azurerm_monitor_metric_alert.dlq
# abajo — Azure Monitor no expone la dimensión EntityName a nivel de
# Subscription individual (solo Queue/Topic completo), así que reenviar
# el dead-letter a una cola propia por instancia es la forma real de
# lograr una alerta que sí distinga cuál instancia se quedó varada.
resource "azurerm_servicebus_queue" "dlq_landing" {
  for_each     = local.instance_suffixes
  name         = "sbq-novapay-pagos${each.value}-dlq-${var.environment}"
  namespace_id = azurerm_servicebus_namespace.this.id
}

# Tras 5 intentos fallidos de ProcessPayment, el mensaje se reenvía a la
# cola de aterrizaje de esta misma instancia en vez de perderse o
# reintentar indefinidamente.
resource "azurerm_servicebus_subscription" "func" {
  for_each      = local.instance_suffixes
  name          = "sub-func-novapay-pagos${each.value}-${var.environment}"
  topic_id      = azurerm_servicebus_topic.pagos_pendientes.id
  lock_duration = "PT1M"

  max_delivery_count                   = var.max_delivery_count
  dead_lettering_on_message_expiration = true
  forward_dead_lettered_messages_to    = azurerm_servicebus_queue.dlq_landing[each.key].name
}

# Regla SqlFilter sobre sourceInstance, con nombre propio (no "$Default").
#
# HALLAZGO REAL (apply real, 2026-08-16): declarar este recurso con
# name = "$Default" — para sobrescribir la regla que Azure crea
# automáticamente al crear la Subscription — dispara un bug real y
# 100% reproducible del provider azurerm 4.81.0 tanto en create como en
# update: "Provider produced inconsistent result after apply: Root
# object was present, but now absent". La causa más probable: esta
# misma versión del provider (milestone confirmado,
# hashicorp/terraform-provider-azurerm#32452) introdujo el feature flag
# servicebus.auto_delete_subscription_default_rule, que borra la regla
# $Default del lado de Azure justo después de crear la Subscription —
# gestionar un recurso Terraform con ese mismo nombre reservado corre
# contra esa carrera.
#
# Solución real: activar ese feature flag (envs/*/versions.tf) para que
# Azure limpie la $Default automática, y declarar esta regla con un
# nombre propio (nunca "$Default") — evita la colisión de raíz en vez
# de pelear contra ella. Sigue siendo la única regla activa de la
# Subscription (la automática ya no existe), así que el aislamiento por
# sourceInstance queda igual de completo que con el diseño original.
resource "azurerm_servicebus_subscription_rule" "func" {
  for_each        = local.instance_suffixes
  name            = "source-instance-filter"
  subscription_id = azurerm_servicebus_subscription.func[each.key].id
  filter_type     = "SqlFilter"

  sql_filter = "sourceInstance = 'func-novapay-pagos${each.value}-${var.environment}'"
}

# Alerta real por instancia: sin esto, un pago que agotó sus reintentos
# en la Subscription de una instancia podría quedar silenciosamente
# varado sin que nadie note cuál de las dos instancias fue. Se escucha
# sobre la cola de aterrizaje de cada instancia (ver comentario en
# azurerm_servicebus_queue.dlq_landing) con un filtro por EntityName —
# el mismo mecanismo que ya usaba la alerta original de la cola única,
# ahora aplicado dos veces, una por instancia.
resource "azurerm_monitor_metric_alert" "dlq" {
  for_each            = local.instance_suffixes
  name                = "alert-dlq-sub-func-novapay-pagos${each.value}-${var.environment}"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_servicebus_namespace.this.id]
  description         = "Se dispara cuando llega al menos un mensaje muerto de sub-func-novapay-pagos${each.value}-${var.environment} a su cola de aterrizaje — un pago de esa instancia agotó sus reintentos y necesita revisión manual."
  frequency           = "PT1M"
  window_size         = "PT5M"
  severity            = 1

  criteria {
    metric_namespace = "Microsoft.ServiceBus/namespaces"
    metric_name      = "ActiveMessages"
    aggregation      = "Maximum"
    operator         = "GreaterThan"
    threshold        = 0

    dimension {
      name     = "EntityName"
      operator = "Include"
      values   = [azurerm_servicebus_queue.dlq_landing[each.key].name]
    }
  }

  action {
    action_group_id = var.action_group_id
  }

  tags = var.tags
}
