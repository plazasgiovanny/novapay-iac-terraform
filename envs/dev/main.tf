# Composición raíz del ambiente dev. Instancia los mismos módulos que
# prod (envs/prod/main.tf), con parámetros de menor costo y sin
# redundancia zonal.

# Etiquetas obligatorias: ningún módulo puede omitirlas porque se
# inyectan de forma centralizada. "policies/require-tags.json"
# además las exige a nivel de política de Azure (ver policies.tf).
locals {
  common_tags = {
    environment         = var.environment
    owner               = "plataforma-novapay"
    cost_center         = "pagos-digitales"
    data_classification = "confidential-pci"
  }
}

resource "azurerm_resource_group" "this" {
  name     = "rg-novapay-${var.environment}"
  location = var.location
  tags     = local.common_tags
}

# Cuenta de almacenamiento requerida por el runtime de Azure
# Functions (no almacena datos de negocio de NovaPay).
resource "azurerm_storage_account" "functions" {
  name                     = "stnovapayfunc${var.environment}"
  resource_group_name      = azurerm_resource_group.this.name
  location                 = azurerm_resource_group.this.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  tags                     = local.common_tags
}

# --- Capa 1: red y seguridad base (sin dependencias entre sí) ---

module "networking" {
  source = "../../modules/networking"

  environment         = var.environment
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  vnet_cidr           = var.vnet_cidr
  hub_vnet_id         = var.hub_vnet_id
  subnets             = var.subnets
  tags                = local.common_tags
}

module "security_keyvault" {
  source = "../../modules/security-keyvault"

  environment         = var.environment
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  tenant_id           = var.tenant_id
  data_subnet_id      = module.networking.subnet_ids["datos"]
  tags                = local.common_tags
  name_suffix         = var.keyvault_name_suffix
}

# Capa 3, adelantada: observability se declara aquí (no al final del
# archivo) porque compute_serverless, más abajo, consume su salida
# appinsights_connection_string. Terraform resuelve por grafo de
# dependencias, no por orden textual del archivo: monitored_resource_ids
# sigue recibiendo, no generando, los IDs de las demás capas.
module "observability" {
  source = "../../modules/observability"

  environment         = var.environment
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  retention_in_days   = var.retention_in_days
  alert_email         = var.alert_email
  tags                = local.common_tags

  monitored_resource_ids = {
    vnet              = module.networking.vnet_id
    key_vault         = module.security_keyvault.key_vault_id
    sql_database      = module.data_sql.database_id
    app_service       = module.compute_appservice.api_id
    functions         = module.compute_appservice.functions_id
    service_bus       = module.messaging_servicebus.namespace_id
    apim              = module.api_management.id
    func_pagos        = module.compute_serverless.function_app_id
    func_pagos_canary = module.compute_serverless_canary.function_app_id
  }
}

# --- Capa 2: plataforma de ejecución (depende de la capa 1) ---

module "data_sql" {
  source = "../../modules/data-sql"

  environment         = var.environment
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  data_subnet_id      = module.networking.subnet_ids["datos"]
  virtual_network_id  = module.networking.vnet_id
  sku_name            = var.sql_sku_name
  zone_redundant      = var.sql_zone_redundant
  aad_admin_login     = var.aad_admin_login
  aad_admin_object_id = var.aad_admin_object_id
  tenant_id           = var.tenant_id
  tags                = local.common_tags
}

# Etapa 1 del Auto-Failover Group de SQL (ADR-06, Bloque 2e U4) — ver
# modules/data-sql-secondary/README.md. Deliberadamente sin conexión al
# resto del diseño todavía (sin Private Endpoint, sin failover group).
module "data_sql_secondary" {
  source = "../../modules/data-sql-secondary"

  environment         = var.environment
  location            = var.sql_secondary_location
  resource_group_name = azurerm_resource_group.this.name
  probe_sku_name      = var.sql_secondary_probe_sku_name
  aad_admin_login     = var.aad_admin_login
  aad_admin_object_id = var.aad_admin_object_id
  tenant_id           = var.tenant_id
  tags                = local.common_tags
}

module "compute_appservice" {
  source = "../../modules/compute-appservice"

  environment                    = var.environment
  location                       = var.location
  resource_group_name            = azurerm_resource_group.this.name
  app_subnet_id                  = module.networking.subnet_ids["aplicacion"]
  sku_name                       = var.appservice_sku_name
  worker_count                   = var.appservice_worker_count
  autoscale_min_count            = var.appservice_autoscale_min
  autoscale_max_count            = var.appservice_autoscale_max
  key_vault_uri                  = module.security_keyvault.vault_uri
  functions_storage_account_name = azurerm_storage_account.functions.name
  functions_storage_account_id   = azurerm_storage_account.functions.id
  tags                           = local.common_tags
}

