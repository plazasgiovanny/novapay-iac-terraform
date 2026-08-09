# Módulo `compute-serverless`

Aprovisiona el Function App `func-novapay-pagos-${env}` que aloja las dos funciones del flujo de confirmación y notificación de pagos (`ValidarPago`, HTTP trigger; `ProcesarPago`, Service Bus trigger — código de Johan). Nuevo desde la Entrega 2, deliberadamente separado del Service Plan Dedicated que usa `compute-appservice`.

## Por qué un módulo nuevo y no una extensión de `compute-appservice`

El Function App `async_workers` de la Entrega 1 corre en el mismo App Service Plan (Dedicated, siempre activo) que el backend transaccional — no hay cómputo serverless real (escalado a cero, cold start, pago por ejecución) en el repositorio. La Entrega 2 evalúa explícitamente esos conceptos (documento de diseño, sección 1), así que este módulo crea un Service Plan de Consumo (`Y1`, parametrizable a `EP1`) exclusivo para este slice, sin modificar ni arriesgar el `async_workers` existente.

## Entradas principales
- `integracion_subnet_id` (de `networking`, subred delegada a `Microsoft.Web/serverFarms`), `function_plan_sku` (default `Y1`), `servicebus_namespace_fqdn` (de `messaging-servicebus`), `appinsights_connection_string` (de `observability`).

## Salidas
- `principal_id`: identidad **única**, compartida por `ValidarPago` y `ProcesarPago` — Azure Functions no tiene identidad a nivel de función individual (documento de diseño, sección 5). Se usa en la raíz para los role assignments de Service Bus y en el script SQL para el usuario contenido AAD.
- `default_hostname` / `function_app_id`: consumidos por `api-management` (backend HTTP y data source de host keys).

## Decisiones de diseño
- **Storage account exclusiva** (`stnovapaypagos${env}`), no compartida con `stnovapayfunc${env}` de `async_workers` — evita acoplar dos workloads con ciclos de vida distintos.
- **`storage_uses_managed_identity = true`**: sin clave de cuenta de almacenamiento en configuración.
- **Conexión a Service Bus solo por FQDN + identidad administrada** (`serviceBusConnection__fullyQualifiedNamespace` / `credential = "managedidentity"`), nunca por cadena de conexión con clave — coherente con `local_auth_enabled = false` del namespace.
- **`function_plan_sku` parametrizado**: si en el despliegue real (Fase 5) la región elegida no soporta integración VNet regional en Consumo Linux, se cambia a `EP1` sin tocar código — riesgo ya anotado en el documento de diseño, sección 9.

Depende de `networking` (subred delegada), `messaging-servicebus` (FQDN) y `observability` (Application Insights) — capa 2: plataforma de ejecución, mismo nivel que `compute-appservice`.
