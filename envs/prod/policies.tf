# Policy-as-code: control preventivo contra drift. Estas definiciones
# no dependen de que el equipo recuerde aplicar una convención; Azure
# Policy la hace cumplir en el plano de control, incluso si alguien
# intenta un cambio fuera de Terraform.

data "azurerm_subscription" "current" {}

resource "azurerm_policy_definition" "deny_public_sql" {
  name         = "novapay-deny-public-sql-${var.environment}"
  policy_type  = "Custom"
  mode         = "Indexed"
  display_name = "NovaPay - Denegar Azure SQL con acceso público habilitado"
  description  = "Impide crear o actualizar servidores Azure SQL con publicNetworkAccess distinto de Disabled (reduce el alcance de cumplimiento PCI DSS)."

  policy_rule = file("${path.module}/../../policies/deny-public-sql.json")
}

resource "azurerm_policy_definition" "require_tags" {
  name         = "novapay-require-tags-${var.environment}"
  policy_type  = "Custom"
  mode         = "Indexed"
  display_name = "NovaPay - Exigir etiquetas obligatorias"
  description  = "Impide crear recursos sin las etiquetas 'environment' y 'data_classification'."

  policy_rule = file("${path.module}/../../policies/require-tags.json")
}

# Alcance deliberadamente acotado por nombre (func-novapay-pagos*), no a
# todo Microsoft.Web/sites: el mismo resource group tiene otros dos
# recursos de ese tipo sin ip_restriction (app-novapay-api-{env}, el App
# Service transaccional de U2, y func-novapay-workers-{env}, el Function
# App de workers asíncronos de U2) que nunca tuvieron ese control en su
# diseño — una política a nivel de todo el tipo de recurso los habría
# bloqueado en el primer "terraform apply", una regresión real, no una
# mejora de seguridad. Solo los 2 Function Apps del flujo de pagos
# (ADR-03 U4) llevan ip_restriction (ver modules/compute-serverless).
# Alias ARM verificado contra la API real (no asumido):
# `az rest --method get --uri "https://management.azure.com/providers/Microsoft.Web?api-version=2021-04-01&$expand=resourceTypes/aliases"`
# confirma "Microsoft.Web/sites/siteConfig.ipSecurityRestrictionsDefaultAction"
# como alias válido para Azure Policy.
resource "azurerm_policy_definition" "require_ip_restriction" {
  name         = "novapay-require-ip-restriction-${var.environment}"
  policy_type  = "Custom"
  mode         = "Indexed"
  display_name = "NovaPay - Exigir ip_restriction en Function Apps de pagos"
  description  = "Impide crear o actualizar func-novapay-pagos-{env}/func-novapay-pagos-canary-{env} sin ipSecurityRestrictionsDefaultAction = Deny (ADR-03/ADR-08 U4 — la restricción real ya usa el service tag AzureCloud.<region>, ver modules/compute-serverless)."

  policy_rule = file("${path.module}/../../policies/require-ip-restriction.json")
}

resource "azurerm_subscription_policy_assignment" "deny_public_sql" {
  name                 = "novapay-deny-public-sql-${var.environment}"
  policy_definition_id = azurerm_policy_definition.deny_public_sql.id
  subscription_id      = data.azurerm_subscription.current.id
}

resource "azurerm_subscription_policy_assignment" "require_tags" {
  name                 = "novapay-require-tags-${var.environment}"
  policy_definition_id = azurerm_policy_definition.require_tags.id
  subscription_id      = data.azurerm_subscription.current.id
}

resource "azurerm_subscription_policy_assignment" "require_ip_restriction" {
  name                 = "novapay-require-ip-restriction-${var.environment}"
  policy_definition_id = azurerm_policy_definition.require_ip_restriction.id
  subscription_id      = data.azurerm_subscription.current.id
}
