# Starts everything the demo case needs on one Windows computer, with the ports sorted out:
#   cold-monitor (this repository)  dashboard and API on 8090
#   cold-monitor-edge               broker for the temperature ESP32 on 1883, bridge on 8081
#   machine-telemetry               broker for the current ESP32 on 1884, platform on 8080, Grafana on 3000
# and registers the demo probe, so its readings reach the dashboard and the Telegram alert.
#
# Usage (PowerShell, Docker Desktop running):  .\maleta\maleta.ps1 [up|build|down|status]
#   up      start (builds only the images that are missing, so it works offline after the first time)
#   build   rebuild every image from the current code, then start
#   down    stop everything; data is kept
#   status  containers and addresses
# If Windows refuses to run scripts: powershell -ExecutionPolicy Bypass -File .\maleta\maleta.ps1
#
# The repositories are expected side by side ($env:EDGE_DIR and $env:MT_DIR override that):
#   cold-monitor-backend\  cold-monitor-dashboard\  cold-monitor-infra\  cold-monitor-edge\  machine-telemetry\
param([ValidateSet('up', 'build', 'down', 'status')][string]$Command = 'up')

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
$Infra = Split-Path $Here -Parent
$Root = Split-Path $Infra -Parent
$Edge = if ($env:EDGE_DIR) { $env:EDGE_DIR } else { Join-Path $Root 'cold-monitor-edge' }
$Mt = if ($env:MT_DIR) { $env:MT_DIR } else { Join-Path $Root 'machine-telemetry' }
$MtMqttPort = 1884
$Code = 'MALETA-01'

function Fail([string]$message) {
    Write-Host "maleta: $message" -ForegroundColor Red
    exit 1
}

# value of a key in an env file, without quotes; empty if absent
function Get-EnvValue([string]$file, [string]$key) {
    if (-not (Test-Path $file)) { return '' }
    $line = Get-Content $file | Where-Object { $_ -match "^$key=" } | Select-Object -Last 1
    if (-not $line) { return '' }
    return ($line -replace "^$key=", '').Trim().Trim('"').Trim("'")
}

# docker compose in a folder, with extra environment variables for that call only
function Invoke-Compose([string]$dir, [hashtable]$vars, [string[]]$arguments) {
    $saved = @{}
    foreach ($name in $vars.Keys) {
        $saved[$name] = [Environment]::GetEnvironmentVariable($name)
        [Environment]::SetEnvironmentVariable($name, $vars[$name])
    }
    Push-Location $dir
    try {
        & docker compose @arguments
        if ($LASTEXITCODE -ne 0) { Fail "docker compose $($arguments -join ' ') failed in $dir" }
    }
    finally {
        Pop-Location
        foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    }
}

function Test-Setup {
    foreach ($dir in @((Join-Path $Root 'cold-monitor-backend'), (Join-Path $Root 'cold-monitor-dashboard'), $Edge, $Mt)) {
        if (-not (Test-Path $dir)) { Fail "missing $dir`: clone the repositories side by side (see maleta\README.md)" }
    }
    foreach ($envFile in @((Join-Path $Infra '.env'), (Join-Path $Edge '.env'), (Join-Path $Mt '.env'))) {
        if (-not (Test-Path $envFile)) { Fail "missing $envFile`: copy .env.example to .env there and fill it in (see maleta\README.md)" }
    }
    if (-not (Test-Path (Join-Path $Here 'maleta.env'))) { Fail 'missing maleta\maleta.env: copy maleta\maleta.env.example and fill it in' }
    if (-not (Get-EnvValue (Join-Path $Mt '.env') 'MQTT_NODE_PASSWORD')) {
        Write-Host "warning: MQTT_NODE_PASSWORD is empty in $Mt\.env, so the current ESP32 cannot log in" -ForegroundColor Yellow
    }
}

function Get-LanIp {
    if (-not (Get-Command Get-NetIPConfiguration -ErrorAction SilentlyContinue)) { return '<IP deste computador>' }
    $config = Get-NetIPConfiguration -ErrorAction SilentlyContinue |
        Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } | Select-Object -First 1
    if ($config) { return $config.IPv4Address[0].IPAddress }
    return '<IP deste computador>'
}

function Wait-Url([string]$url, [int]$seconds, [hashtable]$headers = @{}) {
    for ($i = 0; $i -lt $seconds; $i++) {
        try {
            Invoke-RestMethod -Uri $url -Headers $headers -TimeoutSec 3 | Out-Null
            return $true
        }
        catch { Start-Sleep -Seconds 1 }
    }
    return $false
}

