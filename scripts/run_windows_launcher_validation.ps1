$ErrorActionPreference = "Stop"

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw "Windows launcher validation must run on Windows."
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$moduleRoot = Join-Path $repositoryRoot "native\windows_launcher"
$resultDirectory = Join-Path $repositoryRoot "build\validation\windows_launcher"
$summaryPath = Join-Path $resultDirectory "validation-summary.json"
$evidenceDirectory = if ($env:PROJECT0_EXPERIMENT_EVIDENCE_DIR) {
    $env:PROJECT0_EXPERIMENT_EVIDENCE_DIR
} else {
    Join-Path $repositoryRoot "logs\experiments"
}

New-Item -ItemType Directory -Force -Path $resultDirectory | Out-Null
New-Item -ItemType Directory -Force -Path $evidenceDirectory | Out-Null
$env:PROJECT0_EXPERIMENT_EVIDENCE_DIR = $evidenceDirectory
$startedAt = (Get-Date).ToUniversalTime()
$goVersion = (& go version 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0) {
    throw "Go is required for Windows launcher validation: $goVersion"
}

Push-Location $moduleRoot
try {
    # Evidence generation is a test side effect; force all experiment cases to execute.
    & go test -count=1 ./...
    $exitCode = $LASTEXITCODE
}
finally {
    Pop-Location
}

if ($exitCode -eq 0) {
    Push-Location $PSScriptRoot
    try {
        & go test -count=1 generate_1100_fixture.go generate_1100_fixture_test.go
        $exitCode = $LASTEXITCODE
        if ($exitCode -eq 0) { & .\test_prepare_windows_experiment_1100.ps1 }
    }
    catch {
        Write-Warning $_
        $exitCode = 1
    }
    finally {
        Pop-Location
    }
}

$status = if ($exitCode -eq 0) { "passed" } else { "failed" }
[ordered]@{
    runner = "Go"
    scope = "native/windows_launcher"
    includes_fixture_preparation = $true
    status = $status
    exit_code = $exitCode
    os = [Environment]::OSVersion.VersionString
    go_version = $goVersion
    started_at_utc = $startedAt.ToString("o")
    completed_at_utc = (Get-Date).ToUniversalTime().ToString("o")
} | ConvertTo-Json | Set-Content -Encoding utf8 $summaryPath

exit $exitCode
