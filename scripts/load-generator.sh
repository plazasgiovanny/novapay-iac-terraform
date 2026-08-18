#!/usr/bin/env bash
# scripts/load-generator.sh
#
# Generador de carga sintética real contra POST /api/v1/payments/confirmations
# (APIM real, apim-novapay-{env}) — decisión 2026-08-17: este proyecto
# académico no tiene tráfico orgánico real, así que este script es la
# fuente de carga controlada para los ítems de evidencia dirigida de
# PLAN.md (act-4) §3.5 que la requieren: rampa canary con métricas por
# paso, forzar el rollback automático, y acumular >=100 muestras del
# SLI de latencia de cola.
#
# NUNCA hardcodea la subscription key de APIM — se lee de la variable
# de entorno NOVAPAY_APIM_KEY (obtenerla con
# `az apim subscription show ...` o desde el output sensible de
# Terraform `module.api_management.subscription_primary_key`, nunca
# committeada a este repo).
#
# Ejemplos de uso reales (PLAN.md §3.5):
#   Rampa canary con métricas (>=50 solicitudes en >=15 min, mismo
#   umbral que observe_and_guard en novapay-functions/cd.yml):
#     NOVAPAY_APIM_KEY=... COUNT=60 DURATION_SECONDS=1200 ./load-generator.sh
#
#   ERROR_RATE_PCT NO sirve para forzar el rollback automático de
#   cd.yml — HALLAZGO REAL (2026-08-17, verificado en Application
#   Insights antes de corregir este comentario): un 400 devuelto
#   deliberadamente por ValidatePayment (sin lanzar excepción) queda
#   registrado con success="True" en Application Insights, sin
#   importar el código HTTP. El guardrail de observe_and_guard
#   (cd.yml) filtra success == false, así que nunca se dispara con
#   este tipo de error — verificado con 230+ solicitudes reales sin
#   ningún efecto. Para forzar el rollback de verdad hace falta un
#   fallo real no controlado (5xx/timeout), ver PLAN.md §3.5.
#
#   Acumular >=100 muestras de SLI (puede correrse varias veces y sumar):
#     NOVAPAY_APIM_KEY=... COUNT=100 INTERVAL_SECONDS=5 ./load-generator.sh

set -euo pipefail

APIM_URL="${NOVAPAY_APIM_URL:-https://apim-novapay-prod.azure-api.net/api/v1/payments/confirmations}"
APIM_KEY="${NOVAPAY_APIM_KEY:?Falta la variable de entorno NOVAPAY_APIM_KEY (subscription key de APIM — az apim subscription show, nunca hardcodeada en este script).}"

COUNT="${COUNT:-50}"
# Si se define DURATION_SECONDS, tiene prioridad sobre INTERVAL_SECONDS
# (se recalcula para repartir COUNT solicitudes a lo largo de esa
# ventana — útil para cumplir el umbral de observación real de
# observe_and_guard, >=15 min Y >=50 solicitudes).
DURATION_SECONDS="${DURATION_SECONDS:-}"
INTERVAL_SECONDS="${INTERVAL_SECONDS:-2}"
# 0-100: porcentaje de solicitudes deliberadamente inválidas (Amount
# por encima de Payments:MaxTransactionAmount, ver
# AccountValidationService.cs en novapay-functions) — provoca un 400
# real, no un fallo simulado. Útil para acumular muestras de tasa de
# error real observable end-to-end, pero NO cuenta como
# "success=false" en Application Insights (ValidatePayment maneja la
# validación sin lanzar excepción) — no sirve para disparar el
# guardrail de error rate de cd.yml, ver PLAN.md §3.5.
ERROR_RATE_PCT="${ERROR_RATE_PCT:-0}"
CURRENCY="${CURRENCY:-COP}"

if [ -n "$DURATION_SECONDS" ] && [ "$COUNT" -gt 0 ]; then
  INTERVAL_SECONDS=$(awk -v d="$DURATION_SECONDS" -v c="$COUNT" 'BEGIN { printf "%.2f", d / c }')
fi

echo "Generador de carga NovaPay — destino: $APIM_URL"
echo "COUNT=$COUNT INTERVAL_SECONDS=$INTERVAL_SECONDS ERROR_RATE_PCT=$ERROR_RATE_PCT"
echo ""

success_count=0
error_count=0
resp_body="$(mktemp)"
trap 'rm -f "$resp_body"' EXIT

for i in $(seq 1 "$COUNT"); do
  transaction_id=$(openssl rand -hex 16 | sed -E 's/(.{8})(.{4})(.{4})(.{4})(.{12})/\1-\2-\3-\4-\5/')

  roll=$((RANDOM % 100))
  if [ "$roll" -lt "$ERROR_RATE_PCT" ]; then
    expected="invalid (Amount > limite)"
    amount=99999999
  else
    expected="valid"
    amount=$(((RANDOM % 500000) + 1000))
  fi

  body=$(printf '{"TransactionId":"%s","SourceAccount":"ACC-LOAD-%05d","DestinationAccount":"ACC-LOAD-%05d","Amount":%d,"Currency":"%s"}' \
    "$transaction_id" "$i" "$((i + 1))" "$amount" "$CURRENCY")

  start_ms=$(date +%s%3N)
  http_code=$(curl -sS --max-time 30 -o "$resp_body" -w "%{http_code}" \
    -X POST "$APIM_URL" \
    -H "Content-Type: application/json" \
    -H "Ocp-Apim-Subscription-Key: $APIM_KEY" \
    -d "$body" || echo "000")
  end_ms=$(date +%s%3N)
  elapsed_ms=$((end_ms - start_ms))

  if [ "$http_code" = "202" ]; then
    success_count=$((success_count + 1))
  else
    error_count=$((error_count + 1))
  fi

  printf '[%d/%s] transactionId=%s expected=%s http=%s elapsed_ms=%s\n' \
    "$i" "$COUNT" "$transaction_id" "$expected" "$http_code" "$elapsed_ms"

  if [ "$i" -lt "$COUNT" ]; then
    sleep "$INTERVAL_SECONDS"
  fi
done

total=$((success_count + error_count))
if [ "$total" -gt 0 ]; then
  error_pct=$((error_count * 100 / total))
else
  error_pct=0
fi

echo ""
echo "Resumen: $total solicitudes, $success_count exitosas (202), $error_count con error — ${error_pct}% error rate real."
