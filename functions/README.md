# `functions/` — código de aplicación del flujo serverless

Este directorio vive dentro del mismo repositorio de infraestructura (`novapay-iac-terraform-main`) porque, para el alcance de este entregable académico, mantener infraestructura y aplicación juntas simplifica la coordinación entre Giovanny (Terraform) y Johan (código). No es parte de `azurerm`: Terraform aprovisiona `func-novapay-pagos-{env}` vacío; el `.zip` de despliegue de este proyecto se sube aparte (`func azure functionapp publish` o el pipeline).

## Contenido

| Carpeta | Qué es |
|---|---|
| `NovaPay.Payments/` | Proyecto .NET 8 isolated worker con las dos funciones del flujo: `ValidatePayment` (HTTP trigger) y `ProcessPayment` (Service Bus trigger). Ver su propio `README.md` para setup y ejecución local. |

## Responsabilidad y límite

Igual que `sql/`, este código depende de recursos que ya deben existir (Function App, Service Bus, Azure SQL — `modules/compute-serverless`, `modules/messaging-servicebus`, `modules/data-sql`) y de que el script `sql/002_notificaciones_transaccionales.sql` ya se haya ejecutado contra la base de datos real (usuario contenido AAD + tabla `TransactionalNotifications`). No se puede desplegar ni correr en vacío.
