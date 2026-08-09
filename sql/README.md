# `sql/` — scripts T-SQL versionados

Cambios de esquema y de usuarios contenidos AAD en Azure SQL que quedan **fuera de `azurerm`** por diseño: Azure Resource Manager no tiene control sobre el motor de la base de datos (creación de tablas, usuarios contenidos, permisos). Este límite ya estaba documentado en `modules/data-sql/main.tf` desde la Entrega 1, pero nunca se había materializado como archivo real hasta la Entrega 2 — `002_notificaciones_transaccionales.sql` es el primero.

## Convención

- Un archivo por cambio de esquema, numerado secuencialmente: `NNN_descripcion.sql` (3 dígitos, sin reiniciar por ambiente — la numeración es global al repositorio, no por `dev`/`prod`).
- `001` está implícitamente reservado para el usuario contenido de `app-novapay-api-{env}` de la Entrega 1 (documentado en su momento, nunca materializado como archivo — no se reconstruye retroactivamente para no reescribir historia de una entrega ya cerrada).
- Cada script trae un comentario de cabecera explicando qué entrega/documento de diseño lo origina y cuál es su dependencia (qué recurso de Terraform debe existir antes de ejecutarlo).
- Los placeholders `{env}` se sustituyen manualmente o por el pipeline antes de ejecutar — estos scripts no son módulos de Terraform y no se interpolan automáticamente.

## Ejecución

Manual (Azure Data Studio / `sqlcmd` con autenticación AAD) o por el pipeline, **después** de `terraform apply` — el script referencia recursos (nombres de Function Apps, identidades administradas) que deben existir primero. No se ejecuta como parte de `terraform plan`/`apply`.

## Índice

| Script | Entrega | Contenido |
|---|---|---|
| `002_notificaciones_transaccionales.sql` | Entrega 2 (flujo serverless) | Tabla `dbo.NotificacionesTransaccionales`, usuario contenido AAD de `func-novapay-pagos-{env}`, permisos mínimos. |
