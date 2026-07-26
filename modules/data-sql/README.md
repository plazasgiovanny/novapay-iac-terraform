# Módulo `data-sql`

Azure SQL Database para el estado transaccional de NovaPay. Sin acceso público, con Private Endpoint y administración exclusiva por Microsoft Entra ID (`azuread_authentication_only = true`): no existe usuario/contraseña SQL que custodiar.

## Entradas principales
`data_subnet_id` (de `networking`), `sku_name` / `zone_redundant` (varían por ambiente, sección 3.4), `aad_admin_object_id`.

## Salidas
`server_id`, `database_id`: consumidos por `security-keyvault` y `observability`.

Capa 2 (plataforma de ejecución): depende de `networking`.
