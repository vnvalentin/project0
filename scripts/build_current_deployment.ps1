param(
    [ValidatePattern('^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$')]
    [string]$Version = $(if ($env:PROJECT0_DEPLOYMENT_VERSION) { $env:PROJECT0_DEPLOYMENT_VERSION } else { "0.12.0" })
)

# Slice 108: the server-deployment stage was removed. Servers are deployed from
# published container images by scripts/deploy_containers.sh on the host; this
# script now only builds the local Windows client package.

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$dist = Join-Path $repo "dist"
$current = Join-Path $dist "current"
$payload = Join-Path $repo "native\windows_launcher\payload"
$work = Join-Path $repo "build\deployment-work"
$clientStage = Join-Path $work "client"
$exportSource = Join-Path $work "export-source"
$rceditPath = Join-Path $repo "build\tools\rcedit\node_modules\rcedit\bin\rcedit-x64.exe"
$clientZip = Join-Path $current "Project0-client-windows-x64-$Version.zip"
$launcherPath = Join-Path $current "Project0-Launcher-$Version.exe"
$manifestPath = Join-Path $current "deployment-manifest.json"

function Test-RequiredFile([string]$Path, [string]$Description) {
    if (-not (Test-Path $Path -PathType Leaf)) {
        throw "Missing $Description`: $Path"
    }
}

Set-Location $repo
$godotPath = (Get-Command godot -ErrorAction Stop).Source
Get-Command go -ErrorAction Stop | Out-Null
if (-not (Test-Path $rceditPath -PathType Leaf)) {
    & npm.cmd install --prefix (Join-Path $repo "build\tools\rcedit") rcedit@5.0.2 --no-save --ignore-scripts --no-audit --no-fund
    if ($LASTEXITCODE -ne 0) { throw "Pinned rcedit installation failed: $LASTEXITCODE" }
}
Test-RequiredFile $rceditPath "rcedit executable"
Write-Output "Cleaning generated deployment artifacts..."
if (Test-Path $dist) { Remove-Item $dist -Recurse -Force }
if (Test-Path $payload) { Remove-Item $payload -Recurse -Force }
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
New-Item -ItemType Directory -Force -Path $current, $clientStage | Out-Null

try {
Write-Output "Exporting current Godot Windows client..."
$excludedDirectories = @(
    (Join-Path $repo ".git"),
    (Join-Path $repo ".godot"),
    (Join-Path $repo ".scratch"),
    (Join-Path $repo ".venv"),
    (Join-Path $repo "build"),
    (Join-Path $repo "dashboard"),
    (Join-Path $repo "deploy"),
    (Join-Path $repo "docs"),
    (Join-Path $repo "dist"),
    (Join-Path $repo "infra"),
    (Join-Path $repo "logs"),
    (Join-Path $repo "native"),
    (Join-Path $repo "operator_console"),
    (Join-Path $repo "scripts"),
    (Join-Path $repo "server"),
    (Join-Path $repo "tests"),
    (Join-Path $repo "addons\godot-sqlite"),
    (Join-Path $repo "addons\gut")
)
$robocopyArgs = @($repo, $exportSource, "/E", "/NFL", "/NDL", "/NJH", "/NJS", "/NP", "/XD") + $excludedDirectories
& robocopy @robocopyArgs | Out-Null
if ($LASTEXITCODE -gt 7) {
    throw "Failed to stage the Windows client export source with robocopy (exit code $LASTEXITCODE)."
}
$versionScript = Join-Path $exportSource "shared\client_build_version.gd"
$versionSource = [IO.File]::ReadAllText($versionScript)
$versionPattern = '(?m)^const CLIENT_BUILD_VERSION: String = "[^"]*"'
if ([regex]::Matches($versionSource, $versionPattern).Count -ne 1) {
    throw "Client version assignment is missing or ambiguous."
}
$versionSource = [regex]::Replace($versionSource, $versionPattern, ('const CLIENT_BUILD_VERSION: String = "{0}"' -f $Version))
[IO.File]::WriteAllText($versionScript, $versionSource, [Text.UTF8Encoding]::new($false))
$clientExe = Join-Path $clientStage "Project0.exe"
$godotProcess = Start-Process -FilePath $godotPath -ArgumentList @(
    "--headless", "--path", $exportSource, "--export-release", '"Windows Desktop"', $clientExe
) -Wait -PassThru -NoNewWindow
$exportExitCode = $godotProcess.ExitCode
if ($exportExitCode -ne 0) { throw "Godot export failed: $exportExitCode" }
Test-RequiredFile $clientExe "Godot client executable"
Test-RequiredFile (Join-Path $clientStage "Project0.pck") "Godot client PCK"
$rceditVersion = "$Version.0"
Test-RequiredFile $rceditPath "rcedit executable"
& $rceditPath $clientExe --set-file-version $rceditVersion --set-product-version $rceditVersion
if ($LASTEXITCODE -ne 0) {
    throw "rcedit failed with exit code $LASTEXITCODE."
}
$exportWarning = $null
Write-Output "Creating portable client archive..."
Compress-Archive -Path (Join-Path $clientStage "*") -DestinationPath $clientZip -CompressionLevel Optimal

Write-Output "Building self-service WAN launcher..."
& (Join-Path $PSScriptRoot "build_windows_oneclick.ps1") -SourcePackage $clientStage -OutputPath $launcherPath -Version $Version
if ($LASTEXITCODE -ne 0) { throw "Windows launcher build failed with exit code $LASTEXITCODE" }
Test-RequiredFile $launcherPath "WAN launcher"

Push-Location (Join-Path $repo "native\windows_launcher")
try {
    & go test ./...
    if ($LASTEXITCODE -ne 0) { throw "Windows launcher tests failed with exit code $LASTEXITCODE" }
}
finally {
    Pop-Location
}

$artifacts = @($clientZip, $launcherPath, (Join-Path $current "Project0.exe"), (Join-Path $current "Project0.pck"))
$manifest = [ordered]@{
    version = $Version
    built_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    source_commit = (& git -C $repo rev-parse --short HEAD).Trim()
    source_tree_dirty = @(& git -C $repo status --short).Count -gt 0
    godot_export_exit_code = $exportExitCode
    godot_export_warning = $exportWarning
    artifacts = @($artifacts | ForEach-Object {
        $item = Get-Item $_
        [ordered]@{
            name = $item.Name
            bytes = $item.Length
            sha256 = (Get-FileHash $_ -Algorithm SHA256).Hash
        }
    })
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding utf8
Write-Output "Deployment ready: $current"
Get-ChildItem $current -File | Select-Object Name, Length
}
finally {
    if (Test-Path $work) { Remove-Item $work -Recurse -Force }
}
