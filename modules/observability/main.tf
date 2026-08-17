# Módulo: observability
# Centraliza métricas, logs y trazas de todas las capas anteriores,
# en lugar de dejarlas dispersas por cada servicio administrado.

resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-novapay-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.retention_in_days
  tags                = var.tags
}

# Application Insights workspace-based — trazas distribuidas y
# correlation ID de extremo a extremo (APIM -> eventos -> funciones ->
# BD). Se apoya en el mismo Log Analytics Workspace de arriba, sin
# duplicar el almacenamiento de logs.
resource "azurerm_application_insights" "this" {
  name                = "appi-novapay-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  workspace_id        = azurerm_log_analytics_workspace.this.id
  application_type    = "web"
  tags                = var.tags
}

resource "azurerm_monitor_action_group" "sre" {
  name                = "ag-novapay-sre-${var.environment}"
  resource_group_name = var.resource_group_name
  short_name          = "novapaysre"

  email_receiver {
    name          = "equipo-sre"
    email_address = var.alert_email
  }

  tags = var.tags
}

# Diagnostic settings genéricos: cada recurso de las capas 1 y 2 que
# se quiera observar se agrega a monitored_resource_ids sin tocar la
# lógica de este módulo, enviando todos sus logs y métricas al
# workspace centralizado.
resource "azurerm_monitor_diagnostic_setting" "this" {
  for_each                   = var.monitored_resource_ids
  name                       = "diag-${each.key}-${var.environment}"
  target_resource_id         = each.value
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

# --- Bloque 2d U4 (ADR-07): evento PesoActualizado ---
#
# Traza de cambios de peso del backend pool de APIM, emitida por el job
# de CD de novapay-functions (misma identidad OIDC que ya usa para
# desplegar) en cada PATCH de peso, vía Logs Ingestion API — mecanismo
# recomendado por Microsoft para ingestión desde automatización externa
# sin depender del SDK de Application Insights dentro del pipeline. 3
# recursos nuevos, en orden de dependencia real: DCE -> tabla -> DCR.
# Ver borradores/04_observabilidad_avanzada.md §4.6.

resource "azurerm_monitor_data_collection_endpoint" "pesoactualizado" {
  name                = "dce-novapay-pesoactualizado-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

# HALLAZGO REAL (verificado contra el tutorial oficial de Microsoft
# antes de codificar, no asumido): "A custom table must be created
# before you can send data to it" — la Logs Ingestion API NO crea la
# tabla automáticamente aunque el nombre termine en "_CL" y la DCR
# declare el esquema. azurerm no expone un recurso para declarar el
# esquema de una tabla personalizada nueva
# (azurerm_log_analytics_workspace_table solo administra retención/plan
# de tablas ya existentes, confirmado contra el schema real del
# provider instalado) — se usa azapi_resource contra la API real de
# Tablas (Microsoft.OperationalInsights/workspaces/tables), mismo
# patrón ya establecido para el backend pool de APIM
# (modules/api-management) ante una brecha equivalente del provider.
resource "azapi_resource" "pesoactualizado_table" {
  type      = "Microsoft.OperationalInsights/workspaces/tables@2022-10-01"
  name      = "PesoActualizado_CL"
  parent_id = azurerm_log_analytics_workspace.this.id

  body = {
    properties = {
      schema = {
        name = "PesoActualizado_CL"
        columns = [
          { name = "TimeGenerated", type = "datetime", description = "Momento del cambio de peso." },
          { name = "sourceInstance", type = "string", description = "Function App cuyo peso cambió (func-novapay-pagos-${var.environment} o -canary-${var.environment})." },
          { name = "pesoNuevo", type = "real", description = "Peso nuevo asignado en el backend pool de APIM (0-100)." },
        ]
      }
    }
  }

  schema_validation_enabled = false
}

resource "azurerm_monitor_data_collection_rule" "pesoactualizado" {
  name                        = "dcr-novapay-pesoactualizado-${var.environment}"
  resource_group_name         = var.resource_group_name
  location                    = var.location
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.pesoactualizado.id
  tags                        = var.tags

  # HALLAZGO REAL (terraform validate): el tutorial oficial de ARM usa
  # "kind": "Direct" para este escenario (Logs Ingestion API sin
  # agente), pero el enum real del provider azurerm instalado (~4.81)
  # no acepta ese valor — solo "Linux", "Windows",
  # "AgentDirectToStore", "WorkspaceTransforms". Ninguno de esos aplica
  # a ingestión directa vía REST sin Azure Monitor Agent, así que se
  # omite "kind" por completo (campo opcional) en vez de forzar un
  # valor que no corresponde al escenario real.

  stream_declaration {
    stream_name = "Custom-PesoActualizado"

    column {
      name = "TimeGenerated"
      type = "datetime"
    }
    column {
      name = "sourceInstance"
      type = "string"
    }
    column {
      name = "pesoNuevo"
      type = "real"
    }
  }

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.this.id
      name                  = "logAnalytics"
    }
  }

  data_flow {
    streams       = ["Custom-PesoActualizado"]
    destinations  = ["logAnalytics"]
    output_stream = "Custom-PesoActualizado_CL"
    # Passthrough explícito: las columnas del stream ya coinciden 1:1
    # con las de la tabla destino, así que no hace falta transformar
    # nada — "source" deja pasar cada fila tal cual llega.
    transform_kql = "source"
  }

  # La tabla debe existir antes de que la DCR intente enrutar datos
  # hacia ella (ver HALLAZGO REAL arriba) — orden explícito, no
  # implícito por referencia, porque la DCR no referencia la tabla
  # directamente en su cuerpo (solo el nombre del stream de salida).
  depends_on = [azapi_resource.pesoactualizado_table]
}

