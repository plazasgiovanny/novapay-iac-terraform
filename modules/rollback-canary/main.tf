# Módulo: rollback-canary
# Bloque 2g de la Fase 3 de U4 (ADR-03 §2.6): mecanismo de rollback de
# tráfico ASÍNCRONO e INDEPENDIENTE del job de CD de novapay-functions
# — el job ya tiene su propio guardrail en línea (observe_and_guard,
# rollback inmediato si error rate > 3% en 5 min), pero ese guardrail
# solo protege mientras el job de GitHub Actions sigue vivo. Este
# módulo es la red de seguridad para el caso en que el runner se cae,
# se cancela, o el propio GitHub Actions no está disponible: una
# alerta de Azure Monitor, evaluada por la plataforma (no por un
# proceso en curso), dispara un Action Group cuya acción es esta
# misma Azure Function.
#
# Decisión de implementación (no solo de diseño): "Azure Function",
# tal como especifica ADR-03 §2.6 — evaluada la alternativa de un
# Logic App Consumption (más simple como IaC puro, sin código), se
# optó por honrar el ADR ya revisado. El código (PowerShell, sin
# dependencias del módulo Az — llama directo a la API ARM vía el
# endpoint local de identidad administrada, evitando el costo de
# arranque en frío de cargar el módulo Az) vive en este mismo
# repositorio (function-src/) y se empaqueta con el provider archive
# — no hay un repo/pipeline propio (como novapay-functions) para una
# utilidad de una sola función: sería sobre-ingeniería para 60 líneas
# de PowerShell que rara vez cambian.

data "archive_file" "rollback_canary" {
  type       = "zip"
  source_dir = "${path.module}/function-src"
  # "build/", no ".build/": actions/upload-artifact excluye archivos y
  # carpetas ocultos (prefijo ".") por defecto desde sep-2024 — el
  # zip nunca llegaba al artefacto de CI aunque se listara explícitamente
  # en su "path" (confirmado con un apply real fallido, release
  # v1.0.23/v1.0.24, 2026-08-17: solo "1 file uploaded", nunca el zip;
  # verificado también que no es una diferencia de versión de Terraform
  # — reproducido con la versión exacta de CI, 1.9.8, el archivo se
  # escribe igual en disco local en ambos casos).
  output_path = "${path.module}/build/rollback-canary-${var.environment}.zip"
}

# Cuenta de almacenamiento dedicada — mismo criterio que
# compute-serverless: no compartir con otros Function Apps ni con el
# resto del diseño, para no acoplar ciclos de vida.
resource "azurerm_storage_account" "this" {
  name                     = "stnpyrollback${var.environment}"
  location                 = var.location
  resource_group_name      = var.resource_group_name
  account_tier             = "Standard"
  account_replication_type = "LRS"
  tags                     = var.tags
}

