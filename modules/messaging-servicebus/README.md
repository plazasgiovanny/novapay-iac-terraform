# Módulo `messaging-servicebus`

Aprovisiona el namespace de Azure Service Bus (Standard) y la cola `sbq-novapay-pagos-pendientes` que desacopla las funciones `ValidatePayment` y `ProcessPayment` del flujo de confirmación y notificación de pagos.

## Entradas principales
- `environment`, `location`, `resource_group_name`, `max_delivery_count` (default 5), `action_group_id` (de `observability`, usado por la alerta de DLQ), `tags`.

## Salidas
- `namespace_id`: consumido por `observability` (diagnostic settings) y por los `azurerm_role_assignment` declarados en la raíz.
- `namespace_fqdn`: consumido por `compute-serverless` para el app setting de conexión por identidad administrada (sin clave compartida).
- `queue_id` / `queue_name`: scope exacto de los roles `Azure Service Bus Data Sender` / `Data Receiver` asignados en la raíz a la identidad de `func-novapay-pagos-${env}`.

## Decisiones de diseño
- **`local_auth_enabled = false`**: la única forma de autenticarse contra este namespace es Azure AD/RBAC. No hay claves compartidas (SAS) que rotar ni custodiar.
- **Sin Private Endpoint**: el tier Standard de Service Bus no lo soporta (solo Premium). Limitación aceptada, mitigada por `local_auth_enabled = false`.
- **Deduplicación nativa (`requires_duplicate_detection`, ventana 10 min)** sobre el `MessageId` del mensaje (igual al `transactionId` del contrato del evento): primera capa de idempotencia, complementada por la restricción `UNIQUE` de la tabla `TransactionalNotifications` en Azure SQL (segunda capa, a nivel de persistencia).
- **Alerta real sobre la dead-letter queue** (`azurerm_monitor_metric_alert.dlq`): escucha la métrica `DeadletteredMessages` (namespace `Microsoft.ServiceBus/namespaces`, filtrada por `EntityName` a esta cola específica) y dispara sobre el `action_group` de `observability` en cuanto llega un solo mensaje muerto.

Depende de `observability` (action group para la alerta) — capa 2: plataforma de ejecución, mismo nivel que `compute-appservice` y `compute-serverless`.
