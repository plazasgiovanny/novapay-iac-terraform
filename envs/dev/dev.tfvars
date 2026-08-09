# Valores de ejemplo para el ambiente dev. Los IDs de Microsoft Entra
# ID y de la VNet hub son placeholders ilustrativos: en un despliegue
# real se inyectan desde variables del pipeline o desde un almacén de
# secretos, nunca se hardcodean con valores productivos en este
# archivo (ver .gitignore).

environment = "dev"
location    = "eastus2"

tenant_id       = "00000000-0000-0000-0000-000000000000"
subscription_id = "00000000-0000-0000-0000-000000000000"
hub_vnet_id     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-novapay-hub/providers/Microsoft.Network/virtualNetworks/vnet-novapay-hub"

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
    # Requerida por la integración VNet regional del Function App
    # serverless (modules/compute-serverless).
    delegation = {
      name                    = "delegation-serverless"
      service_delegation_name = "Microsoft.Web/serverFarms"
    }
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

appservice_sku_name      = "P1v3"
appservice_worker_count  = 1
appservice_autoscale_min = 1
appservice_autoscale_max = 2

retention_in_days = 30
alert_email       = "sre-novapay@example.com"

# Flujo serverless. El Function App usa Flex Consumption (FC1,
# hardcodeado en modules/compute-serverless) — no requiere variable
# de SKU aquí.
apim_publisher_name  = "NovaPay - Plataforma"
apim_publisher_email = "sre-novapay@example.com"

# Techo de instancias reconciliado contra el límite real de Azure SQL
# GP_Gen5_2 (200 concurrent workers, Microsoft Learn): reserva ~15%
# del presupuesto (30 workers) para este flujo, compartido con el
# App Service transaccional existente. Con maxConcurrentCalls = 4 en
# el trigger de Service Bus, 5 instancias x 4 = 20 workers en el peor
# caso de ProcessPayment, con margen para ValidatePayment.
serverless_max_instance_count = 5
