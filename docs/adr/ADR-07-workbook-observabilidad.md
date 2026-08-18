# ADR-07: Workbook real de Azure Monitor, resuelto por rol dinámico

**Estado:** Aceptada — 2026-08-15, revisada 2026-08-17 tras evaluación cruzada arquitecto/académica (Sección 4)
**Sección U4 afectada:** 4. Observabilidad avanzada
**Relacionada:** ADR-03 (topología de dos slots con roles dinámicos, la misma que esta observabilidad debe resolver)

## Contexto

La Sección 4 exige SLI/SLO definidos, métricas p95/p99, alertas y estrategia de trazabilidad. U3 dejó definidas 5 métricas mínimas y 3 SLI candidatos, con un dato real de referencia (6.5 s, una sola muestra). Falta: umbrales SLO formalizados y un panel único que visualice SLI vs SLO.

**Hallazgo de la revisión arquitectónica**: la Sección 2 (ADR-03) estableció que "estable" y "candidata" **no son nombres fijos** — el rol vigente/en-rampa rota de instancia física en cada ciclo de despliegue. El diseño original de esta observabilidad no resolvía esto: cualquier consulta KQL que agregara métricas por nombre de recurso fijo (`func-novapay-pagos-{env}` vs. `-canary-{env}`) dejaría de significar "la instancia vigente" apenas ocurriera una promoción.

## Decisión

Construir un **Workbook de Azure Monitor** sobre `appi-novapay-{env}`/`log-novapay-{env}` (sin recursos nuevos), con **resolución de rol en tiempo de consulta**, no por nombre fijo:

1. **Panel de peso actual del backend pool de APIM** (fuente de datos ARM, tiempo real) — responde "¿cuál instancia es la vigente ahora mismo?" sin depender de ningún nombre fijo.
2. **Traza de cambios de peso**: el mismo job de CD que ejecuta la rampa (Sección 2, §2.3) hace un `POST` autenticado (misma identidad OIDC) a una **Data Collection Rule** de `log-novapay-{env}` (Logs Ingestion API de Azure Monitor) en cada `PATCH` de peso (`sourceInstance`, `pesoNuevo`, `timestamp`). Es una línea de tiempo consultable en el mismo eje temporal que los paneles de métricas — la correlación "qué rol tenía cada instancia" se lee **visualmente** (paneles alineados por tiempo), no vía un `join` por solicitud, que multiplicaría filas y sesgaría cualquier percentil. La Logs Ingestion API exige dos sub-recursos previos a la DCR, no solo la regla misma: un **Data Collection Endpoint (DCE)** (el `POST` del job de CD apunta a la URL de ingesta del DCE, no directo a la DCR) y una **tabla personalizada** ya creada en `log-novapay-{env}` (p. ej. `PesoActualizado_CL`, vía `Tables_Create`) con el esquema (`sourceInstance`, `pesoNuevo`, `timestamp`) al que la DCR enruta — sin la tabla creada de antemano, la DCR no tiene destino válido.
3. **Paneles de métricas por `sourceInstance`** (la propiedad ya estampada desde `WEBSITE_SITE_NAME`, Sección 2/ADR-03), agrupando directamente (es una propiedad de cada solicitud, no algo que haya que derivar): latencia p95/p99, tasa de error 5xx, profundidad de cola — cada uno como dos series (una por instancia física).
4. **Alertas referenciadas, no duplicadas**: el Workbook visualiza la alerta de error rate de la instancia en rampa definida en ADR-03/§2.6 (mismo recurso, mismo Action Group) — no se crea una alerta nueva aquí.
5. **DLQ y profundidad de cola desagregadas por Subscription** (dos Subscriptions desde la Sección 2): dos paneles, uno por Subscription, cada uno con su propia serie — nunca una métrica agregada que podría enmascarar una Subscription atascada con la salud de la otra (decisión ya tomada en la Sección 3, §3.4, ahora con mecanismo real aquí).

## Consecuencias

**Positivas**
- Sin costo adicional: reutiliza recursos de observabilidad ya desplegados y pagados desde U2/U3.
- Resuelve el problema de fondo (rol dinámico) en vez de solo visualizar métricas que dejarían de tener sentido tras la primera promoción.
- Evidencia visual real y consolidada, más fuerte que capturas de consultas KQL sueltas.
- Añade p99 (ausente hasta ahora) y cierra, con mecanismo concreto, las alertas por Subscription ya decididas en la Sección 3.

**Negativas**
- Un Workbook es configuración dentro del recurso de Application Insights, no gestionado como código por Terraform salvo que se declare explícitamente — límite reconocido, no oculto.
- El panel de peso vía ARM y la traza de cambios de peso (Data Collection Endpoint + tabla personalizada + Data Collection Rule + Logs Ingestion API) añaden una dependencia nueva y **tres** recursos Terraform adicionales, no uno — si el job de CD falla al emitir el evento, el panel 2 pierde ese ciclo específico — pero los paneles de métricas por `sourceInstance` (3-5) no dependen de él y siguen siendo correctos, así que la pérdida es acotada, no total.