resource "azurerm_storage_container" "deployments" {
  name                  = "deployments"
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

# El nombre del blob incluye el hash del contenido (output_md5, hex —
# archive_file no expone una variante base64, y content_md5 de este
# recurso la exige en ese formato; convertirla no aporta nada real que
# el nombre ya no resuelva): cualquier cambio en function-src/ produce
# un blob nuevo con URL nueva, forzando el redeploy vía el cambio en
# WEBSITE_RUN_FROM_PACKAGE, sin necesidad de content_md5 para detectar
# el cambio.
resource "azurerm_storage_blob" "package" {
  name                   = "rollback-canary-${data.archive_file.rollback_canary.output_md5}.zip"
  storage_account_name   = azurerm_storage_account.this.name
  storage_container_name = azurerm_storage_container.deployments.name
  type                   = "Block"
  source                 = data.archive_file.rollback_canary.output_path
}

# SAS de solo lectura para que WEBSITE_RUN_FROM_PACKAGE pueda leer el
# blob del paquete. Expiración deliberadamente larga (10 años): a
# diferencia de AzureWebJobsStorage (que sí soporta identidad
# administrada de forma nativa en este modelo clásico, ver
# storage_uses_managed_identity abajo), WEBSITE_RUN_FROM_PACKAGE con
# una URL de blob privado requiere un SAS — si expira, el Function App
# deja de poder recuperar su propio paquete en el próximo arranque en
# frío tras escalar a cero. Riesgo real, documentado aquí en vez de
# ocultarlo; no crítico para una función que se invoca con muy poca
# frecuencia (solo ante un rollback real).
data "azurerm_storage_account_sas" "package" {
  connection_string = azurerm_storage_account.this.primary_connection_string
  https_only        = true
  signed_version    = "2022-11-02"

  resource_types {
    service   = false
    container = false
    object    = true
  }

  services {
    blob  = true
    queue = false
    table = false
    file  = false
  }

  start  = "2024-01-01T00:00:00Z"
  expiry = "2034-01-01T00:00:00Z"

  permissions {
    read    = true
    write   = false
    delete  = false
    list    = false
    add     = false
    create  = false
    update  = false
    process = false
    tag     = false
    filter  = false
  }
}

# HALLAZGO REAL (apply real fallido, release v1.0.23, 2026-08-17):
# "os_type = Linux" con sku_name "Y1" (Dynamic) fue rechazado por
# Azure con 400 BadRequest — "Requested features 'Dynamic SKU, Linux
# Worker' not available in resource group rg-novapay-prod". Los planes
# ya existentes en este resource group son FC1 (Flex Consumption,
# compute-serverless) y S1 (Standard, compute-appservice) — nunca un
# Y1/Dynamic clásico de ningún OS, y esta combinación puntual
# (Dynamic + Linux) no está disponible aquí (mismo tipo de límite real
# de la suscripción/región ya documentado varias veces en este
# proyecto, no un error de configuración). Pivote real: Windows sí
# está disponible con Dynamic SKU (el modelo Y1 más antiguo y más
# ampliamente soportado de Azure Functions) — PowerShell corre igual
# de bien ahí, sin cambiar el resto del diseño.
resource "azurerm_service_plan" "this" {
  name                = "asp-novapay-rollback-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  os_type             = "Windows"
  sku_name            = "Y1"
  tags                = var.tags
}

resource "azurerm_windows_function_app" "this" {
  name                 = "func-novapay-rollback-canary-${var.environment}"
  location             = var.location
  resource_group_name  = var.resource_group_name
  service_plan_id      = azurerm_service_plan.this.id
  storage_account_name = azurerm_storage_account.this.name

  # Igual que async_workers (modules/compute-appservice): identidad
  # administrada para AzureWebJobsStorage, sin distribuir la clave de
  # acceso compartida. A diferencia de compute-serverless (Flex
  # Consumption), este modelo clásico de Function App SÍ soporta esto
  # de forma nativa (el bug documentado, hashicorp/terraform-provider-azurerm#29149,
  # es específico de azurerm_function_app_flex_consumption).
  storage_uses_managed_identity = true

  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_stack {
      powershell_core_version = "7.4"
    }
  }

  app_settings = {
    # Despliegue del código embebido en este repo (ver archive_file
    # arriba) — sin CD externo, el propio "terraform apply" es el
    # mecanismo de despliegue para esta utilidad puntual.
    WEBSITE_RUN_FROM_PACKAGE = "${azurerm_storage_blob.package.url}${data.azurerm_storage_account_sas.package.sas}"

    TARGET_SUBSCRIPTION_ID = var.subscription_id
    TARGET_RESOURCE_GROUP  = var.resource_group_name
    TARGET_APIM_NAME       = var.apim_name
    TARGET_POOL_NAME       = var.backend_pool_name
  }

  tags = var.tags
}

resource "azurerm_role_assignment" "storage_access" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = azurerm_windows_function_app.this.identity[0].principal_id
}

