# Módulo `compute-serverless`

Aprovisiona el Function App `func-novapay-pagos-${env}` que aloja las dos funciones del flujo de confirmación y notificación de pagos (`ValidatePayment`, HTTP trigger; `ProcessPayment`, Service Bus trigger). Deliberadamente separado del Service Plan Dedicated que usa `compute-appservice`.

## Por qué Flex Consumption (FC1) y no Y1/EP1

Azure SQL solo expone Private Endpoint (`public_network_access_enabled = false`), así que este Function App necesita integración VNet regional para llegar a la base de datos. El plan de Consumo clásico (Y1) no soporta integración VNet regional bajo ninguna circunstancia — no es un límite por región, es una restricción estructural del SKU. Elastic Premium (EP1) sí la soporta, pero garantiza como mínimo una instancia siempre activa, perdiendo el escalado real a cero. **Flex Consumption (FC1)** soporta integración VNet regional de forma nativa y sigue escalando a cero por defecto (0 instancias "Always Ready" salvo configuración explícita). Costo de la decisión: `azurerm_function_app_flex_consumption` solo existe desde la versión 4.21 del provider `azurerm` (ver `envs/*/versions.tf`).

## Entradas principales
- `integracion_subnet_id` (de `networking`, subred delegada a `Microsoft.Web/serverFarms`), `max_instance_count` (sin default — obliga a decidir explícitamente por ambiente, ver más abajo), `servicebus_namespace_fqdn` (de `messaging-servicebus`), `appinsights_connection_string` (de `observability`).

## Salidas
- `principal_id`: identidad **única**, compartida por `ValidatePayment` y `ProcessPayment` — Azure Functions no tiene identidad a nivel de función individual. Se usa en la raíz para los role assignments de Service Bus y en el script SQL para el usuario contenido AAD. También es la identidad que autentica al Function App contra su propio contenedor de despliegue.
- `default_hostname` / `function_app_id`: consumidos por `api-management` (backend HTTP y data source de host keys).

## Decisiones de diseño
- **Contenedor de almacenamiento explícito** (`azurerm_storage_container.deployments`): Flex Consumption exige un contenedor blob específico para el paquete de despliegue — a diferencia del modelo clásico (`azurerm_linux_function_app`), no basta con apuntar a una cuenta de almacenamiento genérica.
- **`storage_authentication_type = "SystemAssignedIdentity"`**: sin clave de cuenta de almacenamiento en configuración, mismo criterio que el resto del repositorio.
- **Sin bloque `always_ready`**: se deja en su default (0 instancias precalentadas) para no anular el escalado a cero real.
- **`maximum_instance_count = var.max_instance_count` (5 en dev, 15 en prod) / `instance_memory_in_mb = 2048`**: reconciliados contra el límite real de concurrent workers de la Azure SQL Database reutilizada (100 workers por vCore en Gen5, fuente: Microsoft Learn — 200 en dev/`GP_Gen5_2`, 400 en prod/`BC_Gen5_4`). Se reserva como máximo ~15% de ese presupuesto para este flujo, dejando el resto para el App Service transaccional existente. Con `maxConcurrentCalls = 4` en la configuración del trigger de Service Bus, el peor caso de `ProcessPayment` es `max_instance_count × 4` workers concurrentes.
- **Conexión a Service Bus solo por FQDN + identidad administrada** (`serviceBusConnection__fullyQualifiedNamespace` / `credential = "managedidentity"`), nunca por cadena de conexión con clave — coherente con `local_auth_enabled = false` del namespace.

Depende de `networking` (subred delegada), `messaging-servicebus` (FQDN) y `observability` (Application Insights) — capa 2: plataforma de ejecución, mismo nivel que `compute-appservice`.
