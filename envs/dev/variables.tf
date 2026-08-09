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
}

variable "subscription_id" {
  description = "ID de la suscripción de Azure. Obligatorio para el provider desde azurerm 4.x (antes se inferían solo del contexto de Azure CLI)."
  type        = string
}

variable "hub_vnet_id" {
  description = "ID de la VNet hub compartida, gestionada fuera de este repositorio (plataforma central de conectividad)."
  type        = string
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

variable "aad_admin_login" {
  description = "Nombre del grupo de Microsoft Entra ID administrador de Azure SQL."
  type        = string
}

variable "aad_admin_object_id" {
  description = "Object ID de ese grupo."
  type        = string
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
}

variable "keyvault_name_suffix" {
  description = "Sufijo opcional para el nombre del Key Vault, usado para evitar colisión con un vault soft-deleted de un despliegue anterior (ver modules/security-keyvault/variables.tf)."
  type        = string
  default     = ""
}

# --- Variables del flujo serverless ---

variable "apim_publisher_name" {
  description = "Nombre del publicador de la instancia de APIM (requerido por Azure)."
  type        = string
}

variable "apim_publisher_email" {
  description = "Correo del publicador de la instancia de APIM (requerido por Azure)."
  type        = string
}

variable "serverless_max_instance_count" {
  description = "Techo de instancias del Function App serverless, reconciliado contra el límite real de concurrent workers de Azure SQL (200 workers en dev/GP_Gen5_2, 400 en prod/BC_Gen5_4). Distinto por ambiente, sin default deliberado."
  type        = number
}

