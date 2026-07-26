# Módulo: compute-appservice
# Backend transaccional (App Service) y funciones asíncronas (Azure
# Functions) descritos en la sección 2.1. Ambos con identidad
# administrada asignada por el sistema, sin credenciales embebidas.

resource "azurerm_service_plan" "this" {
  name                = "asp-novapay-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  os_type             = "Linux"
  sku_name            = var.sku_name
  worker_count        = var.worker_count
  tags                = var.tags
}

resource "azurerm_linux_web_app" "api" {
  name                = "app-novapay-api-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  service_plan_id     = azurerm_service_plan.this.id

  # Integración de red privada: el tráfico de salida de la aplicación
  # se enruta por la subred de aplicación (contrato recibido del
  # módulo networking), sin exposición pública directa.
  virtual_network_subnet_id = var.app_subnet_id

  # Identidad administrada asignada por el sistema: la aplicación se
  # autentica ante Azure SQL y Key Vault sin ninguna credencial
  # almacenada en configuración ni en variables de entorno
  # (sección 4.5, gestión de secretos).
  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_stack {
      dotnet_version = "8.0"
    }
    minimum_tls_version = "1.2"
    ftps_state          = "Disabled"
  }

  app_settings = {
    # Solo la URI del Key Vault viaja en configuración; ningún
    # secreto ni cadena de conexión en texto plano (sección 4.5).
    KEY_VAULT_URI = var.key_vault_uri
  }

  tags = var.tags
}

# Funciones asíncronas para el motor antifraude y notificaciones
# (sección 2.1), sobre el mismo plan y con el mismo patrón de
# identidad administrada. El acceso a la cuenta de almacenamiento de
# Functions se hace por identidad administrada, no por clave de
# acceso compartida: se elimina el secreto en vez de custodiarlo
# (jerarquía de decisión de la sección 4.5).
resource "azurerm_linux_function_app" "async_workers" {
  name                 = "func-novapay-workers-${var.environment}"
  location             = var.location
  resource_group_name  = var.resource_group_name
  service_plan_id      = azurerm_service_plan.this.id
  storage_account_name = var.functions_storage_account_name

  storage_uses_managed_identity = true

  virtual_network_subnet_id = var.app_subnet_id

  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_stack {
      dotnet_version = "8.0"
    }
  }

  app_settings = {
    KEY_VAULT_URI = var.key_vault_uri
  }

  tags = var.tags
}

# Concede al Function App el permiso mínimo necesario sobre su propia
# cuenta de almacenamiento (mínimo privilegio, sección 4.3), en lugar
# de distribuir la clave de acceso compartida de la cuenta.
resource "azurerm_role_assignment" "functions_storage_access" {
  scope                = var.functions_storage_account_id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = azurerm_linux_function_app.async_workers.identity[0].principal_id
}

# Autoescalado basado en CPU: materializa el requerimiento no funcional
# "Absorber picos de tráfico sin degradación / autoescalado 5-8x el
# promedio" (sección 1.5). Sin este recurso, worker_count sería un
# número fijo y la elasticidad quedaría solo declarada en el papel.
resource "azurerm_monitor_autoscale_setting" "api" {
  name                = "autoscale-novapay-api-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  target_resource_id  = azurerm_service_plan.this.id

  profile {
    name = "cpu-based"

    capacity {
      default = var.worker_count
      minimum = var.autoscale_min_count
      maximum = var.autoscale_max_count
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 70
      }
      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 25
      }
      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }
  }

  tags = var.tags
}
