# Módulo `api-management`

Aprovisiona Azure API Management (Consumption) como API Gateway del flujo de confirmación y notificación de pagos: expone `POST /api/v1/payments/confirmations` y enruta hacia `func-novapay-pagos-${env}`. Nuevo desde la Entrega 2 — no existía gobierno de API en la Entrega 1 (el backend transaccional se exponía directamente).

## Por qué APIM y no Application Gateway

APIM es la única pieza de borde de Azure diseñada para *gobernar APIs* (subscription keys, rate limiting/cuota por consumidor, versionado) — es la respuesta literal al requisito "API Gateway o equivalente" del enunciado. No reemplaza conceptualmente Application Gateway (WAF/inspección de paquetes), pero Application Gateway nunca se provisionó en Terraform (brecha heredada de la Entrega 1, documento de diseño sección 9) y no participa en este flujo. Ver también "Único punto de entrada externo" en el documento de diseño, sección 2.

## Entradas principales
- `publisher_name` / `publisher_email` (requeridos por Azure), `function_app_name` / `function_app_id` / `function_default_hostname` (de `compute-serverless`), `rate_limit_calls_per_minute` (default 60), `quota_calls_per_day` (default 5000).

## Salidas
- `gateway_url`: endpoint público real de esta superficie mientras Azure Front Door no esté provisionado como código.
- `subscription_primary_key` (`sensitive`): lista de antemano para el video de evidencia funcional (Fase 5), en vez de improvisarla en vivo durante la grabación.

## Decisiones de diseño
- **`sku_name = "Consumption_0"`**: sin costo base, pero sin integración VNet — el Function App backend queda protegido por function key + restricción de IP a los rangos de salida documentados de APIM Consumption (limitación aceptada, documento de diseño sección 9).
- **La function key vive como `azurerm_api_management_named_value` con `secret = true`**: cifrada dentro de APIM, nunca en Key Vault, en un `.tfvars`, ni en el código de Johan (documento de diseño, sección 7).
- **`data.azurerm_function_app_host_keys` con `depends_on` explícito**: el nombre del Function App es determinístico (no un ID generado por Azure), así que Terraform no infiere automáticamente que debe esperar a que el recurso exista antes de leer sus host keys. El `depends_on` fuerza el orden correcto; si el primer `apply` no lo resuelve por el orden de refresh, un segundo `apply` lo completa — riesgo conocido de este patrón en el proveedor `azurerm`, documentado como paso esperado del despliegue (Fase 5), no como fallo.
- **Rate limiting y cuota son "conceptuales"**: la política de APIM (`rate-limit-by-key` + `quota-by-key`) se define y se aplica, pero no se somete a prueba de carga real en esta entrega — es exactamente lo que pide el enunciado en la sección de escalabilidad.

Depende de `compute-serverless` (backend real) — capa 2: plataforma de ejecución.
