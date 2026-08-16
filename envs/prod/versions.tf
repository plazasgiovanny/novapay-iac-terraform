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
      version = "~> 4.21"
    }
    # Solo para el backend tipo Pool de APIM (modules/api-management,
    # ADR-03 U4): azurerm_api_management_backend no soporta type="Pool"
    # todavía (issue abierto sin mergear, hashicorp/terraform-provider-azurerm#30855,
    # verificado antes de agregar esta dependencia) — azapi gestiona ese
    # recurso puntual llamando directo a la API ARM
    # (Microsoft.ApiManagement/service/backends). El resto del repo
    # sigue en azurerm.
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
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
    # Sin esto, la regla $Default (TrueFilter) que Azure crea
    # automáticamente al crear cada Subscription queda activa junto a la
    # SqlFilter de sourceInstance que declara este repo (con nombre
    # propio, no "$Default" — ver comentario en
    # modules/messaging-servicebus/main.tf sobre el bug real encontrado
    # al intentar gestionar un recurso llamado literalmente "$Default").
    # Ambas actuando en OR anularía el aislamiento por instancia.
    servicebus {
      auto_delete_subscription_default_rule = true
    }
  }
}

provider "azapi" {
  subscription_id = var.subscription_id
}
