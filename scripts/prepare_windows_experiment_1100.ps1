param(
    [string]$Version = "0.13.0",
    [string]$BuildId = "build-20260925-1820-local"
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$artifactDirectory = Join-Path $repo "dist\current"
$outputDirectory = Join-Path $repo "build\validation\exp_1100"
$enginePath = Join-Path $artifactDirectory "Project0.exe"
$pckPath = Join-Path $artifactDirectory "Project0.pck"

foreach ($path in @($enginePath, $pckPath)) {
    if (-not (Test-Path $path -PathType Leaf)) {
        throw "Missing replacement baseline artifact: $path"
    }
}

New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
$engineHash = (Get-FileHash $enginePath -Algorithm SHA256).Hash.ToLowerInvariant()
$pckHash = (Get-FileHash $pckPath -Algorithm SHA256).Hash.ToLowerInvariant()

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
$manifestPath = Join-Path $outputDirectory "version-manifest-1100.json"
$signaturePath = Join-Path $outputDirectory "version-manifest-1100.sig"
$privateKeyPath = Join-Path $outputDirectory "version-manifest-1100-private.pem"
$manifest | ConvertTo-Json -Depth 6 -Compress | Set-Content -LiteralPath $manifestPath -Encoding utf8
& go run (Join-Path $repo "scripts\generate_1100_fixture.go") $manifestPath $signaturePath $privateKeyPath
if ($LASTEXITCODE -ne 0) { throw "Manifest signing failed with exit code $LASTEXITCODE." }
Write-Output "Prepared signed Experiment 1100 fixture: $outputDirectory"
Get-ChildItem $outputDirectory -File | Select-Object Name, Length