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
#
# HALLAZGO REAL (apply real fallido, release v1.0.17, 2026-08-17): la
# primera versión de esta política apuntaba a "type = Microsoft.Web/sites"
# (el recurso raíz) y terminó bloqueando una actualización legítima y no
# relacionada de ambos Function Apps de pagos con
# RequestDisallowedByPolicy — el PUT/PATCH que el provider azurerm envía
# contra el recurso raíz para cambios que no tocan ip_restriction (p.ej.
# app_settings) no incluye el campo siteConfig.ipSecurityRestrictionsDefaultAction
# en ese payload puntual, así que la política lo evaluaba como "ausente"
# y denegaba cualquier escritura, no solo la que de verdad quitaría la
# restricción. Mismo síntoma documentado por la comunidad en
# https://github.com/Azure/azure-policy/issues/682 (evaluación de
# alias siteConfig.* contra Microsoft.Web/sites no es confiable, ni para
# Deny en escritura ni para el compliance scan). Fix real (mismo patrón
# de la solución aceptada en ese issue): apuntar al sub-recurso real que
# sí carga el body completo de ip_restriction en cada escritura —
# "Microsoft.Web/sites/config" con nombre "web" — filtrado por el ID
# completo (no por "name", que en un sub-recurso solo trae el segmento
# hijo "web", no el sitio padre). Requiere mode = "All": "Indexed" solo
# evalúa tipos que soportan tags/location, y este sub-recurso no los
# soporta directamente (hereda del sitio padre).
# Alias ARM verificado contra la API real (no asumido):
# `az rest --method get --uri "https://management.azure.com/providers/Microsoft.Web?api-version=2021-04-01&$expand=resourceTypes/aliases"`
# confirma "Microsoft.Web/sites/config/web.ipSecurityRestrictionsDefaultAction"
# como alias válido para Azure Policy.
#
# HALLAZGO REAL #2 (apply real fallido, release v1.0.18, 2026-08-17):
# el primer intento de este fix filtraba por "id like
# */sites/func-novapay-pagos*/config/web" — dos caracteres '*'. Azure
# rechaza la definición completa con 400 InvalidPolicyLikeOperator:
# "like"/"notLike" solo admite UN wildcard. Como la definición nunca
# llegó a actualizarse, la política vieja (la del HALLAZGO REAL de
# arriba) siguió activa y volvió a bloquear las mismas escrituras
# legítimas — mismo síntoma, causa distinta. Fix real: templatefile()
# en vez de file() (interpola var.environment) + dos condiciones "like"
# en "anyOf", una por cada Function App de pagos, cada una con un solo
# wildcard al inicio — ver policies/require-ip-restriction.json.tpl.
#
# HALLAZGO REAL #3 (apply real fallido, release v1.0.19, 2026-08-17):
# el fix del HALLAZGO REAL anterior seguía fallando, ahora con 400
# InvalidPolicyAlias — el propio error de Azure trae la lista completa
# de alias soportados para el tipo "Microsoft.Web/sites/config" y
# confirma que "Microsoft.Web/sites/config/web.ipSecurityRestrictionsDefaultAction"
# NO es uno de ellos (el prefijo "web." sí existe para las propiedades
# del array, p.ej. "config/web.ipSecurityRestrictions[*].action", pero
# NO para la propiedad "DefaultAction" — inconsistencia real de
# nomenclatura de Microsoft, no un error nuestro). El alias correcto,
# tomado literalmente de esa misma lista, es
# "Microsoft.Web/sites/config/ipSecurityRestrictionsDefaultAction" (sin
# "web."). La verificación anterior contra el dump genérico de aliases
# del provider (`az rest .../providers/Microsoft.Web?$expand=resourceTypes/aliases`)
# no bastó: ese dump no distingue qué alias es válido para cada
# resourceType específico ("sites" vs "sites/config") — la fuente de
# verdad real es el propio mensaje de error del API de
# CreateOrUpdate de la definición de política, no el dump genérico.
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
