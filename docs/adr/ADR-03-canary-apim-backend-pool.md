# ADR-03: Canary vía backend pool ponderado de API Management, sobre topología blue-green de dos slots fijos

**Estado:** Aceptada — 2026-08-15, revisada 2026-08-16 tras evaluación cruzada arquitecto/académica
**Sección U4 afectada:** 2. Estrategia de despliegue
**Relacionada:** ADR-02 (el pipeline que despliega el artefacto), ADR-04 (mismo principio de no sacrificar el escalado a cero)

## Contexto

La Sección 2 de U4 exige seleccionar e **implementar** de verdad Blue-Green, Canary o Rolling Update, con métricas de validación, criterios de rollback e impacto en disponibilidad. Se evaluaron tres componentes candidatos:

1. **Function App en Flex Consumption** (`func-novapay-pagos-{env}`): no soporta deployment slots (confirmado en la documentación oficial de Microsoft Learn). Su única estrategia zero-downtime nativa es *rolling update*, que además está en preview público y **no está en la lista de regiones GA** (East Asia, West Central US, North Central US, West US 2 — `centralus`, la región real de despliegue, no está incluida).
2. **Migrar a Elastic Premium (EP1)**: sí da deployment slots reales, pero exige un mínimo de 1 instancia siempre activa (~US$146/mes fijos, verificado), lo que **revierte explícitamente el ajuste #5 de la Tabla 3 de U3**.
3. **App Service transaccional** (`api-novapay-{env}`, Standard S1): sí soporta hasta 5 deployment slots de verdad, pero no tiene ningún código de aplicación real desplegado. Construir una API nueva desde cero para tener algo que canary-testear queda fuera del alcance razonable de esta entrega.

Se verificó que los *load-balanced pools* de API Management con enrutamiento **ponderado** —explícitamente descritos como útiles para "blue-green deployments"— **no están restringidos al tier Consumption**; solo el *backend circuit breaker* está excluido en ese tier.

**Dos hallazgos de una revisión cruzada (arquitecto cloud + académica) obligaron a rediseñar el mecanismo original**, documentados abajo como parte de esta misma decisión:

- **Hallazgo grave (arquitecto)**: el diseño original solo enrutaba con peso la ruta HTTP (`ValidatePayment`). Si ambas instancias comparten la misma cola de Service Bus, sus dos `ProcessPayment` quedan como consumidores competidores de la misma cola — el % de canary no protege en absoluto la mitad asíncrona del flujo, la más riesgosa. Un bug en la instancia candidata podría procesar mensajes validados por la instancia estable.
- **Impracticabilidad de una jerarquía fija "estable/candidata"**: el diseño original asumía que la instancia candidata, tras llegar a 100%, debía redesplegarse también sobre la instancia estable para "ponerse al día" — un paso extra, manual y confuso, señalado como poco práctico.

## Decisión

### Topología: dos slots fijos, roles dinámicos (híbrido Blue-Green + Canary)

Se mantienen los dos Function Apps ya nombrados (`func-novapay-pagos-{env}` y `func-novapay-pagos-canary-{env}`) como **recursos fijos**, pero se elimina la jerarquía "estable = estos son siempre buenos, candidata = esta siempre es la nueva". En cualquier momento, exactamente una de las dos instancias tiene el tráfico vigente (mayoritario/100%) y la otra es el **destino del próximo despliegue** (0% o en rampa). Cuál es cuál se determina **dinámicamente**, consultando el peso actual del backend pool de APIM al inicio de cada ciclo de despliegue — no por el nombre del recurso ni por ninguna variable fija. Es, en términos de la Lectura Fundamental de U4 (§2.3), un híbrido: topología de dos entornos fijos que intercambian rol (blue-green) con avance progresivo por peso observando métricas (canary).

### Mecanismo de despliegue (se integra con ADR-02)

1. El pipeline de `novapay-functions` consulta el peso actual del backend pool (`GET` sobre el recurso `Microsoft.ApiManagement/service/backends` tipo `Pool`) para identificar cuál instancia está en 0%.
2. Despliega el nuevo artefacto ahí, con el mecanismo ya definido en ADR-02 (directo a Azure, OIDC propia, atestación de procedencia).
3. **El mismo job de CD** (no un orquestador separado) avanza el peso de esa instancia 5% → 25% → 100% mediante `PATCH` sucesivos sobre el backend pool, reduciendo en espejo el peso de la otra, con una **ventana de observación mínima antes de cada incremento**: al menos 15 minutos **o** 50 solicitudes observadas, lo que tarde más — evita decidir sobre una muestra estadísticamente insuficiente dado el volumen real de NovaPay (~3.5 tx/min promedio). Si las métricas superan un umbral de guardrail en cualquier punto, el propio job detiene el avance y dispara el rollback, sin depender únicamente de la alerta asíncrona de Azure Monitor.

