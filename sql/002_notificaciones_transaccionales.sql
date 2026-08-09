-- sql/002_notificaciones_transaccionales.sql
-- Entrega 2 (flujo serverless) — documento de diseño, secciones 5 y 6.
--
-- ALCANCE REAL DE GIOVANNY: llega hasta la Azure SQL Database
-- aprovisionada (modules/data-sql, reutilizada de la Entrega 1). La
-- creacion de tablas es responsabilidad de Johan (dueno del codigo de
-- funcion y de las reglas de negocio que definen el esquema real que
-- necesita) — decision explicita del equipo, no un olvido. La sentencia
-- CREATE TABLE de la seccion 1 de este archivo es una PROPUESTA de
-- partida, no un script que Giovanny ejecute ni cuente como su entrega:
-- Johan puede tomarla tal cual, ajustarla, o reemplazarla por completo.
--
-- Lo que SI sigue siendo responsabilidad de Giovanny (permisos/identidad,
-- documento de diseño seccion 5) es la seccion 2 de este archivo — pero
-- esas sentencias solo se pueden ejecutar DESPUES de que la tabla exista
-- (sea la propuesta de abajo o la version final de Johan), asi que hay
-- una dependencia de orden real entre ambas partes que debe coordinarse
-- con Johan antes de la Fase 5.
--
-- Fuera de azurerm por diseño: Azure Resource Manager no controla el
-- motor de Azure SQL, así que esto se aplica con un script T-SQL
-- versionado, ejecutado manualmente o por el pipeline después de
-- "terraform apply" (mismo patrón ya documentado, pero nunca
-- materializado como archivo, en modules/data-sql/main.tf de la
-- Entrega 1). Este es el primer script real de la carpeta sql/ — ver
-- sql/README.md para la convención de numeración.
--
-- Sustituir {env} por el ambiente real (dev | prod) antes de ejecutar.
-- El nombre de usuario debe coincidir exactamente con el nombre del
-- recurso Function App (no con su principal_id/GUID) — así es como
-- Azure SQL resuelve un usuario contenido AAD contra una identidad
-- administrada de Azure.

-- =====================================================================
-- 1. PROPUESTA de esquema (responsabilidad de Johan: ejecutar, ajustar
--    o reemplazar). TransactionId es la clave de idempotencia propuesta
--    (segunda capa, la primera es la deduplicación nativa de Service
--    Bus — documento de diseño, sección 4).
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
    -- nativa de Service Bus, sección 4): un intento de insertar el
    -- mismo TransactionId dos veces falla por restricción, no crea
    -- un duplicado.
    CONSTRAINT UQ_TransactionalNotifications_TransactionId UNIQUE (TransactionId)
);
GO

-- =====================================================================
-- 2. Identidad y permisos (responsabilidad real de Giovanny — documento
--    de diseño, sección 5). DEPENDE de que la tabla de la sección 1 ya
--    exista (la propuesta de arriba o la versión final de Johan) — no
--    se puede ejecutar antes, coordinar el orden con Johan.
-- =====================================================================

-- Usuario contenido AAD para la identidad administrada SystemAssigned
-- compartida por ValidatePayment y ProcessPayment (un único Function
-- App = una única identidad — documento de diseño, sección 5). Mismo
-- patrón que ya usa app-novapay-api-{env} en la Entrega 1.
CREATE USER [func-novapay-pagos-{env}] FROM EXTERNAL PROVIDER;
GO

-- Permisos mínimos sobre la tabla: ProcessPayment necesita
-- insertar/actualizar el registro de notificación; no se concede
-- DELETE (no hay caso de uso que lo requiera). Si Johan cambia el
-- nombre de la tabla propuesta en la sección 1, este GRANT debe
-- actualizarse para apuntar al nombre real.
GRANT SELECT, INSERT, UPDATE ON dbo.TransactionalNotifications TO [func-novapay-pagos-{env}];
GO

-- PENDIENTE (no bloquea el Terraform, pero sí bloquea el despliegue
-- real de la Fase 5): ValidatePayment necesita SELECT sobre la(s)
-- tabla(s) existente(s) de cuentas/movimientos de la Entrega 1 para
-- validar cuenta, monto y límites antes de publicar el evento
-- PaymentValidated. El nombre exacto de esas tablas pertenece al
-- esquema ya creado en la Entrega 1 (fuera del alcance de lo que
-- diseñó Giovanny en la Entrega 2) y debe confirmarse con Johan
-- antes de cerrar este GRANT. Ejemplo de la sentencia a completar:
--
-- GRANT SELECT ON dbo.<AccountsTable> TO [func-novapay-pagos-{env}];
