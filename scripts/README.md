# `scripts/`

Herramientas operativas versionadas, fuera del alcance de Terraform (mismo criterio ya establecido para `sql/` — scripts reales, no gestionados por `plan`/`apply`).

## `load-generator.sh`

Generador de carga sintética real contra `POST /api/v1/payments/confirmations` (APIM real). Decisión 2026-08-17: este proyecto académico no tiene tráfico orgánico real, así que este script es la fuente de carga controlada para los ítems de evidencia dirigida de `act-4/PLAN.md` §3.5 que la requieren — no hay generador de terceros de por medio, es simple `curl` en un loop de bash, para máxima transparencia sobre qué solicitud real se envía y con qué resultado.

Requiere `NOVAPAY_APIM_KEY` (subscription key de APIM) como variable de entorno — **nunca** hardcodeada aquí. Obtenerla con:

```bash
SUB=$(az account show --query id -o tsv)
az rest --method post --uri "https://management.azure.com/subscriptions/$SUB/resourceGroups/rg-novapay-prod/providers/Microsoft.ApiManagement/service/apim-novapay-prod/subscriptions/<subscription-id>/listSecrets?api-version=2024-05-01" --query "primaryKey" -o tsv
```

Ver los comentarios del script para ejemplos de invocación exactos (rampa canary con métricas, forzar el rollback automático, acumular ≥100 muestras de SLI).

Cada solicitud usa un `TransactionId` (GUID) único — sin eso, la deduplicación real de `ValidatePayment` (`_notifications.ExistsAsync`) respondería `409 Conflict` en vez de generar tráfico nuevo. Los montos "inválidos" (`ERROR_RATE_PCT`) superan `Payments:MaxTransactionAmount` (validación real en `AccountValidationService.cs`, `novapay-functions`) — provocan un `400` real, no un fallo simulado, y sí cuentan como `success=false` en Application Insights.

Probado contra Azure real (2026-08-17): 3 solicitudes válidas → 3× `202`; 3 solicitudes forzadas a inválidas → 3× `400`.
