# Módulo `security-keyvault`

Custodia de secretos y llaves criptográficas. Autorización por RBAC (no *access policies*), sin endpoint público, con Private Endpoint dentro de la subred de datos.

## Entradas principales
`tenant_id`, `data_subnet_id` (de `networking`).

## Salidas
`key_vault_id` (consumido por `observability` y por la asignación de rol en la raíz), `vault_uri` (consumido por `compute-appservice` para referenciar secretos sin valor literal).

Capa 1 (red y seguridad base): depende de `networking` para el Private Endpoint. Las asignaciones de rol "Key Vault Secrets User" hacia las identidades de `compute-appservice` (mínimo privilegio) se declaran en la composición raíz, no en este módulo, para evitar una dependencia circular entre ambos (ver comentario en `main.tf`).
