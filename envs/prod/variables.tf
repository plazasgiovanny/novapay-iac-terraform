# Declaración de variables de la composición raíz. Los valores reales
# se asignan por ambiente en dev.tfvars / prod.tfvars; este archivo es
# idéntico en envs/dev y envs/prod porque ambos instancian los mismos
# módulos con distintos parámetros.

variable "environment" {
  description = "Nombre del ambiente."
  type        = string
}

variable "location" {
  description = "Región de Azure."
  type        = string
  default     = "eastus2"
}

variable "tenant_id" {
  description = "ID del tenant de Microsoft Entra ID."
  type        = string
  sensitive   = true
}

variable "subscription_id" {
  description = "ID de la suscripción de Azure. Obligatorio para el provider desde azurerm 4.x (antes se inferían solo del contexto de Azure CLI)."
  type        = string
  sensitive   = true
}

variable "hub_vnet_id" {
  description = "ID de la VNet hub compartida, gestionada fuera de este repositorio (plataforma central de conectividad)."
  type        = string
  sensitive   = true
}

variable "vnet_cidr" {
  description = "Bloque CIDR de la VNet spoke de este ambiente."
  type        = string
}

variable "subnets" {
  description = "Mapa de subredes (aplicación, integración, datos, pública) con su CIDR, reglas permitidas y delegación opcional (integracion se delega a Microsoft.Web/serverFarms)."
  type = map(object({
    cidr = string
    allowed_rules = list(object({
      name     = string
      priority = number
      protocol = string
      port     = string
      source   = string
    }))
    delegation = optional(object({
      name                    = string
      service_delegation_name = string
      actions                 = optional(list(string), ["Microsoft.Network/virtualNetworks/subnets/action"])
    }))
  }))
}

variable "sql_sku_name" {
  description = "SKU de Azure SQL Database."
  type        = string
}

variable "sql_zone_redundant" {
  description = "Redundancia zonal de Azure SQL Database."
  type        = bool
}

variable "sql_secondary_location" {
  description = "Región del servidor SQL secundario (Etapa 1 del Auto-Failover Group, ADR-06 U4) — distinta de var.location, sin precedente empírico en esta suscripción todavía."
  type        = string
}

variable "sql_secondary_probe_sku_name" {
  description = "SKU DTU mínimo de la base de datos de prueba en la región secundaria (Free Trial: solo Basic/S0-S3)."
  type        = string
  default     = "Basic"
}

variable "aad_admin_login" {
  description = "Nombre del grupo de Microsoft Entra ID administrador de Azure SQL."
  type        = string
}

variable "aad_admin_object_id" {
  description = "Object ID de ese grupo."
  type        = string
  sensitive   = true
}

variable "appservice_sku_name" {
  description = "SKU del App Service Plan."
  type        = string
}

variable "appservice_worker_count" {
  description = "Número inicial de instancias del App Service Plan."
  type        = number
}

variable "appservice_autoscale_min" {
  description = "Instancias mínimas del perfil de autoescalado."
  type        = number
}

variable "appservice_autoscale_max" {
  description = "Instancias máximas del perfil de autoescalado (techo del rango 5-8x el promedio ante picos de tráfico)."
  type        = number
}

variable "retention_in_days" {
  description = "Retención de logs en Log Analytics."
  type        = number
}

variable "alert_email" {
  description = "Correo del equipo SRE/DevOps para alertas."
  type        = string
  sensitive   = true
}

variable "keyvault_name_suffix" {
  description = "Sufijo opcional para el nombre del Key Vault, usado para evitar colisión con un vault soft-deleted de un despliegue anterior (ver modules/security-keyvault/variables.tf)."
  type        = string
  default     = ""
}

variable "deployer_principal_id" {
  description = "Object ID de la identidad (usuario o service principal) que recibe el rol 'Website Contributor' acotado al Function App serverless, para poder publicar código sin credenciales de larga duración. Vacío por defecto (nadie recibe el rol)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "servicebus_diagnostics_principal_id" {
  description = "Object ID de la identidad (usuario o service principal) que recibe 'Azure Service Bus Data Owner' acotado a la cola sbq-novapay-pagos-pendientes-{env}, para poder usar el Service Bus Explorer del portal (peek/receive/send) y publicar mensajes de prueba/diagnóstico directamente sin pasar por ValidatePayment. Vacío por defecto (nadie recibe el rol)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "novapay_functions_sp_principal_id" {
  description = "Object ID del service principal sp-novapay-functions-{env} (app registration OIDC de novapay-functions, creada fuera de Terraform — Bloque 3.1). Recibe 'Monitoring Metrics Publisher' acotado a la Data Collection Rule del evento PesoActualizado (ADR-07 U4), para que el job de CD pueda emitir el evento de cambio de peso via Logs Ingestion API con la misma identidad OIDC que ya usa para desplegar. Vacío por defecto (nadie recibe el rol) — distinto del Object ID (principalId) de las managed identities de los Function Apps; este es el Object ID del service principal de la app registration."
  type        = string
  default     = ""
  sensitive   = true
}

# --- Variables del flujo serverless ---

variable "apim_publisher_name" {
  description = "Nombre del publicador de la instancia de APIM (requerido por Azure)."
  type        = string
}

variable "apim_publisher_email" {
  description = "Correo del publicador de la instancia de APIM (requerido por Azure)."
  type        = string
  sensitive   = true
}

variable "apim_wire_backend" {
  description = "Ver modules/api-management: false durante el apply inicial de bootstrap (sin código desplegado todavía); true una vez el primer despliegue de código sea exitoso."
  type        = bool
  default     = true
}

variable "serverless_max_instance_count" {
  description = "Techo de instancias del Function App serverless, reconciliado contra el límite real de concurrent workers de Azure SQL (200 workers en dev/GP_Gen5_2, 400 en prod/BC_Gen5_4). Distinto por ambiente, sin default deliberado."
  type        = number
}

