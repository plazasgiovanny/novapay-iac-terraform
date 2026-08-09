-- sql/002_notificaciones_transaccionales.sql
-- Entrega 2 (flujo serverless) — documento de diseño, secciones 5 y 6.
--
-- Fuera de azurerm por diseño: Azure Resource Manager no controla el
-- motor de Azure SQL, así que la creación de tablas y de usuarios
-- contenidos AAD se aplica con un script T-SQL versionado, ejecutado
-- manualmente o por el pipeline después de "terraform apply" (mismo
-- patrón ya documentado, pero nunca materializado como archivo, en
-- modules/data-sql/main.tf de la Entrega 1). Este es el primer script
-- real de la carpeta sql/ — ver sql/README.md para la convención de
-- numeración.
--
-- Sustituir {env} por el ambiente real (dev | prod) antes de ejecutar.
-- El nombre de usuario debe coincidir exactamente con el nombre del
-- recurso Function App (no con su principal_id/GUID) — así es como
-- Azure SQL resuelve un usuario contenido AAD contra una identidad
-- administrada de Azure.

-- 1. Tabla nueva: registro de notificaciones transaccionales.
--    TransactionId es la clave de idempotencia (segunda capa, la
--    primera es la deduplicación nativa de Service Bus — documento de
--    diseño, sección 4).
CREATE TABLE dbo.NotificacionesTransaccionales (
    Id               UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    TransactionId    UNIQUEIDENTIFIER NOT NULL,
    CuentaOrigen     NVARCHAR(50)     NOT NULL,
    CuentaDestino    NVARCHAR(50)     NOT NULL,
    Monto            DECIMAL(18,2)    NOT NULL,
    Canal            NVARCHAR(20)     NOT NULL, -- push | email | sms
    Estado           NVARCHAR(20)     NOT NULL, -- pendiente | enviado | fallido
    FechaCreacion    DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
    FechaEnvio       DATETIME2        NULL,

    CONSTRAINT UQ_NotificacionesTransaccionales_TransactionId UNIQUE (TransactionId)
);
GO

-- 2. Usuario contenido AAD para la identidad administrada SystemAssigned
--    compartida por ValidarPago y ProcesarPago (un único Function App
--    = una única identidad — documento de diseño, sección 5). Mismo
--    patrón que ya usa app-novapay-api-{env} en la Entrega 1.
CREATE USER [func-novapay-pagos-{env}] FROM EXTERNAL PROVIDER;
GO

-- 3. Permisos mínimos sobre la tabla nueva: ProcesarPago necesita
--    insertar/actualizar el registro de notificación; no se concede
--    DELETE (no hay caso de uso que lo requiera).
GRANT SELECT, INSERT, UPDATE ON dbo.NotificacionesTransaccionales TO [func-novapay-pagos-{env}];
GO

-- 4. PENDIENTE (no bloquea el Terraform, pero sí bloquea el despliegue
--    real de la Fase 5): ValidarPago necesita SELECT sobre la(s)
--    tabla(s) existente(s) de cuentas/movimientos de la Entrega 1 para
--    validar cuenta, monto y límites antes de publicar el evento
--    PagoValidado. El nombre exacto de esas tablas pertenece al
--    esquema ya creado en la Entrega 1 (fuera del alcance de lo que
--    diseñó Giovanny en la Entrega 2) y debe confirmarse con Johan
--    antes de cerrar este GRANT. Ejemplo de la sentencia a completar:
--
-- GRANT SELECT ON dbo.<TablaCuentas> TO [func-novapay-pagos-{env}];
