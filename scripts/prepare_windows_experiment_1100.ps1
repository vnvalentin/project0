param(
    [ValidatePattern('^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$')]
    [string]$Version = "0.13.0",
    [string]$BuildId = ""
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$artifactDirectory = Join-Path $repo "dist\current"
$fixtureRoot = Join-Path $repo "build\validation\exp_1100"
$runId = [Guid]::NewGuid().ToString("N")
$outputDirectory = Join-Path $fixtureRoot $runId
$stagingDirectory = Join-Path $fixtureRoot (".pending-" + $runId)
$startedAt = (Get-Date).ToUniversalTime()
$status = "failed"
$failure = $null
$cleanupFailure = $null
if ([string]::IsNullOrWhiteSpace($BuildId)) {
    $BuildId = "build-" + (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ") + "-" + $runId.Substring(0, 8)
}
New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
try {
$enginePath = Join-Path $artifactDirectory "Project0.exe"
$pckPath = Join-Path $artifactDirectory "Project0.pck"

foreach ($path in @($enginePath, $pckPath)) {
    if (-not (Test-Path $path -PathType Leaf)) {
        throw "Missing replacement baseline artifact: $path"
    }
}

$deployment = Get-Content (Join-Path $artifactDirectory "deployment-manifest.json") -Raw | ConvertFrom-Json
if ($deployment.version -ne $Version) { throw "Requested version does not match the built deployment." }
$engineHash = (Get-FileHash $enginePath -Algorithm SHA256).Hash.ToLowerInvariant()
$pckHash = (Get-FileHash $pckPath -Algorithm SHA256).Hash.ToLowerInvariant()
foreach ($artifactPath in @($enginePath, $pckPath, (Join-Path $artifactDirectory "Project0-Launcher-$Version.exe"))) {
    $entry = @($deployment.artifacts | Where-Object { $_.name -eq (Split-Path $artifactPath -Leaf) })
    if ($entry.Count -ne 1 -or $entry[0].sha256 -ne (Get-FileHash $artifactPath -Algorithm SHA256).Hash) {
        throw "Artifact does not match the deployment manifest: $artifactPath"
    }
}

New-Item -ItemType Directory -Path $stagingDirectory | Out-Null
$manifest = [ordered]@{
    schema_version = 1
    required_client_version = $Version
    build_id = $BuildId
    pck_sha256 = $pckHash
    pck_url = "https://192.168.1.254:8443/api/v1/client/Project0.pck"
    size_bytes = (Get-Item $pckPath).Length
    payloads = @(
        [ordered]@{ name = "Project0.exe"; url = "https://192.168.1.254:8443/api/v1/client/Project0.exe"; sha256 = $engineHash },
        [ordered]@{ name = "Project0.pck"; url = "https://192.168.1.254:8443/api/v1/client/Project0.pck"; sha256 = $pckHash }
    )
}
$manifestPath = Join-Path $stagingDirectory "version-manifest-1100.json"
$signaturePath = Join-Path $stagingDirectory "version-manifest-1100.sig"
$publicKeyPath = Join-Path $stagingDirectory "version-manifest-1100-public.pem"
[IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 6 -Compress), [Text.UTF8Encoding]::new($false))
& go run (Join-Path $repo "scripts\generate_1100_fixture.go") $manifestPath $signaturePath $publicKeyPath
if ($LASTEXITCODE -ne 0) { throw "Manifest signing failed with exit code $LASTEXITCODE." }
[IO.Directory]::Move($stagingDirectory, $outputDirectory)
$status = "prepared"
Write-Output "Prepared signed Experiment 1100 fixture: $outputDirectory"
Get-ChildItem $outputDirectory -File | Select-Object Name, Length
}
catch {
    $failure = $_.Exception.Message
    throw
}
finally {
    try {
        if (Test-Path $stagingDirectory) { Remove-Item $stagingDirectory -Recurse -Force }
    }
    catch {
        $cleanupFailure = $_.Exception.Message
        $status = "failed"
        throw
    }
    finally {
        [ordered]@{
            run_id = $runId
            phase = "fixture_preparation"
            experiment_status = "not_executed"
            status = $status
            version = $Version
            build_id = $BuildId
            host_name = $env:COMPUTERNAME
            started_at_utc = $startedAt.ToString("o")
            completed_at_utc = (Get-Date).ToUniversalTime().ToString("o")
            fixture_directory = $(if (Test-Path $outputDirectory) { $outputDirectory } else { $null })
            failure = $failure
            staging_removed = -not (Test-Path $stagingDirectory)
            cleanup_failure = $cleanupFailure
        } | ConvertTo-Json | Set-Content (Join-Path $fixtureRoot "$runId.result.json") -Encoding UTF8
    }
}