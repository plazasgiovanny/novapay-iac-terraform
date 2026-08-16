# Módulo: api-management
# API Gateway del flujo de confirmación y notificación de pagos.
# Único punto de entrada real de esta superficie mientras Azure
# Front Door no esté provisionado como código.

resource "azurerm_api_management" "this" {
  name                = "apim-novapay-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  publisher_name      = var.publisher_name
  publisher_email     = var.publisher_email

  # Consumption: sin costo base, sin integración VNet (limitación
  # aceptada, mitigada con function key — la restricción de IP en el
  # Function App es por región completa, no por APIM específicamente,
  # ver modules/compute-serverless: "ApiManagement" como service_tag no
  # funciona en este tier, hallazgo real documentado ahí).
  sku_name = "Consumption_0"

  tags = var.tags
}

resource "azurerm_api_management_api" "pagos" {
  name                = "pagos-novapay"
  resource_group_name = var.resource_group_name
  api_management_name = azurerm_api_management.this.name
  revision            = "1"
  display_name        = "NovaPay - Payment Confirmation"
  path                = "api/v1/payments"
  protocols           = ["https"]
}

resource "azurerm_api_management_api_operation" "confirmaciones" {
  operation_id        = "post-confirmations"
  api_name            = azurerm_api_management_api.pagos.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name
  display_name        = "Confirm payment"
  method              = "POST"
  url_template        = "/confirmations"

  response {
    status_code = 202
  }
}

# Host key leída en vivo del Function App backend — requiere que su
# runtime responda "list keys" con éxito (necesita código desplegado y
# AzureWebJobsStorage saludable; ver modules/compute-serverless).
# Gateado por var.wire_backend: en el apply inicial de bootstrap (antes
# de que exista ningún código desplegado) esta cadena completa se omite;
# se activa en un apply posterior, ver descripción de la variable.
data "azurerm_function_app_host_keys" "pagos" {
  count               = var.wire_backend ? 1 : 0
  name                = var.function_app_name
  resource_group_name = var.resource_group_name
  depends_on          = [var.function_app_id]
}

resource "azurerm_api_management_named_value" "func_host_key" {
  count               = var.wire_backend ? 1 : 0
  name                = "func-novapay-pagos-host-key"
  resource_group_name = var.resource_group_name
  api_management_name = azurerm_api_management.this.name
  display_name        = "func-novapay-pagos-host-key"
  value               = data.azurerm_function_app_host_keys.pagos[0].default_function_key
  secret              = true
}

resource "azurerm_api_management_backend" "func" {
  count               = var.wire_backend ? 1 : 0
  name                = "func-novapay-pagos-backend"
  resource_group_name = var.resource_group_name
  api_management_name = azurerm_api_management.this.name
  protocol            = "http"
  url                 = "https://${var.function_default_hostname}/api"

  credentials {
    header = {
      "x-functions-key" = "{{${azurerm_api_management_named_value.func_host_key[0].display_name}}}"
    }
  }
}

# Misma cadena que arriba, para la instancia candidata (ADR-03 U4) —
# también gateada por wire_backend: su host key tampoco responde hasta
# que exista código desplegado en func-novapay-pagos-canary-{env}.
data "azurerm_function_app_host_keys" "pagos_canary" {
  count               = var.wire_backend ? 1 : 0
  name                = var.function_app_canary_name
  resource_group_name = var.resource_group_name
  depends_on          = [var.function_app_canary_id]
}

resource "azurerm_api_management_named_value" "func_canary_host_key" {
  count               = var.wire_backend ? 1 : 0
  name                = "func-novapay-pagos-canary-host-key"
  resource_group_name = var.resource_group_name
  api_management_name = azurerm_api_management.this.name
  display_name        = "func-novapay-pagos-canary-host-key"
  value               = data.azurerm_function_app_host_keys.pagos_canary[0].default_function_key
  secret              = true
}

resource "azurerm_api_management_backend" "func_canary" {
  count               = var.wire_backend ? 1 : 0
  name                = "func-novapay-pagos-canary-backend"
  resource_group_name = var.resource_group_name
  api_management_name = azurerm_api_management.this.name
  protocol            = "http"
  url                 = "https://${var.function_canary_default_hostname}/api"

  credentials {
    header = {
      "x-functions-key" = "{{${azurerm_api_management_named_value.func_canary_host_key[0].display_name}}}"
    }
  }
}

