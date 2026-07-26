# novapay-iac-terraform

Infraestructura como Código (Terraform + proveedor `azurerm`) para NovaPay, una fintech latinoamericana de billetera digital y pasarela de pagos. Este repositorio aprovisiona la arquitectura hub-spoke sobre Microsoft Azure descrita en la Entrega 1 de la actividad "Diseño Arquitectónico y Aprovisionamiento de Infraestructura Cloud como Código" (Maestría en Arquitectura de Software, Politécnico Grancolombiano, Módulo Construcción de Software con Tecnología Cloud, Unidad 2).

El código cubre la VNet spoke, sus subredes y NSG, el backend transaccional (App Service + Functions), Azure SQL Database, Key Vault y la observabilidad centralizada — todo bajo un modelo PaaS/cloud-native, sin máquinas virtuales de propósito general.

## Estructura

```
.
├── modules/
│   ├── networking/           # VNet spoke, subredes, NSG deny-by-default, peering al hub
│   ├── security-keyvault/    # Key Vault con RBAC, sin acceso público
│   ├── data-sql/             # Azure SQL Database, autenticación solo Microsoft Entra ID
│   ├── compute-appservice/   # App Service + Functions con identidad administrada
│   └── observability/        # Log Analytics Workspace + diagnostic settings
├── envs/
│   ├── dev/                  # Composición de menor costo, sin redundancia zonal
│   └── prod/                 # SKU de mayor capacidad, redundancia zonal, retención >= 5 años
└── policies/                 # Reglas de Azure Policy (policy-as-code) referenciadas desde envs/*/policies.tf
```

Cada módulo declara su contrato de entrada/salida en `variables.tf`/`outputs.tf` y documenta sus dependencias en su propio `README.md`. El orden de capas (red y seguridad base → plataforma → observabilidad) replica el orden de despliegue descrito en la sección 2.1 del documento de arquitectura.

## Cómo ejecutar por ambiente

```bash
cd envs/dev   # o envs/prod

# Inicializa el backend remoto (Azure Blob Storage) para este ambiente.
terraform init -backend-config=backend.hcl

# Calcula el plan de cambios contra el estado remoto.
terraform plan -var-file=dev.tfvars   # o prod.tfvars

# Aplica los cambios (en la práctica, solo desde el pipeline de CI,
# nunca desde un equipo local — sección 4.3, separación de deberes).
terraform apply -var-file=dev.tfvars
```

Verificación de idempotencia (sección 3.6):

```bash
terraform plan -var-file=dev.tfvars -detailed-exitcode
# 0 = sin cambios pendientes · 1 = error · 2 = hay diferencias por resolver
```

## Notas de seguridad y gobierno

- El estado de Terraform vive únicamente en el backend remoto `azurerm` (Azure Blob Storage), nunca en este repositorio (ver `.gitignore`).
- `dev.tfvars` y `prod.tfvars` contienen solo placeholders ilustrativos (IDs de ejemplo tipo `00000000-...`); los valores reales de un tenant productivo se inyectan desde el pipeline o un almacén de secretos, nunca se versionan.
- Azure SQL y Key Vault no exponen endpoint público: todo el acceso ocurre por Private Endpoint dentro de la subred de datos.
- Las asignaciones de rol de mínimo privilegio que cruzan módulos (por ejemplo, la identidad de App Service sobre Key Vault) se declaran en la composición raíz (`envs/*/main.tf`), no dentro de los módulos, para evitar dependencias circulares entre `security-keyvault` y `compute-appservice`.

## Autoría

Grupo 2 — Maestría en Arquitectura de Software, Politécnico Grancolombiano. Sección de Infraestructura como Código y Seguridad y Gobierno: Giovanny Plazas Lozano.
