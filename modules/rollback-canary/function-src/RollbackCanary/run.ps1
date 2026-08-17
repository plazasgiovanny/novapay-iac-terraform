# Acción real del Action Group de rollback (ADR-03 §2.6, Bloque 2g U4):
# baja a 0% el backend que esté "en rampa" (peso > 0 y < 100) en el
# backend pool ponderado de APIM, sin depender de que el job de CD
# siga vivo — mecanismo asíncrono independiente, ver PLAN.md §3.2.
#
# Determina cuál backend está en rampa consultando el estado REAL del
# pool en el momento de la invocación (no recibe esa información en el
# payload de la alerta): así es idempotente y correcto incluso si la
# alerta llega tarde o duplicada. Si ningún backend está entre 0 y 100
# (ya en 0/100 limpio, o el rollback ya se ejecutó), no hace nada.

using namespace System.Net

param($Request, $TriggerMetadata)

$ErrorActionPreference = "Stop"

$subscriptionId = $env:TARGET_SUBSCRIPTION_ID
$resourceGroup  = $env:TARGET_RESOURCE_GROUP
$apimName       = $env:TARGET_APIM_NAME
$poolName       = $env:TARGET_POOL_NAME
$apiVersion     = "2024-05-01"

function Send-Response($statusCode, $body) {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $statusCode
        Body       = $body
    })
}

try {
    # Token vía la identidad administrada del propio Function App
    # (endpoint local de MSI) — nunca una credencial de larga duración.
    $tokenResponse = Invoke-RestMethod -Method Get `
        -Uri "$($env:IDENTITY_ENDPOINT)?resource=https://management.azure.com/&api-version=2019-08-01" `
        -Headers @{ "X-IDENTITY-HEADER" = $env:IDENTITY_HEADER }
    $authHeader = @{ Authorization = "Bearer $($tokenResponse.access_token)" }

    $poolUri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.ApiManagement/service/$apimName/backends/$poolName" + "?api-version=$apiVersion"

    $pool = Invoke-RestMethod -Method Get -Uri $poolUri -Headers $authHeader
    $services = $pool.properties.pool.services

    $ramping = $services | Where-Object { $_.weight -gt 0 -and $_.weight -lt 100 }

    if (-not $ramping) {
        $estado = ($services | ForEach-Object { "$($_.id)=$($_.weight)" }) -join ", "
        Write-Host "Ningun backend esta en rampa ($estado) -- nada que revertir."
        Send-Response ([HttpStatusCode]::OK) "Nada que revertir: ningun backend esta en rampa."
        return
    }

    $rampingId = $ramping[0].id
    $otherId = ($services | Where-Object { $_.id -ne $rampingId })[0].id

    $body = @{
        properties = @{
            pool = @{
                services = @(
                    @{ id = $rampingId; weight = 0 },
                    @{ id = $otherId; weight = 100 }
                )
            }
        }
    } | ConvertTo-Json -Depth 10

    Invoke-RestMethod -Method Patch -Uri $poolUri -Headers $authHeader -Body $body -ContentType "application/json"

    Write-Host "Rollback ejecutado: $rampingId a 0%, $otherId a 100%."
    Send-Response ([HttpStatusCode]::OK) "Rollback ejecutado: $rampingId a 0%."
}
catch {
    Write-Host "Error ejecutando el rollback: $_"
    Send-Response ([HttpStatusCode]::InternalServerError) "Error ejecutando el rollback: $_"
    throw
}
