# Módulo `compute-appservice`

App Service (.NET 8) para el backend transaccional y Azure Functions para el motor antifraude y notificaciones (sección 2.1). Ambos con identidad administrada asignada por el sistema e integración a la subred de aplicación; sin claves de acceso ni cadenas de conexión en configuración. Incluye un perfil de autoescalado basado en CPU (`azurerm_monitor_autoscale_setting`) que materializa el requerimiento no funcional de escalabilidad de la sección 1.5.

## Entradas principales
`app_subnet_id` (de `networking`), `key_vault_uri` (de `security-keyvault`), `sku_name` / `worker_count` / `autoscale_min_count` / `autoscale_max_count` (varían por ambiente, sección 3.4).

## Salidas
`api_principal_id`, `functions_principal_id`: consumidos por la **composición raíz** (no por otros módulos) para asignar el rol "Key Vault Secrets User" sobre `security-keyvault`, evitando una dependencia circular entre ambos módulos (ver `envs/*/main.tf`). `api_id`, `functions_id`: consumidos por `observability` para diagnostic settings. `api_default_hostname`: backend del Application Gateway.

Capa 2 (plataforma de ejecución): depende de `networking` y `security-keyvault`. El acceso a Azure SQL de estas identidades **no** se resuelve en este módulo ni con un `azurerm_role_assignment`: se documenta en `data-sql` como un paso posterior al `apply` (usuario contenido vía script T-SQL, sección 4.5).
