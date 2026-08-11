# Módulo `api-management`

Aprovisiona Azure API Management (Consumption) como API Gateway del flujo de confirmación y notificación de pagos: expone `POST /api/v1/payments/confirmations` y enruta hacia `func-novapay-pagos-${env}`.

## Por qué APIM y no Application Gateway

APIM es la única pieza de borde de Azure diseñada para *gobernar APIs* (subscription keys, rate limiting/cuota por consumidor, versionado). No reemplaza conceptualmente Application Gateway (WAF/inspección de paquetes) — Application Gateway no está provisionado en este repositorio y no participa en este flujo.

## Entradas principales
- `publisher_name` / `publisher_email` (requeridos por Azure), `function_app_name` / `function_app_id` / `function_default_hostname` (de `compute-serverless`), `rate_limit_calls_per_minute` (default 60).

## Salidas
- `gateway_url`: endpoint público real de esta superficie mientras Azure Front Door no esté provisionado como código.
- `subscription_primary_key` (`sensitive`): subscription key lista de antemano, en vez de generarla manualmente por fuera de Terraform.

## Decisiones de diseño
- **`sku_name = "Consumption_0"`**: sin costo base, pero sin integración VNet — el Function App backend queda protegido por function key + restricción de IP a los rangos de salida documentados de APIM Consumption.
- **La function key vive como `azurerm_api_management_named_value` con `secret = true`**: cifrada dentro de APIM, nunca en Key Vault ni en un `.tfvars`.
- **`data.azurerm_function_app_host_keys` con `depends_on` explícito**: el nombre del Function App es determinístico (no un ID generado por Azure), así que Terraform no infiere automáticamente que debe esperar a que el recurso exista antes de leer sus host keys. El `depends_on` fuerza el orden correcto; si el primer `apply` no lo resuelve por el orden de refresh, un segundo `apply` lo completa — riesgo conocido de este patrón en el proveedor `azurerm`.
- **Solo rate limiting, sin cuota diaria**: el tier `Consumption_0` no soporta `rate-limit-by-key` ni `quota-by-key` (verificado con un `apply` real que devolvió `400 ValidationError`, y confirmado luego en Microsoft Learn — ninguna de las dos lista Consumption entre sus tiers soportados). Se usa `rate-limit` (per-subscription, sí disponible en Consumption); una cuota diaria por key queda fuera de alcance por limitación real del SKU, no por omisión. Tampoco se ha sometido a prueba de carga real.

Depende de `compute-serverless` (backend real) — capa 2: plataforma de ejecución.
