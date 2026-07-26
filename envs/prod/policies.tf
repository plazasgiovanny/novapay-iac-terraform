# Policy-as-code: control preventivo contra drift (sección 4.6). Estas
# definiciones no dependen de que el equipo recuerde aplicar una
# convención; Azure Policy la hace cumplir en el plano de control,
# incluso si alguien intenta un cambio fuera de Terraform.

data "azurerm_subscription" "current" {}

resource "azurerm_policy_definition" "deny_public_sql" {
  name         = "novapay-deny-public-sql-${var.environment}"
  policy_type  = "Custom"
  mode         = "Indexed"
  display_name = "NovaPay - Denegar Azure SQL con acceso público habilitado"
  description  = "Impide crear o actualizar servidores Azure SQL con publicNetworkAccess distinto de Disabled (sección 4.4, reducción de alcance PCI DSS)."

  policy_rule = file("${path.module}/../../policies/deny-public-sql.json")
}

resource "azurerm_policy_definition" "require_tags" {
  name         = "novapay-require-tags-${var.environment}"
  policy_type  = "Custom"
  mode         = "Indexed"
  display_name = "NovaPay - Exigir etiquetas obligatorias"
  description  = "Impide crear recursos sin las etiquetas 'environment' y 'data_classification' (sección 3.4)."

  policy_rule = file("${path.module}/../../policies/require-tags.json")
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
