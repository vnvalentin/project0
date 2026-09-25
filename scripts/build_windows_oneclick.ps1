param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePackage,

    [string]$OutputPath = "dist\Project0-Launcher.exe",

    [ValidatePattern('^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$')]
    [string]$Version = "0.12.0"
)

$ErrorActionPreference = "Stop"
$payload = Join-Path $PSScriptRoot "..\native\windows_launcher\payload"
$launcher = Join-Path $PSScriptRoot "..\native\windows_launcher"

$required = @(
    "Project0.exe",
    "Project0.pck"
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

$output = if ([System.IO.Path]::IsPathRooted($OutputPath)) {
    [System.IO.Path]::GetFullPath($OutputPath)
} else {
    Join-Path (Get-Location) $OutputPath
}
New-Item -ItemType Directory -Force -Path (Split-Path $output) | Out-Null
Push-Location $launcher
try {
    go build -trimpath -ldflags "-H=windowsgui -X main.launcherClientVersion=$Version" -o $output .
    if ($LASTEXITCODE -ne 0) { throw "Launcher compilation failed: $LASTEXITCODE" }
}
finally {
    Pop-Location
}

Copy-Item (Join-Path $SourcePackage "Project0.exe") (Join-Path (Split-Path $output) "Project0.exe")
Copy-Item (Join-Path $SourcePackage "Project0.pck") (Join-Path (Split-Path $output) "Project0.pck")

Write-Output "Built $output"
(Get-FileHash $output -Algorithm SHA256).Hash
