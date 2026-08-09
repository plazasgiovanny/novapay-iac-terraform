# Módulo: api-management
# API Gateway del flujo de confirmación y notificación de pagos
# (documento de diseño, sección 2 — "Correspondencia con el API
# Gateway o equivalente"). Único punto de entrada real de esta
# superficie mientras Azure Front Door no esté provisionado como
# código (brecha heredada de la Entrega 1, sección 9).

resource "azurerm_api_management" "this" {
  name                = "apim-novapay-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  publisher_name      = var.publisher_name
  publisher_email     = var.publisher_email

  # Consumption: sin costo base, sin integración VNet (limitación
  # aceptada y documentada en sección 9 — mitigada con function key +
  # restricción de IP a los rangos de salida de APIM Consumption).
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

# La function key es un secreto real, pero vive únicamente como named
# value cifrado dentro de APIM — nunca en Key Vault, en un .tfvars, ni
# en el código de Johan (documento de diseño, sección 7). depends_on
# explícito: el data source solo puede resolver la clave después de
# que el Function App exista.
data "azurerm_function_app_host_keys" "pagos" {
  name                = var.function_app_name
  resource_group_name = var.resource_group_name
  depends_on          = [var.function_app_id]
}

resource "azurerm_api_management_named_value" "func_host_key" {
  name                = "func-novapay-pagos-host-key"
  resource_group_name = var.resource_group_name
  api_management_name = azurerm_api_management.this.name
  display_name        = "func-novapay-pagos-host-key"
  value               = data.azurerm_function_app_host_keys.pagos.default_function_key
  secret              = true
}

resource "azurerm_api_management_backend" "func" {
  name                = "func-novapay-pagos-backend"
  resource_group_name = var.resource_group_name
  api_management_name = azurerm_api_management.this.name
  protocol            = "http"
  url                 = "https://${var.function_default_hostname}/api"

  credentials {
    header = {
      "x-functions-key" = "{{${azurerm_api_management_named_value.func_host_key.display_name}}}"
    }
  }
}

# Política de la operación: enruta al backend real y aplica rate
# limiting / cuota por subscription key (protección ante abuso,
# documento de diseño, sección 7 — "conceptual", sin prueba de carga
# real en esta entrega).
resource "azurerm_api_management_api_policy" "confirmaciones" {
  api_name            = azurerm_api_management_api.pagos.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name

  xml_content = <<XML
<policies>
  <inbound>
    <base />
    <rate-limit-by-key calls="${var.rate_limit_calls_per_minute}" renewal-period="60" counter-key="@(context.Subscription.Id)" />
    <quota-by-key calls="${var.quota_calls_per_day}" renewal-period="86400" counter-key="@(context.Subscription.Id)" />
    <set-backend-service backend-id="${azurerm_api_management_backend.func.name}" />
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

# Suscripción lista de antemano: evita improvisar una subscription key
# en vivo durante la grabación del video de evidencia (Fase 5, plan
# de grabación descrito en el documento de diseño, sección 9).
resource "azurerm_api_management_subscription" "default" {
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name
  product_id          = azurerm_api_management_product.pagos.id
  display_name        = "novapay-pagos-evidencia-${var.environment}"
  state               = "active"
}