# Rol mínimo para que el job de CD pueda enviar el evento — acotado a
# esta DCR puntual, no a toda la suscripción ni al workspace completo.
resource "azurerm_role_assignment" "dcr_pesoactualizado_metrics_publisher" {
  count                = var.novapay_functions_sp_principal_id != "" ? 1 : 0
  scope                = azurerm_monitor_data_collection_rule.pesoactualizado.id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = var.novapay_functions_sp_principal_id
}

# --- Alerta de burn rate del error budget (§4.4 borradores/04) ---
#
# Solo el aviso al 50% de consumo (notificación humana, sin acción
# automática) es un recurso de Azure Monitor. El bloqueo automático de
# avances de canary al 80% (§4.4) es lógica del propio job de CD de
# novapay-functions (consulta la misma query antes de cada incremento
# de peso) — un "scheduled query rule" no tiene forma de detener un
# job de GitHub Actions en curso, solo de notificar; documentado así
# para no sugerir un mecanismo de bloqueo que esta alerta no provee.
#
# HALLAZGO REAL (apply real fallido, release v1.0.21, 2026-08-17): la
# primera versión de esta query comparaba "ResultCode >= 500" y Azure
# la rechazó con 400 ("Cannot compare values of types string and
# long") — en el esquema workspace-based de Application Insights,
# ResultCode en AppRequests es de tipo string (p.ej. "200", "500"), no
# numérico, pese a "parecer" un código HTTP entero. Fix real: envolver
# en toint(ResultCode) antes de comparar. Mismo error se replicó (y se
# corrigió igual) en los paneles 4 y 6 del Workbook, más abajo — todos
# comparten la misma tabla y columna.
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "error_budget_burn_rate" {
  name                 = "alert-error-budget-burn-rate-${var.environment}"
  resource_group_name  = var.resource_group_name
  location             = var.location
  evaluation_frequency = "PT1H"
  window_duration      = "PT1H"
  scopes               = [azurerm_log_analytics_workspace.this.id]
  severity             = 2
  display_name         = "NovaPay - Consumo de error budget >= 50% (ventana móvil 30 días)"
  description          = "SLO de disponibilidad 99.97% mensual (§4.2) => presupuesto de error 0.03%. Ventana móvil de 30 días (no mes calendario, evita el artefacto de reseteo al cruzar el límite de mes) — ver borradores/04_observabilidad_avanzada.md §4.4."

  criteria {
    query                   = <<-KQL
      AppRequests
      | where TimeGenerated > ago(30d)
      | summarize total = count(), errores = countif(toint(ResultCode) >= 500)
      | extend errorRate = errores * 100.0 / total
      | extend presupuestoConsumido = errorRate / 0.03 * 100
      | project presupuestoConsumido
    KQL
    time_aggregation_method = "Average"
    threshold               = 50
    operator                = "GreaterThanOrEqual"
    metric_measure_column   = "presupuestoConsumido"

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.sre.id]
  }

  tags = var.tags
}

