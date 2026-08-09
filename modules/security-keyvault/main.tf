# Módulo: security-keyvault
# Custodia de secretos y llaves. Autorización basada en roles de Azure
# (RBAC) en lugar de políticas de acceso heredadas, para que el
# principio de mínimo privilegio se exprese como asignaciones de rol
# auditables e independientes del recurso.

resource "azurerm_key_vault" "this" {
  name                = "kv-novapay-${var.environment}${var.name_suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = var.tenant_id
  sku_name            = "standard"

  # RBAC en vez de access policies: cada concesión de acceso queda
  # como una asignación de rol de Azure, versionable y auditable
  # desde el mismo plano de control de IAM.
  rbac_authorization_enabled = true

  # La eliminación definitiva requiere una acción explícita adicional:
  # evita que un "destroy" accidental borre secretos de forma
  # irrecuperable durante el período de retención.
  purge_protection_enabled   = true
  soft_delete_retention_days = 90

  # Sin endpoint público: todo el acceso ocurre por Private Endpoint
  # desde la subred de datos (mismo patrón que Azure SQL).
  public_network_access_enabled = false

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
  }

  tags = var.tags
}

resource "azurerm_private_endpoint" "keyvault" {
  name                = "pe-kv-novapay-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.data_subnet_id

  private_service_connection {
    name                           = "kv-connection"
    private_connection_resource_id = azurerm_key_vault.this.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  tags = var.tags
}

# Nota de diseño (evita dependencia circular): las asignaciones de rol
# "Key Vault Secrets User" para las identidades administradas de
# App Service y Functions se declaran en la composición raíz
# (envs/*/main.tf), no aquí. Este módulo no conoce qué identidades lo
# consumirán, y compute-appservice necesita `vault_uri` (salida de
# este módulo) para arrancar: si este módulo dependiera a su vez de
# las identidades de compute-appservice, el grafo de módulos sería
# circular. La asignación de rol, al vivir en la raíz, referencia
# ambos módulos sin que ninguno dependa del otro.
