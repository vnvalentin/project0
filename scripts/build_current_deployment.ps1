param(
    [string]$Version = $(if ($env:PROJECT0_DEPLOYMENT_VERSION) { $env:PROJECT0_DEPLOYMENT_VERSION } else { "0.12.0" })
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$dist = Join-Path $repo "dist"
$current = Join-Path $dist "current"
$payload = Join-Path $repo "native\windows_launcher\payload"
$dllName = "libwgnetstack_gdext.windows.template_release.x86_64.dll"
$dllSource = Join-Path $repo "native\wgnetstack\gdext\build\$dllName"
$work = Join-Path $repo "build\deployment-work"
$clientStage = Join-Path $work "client"
$clientZip = Join-Path $current "Project0-client-windows-x64-$Version.zip"
$launcherPath = Join-Path $current "Project0-WAN-$Version.exe"
$manifestPath = Join-Path $current "deployment-manifest.json"

function Require-File([string]$Path, [string]$Description) {
    if (-not (Test-Path $Path -PathType Leaf)) {
        throw "Missing $Description`: $Path"
    }
}

Set-Location $repo
Require-File $dllSource "Windows wgnetstack DLL"

Write-Output "Cleaning generated deployment artifacts..."
if (Test-Path $dist) { Remove-Item $dist -Recurse -Force }
if (Test-Path $payload) { Remove-Item $payload -Recurse -Force }
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
New-Item -ItemType Directory -Force -Path $current, $clientStage | Out-Null

Write-Output "Exporting current Godot Windows client..."
$clientExe = Join-Path $clientStage "Project0.exe"
$godotPath = (Get-Command godot -ErrorAction Stop).Source
$godotProcess = Start-Process -FilePath $godotPath -ArgumentList @(
    "--headless", "--path", $repo, "--export-release", '"Windows Desktop"', $clientExe
) -Wait -PassThru -NoNewWindow
$exportExitCode = $godotProcess.ExitCode
Require-File $clientExe "Godot client executable"
Require-File (Join-Path $clientStage "Project0.pck") "Godot client PCK"
$exportWarning = $null
if ($exportExitCode -ne 0) {
    $exportWarning = "Godot returned exit code $exportExitCode after producing complete export artifacts; known GDExtension load warnings were observed during headless export."
    Write-Warning $exportWarning
}
Copy-Item $dllSource (Join-Path $clientStage $dllName)

Write-Output "Creating portable client archive..."
Compress-Archive -Path (Join-Path $clientStage "*") -DestinationPath $clientZip -CompressionLevel Optimal

Write-Output "Building self-service WAN launcher..."
& (Join-Path $PSScriptRoot "build_windows_oneclick.ps1") -SourcePackage $clientStage -OutputPath $launcherPath
if ($LASTEXITCODE -ne 0) { throw "Windows launcher build failed with exit code $LASTEXITCODE" }
Require-File $launcherPath "WAN launcher"

Push-Location (Join-Path $repo "native\windows_launcher")
try {
    & go test ./...
    if ($LASTEXITCODE -ne 0) { throw "Windows launcher tests failed with exit code $LASTEXITCODE" }
}
finally {
    Pop-Location
}

$artifacts = @($clientZip, $launcherPath)
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
Remove-Item $work -Recurse -Force

Write-Output "Deployment ready: $current"
Get-ChildItem $current -File | Select-Object Name, Length