# Backend pool ponderado (ADR-03 U4) — decide qué instancia sirve
# tráfico vigente y en qué proporción, sin jerarquía fija entre las dos.
#
# HALLAZGO REAL (verificado antes de codificar, no asumido):
# azurerm_api_management_backend no soporta type="Pool" en ninguna
# versión publicada del provider — issue abierto sin mergear,
# hashicorp/terraform-provider-azurerm#30855, con un PR de la
# comunidad esperando revisión desde hace meses. Es una funcionalidad
# real de Azure (confirmada en el schema oficial de
# Microsoft.ApiManagement/service/backends, BackendPoolItem con
# "weight" 0-100), simplemente el provider azurerm no la expone
# todavía. azapi (provider genérico de ARM, mismo mecanismo que otros
# equipos usan como workaround mientras el PR no se mergea) gestiona
# este recurso puntual llamando directo a la API — el resto del módulo
# sigue en azurerm sin cambios.
#
# Pesos iniciales: 100/0 (toda la instancia estable, candidata en
# reposo) — el mismo estado estacionario del diseño. lifecycle.ignore_changes
# en "body" es deliberado: una vez creado, el job de CD (ADR-02) hace
# PATCH directo sobre este recurso para mover pesos durante cada ciclo
# de despliegue, fuera del control de Terraform — sin esto, cualquier
# apply posterior revertiría la rampa en curso a los pesos iniciales.
resource "azapi_resource" "backend_pool" {
  count     = var.wire_backend ? 1 : 0
  type      = "Microsoft.ApiManagement/service/backends@2024-05-01"
  name      = "pool-novapay-pagos-${var.environment}"
  parent_id = azurerm_api_management.this.id

  body = {
    properties = {
      type        = "Pool"
      description = "Pool ponderado estable/canary de func-novapay-pagos-${var.environment} — ADR-03 U4."
      pool = {
        services = [
          {
            id     = azurerm_api_management_backend.func[0].id
            weight = 100
          },
          {
            id     = azurerm_api_management_backend.func_canary[0].id
            weight = 0
          },
        ]
      }
    }
  }

  schema_validation_enabled = false

  lifecycle {
    ignore_changes = [body]
  }
}

# Política de la operación: enruta al backend real y aplica rate
# limiting por subscription (protección ante abuso). "rate-limit" (no
# "-by-key") es la única política de throttling disponible en el tier
# Consumption_0 de APIM — verificado en Microsoft Learn, "rate-limit-by-key"
# y "quota-by-key" no listan Consumption entre sus tiers soportados y el
# apply real lo confirmó con un 400 ValidationError. Como ya es "per
# subscription" por diseño, cubre la misma intención sin necesitar
# counter-key. Cuota diaria por key queda fuera de alcance: no tiene
# equivalente en Consumption (limitación real del SKU, no un olvido —
# mismo criterio que Service Bus Standard sin Private Link).
# También gateada por var.wire_backend: sin el Pool creado no hay
# backend-id válido que referenciar. Mientras tanto la operación queda
# sin política propia (hereda el comportamiento por defecto de APIM,
# sin ruta configurada) — aceptable en el bootstrap porque tampoco hay
# código desplegado que pudiera responder. Enruta al Pool (no a un
# backend individual): el Pool decide, según el peso vigente en cada
# momento, cuál de las dos instancias físicas atiende cada solicitud.
resource "azurerm_api_management_api_policy" "confirmaciones" {
  count               = var.wire_backend ? 1 : 0
  api_name            = azurerm_api_management_api.pagos.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name

  xml_content = <<XML
<policies>
  <inbound>
    <base />
    <rate-limit calls="${var.rate_limit_calls_per_minute}" renewal-period="60" />
    <set-backend-service backend-id="${azapi_resource.backend_pool[0].name}" />
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
XML
}

resource "azurerm_api_management_product" "pagos" {
  product_id            = "pagos-novapay"
  resource_group_name   = var.resource_group_name
  api_management_name   = azurerm_api_management.this.name
  display_name          = "NovaPay - Payments"
  subscription_required = true
  approval_required     = false
  published             = true
}

resource "azurerm_api_management_product_api" "pagos" {
  product_id          = azurerm_api_management_product.pagos.product_id
  api_name            = azurerm_api_management_api.pagos.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name
}

# Suscripción por defecto, lista de antemano en vez de generarse
# manualmente por fuera de Terraform.
resource "azurerm_api_management_subscription" "default" {
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name
  product_id          = azurerm_api_management_product.pagos.id
  display_name        = "novapay-pagos-default-${var.environment}"
  state               = "active"
}
