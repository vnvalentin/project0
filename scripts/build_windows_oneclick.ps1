param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePackage,

    [string]$OutputPath = "dist\Project0-WAN.exe"
)

$ErrorActionPreference = "Stop"
$payload = Join-Path $PSScriptRoot "..\native\windows_launcher\payload"
$launcher = Join-Path $PSScriptRoot "..\native\windows_launcher"

$required = @(
    "Project0.exe",
    "Project0.pck",
    "libwgnetstack_gdext.windows.template_release.x86_64.dll"
)
foreach ($name in $required) {
    $source = Join-Path $SourcePackage $name
    if (-not (Test-Path $source -PathType Leaf)) {
        throw "Missing package file: $source"
    }
}
if (Test-Path $payload) {
    Remove-Item $payload -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $payload | Out-Null

Copy-Item (Join-Path $SourcePackage "Project0.exe") $payload
Copy-Item (Join-Path $SourcePackage "Project0.pck") $payload
Copy-Item (Join-Path $SourcePackage "libwgnetstack_gdext.windows.template_release.x86_64.dll") $payload
$nested = Join-Path $payload "native\wgnetstack\gdext\build"
New-Item -ItemType Directory -Force -Path $nested | Out-Null
Copy-Item (Join-Path $SourcePackage "libwgnetstack_gdext.windows.template_release.x86_64.dll") $nested

$output = Join-Path (Get-Location) $OutputPath
New-Item -ItemType Directory -Force -Path (Split-Path $output) | Out-Null
Push-Location $launcher
try {
    go build -trimpath -ldflags "-H=windowsgui" -o $output .
}
finally {
    Pop-Location
}

Write-Output "Built $output"
(Get-FileHash $output -Algorithm SHA256).Hash
