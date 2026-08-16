# Módulo: compute-serverless
# Function App dedicado al flujo de confirmación y notificación de
# pagos. Deliberadamente separado del Service Plan Dedicated de
# compute-appservice.
#
# Plan Flex Consumption (FC1), no Y1 ni EP1: Azure SQL solo expone
# Private Endpoint (acceso público deshabilitado), así que este
# Function App necesita integración VNet regional. El plan de Consumo
# clásico (Y1) no la soporta bajo ninguna circunstancia — no es un
# límite por región, es una restricción estructural del SKU. Elastic
# Premium (EP1) sí la soporta, pero mantiene como mínimo una instancia
# siempre activa, perdiendo el escalado real a cero. FC1 soporta
# integración VNet regional de forma nativa y sigue escalando a cero
# por defecto ("Always Ready" = 0 instancias salvo configuración
# explícita). Costo de la decisión: requiere provider azurerm >= 4.21
# (ver envs/*/versions.tf), ya que azurerm_function_app_flex_consumption
# no existe en versiones anteriores.

# HALLAZGO REAL (smoke test tras activar wire_backend, 2026-08-16): el
# service tag "ApiManagement" NO restringe de forma confiable el
# tráfico de salida de un APIM en tier Consumption — confirmado contra
# documentación oficial de Microsoft ("For API Management instances
# created in service tiers that run on shared infrastructure
# [Consumption, ...], the instance does not have a dedicated IP
# address"; Service Tags "don't map to APIM's public IP ranges
# properly" para restricciones de Function/App Service). Causó un 403
# real bloqueando tráfico legítimo. Mitigación real recomendada por
# Microsoft para este caso: acotar por el datacenter/región completo
# (mucho más amplio que solo APIM, pero es la única opción real de
# restricción por IP sin subir a un tier con VNet integration — mismo
# tipo de trade-off ya aceptado en otras partes del proyecto, p.ej.
# Service Bus Standard sin Private Link).
locals {
  # No hace falta enumerar los ~400 CIDR del tag: "AzureCloud.<region>"
  # es un service tag válido de una sola entrada, Azure lo resuelve
  # server-side.
  outbound_service_tag = "AzureCloud.${var.location}"
}

resource "azurerm_service_plan" "this" {
  name                = "asp-novapay-serverless${var.instance_suffix}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  os_type             = "Linux"
  sku_name            = "FC1"
  tags                = var.tags
}

