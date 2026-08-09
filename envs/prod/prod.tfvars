# Valores de ejemplo para el ambiente prod (sección 3.4). Los IDs de
# Microsoft Entra ID y de la VNet hub son placeholders ilustrativos:
# en un despliegue real se inyectan desde variables del pipeline o
# desde un almacén de secretos, nunca se hardcodean con valores
# productivos en este archivo (ver .gitignore y sección 4.5).

environment = "prod"
location    = "eastus2"

tenant_id       = "00000000-0000-0000-0000-000000000000"
subscription_id = "00000000-0000-0000-0000-000000000000"
hub_vnet_id     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-novapay-hub/providers/Microsoft.Network/virtualNetworks/vnet-novapay-hub"

vnet_cidr = "10.20.0.0/16"

subnets = {
  publica = {
    cidr = "10.20.1.0/24"
    allowed_rules = [
      { name = "allow-https-inbound", priority = 100, protocol = "Tcp", port = "443", source = "Internet" }
    ]
  }
  aplicacion = {
    cidr = "10.20.2.0/24"
    allowed_rules = [
      { name = "allow-from-publica", priority = 100, protocol = "Tcp", port = "443", source = "10.20.1.0/24" }
    ]
  }
  integracion = {
    cidr = "10.20.3.0/24"
    allowed_rules = [
      { name = "allow-from-aplicacion", priority = 100, protocol = "Tcp", port = "443", source = "10.20.2.0/24" }
    ]
    # Delegada desde la Entrega 2: requerida por la integración VNet
    # regional del Function App de plan de Consumo (modules/compute-serverless).
    delegation = {
      name                    = "delegation-serverless"
      service_delegation_name = "Microsoft.Web/serverFarms"
    }
  }
  datos = {
    cidr = "10.20.4.0/24"
    allowed_rules = [
      { name = "allow-sql-from-aplicacion", priority = 100, protocol = "Tcp", port = "1433", source = "10.20.2.0/24" }
    ]
  }
}

# Business Critical con redundancia zonal: réplicas síncronas y
# conmutación por error automática, alineadas con el SLA >= 99.95%
# de la sección 1.5 (contraste directo con GP_Gen5_2/false en dev).
sql_sku_name        = "BC_Gen5_4"
sql_zone_redundant  = true
aad_admin_login     = "grp-novapay-dba"
aad_admin_object_id = "00000000-0000-0000-0000-000000000001"

# 3 instancias iniciales, con perfil de autoescalado 3 a 24 (8x el
# mínimo) para absorber picos de tráfico sin degradación (sección 1.5);
# en dev el rango es 1-2, suficiente para pruebas.
appservice_sku_name      = "P2v3"
appservice_worker_count  = 3
appservice_autoscale_min = 3
appservice_autoscale_max = 24

# Bitácora inmutable >= 5 años (1826 días) exigida por cumplimiento
# normativo, frente a 30 días en dev (sección 1.5).
retention_in_days = 1826
alert_email       = "sre-novapay@example.com"

# Flujo serverless (Entrega 2). El Function App usa Flex Consumption
# (FC1, hardcodeado en modules/compute-serverless) — no requiere
# variable de SKU aquí; ver documento de diseño, sección 1 y 9.
apim_publisher_name  = "NovaPay - Plataforma"
apim_publisher_email = "sre-novapay@example.com"

# Techo de instancias reconciliado contra el límite real de Azure SQL
# BC_Gen5_4 (400 concurrent workers, Microsoft Learn): reserva ~15%
# del presupuesto (60 workers) para este flujo nuevo, compartido con
# el App Service transaccional existente (documento de diseño, sección
# 8). 15 instancias x 4 concurrent calls recomendadas para Johan = 60
# workers en el peor caso de ProcessPayment, con margen para ValidatePayment.
serverless_max_instance_count = 15
