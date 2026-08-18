# ADR-02: Extender el pipeline CI/CD para incluir el código de aplicación

**Estado:** Aceptada — 2026-08-15
**Sección U4 afectada:** 1. Pipeline CI/CD
**Relacionada:** ADR-01 (repo separado), ADR-03 (canary vía APIM, consume las dos instancias que este pipeline despliega)

## Contexto

Hasta la Entrega 2 (U3), el pipeline (`terraform-ci.yml`/`terraform-cd.yml` en `novapay-iac-terraform`) cubre únicamente la infraestructura. El propio documento final de U3 lo reconoce explícitamente: "el código de las funciones ni el script de creación de tablas [están cubiertos]: ambos se siguen desplegando a mano, un límite de alcance reconocido". La Sección 1 de U4 exige evidencia real de "build reproducible" y "despliegue automatizado", no solo del IaC.

## Decisión

Construir un pipeline nuevo, **autocontenido en `novapay-functions`**, en dos etapas:

**CI** (en cada *pull request*): `dotnet restore`/`build` sobre `NovaPay.Payments.csproj` con versión de SDK fijada, pruebas unitarias, empaquetado del artefacto (zip).

**CD** (`on: release: types: [published]`, mismo patrón de disparo que ya usa `terraform-cd.yml`, pero autocontenido en este repo): publica el release con el artefacto adjunto, genera una **atestación de procedencia** del build (`actions/attest-build-provenance`, nativa de GitHub Actions) que ata criptográficamente el zip al commit/build exacto, y **despliega directo a Azure** con `az functionapp deployment source config-zip` (o la acción oficial `Azure/functions-action@v1`), autenticado con la federación OIDC propia de `novapay-functions` (ADR-01) — **sin pasar por Terraform ni por su gate de aprobación de producción**.

**Destino de despliegue dinámico, ligado a la estrategia de canary (ADR-03, revisado)**: los dos Function Apps (`func-novapay-pagos-{env}` y `func-novapay-pagos-canary-{env}`) son slots fijos sin jerarquía permanente. Antes de desplegar, el pipeline consulta el peso actual del backend pool de APIM y despliega el artefacto nuevo en la instancia que esté en 0% en ese momento — nunca en la que sirve el tráfico vigente. Tras la promoción (la instancia nueva llega a 100%), no hay ningún redespliegue adicional: la instancia que quedó en 0% simplemente conserva el código anterior hasta que, en el siguiente ciclo, sea ella la que esté en 0% y reciba el próximo release.

**Control de concurrencia y de estado (cierra hallazgo de verificación arquitectónica posterior)**: el workflow usa `concurrency: group: deploy-novapay-functions-{env}` para serializar despliegues del mismo ambiente (evita que dos releases casi simultáneos disparen dos despliegues paralelos contra el mismo backend pool). Si al consultar el peso del backend pool el estado es ambiguo (ninguna instancia limpiamente en 0%/100%, señal de un ciclo anterior interrumpido), el pipeline aborta y alerta en vez de asumir un destino. Tras desplegar, se ejecuta una verificación post-despliegue **exclusivamente vía Application Insights** (nunca una invocación HTTP directa del runner, que quedaría bloqueada por `ip_restriction` — Sección 5, ADR-08) antes de iniciar cualquier avance de peso; si el despliegue del artefacto queda en estado incierto, no se avanza ningún peso.

**Rollback de código**: no existe un botón de "deshacer" nativo en Flex Consumption (sin *deployment slots*). El rollback es redesplegar, con el mismo workflow, el release **anterior** por tag (parámetro manual del `workflow_dispatch`) — posible porque cada release es un artefacto inmutable conservado íntegro, nunca sobrescrito.

**Migraciones SQL**: se mantienen como paso del pipeline de infraestructura (no del de código), pero se exige que sigan el patrón **expand-contract**: todo cambio de esquema durante una ventana de canary debe ser aditivo/retrocompatible, de forma que la instancia estable (versión anterior) y la candidata (versión nueva) puedan operar simultáneamente contra el mismo esquema sin conflicto. La limpieza de columnas/estructuras obsoletas se hace en un despliegue posterior, ya con el 100% del tráfico en la versión nueva.

## Consecuencias

**Positivas**
- Cierra la brecha reconocida explícitamente en U3.
- Da evidencia real (no solo conceptual) de build reproducible + despliegue automatizado para el criterio de 40 pts de la Sección 1.
- Cadencia de código verdaderamente independiente de infraestructura (ver revisión de ADR-01): un release de código no espera ni depende del `apply` de Terraform.
- El mismo mecanismo de despliegue directo sirve, sin duplicar lógica, para desplegar en el slot que corresponda según la estrategia canary (ADR-03).
- La atestación de procedencia y la consulta dinámica de destino dan trazabilidad real de qué artefacto corre en cada instancia en cada momento — cierra el hallazgo de "cadena de custodia del artefacto" de la revisión arquitectónica, y elimina el paso extra de "redespliegue de sincronización" que la primera versión de este diseño exigía.

**Negativas**
- Dos pipelines que coordinar solo cuando cambia el contrato entre código e infraestructura (no en cada despliegue rutinario, ver ADR-01).
- El rollback de código depende de que el equipo sepa qué tag es el "release anterior" — requiere disciplina de versionado semántico consistente, no automática por sí sola.
- El patrón expand-contract añade disciplina de diseño de migraciones que antes no era obligatoria (una migración destructiva simple ya no es válida durante una ventana de canary).

## Alcance explícito

- **Dentro de alcance**: build + test + empaquetado + publicación de release del proyecto `NovaPay.Payments`; despliegue automatizado de ese artefacto a las dos instancias del Function App.
- **Fuera de alcance de esta entrega**: no se construye código nuevo para `api-novapay-{env}` (ver ADR-03) ni se automatiza ningún otro componente de aplicación que no exista hoy.
