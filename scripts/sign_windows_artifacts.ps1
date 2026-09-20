param(
    [string]$ArtifactDirectory = "dist\current",
    [string]$CertificateThumbprint = $env:PROJECT0_WINDOWS_SIGNING_THUMBPRINT,
    [string]$TimestampUrl = "http://timestamp.digicert.com"
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($CertificateThumbprint)) {
    throw "Set PROJECT0_WINDOWS_SIGNING_THUMBPRINT or pass -CertificateThumbprint."
}

$signtool = Get-Command signtool.exe -ErrorAction SilentlyContinue
if ($null -eq $signtool) {
    throw "signtool.exe was not found. Install the Windows SDK signing tools."
}

$resolvedDirectory = (Resolve-Path $ArtifactDirectory).Path
$artifacts = Get-ChildItem -LiteralPath $resolvedDirectory -Filter "*.exe" -File
if ($artifacts.Count -eq 0) {
    throw "No Windows executables found in $resolvedDirectory."
}

foreach ($artifact in $artifacts) {
    & $signtool.Source sign /sha1 $CertificateThumbprint /fd SHA256 /tr $TimestampUrl /td SHA256 $artifact.FullName
    if ($LASTEXITCODE -ne 0) {
        throw "signtool failed for $($artifact.Name) with exit code $LASTEXITCODE."
    }
}

foreach ($artifact in $artifacts) {
    & $signtool.Source verify /pa /all $artifact.FullName
    if ($LASTEXITCODE -ne 0) {
        throw "signature verification failed for $($artifact.Name)."
    }
    Write-Output "Signed and verified $($artifact.Name)"
}