# Valores de ejemplo para el ambiente dev (sección 3.4). Los IDs de
# Microsoft Entra ID y de la VNet hub son placeholders ilustrativos:
# en un despliegue real se inyectan desde variables del pipeline o
# desde un almacén de secretos, nunca se hardcodean con valores
# productivos en este archivo (ver .gitignore y sección 4.5).

environment = "dev"
location    = "eastus2"

tenant_id   = "00000000-0000-0000-0000-000000000000"
hub_vnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-novapay-hub/providers/Microsoft.Network/virtualNetworks/vnet-novapay-hub"

vnet_cidr = "10.10.0.0/16"

subnets = {
  publica = {
    cidr = "10.10.1.0/24"
    allowed_rules = [
      { name = "allow-https-inbound", priority = 100, protocol = "Tcp", port = "443", source = "Internet" }
    ]
  }
  aplicacion = {
    cidr = "10.10.2.0/24"
    allowed_rules = [
      { name = "allow-from-publica", priority = 100, protocol = "Tcp", port = "443", source = "10.10.1.0/24" }
    ]
  }
  integracion = {
    cidr = "10.10.3.0/24"
    allowed_rules = [
      { name = "allow-from-aplicacion", priority = 100, protocol = "Tcp", port = "443", source = "10.10.2.0/24" }
    ]
  }
  datos = {
    cidr = "10.10.4.0/24"
    allowed_rules = [
      { name = "allow-sql-from-aplicacion", priority = 100, protocol = "Tcp", port = "1433", source = "10.10.2.0/24" }
    ]
  }
}

sql_sku_name        = "GP_Gen5_2"
sql_zone_redundant  = false
aad_admin_login     = "grp-novapay-dba"
aad_admin_object_id = "00000000-0000-0000-0000-000000000001"

appservice_sku_name     = "P1v3"
appservice_worker_count = 1

retention_in_days = 30
alert_email       = "sre-novapay@example.com"
