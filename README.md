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
│   ├── messaging-servicebus/  # Namespace + cola con DLQ para el flujo de confirmación de pagos
│   ├── compute-serverless/    # Function App en Flex Consumption para ese mismo flujo
│   └── api-management/        # API Gateway expuesto a clientes/comercios
├── envs/
│   ├── dev/                   # Composición de menor costo, sin redundancia zonal
│   └── prod/                  # SKU de mayor capacidad, redundancia zonal, retención >= 5 años
├── policies/                  # Reglas de Azure Policy (policy-as-code) referenciadas desde envs/*/policies.tf
└── sql/                       # Scripts T-SQL versionados, fuera del ciclo de vida de azurerm
```

Cada módulo declara su contrato de entrada/salida en `variables.tf`/`outputs.tf` y documenta sus dependencias en su propio `README.md`. El orden de capas (red y seguridad base → plataforma → observabilidad) determina el orden real de despliegue.

## Cómo ejecutar por ambiente

```bash
cd envs/dev   # o envs/prod

# Inicializa el backend remoto (Azure Blob Storage) para este ambiente.
terraform init -backend-config=backend.hcl

# Calcula el plan de cambios contra el estado remoto.
terraform plan -var-file=dev.tfvars   # o prod.tfvars

# Aplica los cambios (en la práctica, solo desde el pipeline de CI,
# nunca desde un equipo local).
terraform apply -var-file=dev.tfvars
```

Verificación de idempotencia:

```bash
terraform plan -var-file=dev.tfvars -detailed-exitcode
# 0 = sin cambios pendientes · 1 = error · 2 = hay diferencias por resolver
```

## Notas de seguridad y gobierno

- El estado de Terraform vive únicamente en el backend remoto `azurerm` (Azure Blob Storage), nunca en este repositorio (ver `.gitignore`).
- `dev.tfvars` y `prod.tfvars` contienen solo placeholders ilustrativos (IDs de ejemplo tipo `00000000-...`); los valores reales de un tenant productivo se inyectan desde el pipeline o un almacén de secretos, nunca se versionan.
- Azure SQL y Key Vault no exponen endpoint público: todo el acceso ocurre por Private Endpoint dentro de la subred de datos.
- Las asignaciones de rol de mínimo privilegio que cruzan módulos (por ejemplo, la identidad de App Service sobre Key Vault) se declaran en la composición raíz (`envs/*/main.tf`), no dentro de los módulos, para evitar dependencias circulares entre `security-keyvault` y `compute-appservice`.
