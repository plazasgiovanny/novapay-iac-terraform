# Módulo: data-sql
# Azure SQL Database para el estado transaccional de NovaPay (cuentas,
# saldos, movimientos), sin endpoint público y con autenticación
# exclusiva por Microsoft Entra ID (sin usuario/contraseña SQL).

resource "azurerm_mssql_server" "this" {
  name                = "sql-novapay-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  version             = "12.0"

  # El servidor no expone endpoint público: todo el acceso ocurre por
  # Private Endpoint dentro de la subred de datos. Esta decisión
  # reduce directamente el alcance de cumplimiento PCI DSS.
  public_network_access_enabled = false

  identity {
    type = "SystemAssigned"
  }

  # Administración exclusiva por Microsoft Entra ID: se elimina el
  # usuario/contraseña "sa" desde el aprovisionamiento, en lugar de
  # custodiar esa credencial.
  azuread_administrator {
    login_username              = var.aad_admin_login
    object_id                   = var.aad_admin_object_id
    tenant_id                   = var.tenant_id
    azuread_authentication_only = true
  }

  tags = var.tags
}

resource "azurerm_mssql_database" "core" {
  name      = "sqldb-novapay-core-${var.environment}"
  server_id = azurerm_mssql_server.this.id
  sku_name  = var.sku_name

  # Redundancia zonal en producción: réplicas síncronas y conmutación
  # por error automática que sostienen el SLA >= 99.95%.
  zone_redundant = var.zone_redundant

  tags = var.tags
}

resource "azurerm_private_endpoint" "sql" {
  name                = "pe-sql-novapay-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.data_subnet_id

  private_service_connection {
    name                           = "sql-connection"
    private_connection_resource_id = azurerm_mssql_server.this.id
    subresource_names              = ["sqlServer"]
    is_manual_connection           = false
  }

  tags = var.tags
}

# Nota de gobierno: las identidades administradas de App Service y
# Functions (salidas de compute-appservice) se mapean como usuarios
# contenidos en la base de datos ("CREATE USER [app-novapay-api] FROM
# EXTERNAL PROVIDER") mediante un script T-SQL versionado que el
# pipeline ejecuta tras el "apply". No es un recurso de azurerm: la
# creación de usuarios contenidos ocurre dentro del motor de la base
# de datos, no en el plano de control de Azure Resource Manager, y
# por tanto queda fuera del alcance de este módulo — se documenta
# aquí para que la frontera quede explícita.
