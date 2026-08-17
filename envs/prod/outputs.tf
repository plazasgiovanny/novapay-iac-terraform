# Outputs a nivel de raíz — solo lo que necesita salir de este
# ambiente hacia otro sistema (GitHub Secrets de novapay-functions),
# no lo que ya se consume internamente entre módulos.

output "apim_verify_key" {
  description = "Secreto que gatea la ruta directa de verificación post-despliegue en APIM (ver HALLAZGO REAL en modules/api-management/main.tf, azurerm_api_management_api_policy.confirmaciones). Configurar como secret de GitHub en novapay-functions: APIM_VERIFY_KEY."
  value       = module.api_management.verify_key
  sensitive   = true
}
