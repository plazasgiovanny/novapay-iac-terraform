# El source (no la versión — eso lo fija la raíz) tiene que declararse
# también en este módulo: sin esto, Terraform asume el namespace por
# defecto "hashicorp/azapi" para el nombre local "azapi", que no existe
# (el provider real es "Azure/azapi"). Ver envs/*/versions.tf para el
# porqué de esta dependencia (backend tipo Pool de APIM, ADR-03 U4).
terraform {
  required_providers {
    azapi = {
      source = "Azure/azapi"
    }
  }
}
