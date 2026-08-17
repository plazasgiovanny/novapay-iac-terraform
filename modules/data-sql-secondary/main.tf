# Módulo: data-sql-secondary
# Auto-Failover Group de Azure SQL (ADR-06, U4).
#
# Etapa 1 (completada 2026-08-17, release v1.0.20-v1.0.22): servidor
# lógico secundario aislado, para validar con un recurso real si esta
# suscripción permite aprovisionar Azure SQL en una región distinta de
# "centralus" (la del servidor primario, modules/data-sql) — ninguna
# otra región tenía precedente empírico. `northcentralus` resultó
# bloqueada (mismo error que eastus2/eastus/westus2/southcentralus);
# `canadacentral` sí validó. La base de datos "probe" (SKU mínimo,
# aislada) que se usó para esa validación ya cumplió su propósito y se
# elimina en esta etapa — el Auto-Failover Group de abajo crea su
# propia réplica real sobre `sqldb-novapay-core-${var.environment}`,
# administrada por Azure, no por este módulo.
#
# Etapa 2 (esta): Private Endpoint del servidor secundario (reutiliza
# la MISMA zona DNS privada del servidor primario, no una nueva — así
# es como el listener del failover group resuelve correctamente hacia
# el lado vigente tras una conmutación, confirmado contra la
# documentación oficial de Microsoft sobre Private Link + Failover
# Groups antes de codificar, no asumido). El recurso
# azurerm_mssql_failover_group en sí vive en la raíz del ambiente
# (envs/{prod,dev}/main.tf), no en este módulo ni en data-sql: une dos
# servidores de dos módulos distintos, mismo criterio ya usado para
# las asignaciones de rol que cruzan capas (ver comentario en
# envs/prod/main.tf sobre security-keyvault/compute-appservice).

resource "azurerm_mssql_server" "secondary" {
  name                = "sql-novapay-secondary-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  version             = "12.0"

  # Mismo criterio de seguridad que el servidor primario (modules/data-sql):
  # sin endpoint público, autenticación exclusiva por Microsoft Entra ID.
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

# Cross-región real: este Private Endpoint vive en la subred de datos
# de la región PRIMARIA (centralus), apuntando a un servidor SQL en
# canadacentral — verificado contra la documentación oficial de Azure
# Private Link antes de asumirlo (Azure SQL Database está en la lista
# de servicios que sí soportan Private Endpoint cross-región; Cosmos DB
# y Key Vault, por ejemplo, no). No hace falta una VNet nueva en
# canadacentral solo para esto.
resource "azurerm_private_endpoint" "secondary" {
  name                = "pe-sql-novapay-secondary-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.data_subnet_id

  private_service_connection {
    name                           = "sql-secondary-connection"
    private_connection_resource_id = azurerm_mssql_server.secondary.id
    subresource_names              = ["sqlServer"]
    is_manual_connection           = false
  }

  # La MISMA zona DNS privada del servidor primario (salida
  # private_dns_zone_id de modules/data-sql) — no una zona nueva. Con
  # ambos servidores registrados en la misma zona, el registro DNS del
  # listener del failover group (envs/{prod,dev}/main.tf) se resuelve
  # de forma privada hacia el lado que esté vigente en cada momento.
  private_dns_zone_group {
    name                 = "sql-secondary-dns-zone-group"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }

  tags = var.tags
}
