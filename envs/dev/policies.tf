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

# Ver comentario detallado en envs/prod/policies.tf sobre el alcance
# acotado por nombre (func-novapay-pagos*), el hallazgo real del apply
# fallido que forzó apuntar al sub-recurso config/web (no al recurso
# raíz Microsoft.Web/sites) y la verificación real del alias ARM.
resource "azurerm_policy_definition" "require_ip_restriction" {
  name         = "novapay-require-ip-restriction-${var.environment}"
  policy_type  = "Custom"
  mode         = "All"
  display_name = "NovaPay - Exigir ip_restriction en Function Apps de pagos"
  description  = "Impide crear o actualizar el config/web de func-novapay-pagos-{env}/func-novapay-pagos-canary-{env} sin ipSecurityRestrictionsDefaultAction = Deny (ADR-03/ADR-08 U4 — la restricción real ya usa el service tag AzureCloud.<region>, ver modules/compute-serverless)."

  policy_rule = templatefile("${path.module}/../../policies/require-ip-restriction.json.tpl", {
    environment = var.environment
  })
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