**Control de concurrencia y de estado**: el workflow usa un `concurrency group` por ambiente para serializar despliegues (evita dos releases casi simultáneos disparando dos ciclos en paralelo contra el mismo backend pool). Si al consultar el peso el estado es ambiguo (ninguna instancia limpiamente en 0%/100%, señal de un ciclo anterior interrumpido), el pipeline aborta y alerta en vez de asumir un destino.
4. Al llegar a 100%, la promoción queda completa. **No hay redespliegue adicional**: la instancia que bajó a 0% simplemente conserva el código anterior hasta que, en el siguiente ciclo, el paso 1 la identifique como destino del próximo release.

**Zona gris identificada y ya mitigada — Terraform vs. pesos en runtime** (auditoría de rigor arquitectónico, 2026-08-17): el recurso `Pool` (`azapi_resource.backend_pool`, `modules/api-management/main.tf`, `novapay-iac-terraform`) está declarado en Terraform, pero el job de CD de `novapay-functions` muta su peso en runtime vía `PATCH` directo, fuera de Terraform. Sin protección, cualquier `terraform apply` posterior revertiría silenciosamente una rampa en curso o recién completada a los pesos iniciales (100/0) declarados en el `.tf`. Esto **ya está mitigado desde el diseño original** con `lifecycle { ignore_changes = [body] }` sobre ese recurso — Terraform nunca vuelve a tocar el `body` (que incluye los pesos) una vez creado el recurso, sin importar cuántos `apply` corran después. No quedaba documentado en este ADR, solo en el comentario del módulo — corregido aquí para que la decisión sea trazable sin tener que leer el código Terraform.

### Aislamiento real end-to-end (cierra el hallazgo grave)

Se reemplaza la cola única de Service Bus por un **Topic** (`sbt-novapay-pagos-pendientes-{env}`) con **dos Subscriptions**, cada una con un filtro SQL sobre una propiedad del mensaje:

- `ValidatePayment` (en cualquiera de las dos instancias) estampa en cada mensaje la propiedad `sourceInstance = WEBSITE_SITE_NAME` — variable de entorno **nativa** de Azure Functions/App Service, ya presente sin configuración manual, con el nombre exacto del recurso que la generó. No requiere ninguna variable nueva en Terraform, ni riesgo de desincronización entre código e infraestructura.
- Subscription `sub-func-novapay-pagos-{env}`, filtro `sourceInstance = 'func-novapay-pagos-{env}'` → consumida solo por `ProcessPayment` de esa instancia.
- Subscription `sub-func-novapay-pagos-canary-{env}`, filtro `sourceInstance = 'func-novapay-pagos-canary-{env}'` → consumida solo por `ProcessPayment` de la otra.
- Cada Subscription conserva su propia Dead-Letter Queue (eso no cambia respecto al diseño de cola única); al compartir la misma propiedad `sourceInstance`, las métricas de ambas se consultan de forma unificada filtrando por esa propiedad en Application Insights/KQL, en vez de tener que inferir el origen por en qué cola cayó el mensaje.

Standard tier (ya desplegado en `sb-novapay-{env}`) soporta Topics/Subscriptions con filtros SQL sin necesidad de upgrade — verificado; Basic tier no los soporta.

### Rollback automático

**De tráfico**: una alerta de Azure Monitor sobre tasa de error 5xx de la instancia en rampa (umbral >3% en ventana de 5 minutos) dispara un **Action Group** cuya acción es una Azure Function dedicada, con una identidad administrada acotada al rol `API Management Service Contributor` sobre el recurso puntual de `apim-novapay-{env}` (no sobre el grupo de recursos), que hace `PATCH` sobre el backend pool para bajar el peso de la instancia en rampa a 0%.

**De código** (si el problema persiste tras bajar el tráfico): redesplegar el release anterior por tag sobre esa misma instancia, mecanismo ya definido en ADR-02.

