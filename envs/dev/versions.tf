# Fija las versiones de Terraform y del proveedor azurerm para reproducibilidad.
terraform {
  required_version = "~> 1.9"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # >= 4.21: azurerm_function_app_flex_consumption (modules/compute-serverless)
      # solo existe desde esa versión. El salto de 3.110 a 4.x trae cambios
      # incompatibles documentados en la guía oficial de migración de HashiCorp;
      # se auditó el repo completo contra esa guía antes de subir la versión.
      #
      # HALLAZGO REAL (2026-08-17): Dependabot abrió y se mergeó un PR
      # subiendo esto a "~> 5.1" (salto de versión MAYOR, sin auditar
      # contra la guía de migración de HashiCorp — mismo tipo de riesgo
      # ya reconocido para el salto 3.x→4.x, esta vez sin la revisión
      # previa). Revertido a 4.21 para volver a espejar envs/prod
      # (que sigue en 4.21, nunca se tocó) — dev sin esto queda
      # divergente del ambiente real sin ninguna razón funcional.
      version = "~> 4.21"
    }
    # Ver envs/prod/versions.tf: solo para el backend tipo Pool de APIM
    # (modules/api-management, ADR-03 U4) — azurerm_api_management_backend
    # no soporta type="Pool" todavía.
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
    # Ver envs/prod/versions.tf: solo para empaquetar el código
    # embebido del Function App de rollback-canary (Bloque 2g U4).
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  # El estado vive en Azure Blob Storage, segmentado por ambiente. Los
  # valores concretos de cuenta de almacenamiento y contenedor se inyectan
  # desde backend.hcl para no duplicar configuración entre dev y prod.
  backend "azurerm" {}
}

provider "azurerm" {
  # Desde azurerm 4.x, el Subscription ID ya no se infiere solo del
  # contexto de Azure CLI: el provider exige declararlo explícitamente
  # (subscription_id) o vía ARM_SUBSCRIPTION_ID.
  subscription_id = var.subscription_id

  features {
    key_vault {
      purge_soft_delete_on_destroy = false
    }
    # Ver envs/prod/versions.tf para el detalle: sin esto, la regla
    # $Default (TrueFilter) que Azure crea automáticamente por
    # Subscription queda activa junto a la SqlFilter de sourceInstance,
    # anulando el aislamiento por instancia.
    servicebus {
      auto_delete_subscription_default_rule = true
    }
  }
}

provider "azapi" {
  subscription_id = var.subscription_id
}