# Asignaciones de rol que cruzan capa 1 y capa 2: viven en la raíz
# para no introducir una dependencia circular entre security-keyvault
# y compute-appservice (ver nota en modules/security-keyvault/main.tf).
# Mínimo privilegio: cada identidad recibe únicamente el rol que
# necesita, sobre el alcance mínimo (el vault, no la suscripción completa).
resource "azurerm_role_assignment" "api_kv_secrets_user" {
  scope                = module.security_keyvault.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.compute_appservice.api_principal_id
}

resource "azurerm_role_assignment" "functions_kv_secrets_user" {
  scope                = module.security_keyvault.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.compute_appservice.functions_principal_id
}

# --- Capa 2, continuación: flujo serverless de confirmación de pagos ---

module "messaging_servicebus" {
  source = "../../modules/messaging-servicebus"

  environment         = var.environment
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  action_group_id     = module.observability.action_group_id
  tags                = local.common_tags
}

module "compute_serverless" {
  source = "../../modules/compute-serverless"

  environment                   = var.environment
  location                      = var.location
  resource_group_name           = azurerm_resource_group.this.name
  integracion_subnet_id         = module.networking.subnet_ids["integracion"]
  max_instance_count            = var.serverless_max_instance_count
  instance_suffix               = ""
  storage_account_name          = "stnovapaypagos${var.environment}"
  servicebus_namespace_fqdn     = module.messaging_servicebus.namespace_fqdn
  servicebus_topic_name         = module.messaging_servicebus.topic_name
  servicebus_subscription_name  = module.messaging_servicebus.subscription_names["estable"]
  sql_server_fqdn               = module.data_sql.fully_qualified_domain_name
  sql_database_name             = module.data_sql.database_name
  appinsights_connection_string = module.observability.appinsights_connection_string
  tags                          = local.common_tags
}

module "compute_serverless_canary" {
  source = "../../modules/compute-serverless"

  environment                   = var.environment
  location                      = var.location
  resource_group_name           = azurerm_resource_group.this.name
  integracion_subnet_id         = module.networking.subnet_ids["integracion"]
  max_instance_count            = var.serverless_max_instance_count
  instance_suffix               = "-canary"
  storage_account_name          = "stnpypagoscanary${var.environment}"
  servicebus_namespace_fqdn     = module.messaging_servicebus.namespace_fqdn
  servicebus_topic_name         = module.messaging_servicebus.topic_name
  servicebus_subscription_name  = module.messaging_servicebus.subscription_names["canary"]
  sql_server_fqdn               = module.data_sql.fully_qualified_domain_name
  sql_database_name             = module.data_sql.database_name
  appinsights_connection_string = module.observability.appinsights_connection_string
  tags                          = local.common_tags
}

module "api_management" {
  source = "../../modules/api-management"

  environment                      = var.environment
  location                         = var.location
  resource_group_name              = azurerm_resource_group.this.name
  publisher_name                   = var.apim_publisher_name
  publisher_email                  = var.apim_publisher_email
  function_app_name                = module.compute_serverless.function_app_name
  function_app_id                  = module.compute_serverless.function_app_id
  function_default_hostname        = module.compute_serverless.default_hostname
  function_app_canary_name         = module.compute_serverless_canary.function_app_name
  function_app_canary_id           = module.compute_serverless_canary.function_app_id
  function_canary_default_hostname = module.compute_serverless_canary.default_hostname
  tags                             = local.common_tags
}

# Cada instancia física recibe Sender sobre el Topic completo (ambas
# publican al mismo Topic) pero Receiver únicamente sobre su propia
# Subscription — nunca la del otro slot (ver envs/prod/main.tf para el
# detalle del razonamiento, idéntico aquí).
resource "azurerm_role_assignment" "func_pagos_sb_sender" {
  scope                = module.messaging_servicebus.topic_id
  role_definition_name = "Azure Service Bus Data Sender"
  principal_id         = module.compute_serverless.principal_id
}

resource "azurerm_role_assignment" "func_pagos_sb_receiver" {
  scope                = module.messaging_servicebus.subscription_ids["estable"]
  role_definition_name = "Azure Service Bus Data Receiver"
  principal_id         = module.compute_serverless.principal_id
}

resource "azurerm_role_assignment" "func_pagos_canary_sb_sender" {
  scope                = module.messaging_servicebus.topic_id
  role_definition_name = "Azure Service Bus Data Sender"
  principal_id         = module.compute_serverless_canary.principal_id
}

resource "azurerm_role_assignment" "func_pagos_canary_sb_receiver" {
  scope                = module.messaging_servicebus.subscription_ids["canary"]
  role_definition_name = "Azure Service Bus Data Receiver"
  principal_id         = module.compute_serverless_canary.principal_id
}
