# `rollback-canary`

Bloque 2g de la Fase 3 de U4 (ADR-03 §2.6). Mecanismo de rollback de tráfico **asíncrono e independiente** del job de CD de `novapay-functions`: ese job ya tiene su propio guardrail en línea (`observe_and_guard`, rollback inmediato si el error rate supera 3% en 5 minutos), pero ese guardrail solo protege mientras el job de GitHub Actions sigue vivo. Este módulo es la red de seguridad para el caso en que el runner se cae, se cancela, o GitHub Actions no está disponible.

## Componentes

1. **Alerta** (`azurerm_monitor_scheduled_query_rules_alert_v2`): evalúa cada 5 minutos el error rate de ambos Function Apps de pagos (sin depender de saber cuál está en rampa — evalúa los dos y toma el máximo).
2. **Action Group**: su acción es la Azure Function de abajo, invocada por HTTP POST con la function key incrustada en la URL (requisito real de Azure Monitor para acciones tipo Function — Azure Monitor no autentica por identidad administrada contra Function Apps).
3. **Azure Function** (`func-novapay-rollback-canary-{env}`, PowerShell, Consumption Y1): al invocarse, consulta el estado **real** del backend pool de APIM en ese momento (no confía en el payload de la alerta), determina cuál backend está "en rampa" (peso entre 0 y 100) y lo baja a 0% — idempotente: si no hay ningún backend en ese estado, no hace nada.

## Por qué el código vive en este repositorio

ADR-03 §2.6 especifica "Azure Function" (no un Logic App, evaluado como alternativa más simple de IaC puro). Implementarlo fielmente exige código real, pero crear un tercer repo/pipeline (como `novapay-functions`) para una utilidad de una sola función sería sobre-ingeniería. El código (PowerShell, `function-src/`) se empaqueta con el provider `archive` y se despliega vía `WEBSITE_RUN_FROM_PACKAGE` en el mismo `terraform apply` — sin CD externo.

## Limitaciones reconocidas, no ocultas

- El SAS del blob de despliegue (`WEBSITE_RUN_FROM_PACKAGE`) tiene una expiración larga (10 años) porque, a diferencia de `AzureWebJobsStorage` (que sí usa identidad administrada nativamente en este modelo clásico de Function App), la lectura del paquete de despliegue vía URL privada sí requiere un SAS. Si expirara, el Function App no podría recuperar su paquete en el próximo arranque en frío tras escalar a cero — riesgo real, aceptable dado que esta función se invoca con muy poca frecuencia.
- `run.ps1` no usa el módulo `Az` de PowerShell (llama directo a la API ARM vía el endpoint local de identidad administrada) para evitar el costo de arranque en frío de cargar ese módulo — relevante porque esta función debe responder rápido ante un incidente real.
