# Módulo: compute-serverless
# Function App dedicado al flujo de confirmación y notificación de
# pagos (Entrega 2, documento de diseño sección 1 y 4). Deliberadamente
# separado del Service Plan Dedicated de compute-appservice.
#
# Historial de esta decisión (documentado también en el documento de
# diseño, sección 1 y 9): la primera versión de este módulo usaba el
# plan de Consumo clásico (Y1, azurerm_linux_function_app). Se descubrió
# al pasar a código que Y1 NO soporta integración VNet regional bajo
# ninguna circunstancia (no es un límite "según la región" como se
# pensó inicialmente) — y este Function App SÍ necesita esa integración
# para llegar a Azure SQL, que solo expone un Private Endpoint en la
# subred "datos" (acceso público deshabilitado desde la Entrega 1). La
# alternativa Elastic Premium (EP1) sí soporta VNet integration, pero
# mantiene como mínimo una instancia siempre activa — pierde el
# escalado real a cero que motivó elegir un plan serverless en primer
# lugar. Se optó por **Flex Consumption (FC1)**: soporta integración
# VNet regional de forma nativa Y sigue escalando a cero por defecto
# ("Always Ready" = 0 instancias si no se configura lo contrario),
# preservando intacto el argumento de cold start real de la sección 1.
# El costo de esta decisión es un salto de versión mayor del provider
# azurerm (~> 3.110 -> ~> 4.21, ver envs/*/versions.tf), porque el
# recurso azurerm_function_app_flex_consumption solo existe desde la
# versión 4.21 del provider.

resource "azurerm_service_plan" "this" {
  name                = "asp-novapay-serverless-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  os_type             = "Linux"
  sku_name            = "FC1"
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

# Flex Consumption exige un contenedor blob explícito para el paquete
# de despliegue (no basta con "una cuenta de almacenamiento" como en
# el modelo clásico de azurerm_linux_function_app).
resource "azurerm_storage_container" "deployments" {
  name                  = "func-novapay-pagos-deployments"
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

resource "azurerm_function_app_flex_consumption" "this" {
  name                = "func-novapay-pagos-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  service_plan_id     = azurerm_service_plan.this.id

  # Autenticación al contenedor de despliegue por identidad
  # administrada, no por cadena de conexión con clave — continúa la
  # jerarquía "eliminar el secreto" (documento de diseño, sección 7).
  storage_container_type      = "blobContainer"
  storage_container_endpoint  = "${azurerm_storage_account.this.primary_blob_endpoint}${azurerm_storage_container.deployments.name}"
  storage_authentication_type = "SystemAssignedIdentity"

  runtime_name    = "dotnet-isolated"
  runtime_version = "8.0"

  # Techo de instancias reconciliado contra el límite REAL de Azure SQL
  # (100 concurrent workers por vCore en Gen5 — Microsoft Learn), no un
  # número arbitrario: reserva como máximo ~15% del presupuesto total
  # de workers de la base de datos reutilizada para este flujo nuevo,
  # dejando el resto para el App Service transaccional existente
  # (documento de diseño, sección 8, con la cuenta completa mostrada).
  # Distinto por ambiente porque el SKU de Azure SQL también lo es
  # (GP_Gen5_2 en dev = 200 workers; BC_Gen5_4 en prod = 400).
  maximum_instance_count = var.max_instance_count
  instance_memory_in_mb  = 2048

  # Deliberadamente SIN bloque "always_ready": el default (0 instancias
  # precalentadas) es lo que preserva el cold start real que motivó
  # elegir un plan serverless en la sección 1 del documento de diseño.

  # Integración VNet regional hacia la subred integracion, delegada a
  # Microsoft.Web/serverFarms (módulo networking) — a diferencia del
  # plan de Consumo clásico (Y1), Flex Consumption sí la soporta de
  # forma nativa.
  virtual_network_subnet_id = var.integracion_subnet_id

  # Identidad SystemAssigned única, compartida por las dos funciones
  # que aloja este recurso (ValidatePayment, ProcessPayment). Azure Functions
  # no tiene identidad a nivel de función individual — ver documento de
  # diseño, sección 5. También es la identidad que autentica contra el
  # contenedor de despliegue (storage_authentication_type de arriba).
  identity {
    type = "SystemAssigned"
  }

  site_config {}

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

  # Nota de despliegue (Fase 5): con storage_authentication_type =
  # "SystemAssignedIdentity", el propio Function App necesita el rol
  # de abajo (storage_access) para poder leer su paquete de despliegue.
  # Si el primer "apply" falla porque el rol aún no propagó cuando
  # Azure intenta validar el acceso, un segundo "apply" lo resuelve —
  # mismo tipo de riesgo de orden ya documentado para el data source
  # de host keys en modules/api-management.
}

# Permiso mínimo sobre su propia cuenta de almacenamiento, mismo
# patrón que functions_storage_access en compute-appservice — sin
# distribuir la clave de acceso compartida de la cuenta. Cubre tanto
# el contenedor de despliegue como cualquier otro blob de runtime.
resource "azurerm_role_assignment" "storage_access" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = azurerm_function_app_flex_consumption.this.identity[0].principal_id
}