**HALLAZGO REAL corregido en el guardrail en línea (2026-08-17, auditoría de rigor arquitectónico, ver PLAN.md §3.5)**: el guardrail del propio job de CD (arriba, "el propio job detiene el avance") y la alerta asíncrona de este ADR ambas se basaban únicamente en `success == false` / tasa de error 5xx — ciegas a una regresión de negocio real: un bug de despliegue que empiece a rechazar con `400` solicitudes que antes eran válidas. `ValidatePayment` maneja esos casos sin lanzar excepción, así que Application Insights los marca `success=true` sin importar el código HTTP — verificado con más de 230 solicitudes reales que nunca dispararon el guardrail pese a ser errores reales. Corregido en el guardrail en línea (`.github/scripts/ramp-step.sh`, `novapay-functions`): compara la tasa de `400` de la instancia en rampa contra la del otro rol en la misma ventana de 5 minutos (ambas reciben la misma mezcla real de tráfico) — una diferencia mayor a 10 puntos porcentuales, con un piso mínimo de 3 solicitudes rechazadas, dispara el mismo rollback. La alerta asíncrona de Azure Monitor (arriba) queda con la misma limitación original (solo 5xx) — brecha reconocida, no cerrada, porque su propósito es cubrir el caso en que el job de CD no está disponible, y ese escenario es menos probable de coincidir con una regresión de negocio recién desplegada que todavía no pasó por ningún guardrail.

### Session affinity

No se habilita: cada llamada a `POST /api/v1/payments/confirmations` es una confirmación de pago única e idempotente de un sistema (comercio/cliente), no una sesión interactiva de usuario — el enrutamiento ponderado puro es suficiente y correcto para este caso.

## Consecuencias

**Positivas**
- Prueba el flujo serverless **real** ya construido y documentado en U3, de extremo a extremo (síncrono y asíncrono) — cierra el hallazgo grave, no solo lo reconoce.
- La promoción no requiere ningún paso manual ni redespliegue adicional: es puramente un cambio de peso, resuelto por el mismo mecanismo que ya gestiona el avance progresivo.
- El aislamiento por Topic+Subscription es simétrico y gratuito de mantener (`WEBSITE_SITE_NAME` no requiere configuración ni puede desincronizarse).
- Un rollback abrupto de tráfico no genera duplicados ni inconsistencias: cualquier reintento del comercio tras el rollback cae en la instancia vigente y se deduplica por la doble capa de idempotencia ya construida en U3 (MessageId + restricción UNIQUE) — sostenido también con el Topic nuevo, porque la deduplicación de Service Bus opera igual sobre Topics que sobre Queues.
- No compromete el escalado a cero (ambas instancias siguen en Flex Consumption) ni revierte ninguna decisión ya calificada.

**Negativas**
- El backend circuit breaker de APIM no está soportado en tier Consumption; el rollback automático depende de una alerta de Azure Monitor + Action Group custom, no del mecanismo nativo.
- Migrar de Queue a Topic+2 Subscriptions es un cambio estructural del módulo `messaging-servicebus` (no solo un parámetro nuevo) — mayor superficie de Terraform a mantener que la cola única original, y dos Dead-Letter Queues que monitorear en vez de una (mitigado por la propiedad compartida `sourceInstance` para consultas unificadas).
- `api-novapay-{env}` (la API transaccional) queda explícitamente **fuera de alcance** de esta entrega — sigue sin código real desplegado.
- El nombre `func-novapay-pagos-canary-{env}` queda como identificador estructural del segundo slot fijo, no como afirmación de que ahí siempre corre código sin probar — debe aclararse así en el documento final para no confundir al lector.

## Alternativas descartadas

- Elastic Premium para el Function App (revierte U3, +US$146/mes fijos).
- Construir una API nueva para `api-novapay-{env}` solo para tener algo que canary-testear.
- Rolling update nativo de Flex Consumption (no GA en la región real de despliegue; tampoco permite enrutar % de tráfico).
- Jerarquía fija "estable siempre estable, candidata siempre candidata" con redespliegue de sincronización posterior a cada promoción (primera versión de este ADR): descartada por impráctica — exigía un paso operativo extra en cada ciclo sin aportar nada que el modelo de slots dinámicos no resuelva mejor.
- Cola única de Service Bus con versionado por propiedad inspeccionada manualmente por el consumidor (contrapropuesta inicial evaluada): descartada porque un Queue simple no permite enrutamiento server-side por propiedad — el consumidor tendría que abandonar mensajes que no le corresponden, generando reintentos y ruido en vez de aislamiento real. El mecanismo correcto para lograr lo mismo es Topic + Subscriptions con filtro SQL, adoptado en su lugar.
