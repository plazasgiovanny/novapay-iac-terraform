# Módulo: data-sql-secondary
# Etapa 1 del Auto-Failover Group de Azure SQL (ADR-06, U4): SOLO un
# servidor lógico secundario + una base de datos vacía de SKU mínimo en
# una segunda región, deliberadamente aislado del resto del diseño (sin
# Private Endpoint, sin VNet, sin replicación/failover group todavía).
#
# El propósito único de esta etapa es validar con un recurso real si
# esta suscripción permite aprovisionar Azure SQL en la región elegida
# — ninguna región fuera de "centralus" (la del servidor primario,
# modules/data-sql) tiene precedente empírico en esta suscripción, y ya
# se documentó que varias regiones bloquean Azure SQL por completo (ver
# envs/prod/prod.tfvars, HALLAZGO REAL sobre eastus2/eastus/westus2/
# southcentralus). Si el apply falla aquí, se degrada a Active
# Geo-Replication simple sin Failover Group (alternativa ya descrita en
# ADR-06) — no bloquea el resto del checklist de Fase 3.
#
# Etapa 2 (failover group + Private Endpoint cross-región + reconfigurar
# los 3 componentes al listener DNS) se construye en un módulo/PR
# aparte, solo si esta etapa valida.

resource "azurerm_mssql_server" "secondary" {
  name                = "sql-novapay-secondary-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  version             = "12.0"

  # Mismo criterio de seguridad que el servidor primario (modules/data-sql):
  # sin endpoint público, autenticación exclusiva por Microsoft Entra ID.
  # Sin Private Endpoint todavía (aislado a propósito en esta etapa) — el
  # servidor queda inalcanzable por diseño hasta la Etapa 2, no es un
  # descuido.
  public_network_access_enabled = false

  identity {
    type = "SystemAssigned"
  }

  azuread_administrator {
    login_username              = var.aad_admin_login
    object_id                   = var.aad_admin_object_id
    tenant_id                   = var.tenant_id
    azuread_authentication_only = true
  }

  tags = var.tags
}

# Base de datos vacía de SKU mínimo — no es la réplica real del
# failover group (esa la crea Azure automáticamente al configurar el
# failover group en la Etapa 2 sobre la base primaria existente). Sirve
# únicamente para confirmar que esta suscripción también permite crear
# una base de datos en la región secundaria, no solo el servidor lógico
# (el servidor en sí no tiene costo; la base sí). SKU DTU (no vCore):
# esta suscripción es Free Trial y solo permite Basic/Standard S0-S3
# (ver HALLAZGO REAL en envs/prod/prod.tfvars sobre sql_sku_name) — el
# mismo límite aplica aquí.
resource "azurerm_mssql_database" "probe" {
  name      = "sqldb-novapay-secondary-probe-${var.environment}"
  server_id = azurerm_mssql_server.secondary.id
  sku_name  = var.probe_sku_name

  tags = var.tags
}
