# Mismo motivo que modules/api-management/versions.tf: sin esto,
# Terraform asume el namespace por defecto "hashicorp/azapi" para el
# nombre local "azapi", que no existe. Necesario aquí porque
# azurerm_log_analytics_workspace_table solo administra retención/plan
# de tablas ya existentes, no el esquema de una tabla personalizada
# nueva (Bloque 2d, ADR-07 U4) — se usa azapi_resource contra la API
# real de Tablas de Log Analytics.
terraform {
  required_providers {
    azapi = {
      source = "Azure/azapi"
    }
  }
}
