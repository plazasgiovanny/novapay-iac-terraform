# `data-sql-secondary`

Etapa 1 del Auto-Failover Group de Azure SQL (ADR-06, Bloque 2e de la Fase 3 de U4). Aprovisiona **solo** un servidor lógico secundario + una base de datos vacía de SKU mínimo en una segunda región — deliberadamente aislado del resto: sin Private Endpoint, sin integración de red, sin replicación ni failover group todavía.

## Por qué una etapa separada

Ninguna región distinta de `centralus` (la del servidor primario, `modules/data-sql`) tiene precedente empírico en esta suscripción. Ya se documentó que varias regiones (`eastus2`, `eastus`, `westus2`, `southcentralus`) bloquean Azure SQL por completo para esta suscripción ("Provisioning is restricted in this region"). Comprometerse de una vez al failover group completo (Etapa 2: `azurerm_mssql_failover_group` + Private Endpoint cross-región + reconfigurar `app_settings` en los 3 componentes) sin validar primero que la región elegida siquiera permite crear un servidor SQL sería construir sobre un supuesto no verificado.

## Resultado posible

- **Si el apply tiene éxito**: la región es viable, se procede con la Etapa 2 en un módulo/PR aparte.
- **Si el apply falla** por restricción de región/cuota: se prueba la siguiente región candidata. Si ninguna funciona, se degrada a Active Geo-Replication simple sin Failover Group (alternativa ya descrita en ADR-06) — no bloquea el resto del checklist de Fase 3.

## Historial real de regiones probadas

- `northcentralus` — **descartada** (apply real fallido, 2026-08-17): `ProvisioningDisabled`, "Provisioning is restricted in this region" — mismo error que ya bloqueaba `eastus2`/`eastus`/`westus2`/`southcentralus` para el servidor primario.
- `canadacentral` — candidata actual (`envs/prod/prod.tfvars`), sin probar todavía.

## Limpieza si no se avanza a la Etapa 2

Si la región valida pero por alguna razón no se continúa con la Etapa 2 en la misma sesión de trabajo, este módulo puede eliminarse de `envs/{prod,dev}/main.tf` sin dejar dependencias huérfanas — nada más en el diseño lo referencia todavía.
