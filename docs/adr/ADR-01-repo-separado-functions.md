# ADR-01: Separar el código de las Functions en un repositorio nuevo

**Estado:** Aceptada — 2026-08-15, revisada 2026-08-16 (permisos reales de la federación OIDC y formato de subject claim, ver Consecuencias)
**Sección U4 afectada:** 1. Pipeline CI/CD

## Contexto

El código de `NovaPay.Payments` (las Azure Functions `ValidatePayment`/`ProcessPayment` de la Entrega 2) vive hoy dentro del monorepo de infraestructura `novapay-iac-terraform`, en `functions/NovaPay.Payments/`. Para dar evidencia real de "pipeline-as-code con build reproducible y despliegue automatizado" (Sección 1 de la actividad de U4), y para no acoplar la cadencia de release del código de aplicación (cambia con frecuencia) a la del código de infraestructura (cambia rara vez), conviene separar ambos.

## Decisión

Crear un repositorio nuevo, **público**, llamado **`novapay-functions`**, con **historial de commits limpio** (no se migra el historial previo del código dentro del monorepo — decisión consciente, no un descuido).

**Principio de separación (revisado tras hallazgo de revisión arquitectónica, ver ADR-02): Terraform gestiona el *shell* del recurso (runtime, integración VNet, identidad, escalado); `novapay-functions` gestiona el código que corre dentro de ese shell, y lo despliega directo a Azure con su propia identidad — sin pasar por Terraform ni por su gate de aprobación de producción.** No existe ningún disparo automático cross-repo: el repo de infraestructura nunca necesita enterarse de un release de código, porque nunca lo despliega. El *release/tag versionado* que publica `novapay-functions` es lo que dispara su **propio** pipeline de despliegue (mismo patrón `on: release: types: [published]` que ya usa `terraform-cd.yml`, pero autocontenido en este repo), no una señal hacia el otro repositorio. La coordinación cross-repo solo es necesaria cuando cambia el *contrato* entre ambos (ej. nueva subred, nueva referencia de Key Vault) — eso se resuelve con un PR humano normal, no con automatización.

**Riesgo de visibilidad pública, evaluado explícitamente**: el código no contiene secretos (mismo patrón de identidad administrada/Key Vault ya establecido en el proyecto desde U2), por lo que el riesgo real de hacerlo público es de exposición de lógica de negocio, no de credenciales. Hay precedente aceptado: `novapay-iac-terraform` ya es público desde la Entrega 1. Se mantiene la misma política por consistencia, dejando esta evaluación de riesgo registrada explícitamente en vez de implícita.

## Consecuencias

**Positivas**
- Cadencia de release independiente entre código e infraestructura — real, no solo declarada, porque el código nunca pasa por el `apply` de Terraform ni por su gate de producción.
- Aplica literalmente el principio de "artefacto inmutable" descrito por Humble y Farley (2010, p. 113): el mismo paquete atraviesa ambientes, nunca se reconstruye en cada etapa.
- Separación de permisos **definida de forma concreta, no solo declarada**: federación OIDC nueva con *subject claim* `repo:<org>@<orgId>/novapay-functions@<repoId>:environment:production` — **formato inmutable, no el clásico `repo:<org>/<repo>:...`** (hallazgo real del primer intento de despliegue, 2026-08-16: GitHub cambió el subject claim por defecto a este formato con IDs numéricos para todo repo creado después del 2026-07-15, para evitar ataques de "subject recycling" si el nombre del repo/org se reutiliza; el intento inicial con el formato clásico falló con `AADSTS700213`, corregido actualizando el `federated-credential` de Entra ID), autorizada para dos roles, cada uno acotado al recurso puntual — nunca al grupo de recursos completo: `Website Contributor` sobre los IDs de los dos Function Apps (estable y candidata, ver ADR-03), para desplegar código; y `API Management Service Contributor` sobre `apim-novapay-{env}` puntualmente, porque el mismo job de CD hace `PATCH` directo sobre el backend pool para avanzar la rampa (ver ADR-03 "Mecanismo de despliegue") — sin este segundo rol el pipeline no podría mover pesos, una inconsistencia entre este ADR y ADR-03 detectada y corregida el 2026-08-16 (versión original de este ADR solo mencionaba `Website Contributor`). Mismo patrón de "scope sobre el recurso, no el grupo de recursos" que ya usa el proyecto para los roles de Service Bus (Entrega 2, Fragmento 3).

**Negativas**
- Dos repositorios que coordinar en vez de uno (aunque, tras el rediseño del mecanismo, esa coordinación se limita a cambios de contrato poco frecuentes, no a cada despliegue); dos federaciones de identidad de carga de trabajo que mantener.
- Se pierde el historial de commits previo del código de las Functions (documentado como decisión explícita, no como pérdida accidental).
- Las rutas de archivo citadas en el PDF final ya calificado de la Entrega 2 (`Functions/ValidatePayment.cs`, `functions/NovaPay.Payments/host.json`) quedan obsoletas frente al nuevo repositorio; debe aclararse en el documento de U4 que esas citas correspondían a la estructura vigente en el momento de esa entrega.

## Alternativas consideradas

- **Mantener el monorepo actual**: menor esfuerzo de migración, sin romper citas previas, pero mezcla en un solo pipeline dos cadencias de cambio distintas (infra vs. código de aplicación).
