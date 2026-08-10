# NovaPay.Payments

Azure Functions (.NET 8, isolated worker) que aloja `ValidatePayment` y `ProcessPayment`, el flujo de confirmación y notificación de pagos de NovaPay descrito en la Entrega 2 (Unidad 3). Se despliega sobre `func-novapay-pagos-{env}` (Flex Consumption), aprovisionado por `modules/compute-serverless`.

## Estructura

```
NovaPay.Payments/
├── Functions/
│   ├── ValidatePayment.cs   # HTTP trigger, POST /api/confirmations
│   └── ProcessPayment.cs    # Service Bus trigger, cola sbq-novapay-pagos-pendientes-{env}
├── Models/
│   ├── PaymentConfirmationRequest.cs  # body del POST
│   └── PaymentValidatedEvent.cs       # evento publicado en la cola
├── Data/
│   ├── SqlConnectionFactory.cs               # conexión a Azure SQL vía Managed Identity
│   ├── TransactionalNotificationsRepository.cs  # idempotencia (UNIQUE TransactionId) + persistencia
│   └── AccountValidationService.cs           # validación de cuenta/límites — PENDIENTE, ver abajo
├── Program.cs
└── host.json
```

## Cómo funciona el flujo

1. `ValidatePayment` recibe `POST /api/confirmations` (APIM reenvía aquí).
2. Valida el body, revisa si el `transactionId` ya fue procesado (`409` si sí), valida cuenta/monto/límites (`400` si no pasa), y si todo está bien:
   - responde `202 Accepted` con `{transactionId, status:"pending"}`,
   - publica un `ServiceBusMessage` con `MessageId = transactionId` (activa la deduplicación nativa de la cola) y el evento `PaymentValidated` serializado como body.
3. `ProcessPayment` consume ese mensaje, inserta en `dbo.TransactionalNotifications` (segunda capa de idempotencia: si el `INSERT` viola `UNIQUE(TransactionId)`, se trata como ya procesado, no como error) y marca la notificación como `sent` (simulada, sin proveedor externo real).
4. Si `ProcessPayment` lanza una excepción no controlada (error transitorio), el runtime abandona el mensaje y Service Bus lo reintenta según `host.json` (`maxRetryCount = 5`, backoff exponencial 5s–60s) hasta el `max_delivery_count = 5` de la cola; agotados los intentos, cae a la Dead-Letter Queue.

## Requisitos previos (ya verificados en esta máquina)

- .NET SDK con soporte para `net8.0` (no hace falta el SDK 8.x instalado aparte: el runtime `Microsoft.NETCore.App 8.0.27` ya está presente, y los SDKs 9/10 pueden compilar/ejecutar proyectos `net8.0` sin problema).
- Azure Functions Core Tools v4 (`func --version`).
- Azure CLI (`az`), con sesión iniciada contra la suscripción real de NovaPay si vas a probar contra recursos reales (`az account set --subscription <id>`).

## Configuración local

```bash
cp local.settings.json.example local.settings.json
```

`local.settings.json` **no se versiona** (está en `.gitignore`). Ajusta los valores al ambiente real (`dev` normalmente):

| Setting | De dónde sale |
|---|---|
| `serviceBusConnection__fullyQualifiedNamespace` | `sb-novapay-{env}.servicebus.windows.net` — salida `namespace_fqdn` de `messaging-servicebus` |
| `ServiceBusQueueName` | `sbq-novapay-pagos-pendientes-{env}` — salida `queue_name` de `messaging-servicebus` |
| `SqlServer__Fqdn` | `sql-novapay-{env}.database.windows.net` — salida `fully_qualified_domain_name` de `data-sql` |
| `SqlServer__Database` | `sqldb-novapay-core-{env}` — salida `database_name` de `data-sql` |

Estos cuatro valores ya viajan como app settings reales una vez desplegado (`modules/compute-serverless/main.tf`) — `local.settings.json` solo los duplica para desarrollo local.

**Importante sobre identidad para pruebas locales**: en Azure, la autenticación es 100% por Managed Identity (Service Bus y SQL). Localmente no existe Managed Identity, así que `DefaultAzureCredential`/`Authentication=Active Directory Default` cae a tu sesión de `az login` — tu usuario necesita los mismos roles que la identidad del Function App (`Azure Service Bus Data Sender`/`Data Receiver` sobre la cola, usuario AAD con `SELECT/INSERT/UPDATE` sobre `TransactionalNotifications`) para que las pruebas locales funcionen de extremo a extremo contra los recursos reales de `dev`.

## Ejecutar localmente

```bash
dotnet build
func start
```

`ValidatePayment` queda en `http://localhost:7071/api/confirmations`.

## Desplegar

```bash
func azure functionapp publish func-novapay-pagos-<env>
```

## Pendiente / coordinación necesaria

- **Tabla de cuentas real**: `AccountValidationService` todavía no consulta el core bancario — solo aplica un límite máximo configurable (`Payments__MaxTransactionAmount`). El nombre real de la tabla de cuentas/movimientos está señalado como pendiente en `sql/002_notificaciones_transaccionales.sql` (línea 79, en el repo raíz). Hay que confirmarlo y completar `AccountValidationService.ValidateAsync`.
- **Script SQL**: `sql/002_notificaciones_transaccionales.sql` debe ejecutarse contra `sqldb-novapay-core-{env}` (crea la tabla + el usuario contenido AAD `func-novapay-pagos-{env}`) antes de que esta app pueda escribir nada.
- **App settings de Terraform**: se agregaron `ServiceBusQueueName`, `SqlServer__Fqdn` y `SqlServer__Database` a `modules/compute-serverless/main.tf` (antes no existían) para que esta app no tenga que hardcodear nombres de recursos por ambiente — cambio que hay que coordinar con Giovanny y aplicar con `terraform apply` antes del próximo despliegue.
- **Reactivar el backend de APIM**: una vez este código esté desplegado y `/api/confirmations` responda, descomentar el bloque `data.azurerm_function_app_host_keys` en `modules/api-management/main.tf` (hoy comentado porque fallaba con el Function App vacío).