# --- Workbook (6 paneles, borradores/04_observabilidad_avanzada.md §4.6) ---
#
# "name" debe ser un GUID (requisito real de la API de Workbooks, no
# una convención de nombres legible) — valor fijo generado una sola
# vez, arbitrario, solo necesita ser único dentro del resource group.
# "display_name" es el nombre legible que se ve en el portal.
locals {
  workbook_id = "42e49c7a-0dbc-4337-832f-27a09bf7b712"

  workbook_items = [
    # Panel 1: peso actual del backend pool de APIM — fuente ARM en
    # tiempo real, deliberadamente independiente del evento
    # PesoActualizado (panel 2) para no depender de que el job de CD
    # lo haya emitido con éxito (ver ADR-07, "consecuencias negativas").
    {
      type = 3
      content = {
        version = "KqlItem/1.0"
        query = jsonencode({
          version       = "ARMEndpoint/1.0"
          data          = null
          headers       = []
          method        = "GET"
          path          = "${var.apim_backend_pool_id}?api-version=2024-05-01"
          urlParams     = []
          batchDisabled = false
          transformers = [
            {
              type = "jsonpath"
              settings = {
                tablePath = "$.properties.pool.services"
                columns = [
                  { path = "$.id", columnid = "Backend" },
                  { path = "$.weight", columnid = "Peso" },
                ]
              }
            }
          ]
        })
        size      = 4
        queryType = 12
      }
      name = "peso-actual-pool"
    },
    # Panel 2: traza de cambios de peso — eje temporal compartido con
    # los paneles 3-5 (correlación visual, no join calculado; ver
    # ADR-07 sobre por qué un join por solicitud multiplicaría filas).
    {
      type = 3
      content = {
        version                 = "KqlItem/1.0"
        query                   = "PesoActualizado_CL\n| project TimeGenerated, sourceInstance, pesoNuevo\n| order by TimeGenerated asc"
        size                    = 0
        queryType               = 0
        resourceType            = "microsoft.operationalinsights/workspaces"
        crossComponentResources = [azurerm_log_analytics_workspace.this.id]
        visualization           = "linechart"
      }
      name = "traza-cambios-peso"
    },
    # Panel 3: latencia p95/p99 por sourceInstance (dos series).
    {
      type = 3
      content = {
        version                 = "KqlItem/1.0"
        query                   = "AppRequests\n| where AppRoleName in (\"func-novapay-pagos-${var.environment}\", \"func-novapay-pagos-canary-${var.environment}\")\n| summarize p95=percentile(DurationMs, 95), p99=percentile(DurationMs, 99) by AppRoleName, bin(TimeGenerated, 5m)"
        size                    = 0
        queryType               = 0
        resourceType            = "microsoft.operationalinsights/workspaces"
        crossComponentResources = [azurerm_log_analytics_workspace.this.id]
        visualization           = "linechart"
      }
      name = "latencia-p95-p99"
    },
    # Panel 4: tasa de error 5xx por sourceInstance (dos series).
    {
      type = 3
      content = {
        version                 = "KqlItem/1.0"
        query                   = "AppRequests\n| where AppRoleName in (\"func-novapay-pagos-${var.environment}\", \"func-novapay-pagos-canary-${var.environment}\")\n| summarize total=count(), errores=countif(toint(ResultCode) >= 500) by AppRoleName, bin(TimeGenerated, 5m)\n| extend tasaError = errores * 100.0 / total\n| project TimeGenerated, AppRoleName, tasaError"
        size                    = 0
        queryType               = 0
        resourceType            = "microsoft.operationalinsights/workspaces"
        crossComponentResources = [azurerm_log_analytics_workspace.this.id]
        visualization           = "linechart"
      }
      name = "tasa-error-5xx"
    },
    # Panel 5: profundidad de cola y DLQ por Subscription — vía las dos
    # colas de aterrizaje dedicadas (modules/messaging-servicebus,
    # Bloque 2a), no las Subscriptions directamente: Azure Monitor no
    # expone EntityName a nivel de Subscription individual (mismo
    # hallazgo real ya documentado en PLAN.md §3.2), así que la métrica
    # de Queue "ActiveMessages" sobre cada cola de aterrizaje es el
    # proxy real por instancia, igual que la alerta de DLQ existente.
    {
      type = 3
      content = {
        version                 = "KqlItem/1.0"
        query                   = "AzureMetrics\n| where ResourceProvider == \"MICROSOFT.SERVICEBUS\"\n| where MetricName == \"ActiveMessages\"\n| where Resource in~ (\"sbq-novapay-pagos-dlq-${var.environment}\", \"sbq-novapay-pagos-canary-dlq-${var.environment}\")\n| summarize Profundidad = avg(Total) by Resource, bin(TimeGenerated, 5m)"
        size                    = 0
        queryType               = 0
        resourceType            = "microsoft.operationalinsights/workspaces"
        crossComponentResources = [azurerm_log_analytics_workspace.this.id]
        visualization           = "linechart"
      }
      name = "dlq-por-subscription"
    },
    # Panel 6: SLI vs SLO — resumen del consumo de error budget (§4.2,
    # §4.4), misma query que alimenta la alerta de burn rate.
    {
      type = 3
      content = {
        version                 = "KqlItem/1.0"
        query                   = "AppRequests\n| where TimeGenerated > ago(30d)\n| summarize total=count(), errores=countif(toint(ResultCode) >= 500)\n| extend errorRate = errores * 100.0 / total\n| extend disponibilidad = 100 - errorRate\n| extend presupuestoConsumidoPct = errorRate / 0.03 * 100\n| project disponibilidad, SLO_disponibilidad = 99.97, presupuestoConsumidoPct"
        size                    = 0
        queryType               = 0
        resourceType            = "microsoft.operationalinsights/workspaces"
        crossComponentResources = [azurerm_log_analytics_workspace.this.id]
        visualization           = "table"
      }
      name = "sli-vs-slo"
    },
  ]
}

resource "azurerm_application_insights_workbook" "observability" {
  name                = local.workbook_id
  resource_group_name = var.resource_group_name
  location            = var.location
  display_name        = "NovaPay - Observabilidad de pagos (${var.environment})"
  # lower(): el provider valida que source_id no tenga mayúsculas, pero
  # el .id real de Application Insights preserva el casing tal cual lo
  # devuelve ARM (p.ej. "resourceGroups", "Microsoft.Insights") — sin
  # esto, el propio "terraform plan" falla con "expected value of
  # source_id to not contain any uppercase letter" antes de llegar a
  # tocar Azure.
  source_id = lower(azurerm_application_insights.this.id)
  category  = "workbook"

  data_json = jsonencode({
    version   = "Notebook/1.0"
    items     = local.workbook_items
    "$schema" = "https://github.com/Microsoft/Application-Insights-Workbooks/blob/master/schema/workbook.json"
  })

  tags = var.tags
}
