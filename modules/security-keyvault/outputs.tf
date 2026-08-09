output "key_vault_id" {
  description = "ID del Key Vault, consumido por observability para diagnostic settings."
  value       = azurerm_key_vault.this.id
}

output "vault_uri" {
  description = "URI del Key Vault. La aplicación referencia secretos por esta URI, nunca por valor literal."
  value       = azurerm_key_vault.this.vault_uri
}
