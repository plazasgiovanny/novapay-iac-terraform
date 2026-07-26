# Módulo `compute-appservice`

App Service (.NET 8) para el backend transaccional y Azure Functions para el motor antifraude y notificaciones (sección 2.1). Ambos con identidad administrada asignada por el sistema e integración a la subred de aplicación; sin claves de acceso ni cadenas de conexión en configuración.

## Entradas principales
`app_subnet_id` (de `networking`), `key_vault_uri` (de `security-keyvault`), `sku_name` / `worker_count` (varían por ambiente, sección 3.4).

## Salidas
`api_principal_id`, `functions_principal_id`: consumidos por `data-sql` y `security-keyvault` para asignar roles de mínimo privilegio. `api_default_hostname`: backend del Application Gateway.

Capa 2 (plataforma de ejecución): depende de `networking` y `security-keyvault`.
