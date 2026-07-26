# Composición raíz del ambiente dev. Instancia los mismos módulos que
# prod (envs/prod/main.tf), con parámetros de menor costo y sin
# redundancia zonal (sección 3.4).

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
}

# --- Capa 2: plataforma de ejecución (depende de la capa 1) ---

module "data_sql" {
  source = "../../modules/data-sql"

  environment         = var.environment
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  data_subnet_id      = module.networking.subnet_ids["datos"]
  sku_name            = var.sql_sku_name
  zone_redundant      = var.sql_zone_redundant
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
  key_vault_uri                  = module.security_keyvault.vault_uri
  functions_storage_account_name = azurerm_storage_account.functions.name
  functions_storage_account_id   = azurerm_storage_account.functions.id
  tags                           = local.common_tags
}

# Asignaciones de rol que cruzan capa 1 y capa 2: viven en la raíz
# para no introducir una dependencia circular entre security-keyvault
# y compute-appservice (ver nota en modules/security-keyvault/main.tf).
# Materializan el principio de mínimo privilegio de la sección 4.3:
# cada identidad recibe únicamente el rol que necesita, sobre el
# alcance mínimo (el vault, no la suscripción completa).
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

# --- Capa 3: observabilidad (transversal a las capas 1 y 2) ---

module "observability" {
  source = "../../modules/observability"

  environment         = var.environment
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  retention_in_days   = var.retention_in_days
  alert_email         = var.alert_email
  tags                = local.common_tags

  # Se observan las capas 1 y 2 sin que el módulo observability
  # necesite conocer su tipo (contrato de la sección 3.3).
  monitored_resource_ids = {
    vnet         = module.networking.vnet_id
    key_vault    = module.security_keyvault.key_vault_id
    sql_database = module.data_sql.database_id
    app_service  = module.compute_appservice.api_id
    functions    = module.compute_appservice.functions_id
  }
}
