# Architecture Decision Records — NovaPay

Registro de las decisiones arquitectónicas y técnicas detrás del diseño de este repositorio. Formato: Contexto / Decisión / Consecuencia positiva / Consecuencia negativa, extendido con Estado, sección afectada, decisiones relacionadas y alternativas consideradas cuando aplica.

Estas decisiones nacieron de una sesión de preflight en la que se verificaron los límites técnicos reales (Azure CLI contra la suscripción real, documentación oficial de Microsoft Learn) antes de decidir — ninguna capacidad de plataforma se asumió sin comprobarla. Fecha original: 2026-08-15, con revisiones posteriores documentadas en el encabezado de cada ADR.

| # | ADR | Área afectada | Decisión en una línea |
|---|---|---|---|
| 1 | [ADR-01](ADR-01-repo-separado-functions.md) | Pipeline CI/CD | Separar el código de las Functions en un repo nuevo (`novapay-functions`) |
| 2 | [ADR-02](ADR-02-pipeline-codigo-aplicacion.md) | Pipeline CI/CD | Extender el pipeline para compilar y desplegar el código de aplicación, no solo IaC |
| 3 | [ADR-03](ADR-03-canary-apim-backend-pool.md) | Estrategia de despliegue | Canary vía backend pool ponderado de APIM entre dos instancias del Function App real |
| 4 | [ADR-04](ADR-04-multizona-function-app-condicional.md) | Escalabilidad y HA | Multi-zona condicional y reversible en el Function App (no permanente) |
| 5 | [ADR-05](ADR-05-multizona-appservice-descartada.md) | Escalabilidad y HA | Multi-zona en App Service: solo diseño, no implementación (cuota bloqueada) |
| 6 | [ADR-06](ADR-06-geo-replicacion-sql.md) | Escalabilidad y HA | Auto-Failover Group real en Azure SQL como estrategia de replicación de datos |
| 7 | [ADR-07](ADR-07-workbook-observabilidad.md) | Observabilidad avanzada | Workbook real de Azure Monitor para SLI vs SLO |
| 8 | [ADR-08](ADR-08-devsecops-tooling.md) | Seguridad (DevSecOps) | Dependabot + CodeQL + tfsec/checkov + política `ip_restriction` real |

## Cómo se usan estos ADR

Cada módulo de `modules/` y cada composición de `envs/` que implemente uno de estos mecanismos debe referenciar el ADR correspondiente en su propio `README.md` o en los comentarios del recurso, en vez de repetir la justificación completa. Varios ADR documentan explícitamente una opción descartada con su razón (ADR-03 descarta Elastic Premium y App Service; ADR-05 descarta el upgrade de App Service) — son también la fuente de verdad para entender por qué el diseño no tomó el camino aparentemente más simple.
