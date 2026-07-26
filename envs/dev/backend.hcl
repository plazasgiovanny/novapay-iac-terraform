# Configuración parcial del backend azurerm (sección 3.5). No
# contiene credenciales: la autenticación hacia la cuenta de
# almacenamiento la resuelve el pipeline mediante identidad federada
# (OIDC), nunca una clave de acceso en este archivo (sección 4.2).
#
# Uso: terraform init -backend-config=backend.hcl

resource_group_name  = "rg-novapay-tfstate"
storage_account_name = "stnovapaytfstatedev"
container_name       = "tfstate"
key                  = "dev.terraform.tfstate"
