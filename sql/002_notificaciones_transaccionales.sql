-- sql/002_notificaciones_transaccionales.sql
--
-- Alcance de este módulo de infraestructura: aprovisiona la Azure SQL
-- Database (modules/data-sql), no crea el esquema de tablas de negocio.
-- La sección 1 (CREATE TABLE) es una propuesta de esquema de partida,
-- fuera del alcance de este repositorio de infraestructura — puede
-- tomarse tal cual, ajustarse, o reemplazarse por completo.
--
-- La sección 2 (CREATE USER / GRANT) sí es responsabilidad de este
-- repositorio (permisos/identidad), pero depende de que la tabla ya
-- exista, así que su ejecución debe coordinarse con quien cree el
-- esquema final.
--
-- Fuera de azurerm por diseño: Azure Resource Manager no controla el
-- motor de Azure SQL, así que esto se aplica con un script T-SQL
-- versionado, ejecutado manualmente o por el pipeline después de
-- "terraform apply". Ver sql/README.md para la convención de numeración.
--
-- Sustituir {env} por el ambiente real (dev | prod) antes de ejecutar.
-- El nombre de usuario debe coincidir exactamente con el nombre del
-- recurso Function App (no con su principal_id/GUID) — así es como
-- Azure SQL resuelve un usuario contenido AAD contra una identidad
-- administrada de Azure.

-- =====================================================================
-- 1. Propuesta de esquema (fuera del alcance de este módulo de
--    infraestructura: ejecutarla, ajustarla o reemplazarla es decisión
--    de quien construya la función). TransactionId es la clave de
--    idempotencia propuesta (segunda capa; la primera es la
--    deduplicación nativa de Service Bus).
-- =====================================================================
CREATE TABLE dbo.TransactionalNotifications (
    Id                  UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    TransactionId       UNIQUEIDENTIFIER NOT NULL,
    SourceAccount       NVARCHAR(50)     NOT NULL,
    DestinationAccount  NVARCHAR(50)     NOT NULL,
    Amount              DECIMAL(18,2)    NOT NULL,
    Channel             NVARCHAR(20)     NOT NULL, -- push | email | sms
    Status              NVARCHAR(20)     NOT NULL, -- pending | sent | failed
    CreatedAt           DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
    SentAt              DATETIME2        NULL,

    -- Segunda capa de idempotencia (la primera es la deduplicación
    -- nativa de Service Bus): un intento de insertar el mismo
    -- TransactionId dos veces falla por restricción, no crea un duplicado.
    CONSTRAINT UQ_TransactionalNotifications_TransactionId UNIQUE (TransactionId)
);
GO

-- =====================================================================
-- 2. Identidad y permisos (responsabilidad de este repositorio de
--    infraestructura). DEPENDE de que la tabla de la sección 1 ya
--    exista (la propuesta de arriba o la versión final del esquema
--    real) — no se puede ejecutar antes.
-- =====================================================================

-- Usuario contenido AAD para la identidad administrada SystemAssigned
-- compartida por ValidatePayment y ProcessPayment (un único Function
-- App = una única identidad). Mismo patrón que ya usa
-- app-novapay-api-{env}.
CREATE USER [func-novapay-pagos-{env}] FROM EXTERNAL PROVIDER;
GO

-- Permisos mínimos sobre la tabla: ProcessPayment necesita
-- insertar/actualizar el registro de notificación; no se concede
-- DELETE (no hay caso de uso que lo requiera). Si el nombre de la
-- tabla cambia respecto a la propuesta de la sección 1, este GRANT
-- debe actualizarse para apuntar al nombre real.
GRANT SELECT, INSERT, UPDATE ON dbo.TransactionalNotifications TO [func-novapay-pagos-{env}];
GO

-- PENDIENTE (no bloquea el Terraform, pero sí bloquea el despliegue
-- real): ValidatePayment necesita SELECT sobre la(s) tabla(s)
-- existentes de cuentas/movimientos para validar cuenta, monto y
-- límites antes de publicar el evento PaymentValidated. El nombre
-- exacto de esas tablas pertenece al esquema transaccional ya
-- existente (fuera del alcance de este repositorio de infraestructura)
-- y debe confirmarse antes de cerrar este GRANT. Ejemplo de la
-- sentencia a completar:
--
-- GRANT SELECT ON dbo.<AccountsTable> TO [func-novapay-pagos-{env}];
