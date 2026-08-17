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
-- HALLAZGO REAL (bootstrap real de Fase 3, 2026-08-16): con
-- azureAdOnlyAuthentication=true y sin acceso público (Private
-- Endpoint), este script solo puede ejecutarse desde dentro de la
-- VNet — no hay bastion/jumpbox permanente en el diseño; se aprovisionó
-- uno temporal (VM + Azure Bastion en la subred snet-datos-prod / hub,
-- ambos borrados después) solo para correr este script. Ver PLAN.md
-- (act-4) §3.5 para el detalle completo de cómo se ejecutó realmente.
--
-- HALLAZGO REAL #2, más importante: "CREATE USER ... FROM EXTERNAL
-- PROVIDER" (sección 2 original) requiere que la identidad del SQL
-- Server tenga el rol de directorio "Directory Readers" en Entra ID —
-- en un tenant institucional (poligran.edu.co) ni el usuario AAD admin
-- del proyecto tiene privilegios para otorgar ese rol (Authorization_RequestDenied
-- al intentarlo). La sección 2 de abajo usa el mecanismo alternativo
-- real que sí funciona sin ese permiso: "CREATE USER ... WITH SID =
-- 0x<...>, TYPE = E", que no necesita resolver el nombre contra Graph.
--
-- HALLAZGO REAL #3, el que más tiempo costó diagnosticar: para una
-- identidad administrada (managed identity), el SID debe derivarse del
-- **Application (Client) ID** de la identidad, NO de su Object ID
-- (principalId) — son dos GUID distintos para la misma identidad.
-- Usar el Object ID por error compila y "funciona" (CREATE USER no
-- falla), pero el login real de la aplicación sigue fallando con
-- "Login failed for user '<token-identified principal>'." sin ningún
-- error más específico. Para obtener el Application ID de una managed
-- identity system-assigned:
--   az rest --method get --uri "https://graph.microsoft.com/v1.0/servicePrincipals/<principalId>?\$select=appId"
-- (principalId = el que devuelve "az functionapp identity show").
--
-- Sustituir {env} por el ambiente real (dev | prod) antes de ejecutar.
-- Ejecutar la sección 2 UNA VEZ POR CADA instancia física del Function
-- App serverless (estable y canary, ADR-03 U4 — cada una tiene su
-- propia identidad SystemAssigned, no se comparte entre instancias).

-- =====================================================================
-- 1. Propuesta de esquema (fuera del alcance de este módulo de
--    infraestructura: ejecutarla, ajustarla o reemplazarla es decisión
--    de quien construya la función). TransactionId es la clave de
--    idempotencia propuesta (segunda capa; la primera es la
--    deduplicación nativa de Service Bus). Ejecutar una sola vez
--    (compartida por ambas instancias).
-- =====================================================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'TransactionalNotifications')
BEGIN
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
END
GO

-- =====================================================================
-- 2. Identidad y permisos (responsabilidad de este repositorio de
--    infraestructura). DEPENDE de que la tabla de la sección 1 ya
--    exista. Reemplazar {AppId} por el Application ID real de cada
--    instancia (ver HALLAZGO REAL #3 arriba) y {UserName} por el
--    nombre exacto del Function App (func-novapay-pagos-{env} o
--    func-novapay-pagos-canary-{env}) — el nombre de usuario es solo
--    una etiqueta legible, lo que realmente vincula la identidad es
--    el SID.
-- =====================================================================
DECLARE @sid VARBINARY(16) = CONVERT(VARBINARY(16), '{AppId}');
-- Nota: el CONVERT directo de una cadena GUID a VARBINARY(16) en
-- T-SQL ya produce el mismo layout little-endian que .NET Guid.ToByteArray()
-- / Python uuid.bytes_le — no hace falta reordenar bytes a mano.

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '{UserName}')
BEGIN
    EXEC('CREATE USER [{UserName}] WITH SID = ' + CONVERT(VARCHAR(34), @sid, 1) + ', TYPE = E;');
END
GO

-- Permisos mínimos sobre la tabla: ProcessPayment necesita
-- insertar/actualizar el registro de notificación; no se concede
-- DELETE (no hay caso de uso que lo requiera). Si el nombre de la
-- tabla cambia respecto a la propuesta de la sección 1, este GRANT
-- debe actualizarse para apuntar al nombre real.
GRANT SELECT, INSERT, UPDATE ON dbo.TransactionalNotifications TO [{UserName}];
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
-- GRANT SELECT ON dbo.<AccountsTable> TO [{UserName}];
