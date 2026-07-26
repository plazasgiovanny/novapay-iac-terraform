# Configuración parcial del backend azurerm (sección 3.5). No
# contiene credenciales: la autenticación hacia la cuenta de
# almacenamiento la resuelve el pipeline mediante identidad federada
# (OIDC), nunca una clave de acceso en este archivo (sección 4.2).
#
# Nota de segmentación de estado: prod usa una cuenta de
# almacenamiento distinta a la de dev (no solo un contenedor o clave
# distintos), de modo que un error de permisos en un ambiente no
# pueda alcanzar el estado del otro (sección 3.5).
#
# Uso: terraform init -backend-config=backend.hcl

resource_group_name  = "rg-novapay-tfstate"
storage_account_name = "stnovapaytfstateprod"
container_name       = "tfstate"
key                  = "prod.terraform.tfstate"