# ADR-03 §2.6: rol acotado al recurso puntual de APIM, nunca al
# resource group completo — único permiso que esta identidad necesita
# para poder bajar el peso del backend pool a 0%.
resource "azurerm_role_assignment" "apim_contributor" {
  scope                = var.apim_id
  role_definition_name = "API Management Service Contributor"
  principal_id         = azurerm_windows_function_app.this.identity[0].principal_id
}

# HALLAZGO REAL esperado (mismo patrón ya documentado en
# modules/api-management sobre data.azurerm_function_app_host_keys):
# esta data source espera un runtime que ya respondió "list keys" con
# éxito. Aquí el código se despliega de forma síncrona en el mismo
# apply (WEBSITE_RUN_FROM_PACKAGE, no un pipeline externo posterior),
# así que no debería colgarse — pero si el primer apply falla en este
# punto, un segundo apply lo resuelve (igual que en api-management).
data "azurerm_function_app_host_keys" "this" {
  name                = azurerm_windows_function_app.this.name
  resource_group_name = var.resource_group_name

  depends_on = [azurerm_windows_function_app.this]
}

# El Action Group de rollback llama a esta función vía HTTP POST — la
# función key es obligatoria (authLevel "function" en function.json):
# a diferencia de una llamada normal, Azure Monitor no autentica por
# identidad administrada contra Function Apps, incrusta la key en la
# URL (confirmado contra la documentación oficial de Action Groups
# antes de codificar, no asumido).
resource "azurerm_monitor_action_group" "this" {
  name                = "ag-novapay-rollback-canary-${var.environment}"
  resource_group_name = var.resource_group_name
  short_name          = "rollbackcnry"
  tags                = var.tags

  azure_function_receiver {
    name                     = "rollback-canary-function"
    function_app_resource_id = azurerm_windows_function_app.this.id
    function_name            = "RollbackCanary"
    http_trigger_url         = "https://${azurerm_windows_function_app.this.default_hostname}/api/RollbackCanary?code=${data.azurerm_function_app_host_keys.this.default_function_key}"
    use_common_alert_schema  = true
  }
}

# ADR-03 §2.6: "una alerta de Azure Monitor sobre tasa de error 5xx de
# la instancia en rampa (umbral >3% en ventana de 5 minutos)". No se
# puede acotar por nombre fijo de recurso (rol dinámico, ver ADR-07):
# la query evalúa AMBOS Function Apps de pagos y toma el máximo, sin
# necesidad de saber de antemano cuál está en rampa — la propia
# función (run.ps1) determina eso consultando el pool en tiempo real
# al momento de la invocación, no a partir del payload de la alerta.
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "canary_error_rate" {
  name                 = "alert-canary-error-rate-${var.environment}"
  resource_group_name  = var.resource_group_name
  location             = var.location
  evaluation_frequency = "PT5M"
  window_duration      = "PT5M"
  scopes               = var.action_group_alert_scopes
  severity             = 1
  display_name         = "NovaPay - Error rate > 3% en instancia de pagos (ventana 5 min)"
  description          = "Red de seguridad asíncrona independiente del job de CD (ADR-03 §2.6) — el guardrail en línea del propio job (observe_and_guard) ya cubre el caso normal; esta alerta cubre el caso en que ese job no está disponible."

  criteria {
    query                   = <<-KQL
      AppRequests
      | where TimeGenerated > ago(5m)
      | where AppRoleName in (${join(", ", [for r in var.role_names_in_ramp : "\"${r}\""])})
      | summarize total = count(), errores = countif(toint(ResultCode) >= 500) by AppRoleName
      | extend errorPct = errores * 100.0 / total
      | summarize maxErrorPct = max(errorPct)
      | project maxErrorPct
    KQL
    time_aggregation_method = "Maximum"
    threshold               = 3
    operator                = "GreaterThan"
    metric_measure_column   = "maxErrorPct"

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.this.id]
  }

  tags = var.tags
}
