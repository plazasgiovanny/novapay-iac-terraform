# `sql/` — scripts T-SQL versionados

Cambios de esquema y de usuarios contenidos AAD en Azure SQL que quedan **fuera de `azurerm`** por diseño: Azure Resource Manager no tiene control sobre el motor de la base de datos (creación de tablas, usuarios contenidos, permisos). Este límite ya estaba documentado en `modules/data-sql/main.tf`, pero nunca se había materializado como archivo real hasta `002_notificaciones_transaccionales.sql`.

## Límite de responsabilidad

Este repositorio de infraestructura llega hasta la **Azure SQL Database aprovisionada** (`modules/data-sql`) — no hasta las tablas de negocio. La creación de tablas queda fuera de su alcance: es responsabilidad de quien construye la aplicación que las usa. Por eso `002_notificaciones_transaccionales.sql` contiene dos partes con alcances distintos: la sección de `CREATE TABLE` es una **propuesta** de esquema de partida (puede tomarse, ajustarse o reemplazarse — no forma parte del alcance de este repositorio); la sección de `CREATE USER`/`GRANT` sí es parte de este repositorio (identidad/permisos), pero depende en orden de que la tabla ya exista.

## Convención

- Un archivo por cambio de esquema, numerado secuencialmente: `NNN_descripcion.sql` (3 dígitos, sin reiniciar por ambiente — la numeración es global al repositorio, no por `dev`/`prod`).
- `001` está implícitamente reservado para el usuario contenido de `app-novapay-api-{env}` (documentado en su momento, nunca materializado como archivo).
- Cada script trae un comentario de cabecera explicando cuál es su dependencia (qué recurso de Terraform debe existir antes de ejecutarlo) y qué parte del script queda fuera del alcance de este repositorio, si mezcla ambos casos (ver arriba).
- Los placeholders `{env}` se sustituyen manualmente o por el pipeline antes de ejecutar — estos scripts no son módulos de Terraform y no se interpolan automáticamente.

## Ejecución

Manual (Azure Data Studio / `sqlcmd` con autenticación AAD) o por el pipeline, **después** de `terraform apply` — el script referencia recursos (nombres de Function Apps, identidades administradas) que deben existir primero. No se ejecuta como parte de `terraform plan`/`apply`.

## Índice

| Script | Contenido |
|---|---|
| `002_notificaciones_transaccionales.sql` | Propuesta de tabla `dbo.TransactionalNotifications` (fuera del alcance de este repositorio) + usuario contenido AAD de `func-novapay-pagos-{env}` y permisos mínimos (parte real de este repositorio). |
