# Ver envs/prod/outputs.tf.

output "apim_verify_key" {
  description = "Secreto que gatea la ruta directa de verificación post-despliegue en APIM. Configurar como secret de GitHub en novapay-functions: APIM_VERIFY_KEY."
  value       = module.api_management.verify_key
  sensitive   = true
}
