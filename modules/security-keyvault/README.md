# Módulo `security-keyvault`

Custodia de secretos y llaves criptográficas. Autorización por RBAC (no *access policies*), sin endpoint público, con Private Endpoint y asignación de rol explícita por identidad autorizada (mínimo privilegio, sección 4.3).

## Entradas principales
`tenant_id`, `data_subnet_id`.

## Salidas
`key_vault_id` (consumido por `observability` y por la asignación de rol en la raíz), `vault_uri` (consumido por `compute-appservice` para referenciar secretos sin valor literal).

No depende de ningún otro módulo (capa 1: red y seguridad base). Las asignaciones de rol "Key Vault Secrets User" hacia las identidades de `compute-appservice` se declaran en la composición raíz, no en este módulo, para evitar una dependencia circular entre ambos (ver comentario en `main.tf`).
