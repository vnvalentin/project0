$ErrorActionPreference = "Stop"
$godot = if ($env:GODOT_BIN) { $env:GODOT_BIN } else { "godot" }
$runnerOutput = & $godot --headless --path . -s scripts/run_client_ui_smoke.gd
$exitCode = $LASTEXITCODE
for ($attempt = 0; $attempt -lt 1000 -and -not (Test-Path "build/validation/client-ui-summary.json"); $attempt++) {
    [System.Threading.Thread]::Yield() | Out-Null
}
if (-not (Test-Path "build/validation/client-ui-summary.json")) {
    $jsonLine = $runnerOutput | Where-Object { $_ -match '^\{"failures"' } | Select-Object -Last 1
    if ($jsonLine) {
        New-Item -ItemType Directory -Force -Path "build/validation" | Out-Null
        Set-Content -Path "build/validation/client-ui-summary.json" -Value $jsonLine
    }
}
if (Test-Path "build/validation/client-ui-summary.json") {
    Get-Content "build/validation/client-ui-summary.json"
} else {
    Write-Warning "Telemetry file was not visible before process teardown; collect build/validation after the runner exits."
}
exit $exitCode
