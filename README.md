# novapay-iac-terraform

Infraestructura como Código (Terraform + proveedor `azurerm`) para NovaPay, una fintech latinoamericana de billetera digital y pasarela de pagos. Este repositorio aprovisiona la arquitectura hub-spoke sobre Microsoft Azure: red, seguridad, datos, cómputo y observabilidad, más el flujo serverless de confirmación y notificación de pagos.

El código cubre la VNet spoke, sus subredes y NSG, el backend transaccional (App Service + Functions) con autoescalado basado en CPU, Azure SQL Database, Key Vault, la observabilidad centralizada, y el flujo serverless de confirmación de pagos (API Management, Service Bus, Function App en Flex Consumption) — todo bajo un modelo PaaS/cloud-native, sin máquinas virtuales de propósito general.

## Estructura

```
.
├── modules/
│   ├── networking/            # VNet spoke, subredes, NSG deny-by-default, peering al hub
│   ├── security-keyvault/     # Key Vault con RBAC, sin acceso público
│   ├── data-sql/              # Azure SQL Database, autenticación solo Microsoft Entra ID
│   ├── compute-appservice/    # App Service + Functions con identidad administrada
│   ├── observability/         # Log Analytics Workspace, Application Insights, diagnostic settings
│   ├── messaging-servicebus/  # Namespace + Topic con una Subscription por instancia (estable/canary) del flujo de pagos
│   ├── compute-serverless/    # Function App en Flex Consumption, instanciado dos veces (estable/canary)
│   └── api-management/        # API Gateway expuesto a clientes/comercios, backend pool ponderado
├── envs/
│   ├── dev/                   # Composición de menor costo, sin redundancia zonal
│   └── prod/                  # SKU de mayor capacidad, redundancia zonal, retención >= 5 años
├── policies/                  # Reglas de Azure Policy (policy-as-code) referenciadas desde envs/*/policies.tf
└── sql/                       # Scripts T-SQL versionados, fuera del ciclo de vida de azurerm
```

El código de aplicación del flujo serverless (`ValidatePayment`/`ProcessPayment`) vivía en este repo hasta la Unidad 4 (`functions/NovaPay.Payments/`); se extrajo a un repositorio propio, [`novapay-functions`](https://github.com/plazasgiovanny/novapay-functions), con cadencia de release independiente de la infraestructura. Este repo aprovisiona el *shell* del recurso (runtime, integración VNet, identidad, escalado); `novapay-functions` gestiona y despliega el código que corre dentro.

Cada módulo declara su contrato de entrada/salida en `variables.tf`/`outputs.tf` y documenta sus dependencias en su propio `README.md`. El orden de capas (red y seguridad base → plataforma → observabilidad) determina el orden real de despliegue.

## Cómo ejecutar por ambiente

```bash
cd envs/dev   # o envs/prod

# Inicializa el backend remoto (Azure Blob Storage) para este ambiente.
terraform init -backend-config=backend.hcl

# Calcula el plan de cambios contra el estado remoto.
terraform plan -var-file=dev.tfvars   # o prod.tfvars

# Aplica los cambios. En prod, el "apply" real ocurre solo desde el
# pipeline de CI/CD (ver más abajo) — este comando local es para dev
# o para diagnosticar localmente, no para un apply real de prod.
terraform apply -var-file=dev.tfvars
```

Verificación de idempotencia:

```bash
terraform plan -var-file=dev.tfvars -detailed-exitcode
# 0 = sin cambios pendientes · 1 = error · 2 = hay diferencias por resolver
```

## Pipeline CI/CD

`prod` se gestiona mediante dos workflows de GitHub Actions (`.github/workflows/`), ambos autenticados contra Azure vía OIDC (identidad federada, sin secretos de larga duración):

- **`terraform-ci.yml`** — en cada Pull Request hacia `main`: `fmt`, `validate` y `plan` (de solo lectura). El resultado del plan se publica en el resumen del run.
- **`terraform-cd.yml`** — al publicar un GitHub Release: calcula el plan y lo sube como artifact (`plan`, sin gate), y luego lo aplica (`apply`) bajo el Environment `production`, que exige aprobación humana manual antes de tocar Azure real. El `apply` usa exactamente el plan que el reviewer aprobó, no uno recalculado a ciegas.

Validado con una ejecución real de extremo a extremo (PR → CI → merge → release → aprobación → apply) contra `prod`: `Apply complete! Resources: 0 added, 9 changed, 0 destroyed.`

**Límite reconocido**: el Service Principal del pipeline necesita el rol `Resource Policy Contributor` a nivel de **suscripción completa** (no un resource group), porque `azurerm_policy_definition`/`azurerm_subscription_policy_assignment` (`envs/*/policies.tf`) actúan a ese nivel — no fue posible acotar el 100% de sus permisos a `rg-novapay-prod`.

**Drift perpetuo conocido (no es un bug de este repo)**: dos atributos oscilan entre "sin cambios" y "cambio pendiente" en plans sucesivos incluso después de un `apply` exitoso, por comportamiento documentado del proveedor `azurerm`/API de Azure, no por un error de configuración:
- `azurerm_monitor_diagnostic_setting` con `enabled_metric { category = "AllMetrics" }` sobre Azure SQL Database — Azure no siempre normaliza las categorías como Terraform espera ([issue #17172](https://github.com/hashicorp/terraform-provider-azurerm/issues/17172), [issue #29772](https://github.com/hashicorp/terraform-provider-azurerm/issues/29772) del proveedor `azurerm`).
- `site_config.application_insights_connection_string` en el Function App serverless — el proveedor `azurerm` tiene un comportamiento documentado con los atributos de conexión a Application Insights en Function Apps ([issue #16077](https://github.com/hashicorp/terraform-provider-azurerm/issues/16077)).

Mitigación futura: `lifecycle { ignore_changes = [...] }` sobre esos atributos puntuales, deliberadamente no aplicada aquí para no ocultar el estado real mientras se documenta como hallazgo.

## Notas de seguridad y gobierno

- El estado de Terraform vive únicamente en el backend remoto `azurerm` (Azure Blob Storage), nunca en este repositorio (ver `.gitignore`).
- `dev.tfvars` y `prod.tfvars` contienen solo placeholders ilustrativos (IDs de ejemplo tipo `00000000-...`); los valores reales de un tenant productivo se inyectan desde el pipeline o un almacén de secretos, nunca se versionan.
- Azure SQL y Key Vault no exponen endpoint público: todo el acceso ocurre por Private Endpoint dentro de la subred de datos.
- Las asignaciones de rol de mínimo privilegio que cruzan módulos (por ejemplo, la identidad de App Service sobre Key Vault) se declaran en la composición raíz (`envs/*/main.tf`), no dentro de los módulos, para evitar dependencias circulares entre `security-keyvault` y `compute-appservice`.
