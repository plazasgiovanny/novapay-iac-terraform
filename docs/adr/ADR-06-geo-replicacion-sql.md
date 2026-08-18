# ADR-06: Auto-Failover Group real en Azure SQL (sobre Active Geo-Replication)

**Estado:** Aceptada — 2026-08-15, revisada 2026-08-16 tras hallazgo de revisión arquitectónica (Sección 3)
**Sección U4 afectada:** 3. Escalabilidad y Alta Disponibilidad

## Contexto

La Sección 3 exige diseñar una "estrategia de replicación de datos". Azure SQL Database en tier **Standard** (S3, el tier realmente desplegado en `sqldb-novapay-core-{env}` desde U3) no soporta redundancia zonal síncrona — solo Premium DTU o vCore GP/BC/Hyperscale. Sin embargo, se verificó que **Active Geo-Replication asíncrona sí está disponible en el tier Standard**, sin requerir upgrade: hasta 4 réplicas legibles, en regiones distintas, con el mismo tier que la primaria.

**Hallazgo de la revisión arquitectónica**: el diseño original (solo Active Geo-Replication simple) no explicaba cómo la aplicación se reconectaría tras un failover real. La réplica es de solo lectura y su promoción a primaria es un evento distinto; si la cadena de conexión de `func-novapay-pagos-{env}`/`-canary-{env}` apunta directamente al servidor primario original, promover la réplica no redirige el tráfico — alguien tendría que actualizar App Settings/Key Vault a mano, un paso no trivial que el diseño original omitía por completo.

Se verificó que **Auto-Failover Groups** —construido sobre el mismo mecanismo de Active Geo-Replication— también está soportado en tier Standard (mismo requisito: ambos lados con el mismo tier), y añade exactamente lo que falta: un **listener DNS estable** (`<failover-group-name>.database.windows.net`) al que la aplicación se conecta una sola vez; el listener resuelve siempre al servidor primario vigente, sin que la aplicación necesite saber cuál es en cada momento.

## Decisión

Crear un **Auto-Failover Group** real entre `sql-novapay-{env}` (primario) y un servidor secundario en una segunda región, conteniendo `sqldb-novapay-core-{env}`, con **política de failover manual** (no automática): el grupo da el listener DNS y la replicación continua, pero la decisión de promover el secundario a primario la toma un humano, no un umbral automático — evita que un problema transitorio dispare una conmutación con pérdida de datos sin evaluación previa. La cadena de conexión de **todo componente que hable con la base de datos** —las dos instancias del Function App (Sección 2) y `api-novapay-{env}`, que conserva su cadena de conexión de infraestructura desde la Entrega 1 aunque no tenga código propio en esta entrega (ADR-03)— se configura contra el **listener**, no contra el nombre del servidor primario. Es un cambio de valor en `app_settings` de Terraform, sin tocar código.

## Consecuencias

**Positivas**
- Evidencia real (grupo de failover visible y consultable) sin cambiar de tier ni alterar el costo estructural ya aceptado del proyecto.
- Complementa directamente el requerimiento no funcional de recuperación ante desastres ya comprometido en la Entrega 1 (Tabla 1: RTO≤1h, RPO≤15min) con un mecanismo real, no solo declarado.
- **Cierra el hallazgo de reconexión**: la aplicación nunca necesita cambiar configuración tras un failover, porque siempre apunta al listener, no al servidor.
- No compite con el escalado a cero de ningún otro componente — es una decisión aislada al nivel de datos.
- Compatible con el marco de "consistencia fuerte vs. disponibilidad" que describe la Lectura Fundamental de U4 (§3.1): NovaPay acepta conscientemente una ventana de eventual consistency en el failover (RPO no-cero) a cambio de disponibilidad regional — la misma decisión de fondo que ScaleNow toma para su módulo transaccional en el caso de la lectura, aplicada aquí a nivel de infraestructura de datos en vez de a nivel de dominio de negocio.

**Negativas**
- Costo adicional real: un segundo servidor/base de datos activo (aunque de solo lectura mientras no hay failover), facturado de forma continua.
- La replicación subyacente sigue siendo **asíncrona**: existe una ventana de posible pérdida de datos en un failover real (RPO no-cero), que debe reconocerse explícitamente en el documento, no presentarse como consistencia garantizada.
- Un failover real (promover el secundario) no se ejecuta en esta entrega — solo se demuestra la existencia y sincronización del grupo, no el proceso de conmutación completo. Con política manual, la promoción exige una decisión y un comando explícitos (`az sql failover-group set-primary`), documentados a nivel de diseño pero no ejecutados como evidencia de esta entrega.

## Alternativas descartadas

- Active Geo-Replication simple sin Auto-Failover Group (primera versión de este ADR): descartada porque no resuelve el problema de reconexión de la aplicación tras un failover — un mecanismo de DR real debe incluir cómo el cliente encuentra al nuevo primario, no solo que el nuevo primario exista.
- Política de failover automática: descartada para un flujo de pagos — una conmutación automática ante un problema transitorio podría asumir una pérdida de datos innecesaria sin evaluación humana previa.
