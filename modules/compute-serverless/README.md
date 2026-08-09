# Módulo `compute-serverless`

Aprovisiona el Function App `func-novapay-pagos-${env}` que aloja las dos funciones del flujo de confirmación y notificación de pagos (`ValidarPago`, HTTP trigger; `ProcesarPago`, Service Bus trigger — código de Johan). Nuevo desde la Entrega 2, deliberadamente separado del Service Plan Dedicated que usa `compute-appservice`.

## Historial de esta decisión: Y1 → EP1 → **Flex Consumption (FC1)**

1. **Primer diseño (Y1, plan de Consumo clásico)**: motivado por evaluar cold start real y escalado a cero, conceptos que `async_workers` (Dedicated, Entrega 1) no exhibe.
2. **Hallazgo al pasar a código**: Azure SQL solo expone Private Endpoint (`public_network_access_enabled = false` desde la Entrega 1), así que este Function App necesita integración VNet regional para llegar a la base de datos. **El plan de Consumo Y1 no soporta integración VNet regional bajo ninguna circunstancia** — no es un límite "según la región", es una restricción estructural del SKU.
3. **Alternativa descartada (EP1, Elastic Premium)**: sí soporta VNet integration, pero garantiza como mínimo una instancia siempre activa — pierde el argumento de cold start real que motivó elegir un plan serverless en primer lugar.
4. **Decisión final (FC1, Flex Consumption)**: soporta integración VNet regional de forma nativa **y** sigue escalando a cero por defecto (0 instancias "Always Ready" si no se configura lo contrario) — preserva intacto el argumento de cold start de la sección 1 del documento de diseño, sin sacrificar el acceso privado a SQL. El costo: `azurerm_function_app_flex_consumption` solo existe desde la versión 4.21 del provider `azurerm`, lo que obligó a subir el provider de todo el repositorio de `~> 3.110` a `~> 4.21` (ver `envs/*/versions.tf` y la nota de migración en la raíz del repo).

## Entradas principales
- `integracion_subnet_id` (de `networking`, subred delegada a `Microsoft.Web/serverFarms`), `servicebus_namespace_fqdn` (de `messaging-servicebus`), `appinsights_connection_string` (de `observability`).

## Salidas
- `principal_id`: identidad **única**, compartida por `ValidarPago` y `ProcesarPago` — Azure Functions no tiene identidad a nivel de función individual (documento de diseño, sección 5). Se usa en la raíz para los role assignments de Service Bus y en el script SQL para el usuario contenido AAD. También es la identidad que autentica al Function App contra su propio contenedor de despliegue.
- `default_hostname` / `function_app_id`: consumidos por `api-management` (backend HTTP y data source de host keys).

## Decisiones de diseño
- **Contenedor de almacenamiento explícito** (`azurerm_storage_container.deployments`): Flex Consumption exige un contenedor blob específico para el paquete de despliegue — a diferencia del modelo clásico (`azurerm_linux_function_app`), no basta con apuntar a una cuenta de almacenamiento genérica.
- **`storage_authentication_type = "SystemAssignedIdentity"`**: sin clave de cuenta de almacenamiento en configuración, mismo criterio que el resto del repositorio.
- **Sin bloque `always_ready`**: se deja en su default (0 instancias precalentadas) deliberadamente, para no anular el cold start real que es parte del objetivo pedagógico de esta entrega.
- **`maximum_instance_count = 40` / `instance_memory_in_mb = 2048`**: valores de partida razonables para el volumen de prueba de esta entrega, no una proyección de carga real — ajustar en la Fase 5 si la evidencia real lo justifica.
- **Conexión a Service Bus solo por FQDN + identidad administrada** (`serviceBusConnection__fullyQualifiedNamespace` / `credential = "managedidentity"`), nunca por cadena de conexión con clave — coherente con `local_auth_enabled = false` del namespace.

Depende de `networking` (subred delegada), `messaging-servicebus` (FQDN) y `observability` (Application Insights) — capa 2: plataforma de ejecución, mismo nivel que `compute-appservice`.
