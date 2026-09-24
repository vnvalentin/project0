$ErrorActionPreference = "Stop"

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw "Windows launcher validation must run on Windows."
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$moduleRoot = Join-Path $repositoryRoot "native\windows_launcher"
$resultDirectory = Join-Path $repositoryRoot "build\validation\windows_launcher"
$summaryPath = Join-Path $resultDirectory "validation-summary.json"

New-Item -ItemType Directory -Force -Path $resultDirectory | Out-Null
$startedAt = (Get-Date).ToUniversalTime()
$goVersion = (& go version 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0) {
    throw "Go is required for Windows launcher validation: $goVersion"
}

Push-Location $moduleRoot
try {
    & go test ./...
    $exitCode = $LASTEXITCODE
}
finally {
    Pop-Location
}

$status = if ($exitCode -eq 0) { "passed" } else { "failed" }
[ordered]@{
    runner = "Go"
    scope = "native/windows_launcher"
    status = $status
    exit_code = $exitCode
    os = [Environment]::OSVersion.VersionString
    go_version = $goVersion
    started_at_utc = $startedAt.ToString("o")
    completed_at_utc = (Get-Date).ToUniversalTime().ToString("o")
} | ConvertTo-Json | Set-Content -Encoding utf8 $summaryPath

exit $exitCode
