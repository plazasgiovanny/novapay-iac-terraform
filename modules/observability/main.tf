# Módulo: observability
# Centraliza métricas, logs y trazas de todas las capas anteriores
# (sección 1.5, requerimiento no funcional de observabilidad), en
# lugar de dejarlas dispersas por cada servicio administrado.

resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-novapay-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.retention_in_days
  tags                = var.tags
}

# Application Insights workspace-based, nuevo desde la Entrega 2
# (documento de diseño, sección 4) — trazas distribuidas y
# correlation ID de extremo a extremo (APIM -> eventos -> funciones ->
# BD). No existía Application Insights en el repositorio hasta ahora;
# se apoya en el mismo Log Analytics Workspace de arriba, sin duplicar
# el almacenamiento de logs.
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
# el equipo decida observar se agrega a monitored_resource_ids sin
# tocar la lógica de este módulo (mismo patrón de contrato de la
# sección 3.3), enviando todos sus logs y métricas al workspace
# centralizado.
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
