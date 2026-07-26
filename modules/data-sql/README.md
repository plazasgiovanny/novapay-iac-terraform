# Módulo `data-sql`

Azure SQL Database para el estado transaccional de NovaPay. Sin acceso público, con Private Endpoint y administración exclusiva por Microsoft Entra ID (`azuread_authentication_only = true`): no existe usuario/contraseña SQL que custodiar.

## Entradas principales
`data_subnet_id` (de `networking`), `sku_name` / `zone_redundant` (varían por ambiente, sección 3.4), `aad_admin_object_id`.

## Salidas
`database_id`: consumido por `observability` para diagnostic settings. `server_id` y `fully_qualified_domain_name`: expuestos para diagnóstico y para el script T-SQL post-apply que crea los usuarios contenidos (sección 4.5), no consumidos por otro módulo de Terraform.

Capa 2 (plataforma de ejecución): depende de `networking`.
