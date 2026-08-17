# `data-sql-secondary`

Auto-Failover Group de Azure SQL (ADR-06, Bloque 2e de la Fase 3 de U4).

## Etapa 1 (completada 2026-08-17)

Servidor lógico secundario aislado (sin Private Endpoint, sin failover group), para validar con un recurso real si esta suscripción permite aprovisionar Azure SQL en una región distinta de `centralus` — ninguna otra región tenía precedente empírico. `northcentralus` resultó bloqueada (`ProvisioningDisabled`, mismo error que `eastus2`/`eastus`/`westus2`/`southcentralus`); `canadacentral` sí validó. La base de datos "probe" usada para esa validación ya cumplió su propósito y se eliminó en la Etapa 2.

## Etapa 2 (esta)

- **Private Endpoint del servidor secundario**, en la subred de datos de la región **primaria** (centralus) — no hace falta una VNet nueva en `canadacentral`: Azure SQL Database soporta Private Endpoint cross-región (verificado contra la documentación oficial de Azure Private Link antes de asumirlo; Cosmos DB y Key Vault, por ejemplo, no lo soportan).
- Registrado en la **misma** zona DNS privada (`privatelink.database.windows.net`) que ya usa el servidor primario (`modules/data-sql`, salida `private_dns_zone_id`) — no una zona nueva. Con ambos servidores en la misma zona, el registro DNS del listener del failover group se resuelve de forma privada hacia el lado que esté vigente en cada momento, sin que la aplicación necesite saber cuál es.
- El recurso `azurerm_mssql_failover_group` en sí **no vive en este módulo** — une el servidor primario (`modules/data-sql`) con el secundario (este módulo), así que vive en la raíz del ambiente (`envs/{prod,dev}/main.tf`), mismo criterio ya usado para las asignaciones de rol que cruzan capas.
- La réplica real de `sqldb-novapay-core-{env}` en el servidor secundario la crea y administra Azure automáticamente al configurar el failover group — no es un recurso Terraform aparte.
- Política de failover **manual** (ADR-06): el listener y la replicación continua sí son automáticos, pero promover el secundario a primario exige una decisión y un comando explícitos, nunca un umbral automático.
- Los 2 Function Apps de pagos (`compute-serverless`/`compute-serverless-canary`) se reconfiguran para conectarse al **listener** del failover group, no al FQDN del servidor primario directamente. `api-novapay-{env}` (`compute-appservice`) queda **fuera de este cambio**: no tiene ningún `app_settings`/secreto de Key Vault gestionado por Terraform para la conexión a SQL en este repositorio — su "cadena de conexión de infraestructura desde la Entrega 1" (ADR-06) es un artefacto heredado de una entrega anterior, fuera del alcance de este repositorio de infraestructura.

## Costo real, no oculto

A diferencia de la Etapa 1 (una base `Basic` mínima, ~US$5/mes), la réplica real que Azure crea para el failover group iguala el tier de la base primaria (`sql_sku_name`, `S3` en prod) — es un costo continuo real, no un experimento barato. Aceptado explícitamente en ADR-06 ("Negativas": costo adicional real de un segundo servidor/base de datos activo).