# Cuenta de almacenamiento exclusiva de esta instancia (runtime, no
# datos de negocio) — no se comparte con stnovapayfunc${env}
# (async_workers) ni con la otra instancia física (estable/canary),
# para no acoplar workloads con ciclos de vida y volúmenes de
# operación distintos, ni permitir que un despliegue corrupto de una
# instancia afecte a la otra.
resource "azurerm_storage_account" "this" {
  name                     = var.storage_account_name
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
  name                  = "func-novapay-pagos${var.instance_suffix}-deployments"
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

resource "azurerm_function_app_flex_consumption" "this" {
  name                = "func-novapay-pagos${var.instance_suffix}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  service_plan_id     = azurerm_service_plan.this.id

  # Autenticación al contenedor de despliegue por identidad
  # administrada, no por cadena de conexión con clave.
  storage_container_type      = "blobContainer"
  storage_container_endpoint  = "${azurerm_storage_account.this.primary_blob_endpoint}${azurerm_storage_container.deployments.name}"
  storage_authentication_type = "SystemAssignedIdentity"

  runtime_name    = "dotnet-isolated"
  runtime_version = "8.0"

  # Techo de instancias reconciliado contra el límite real de Azure SQL
  # (100 concurrent workers por vCore en Gen5 — Microsoft Learn), no un
  # número arbitrario: reserva como máximo ~15% del presupuesto total
  # de workers de la base de datos para este flujo, dejando el resto
  # para el App Service transaccional existente. Distinto por ambiente
  # porque el SKU de Azure SQL también lo es (GP_Gen5_2 en dev = 200
  # workers; BC_Gen5_4 en prod = 400).
  maximum_instance_count = var.max_instance_count
  instance_memory_in_mb  = 2048

  # Deliberadamente SIN bloque "always_ready": el default (0 instancias
  # precalentadas) es lo que preserva el escalado real a cero.

  # Integración VNet regional hacia la subred integracion, delegada a
  # Microsoft.Web/serverFarms (módulo networking) — a diferencia del
  # plan de Consumo clásico (Y1), Flex Consumption sí la soporta de
  # forma nativa.
  virtual_network_subnet_id = var.integracion_subnet_id

  # Identidad SystemAssigned única, compartida por las dos funciones
  # que aloja este recurso (ValidatePayment, ProcessPayment). Azure
  # Functions no tiene identidad a nivel de función individual.
  # También es la identidad que autentica contra el contenedor de
  # despliegue (storage_authentication_type de arriba).
  identity {
    type = "SystemAssigned"
  }

  # ip_restriction del sitio principal (tráfico de invocación real, el
  # que atraviesa APIM) — DENY por defecto salvo el datacenter/región
  # completo (ver local.outbound_service_tag arriba: "ApiManagement" no
  # sirve para esto en tier Consumption). Deliberadamente NO se toca
  # scm_ip_restriction aquí: el despliegue de código (ADR-02, zip
  # deploy vía OIDC desde GitHub Actions) usa el endpoint SCM/Kudu, con
  # IPs de runner dinámicas que no pertenecen a ningún service tag fijo
  # — restringirlo también rompería el pipeline de despliegue de
  # novapay-functions.
  site_config {
    ip_restriction_default_action = "Deny"

    ip_restriction {
      name        = "allow-region"
      priority    = 100
      action      = "Allow"
      service_tag = local.outbound_service_tag
    }
  }

  app_settings = {
    # AzureWebJobsStorage por connection string, no por identidad
    # administrada — excepción deliberada al patrón "sin cadenas de
    # conexión" del resto de este bloque. azurerm_function_app_flex_consumption
    # tiene un bug conocido y documentado (hashicorp/terraform-provider-azurerm#29149):
    # la plataforma de Azure reinyecta un AzureWebJobsStorage plano con
    # credencial inválida sin importar la configuración por identidad
    # (__accountName/__credential), lo que rompe el host. El workaround
    # oficial de Microsoft (AzureWebJobsStorage = "") solo evita el
    # crash del host, pero un reporte confirmado de la comunidad muestra
    # que además rompe el scale controller de triggers no-HTTP (colas)
    # — inaceptable para ProcessPayment. Única solución confiable:
    # connection string real, pero gestionada 100% por Terraform, nunca
    # a mano (mismo criterio ya aceptado para la function key de APIM).
    AzureWebJobsStorage = azurerm_storage_account.this.primary_connection_string

    # Application Insights por connection string (no instrumentation
    # key legacy) — trazas distribuidas de extremo a extremo.
    APPLICATIONINSIGHTS_CONNECTION_STRING = var.appinsights_connection_string

    # Conexión a Service Bus por identidad administrada: solo el FQDN
    # del namespace viaja en configuración, nunca una cadena de
    # conexión con clave compartida.
    serviceBusConnection__fullyQualifiedNamespace = var.servicebus_namespace_fqdn
    serviceBusConnection__credential              = "managedidentity"

    # Topic (compartido por ambas instancias) y Subscription (propia de
    # esta instancia), para que los triggers/output bindings de
    # ValidatePayment/ProcessPayment (%ServiceBusTopicName%/
    # %ServiceBusSubscriptionName%) no los hardcodeen por ambiente.
    ServiceBusTopicName        = var.servicebus_topic_name
    ServiceBusSubscriptionName = var.servicebus_subscription_name

    # Conexión a Azure SQL por identidad administrada (Authentication=
    # Active Directory Default en el código de la función) — solo
    # nombres, nunca cadena de conexión con contraseña.
    SqlServer__Fqdn     = var.sql_server_fqdn
    SqlServer__Database = var.sql_database_name
  }

  tags = var.tags

  # Nota de despliegue: con storage_authentication_type =
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
