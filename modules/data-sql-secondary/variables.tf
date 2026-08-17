variable "environment" {
  description = "Nombre del ambiente (dev, prod)."
  type        = string
}

variable "location" {
  description = "Región secundaria de Azure, distinta de la región del servidor primario (modules/data-sql). Sin precedente empírico en esta suscripción — es el propio propósito de esta etapa validarla."
  type        = string
}

variable "resource_group_name" {
  description = "Grupo de recursos del ambiente (el mismo del resto del diseño — el aislamiento de esta etapa es funcional, no de resource group)."
  type        = string
}

variable "probe_sku_name" {
  description = "SKU DTU de la base de datos de prueba (Basic/S0-S3 — esta suscripción es Free Trial, ver HALLAZGO REAL en envs/prod/prod.tfvars). Deliberadamente el mínimo: esta base no sirve para nada más que confirmar aprovisionamiento."
  type        = string
  default     = "Basic"
}

variable "aad_admin_login" {
  description = "Mismo administrador de Microsoft Entra ID que el servidor primario (modules/data-sql)."
  type        = string
}

variable "aad_admin_object_id" {
  description = "Object ID de Microsoft Entra ID del administrador anterior."
  type        = string
}

variable "tenant_id" {
  description = "ID del tenant de Microsoft Entra ID."
  type        = string
}

variable "tags" {
  description = "Etiquetas obligatorias."
  type        = map(string)
}
