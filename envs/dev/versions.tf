# Fija las versiones de Terraform y del proveedor azurerm para
# garantizar reproducibilidad: el mismo código produce el mismo
# resultado sin importar quién o cuándo lo ejecute (sección 3.6).
terraform {
  required_version = "~> 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.110"
    }
  }

  # El estado vive en Azure Blob Storage, segmentado por ambiente
  # (sección 3.5). Los valores concretos de cuenta de almacenamiento
  # y contenedor se inyectan desde backend.hcl para no duplicar
  # configuración entre dev y prod.
  backend "azurerm" {}
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = false
    }
  }
}
