# Módulo `observability`

Log Analytics Workspace centralizado, Application Insights (workspace-based) y grupo de acción de alertas. Recibe, vía `monitored_resource_ids`, los IDs de recursos de las capas 1 y 2 y les configura *diagnostic settings* genéricos (todos los logs y métricas) sin que este módulo necesite conocer el tipo de cada recurso.

## Entradas principales
`monitored_resource_ids` (mapa nombre -> ID, provisto por la composición raíz), `retention_in_days` (30 en dev, ≥ 1826 en prod).

## Salidas
`appinsights_id` (se agrega también a `monitored_resource_ids` en la raíz), `appinsights_connection_string` y `appinsights_instrumentation_key` (ambas `sensitive`, consumidas por `compute-serverless`).

## Application Insights

En modo **workspace-based** (`workspace_id = azurerm_log_analytics_workspace.this.id`), reutilizando el mismo workspace en vez de crear un almacén de logs paralelo — trazas distribuidas y correlation ID de extremo a extremo para el flujo serverless.

Capa 3 (observabilidad): se conecta transversalmente a las capas 1 y 2, nunca al revés.
