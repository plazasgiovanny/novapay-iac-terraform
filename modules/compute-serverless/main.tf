# Módulo: compute-serverless
# Function App dedicado al flujo de confirmación y notificación de
# pagos (Entrega 2, documento de diseño sección 1 y 4). Deliberadamente
# separado del Service Plan Dedicated de compute-appservice: corre en
# plan de Consumo (o Elastic Premium si la región lo exige), único
# cómputo del repositorio que escala a cero y exhibe cold start real.

resource "azurerm_service_plan" "this" {
  name                = "asp-novapay-serverless-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  os_type             = "Linux"
  sku_name            = var.function_plan_sku
  tags                = var.tags
}

# Cuenta de almacenamiento exclusiva de este Function App (runtime,
# no datos de negocio) — no se comparte con stnovapayfunc${env}
# (async_workers) para no acoplar dos workloads con ciclos de vida y
# volúmenes de operación distintos.
resource "azurerm_storage_account" "this" {
  name                     = "stnovapaypagos${var.environment}"
  location                 = var.location
  resource_group_name      = var.resource_group_name
  account_tier             = "Standard"
  account_replication_type = "LRS"
  tags                     = var.tags
}

resource "azurerm_linux_function_app" "this" {
  name                = "func-novapay-pagos-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  service_plan_id     = azurerm_service_plan.this.id

  storage_account_name          = azurerm_storage_account.this.name
  storage_uses_managed_identity = true

  # Integración VNet regional hacia la subred integracion, delegada a
  # Microsoft.Web/serverFarms (módulo networking) — requisito del plan
  # de Consumo/Elastic Premium en Linux, a diferencia del Dedicated de
  # compute-appservice, que no requiere delegación explícita.
  virtual_network_subnet_id = var.integracion_subnet_id

  # Identidad SystemAssigned única, compartida por las dos funciones
  # que aloja este recurso (ValidarPago, ProcesarPago). Azure Functions
  # no tiene identidad a nivel de función individual — ver documento de
  # diseño, sección 5.
  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_stack {
      dotnet_version              = "8.0"
      use_dotnet_isolated_runtime = true
    }
  }

  app_settings = {
    # Application Insights por connection string (no instrumentation
    # key legacy) — trazas distribuidas de extremo a extremo.
    APPLICATIONINSIGHTS_CONNECTION_STRING = var.appinsights_connection_string

    # Conexión a Service Bus por identidad administrada: solo el FQDN
    # del namespace viaja en configuración, nunca una cadena de
    # conexión con clave compartida (documento de diseño, sección 7).
    serviceBusConnection__fullyQualifiedNamespace = var.servicebus_namespace_fqdn
    serviceBusConnection__credential              = "managedidentity"
  }

  tags = var.tags
}

# Permiso mínimo sobre su propia cuenta de almacenamiento, mismo
# patrón que functions_storage_access en compute-appservice — sin
# distribuir la clave de acceso compartida de la cuenta.
resource "azurerm_role_assignment" "storage_access" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = azurerm_linux_function_app.this.identity[0].principal_id
}
