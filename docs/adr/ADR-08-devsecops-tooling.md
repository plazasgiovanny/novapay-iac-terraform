# ADR-08: Dependabot + CodeQL + tfsec/checkov + política ip_restriction real

**Estado:** Aceptada — 2026-08-15, revisada 2026-08-17 tras evaluación cruzada arquitecto/académica (Sección 5)
**Sección U4 afectada:** 5. Seguridad integrada (DevSecOps)

## Contexto

La Sección 5 exige escaneo de dependencias, políticas como código, gestión de secretos y "principio de mínimo privilegio validado". El proyecto ya tiene, desde U2, dos políticas de Azure Policy reales y asignadas (`deny-public-sql`, `require-tags`) y una gestión de secretos madura. Pero no existía escaneo de dependencias, ni SAST sobre código propio, y U3 reconoció una brecha pendiente: el Function App no restringe su tráfico entrante a las IP de salida de API Management.

**Hallazgo de la revisión arquitectónica**: el modelo de identidades de esta Sección 5 solo auditaba lo heredado de U2/U3, sin actualizarse con las identidades nuevas creadas en las Secciones 1-4 de esta misma entrega — en particular, faltaba por completo el rol que necesita la identidad del job de CD para publicar el evento `PesoActualizado` en la Data Collection Rule de la Sección 4 (`Monitoring Metrics Publisher`, verificado como el rol real que exige la Logs Ingestion API de Azure Monitor). También se detectó una contradicción no resuelta entre `ip_restriction` (esta sección) y el paso de verificación post-despliegue de la Sección 1, y ausencia de SAST sobre el código C# propio.

## Decisión

1. **GitHub Dependabot** (alerts + security updates) sobre ambos repositorios (`novapay-iac-terraform` para Terraform, `novapay-functions` para NuGet).
2. **CodeQL** (SAST) sobre `novapay-functions` — gratuito en repos públicos, complementa a Dependabot (que solo cubre dependencias, no código propio) analizando el código C# de `NovaPay.Payments` en busca de vulnerabilidades introducidas por el equipo.
3. **tfsec/checkov** como paso de CI sobre el Terraform, para configuración insegura.
4. **`ip_restriction`** real en el Function App + política de Azure Policy que lo exija — con la aclaración de que la verificación post-despliegue de la Sección 1 debe hacerse exclusivamente vía confirmación en Application Insights, nunca por invocación HTTP directa desde el runner de CI (que la propia política bloquearía).
5. **Tabla de identidades nuevas de esta entrega**, con el mismo rigor dimensional que la Tabla 3 de IAM de U2 (rol/alcance/nota): la OIDC de `novapay-functions` recibe un **segundo rol** (`Monitoring Metrics Publisher`, alcance: la DCR puntual de la Sección 4). Es la misma identidad (mismo *principal*) la que tiene `Website Contributor` (alcance: los 2 Function Apps) — pero, al ser rol y alcance distintos, son **dos recursos `azurerm_role_assignment` separados** para ese mismo principal, no uno compartido (un `role_assignment` es una tripleta única de principal+rol+alcance).
6. **GitHub Advanced Security** (secret scanning + push protection) habilitado explícitamente sobre ambos repos públicos — gratuito, mitigación complementaria al hecho de que el código sea público.

## Consecuencias

**Positivas**
- Cierra la brecha ya reconocida en la entrega anterior (`ip_restriction`) sin dejar una contradicción operativa nueva sin resolver.
- Auditoría de identidades completa y actualizada para toda la entrega, no solo lo heredado — cierra el hallazgo más serio de la revisión arquitectónica.
- Cobertura de seguridad en tres capas distintas y complementarias: dependencias (Dependabot/SCA), código propio (CodeQL/SAST), configuración de infraestructura (tfsec/checkov) — ninguna se solapa con las otras.
- Todo gratuito y sin infraestructura de pago (repos públicos habilitan Dependabot, CodeQL y Advanced Security sin costo).

**Negativas**
- Una identidad (la OIDC de `novapay-functions`) acumula ahora dos roles distintos sobre dos recursos distintos — debe auditarse periódicamente que ninguno de los dos se amplíe de alcance sin revisión (riesgo de *scope creep* incremental, no de diseño actual).
- CodeQL añade tiempo al pipeline de CI (análisis estático no es instantáneo) — aceptable dado el tamaño actual del proyecto.

## Alternativas descartadas

- Dependabot como única herramienta de escaneo (sin CodeQL): deja sin cubrir vulnerabilidades introducidas en el código propio, relevante para lógica de validación de pagos.
- No declarar explícitamente el rol de la DCR y dejarlo implícito: descartado tras el hallazgo arquitectónico — toda identidad y su alcance deben quedar auditables en un solo lugar (Tabla de esta sección), no dispersas entre ADR de otras secciones.