# the demo probe's equipment id, registering it the first time (a device key may list and register equipment)
function Get-EquipmentId([string]$api, [string]$key, [string]$min, [string]$max) {
    $headers = @{ 'X-API-Key' = $key }
    $list = Invoke-RestMethod -Uri "$api/equipment" -Headers $headers
    foreach ($equipment in $list) {
        if ($equipment.code -eq $Code) { return $equipment.id }
    }
    $body = @{ code = $Code; name = 'Sonda da maleta'; location = 'Demonstração'; type = 'COLD_ROOM';
        minTemperature = [double]$min; maxTemperature = [double]$max } | ConvertTo-Json
    $created = Invoke-RestMethod -Method Post -Uri "$api/equipment" -Headers $headers -ContentType 'application/json; charset=utf-8' `
        -Body ([Text.Encoding]::UTF8.GetBytes($body))
    Write-Host "registered $Code ($min to $max °C)"
    return $created.id
}

# the broker users of cold-monitor-edge's Mosquitto, from the passwords in its .env and in maleta.env
function Set-EdgeUsers {
    $file = Join-Path $Edge 'mosquitto\passwd'
    $bridge = Get-EnvValue (Join-Path $Edge '.env') 'MQTT_BRIDGE_PASSWORD'
    $device = Get-EnvValue (Join-Path $Here 'maleta.env') 'COLD_DEVICE_ID'
    $password = Get-EnvValue (Join-Path $Here 'maleta.env') 'COLD_DEVICE_PASSWORD'
    if ((Test-Path $file) -and (-not $device -or (Select-String -Path $file -Pattern "^$device`:" -Quiet))) { return }
    if (-not $bridge) { Fail "MQTT_BRIDGE_PASSWORD is empty in $Edge\.env" }
    Write-Host 'creating the broker users of cold-monitor-edge'
    $script = 'touch /mosquitto/config/passwd && mosquitto_passwd -b /mosquitto/config/passwd bridge "$B" && ' +
        'if [ -n "$D" ]; then mosquitto_passwd -b /mosquitto/config/passwd "$D" "$P"; fi; chmod 0700 /mosquitto/config/passwd'
    & docker run --rm -v "$(Join-Path $Edge 'mosquitto'):/mosquitto/config" -e "B=$bridge" -e "D=$device" -e "P=$password" `
        eclipse-mosquitto:2 sh -c $script
    if ($LASTEXITCODE -ne 0) { Fail 'could not create the broker users' }
}

# the edge's compose requires the key even to stop or list; it is the same one Start-Maleta passes
function Get-EdgeKey {
    return @{ BACKEND_API_KEY = (Get-EnvValue (Join-Path $Infra '.env') 'DEVICE_API_KEY') }
}

function Start-Maleta([bool]$build) {
    Test-Setup
    $upArgs = @('up', '-d')
    if ($build) { $upArgs += '--build' }
    $key = Get-EnvValue (Join-Path $Infra '.env') 'DEVICE_API_KEY'
    $port = Get-EnvValue (Join-Path $Infra '.env') 'DASHBOARD_PORT'
    if (-not $port) { $port = '8090' }
    $api = "http://localhost:$port/api/v1"

    Write-Host '== cold-monitor' -ForegroundColor Cyan
    Invoke-Compose $Infra @{} $upArgs
    if (-not (Wait-Url "$api/equipment" 180 @{ 'X-API-Key' = $key })) { Fail "the cold-monitor API did not answer at $api" }

    $maleta = Join-Path $Here 'maleta.env'
    $min = Get-EnvValue $maleta 'PROBE_MIN'; if (-not $min) { $min = '10' }
    $max = Get-EnvValue $maleta 'PROBE_MAX'; if (-not $max) { $max = '35' }
    $id = Get-EquipmentId $api $key $min $max
    $probe = Get-EnvValue $maleta 'PROBE'
    $probes = ''
    if ($probe) { $probes = "$probe=$id" }
    else { Write-Host 'warning: PROBE is empty in maleta\maleta.env, so the bridge drops the probe''s readings' -ForegroundColor Yellow }

    Write-Host '== cold-monitor-edge' -ForegroundColor Cyan
    Set-EdgeUsers
    # these win over the edge's .env: the backend is this computer's cold-monitor, with its key and the demo probe
    Invoke-Compose $Edge @{ BACKEND_URL = "http://host.docker.internal:$port"; BACKEND_API_KEY = $key; BRIDGE_PROBES = $probes } $upArgs

    Write-Host '== machine-telemetry' -ForegroundColor Cyan
    Invoke-Compose $Mt @{ MQTT_PORT = "$MtMqttPort" } $upArgs
    if (-not (Wait-Url 'http://localhost:3000/api/health' 180)) {
        Write-Host 'warning: Grafana did not answer on port 3000 yet' -ForegroundColor Yellow
    }

    $ip = Get-LanIp
    Write-Host ''
    Write-Host 'Maleta pronta / demo case ready.' -ForegroundColor Green
    Write-Host "  Temperatura (cold-monitor):   http://$ip`:$port        (no notebook: http://localhost:$port)"
    Write-Host "  Máquinas (Grafana):           http://$ip`:3000         (no notebook: http://localhost:3000)"
    Write-Host "  ESP32 de temperatura, broker: mqtt://$ip`:1883"
    Write-Host "  ESP32 de corrente, broker:    mqtt://$ip`:$MtMqttPort"
    Write-Host 'Se o IP mudou desde a gravação dos ESP32, ajuste o broker no menuconfig deles (ou fixe o IP do notebook).'
}

switch ($Command) {
    'up' { Start-Maleta $false }
    'build' { Start-Maleta $true }
    'down' {
        Invoke-Compose $Mt @{} @('down')
        Invoke-Compose $Edge (Get-EdgeKey) @('down')
        Invoke-Compose $Infra @{} @('down')
    }
    'status' {
        $format = @('ps', '--format', 'table {{.Service}}\t{{.Status}}\t{{.Ports}}')
        Write-Host '== cold-monitor-infra' -ForegroundColor Cyan
        Invoke-Compose $Infra @{} $format
        Write-Host '== cold-monitor-edge' -ForegroundColor Cyan
        Invoke-Compose $Edge (Get-EdgeKey) $format
        Write-Host '== machine-telemetry' -ForegroundColor Cyan
        Invoke-Compose $Mt @{} $format
    }
}
