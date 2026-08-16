# Valores de ejemplo para el ambiente prod. Los IDs de Microsoft Entra
# ID y de la VNet hub son placeholders ilustrativos: en un despliegue
# real se inyectan desde variables del pipeline o desde un almacén de
# secretos, nunca se hardcodean con valores productivos en este
# archivo (ver .gitignore).

environment = "prod"
# HALLAZGO REAL (terraform apply contra Azure): esta suscripción bloquea
# Azure SQL en eastus2/eastus/westus2/southcentralus ("Provisioning is
# restricted in this region") y tiene cuota 0 de App Service Plan (todas
# las SKU, no solo Premium) en eastus2. Probado con recursos reales:
# centralus sí permite ambos. Pendiente confirmar con soporte de Azure
# si es una restricción propia de este tipo de suscripción o temporal.
location = "centralus"

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
    # HALLAZGO REAL (apply real fallido): la integración VNet regional
    # clásica de App Service/Functions (compute-appservice, no Flex
    # Consumption) sí exige delegación a Microsoft.Web/serverFarms,
    # aunque el módulo no la declaraba como obligatoria hasta ahora —
    # "Subnet ... is missing a delegation to Microsoft.Web/serverFarms".
    delegation = {
      name                    = "delegation-appservice"
      service_delegation_name = "Microsoft.Web/serverFarms"
    }
  }
  integracion = {
    cidr = "10.20.3.0/24"
    allowed_rules = [
      { name = "allow-from-aplicacion", priority = 100, protocol = "Tcp", port = "443", source = "10.20.2.0/24" }
    ]
    # Requerida por la integración VNet regional del Function App
    # serverless en Flex Consumption (modules/compute-serverless).
    # HALLAZGO REAL: Flex Consumption delega a Microsoft.App/environments
    # (no Microsoft.Web/serverFarms, que es el delegado correcto solo
    # para el modelo clásico de App Service/Functions) y su action
    # requerido es distinto (.../subnets/join/action, no .../subnets/action)
    # — confirmado tras un apply real fallido por SubnetMissingRequiredDelegation.
    delegation = {
      name                    = "delegation-serverless"
      service_delegation_name = "Microsoft.App/environments"
      actions                 = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
  datos = {
    cidr = "10.20.4.0/24"
    allowed_rules = [
      { name = "allow-sql-from-aplicacion", priority = 100, protocol = "Tcp", port = "1433", source = "10.20.2.0/24" }
    ]
  }
}

# HALLAZGO REAL (terraform apply contra Azure): esta suscripción es
# Free Trial — "Free Trial subscriptions can provision Basic, Standard
# S0 through S3 databases... up to 100 eDTU". Business Critical
# (BC_Gen5_4, vCore) queda descartado por completo, no solo limitado.
# Se usa Standard S3 (DTU, el techo permitido) sin redundancia zonal
# (no confirmado que Free Trial la soporte). Pendiente reflejar este
# cambio en el documento de diseño — se pierde el argumento de SLA
# >= 99.95% vía Business Critical que motivó la elección original.
sql_sku_name        = "S3"
sql_zone_redundant  = false
aad_admin_login     = "grp-novapay-dba"
aad_admin_object_id = "00000000-0000-0000-0000-000000000001"

# HALLAZGO REAL (terraform apply contra Azure): esta suscripción tiene
# cuota 0 para SKU Premium v3 (P1v3/P2v3) en todas las regiones probadas
# (eastus2 y centralus) — "Current Limit (PremiumV3 VMs): 0". Se usa
# Standard (S1) en su lugar: sigue soportando autoescalado (a diferencia
# de Basic, que no lo soporta), a costa de perder el argumento de
# capacidad/SLA que motivó Premium en el diseño original. Pendiente
# reflejar este cambio en el documento de diseño.
#
# 3 instancias iniciales, con perfil de autoescalado 3 a 24 (8x el
# mínimo) para absorber picos de tráfico sin degradación; en dev el
# rango es 1-2, suficiente para pruebas.
appservice_sku_name      = "S1"
appservice_worker_count  = 3
appservice_autoscale_min = 3
appservice_autoscale_max = 5 # TEMPORAL: cap de costo para la ventana de despliegue de evidencia (ver 03_guia_despliegue_manual.md). Revertir a 24 en el Paso 9.

# Bitácora >= 5 años exigida por cumplimiento normativo, frente a 30
# días en dev. HALLAZGO REAL (terraform plan contra Azure): Log
# Analytics Workspace no soporta retención nativa mayor a 730 días
# (2 años) — 1826 es rechazado por la API. Se usa el máximo real (730)
# aquí; para retención de 5 años se necesitaría exportar a un storage
# con política de inmutabilidad (Data Export + Archive tier), fuera
# del alcance actual. Pendiente actualizar el documento de diseño.
retention_in_days = 730
alert_email       = "sre-novapay@example.com"

# Cada intento real de despliegue destruido deja su Key Vault en
# soft-delete con purge_protection_enabled = true (no se puede purgar
# ni reusar el nombre hasta que expire su retención) — kv-novapay-prod,
# kv-novapay-prod-v2 y kv-novapay-prod-v3 ya quedaron así tras rondas
# anteriores (esta última tras el ciclo de reconstrucción de Fase 3,
# 2026-08). Sufijo temporal para poder desplegar mientras tanto; quitar
# cuando ya no aplique (y limpiar los soft-deleted acumulados).
keyvault_name_suffix = "-v4"

# Rol de despliegue (Website Contributor, acotado al Function App
# serverless) para poder publicar código sin publish profile. Vacío
# por defecto (var.deployer_principal_id) — el valor real de quien
# despliega va en local.auto.tfvars (no versionado), nunca aquí.

# Flujo serverless. El Function App usa Flex Consumption (FC1,
# hardcodeado en modules/compute-serverless) — no requiere variable
# de SKU aquí.
apim_publisher_name  = "NovaPay - Plataforma"
apim_publisher_email = "sre-novapay@example.com"

# HALLAZGO REAL (apply de reconstrucción, 2026-08-16): el apply se
# quedó colgado en data.azurerm_function_app_host_keys — el Function
# App recién creado no tiene código desplegado todavía (eso lo hace un
# pipeline aparte, ver ADR-01/02), así que su runtime nunca responde
# "list keys" con éxito. false para completar el bootstrap sin esa
# cadena. Vuelve a true aquí: el primer despliegue de código a ambas
# instancias (func-novapay-pagos-prod y -canary-prod, vía
# bootstrap-deploy.yml en novapay-functions, break-glass fuera del
# pipeline normal de CD por el mismo motivo circular) ya fue exitoso —
# az functionapp keys list confirma host key real en ambas.
apim_wire_backend = true

# Techo de instancias reconciliado contra el límite real de Azure SQL
# BC_Gen5_4 (400 concurrent workers, Microsoft Learn): reserva ~15%
# del presupuesto (60 workers) para este flujo, compartido con el
# App Service transaccional existente. Con maxConcurrentCalls = 4 en
# el trigger de Service Bus, 15 instancias x 4 = 60 workers en el
# peor caso de ProcessPayment, con margen para ValidatePayment.
serverless_max_instance_count = 15
