#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PackPath,
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$GodotPath,
    [ValidatePattern('^\d+\.\d+\.\d+$')][string]$ExpectedEngineVersion = '4.7.2',
    [ValidateRange(5, 120)][int]$TimeoutSeconds = 30
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
if (Test-Path -LiteralPath $OutputPath) { throw "Evidence already exists: $OutputPath" }
$evidence = Split-Path $OutputPath -Parent
New-Item -ItemType Directory -Path $evidence -Force | Out-Null
$root = Join-Path ([IO.Path]::GetTempPath()) ('project0-pack-audit-' + [Guid]::NewGuid().ToString('N'))
$process = $null
$started = $false
$stdout = $null
$stderr = $null
$result = [ordered]@{
    schema_version = 1; check = 'windows-client-package-boundary'
    host = [Environment]::MachineName; platform = 'windows'; owner = 'windows-client'
    command = @('pwsh', '-File', $PSCommandPath, '-PackPath', $PackPath, '-GodotPath', $GodotPath, '-ExpectedEngineVersion', $ExpectedEngineVersion, '-OutputPath', $OutputPath)
    dependencies = @('godot-client', 'powershell'); passed = $false
    runtime_acceptance = $false; failure = $null; cleanup = $false
    inspector_sha256 = $null
    command_sha256 = (Get-FileHash $PSCommandPath).Hash
    inventory = $null; pack_sha256 = $null; engine_sha256 = $null; engine_exit_code = $null
}
try {
    if (-not $IsWindows) { throw 'Windows execution required' }
    if (-not $GodotPath) { $GodotPath = (Get-Command godot -ErrorAction Stop).Source }
    $result.inspector_sha256 = (Get-FileHash (Join-Path $PSScriptRoot 'client_package_inventory.gd')).Hash
    $manifestPath = Join-Path $PSScriptRoot 'validation_ownership.json'
    $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
    $hostId = if ($env:GITHUB_ACTIONS -eq 'true') { 'github-actions-windows' } else { [Environment]::MachineName }
    if ($hostId -notin $manifest.hosts.windows) { throw "Unassigned Windows validation host: $hostId" }
    $PackPath = (Resolve-Path -LiteralPath $PackPath).Path
    $GodotPath = (Resolve-Path -LiteralPath $GodotPath).Path
    $result.pack_sha256 = (Get-FileHash -LiteralPath $PackPath).Hash
    $result.engine_sha256 = (Get-FileHash -LiteralPath $GodotPath).Hash
    $result.engine_path = $GodotPath
    $result.ownership_sha256 = (Get-FileHash -LiteralPath $manifestPath).Hash
    New-Item -ItemType Directory -Path $root | Out-Null
    $resourceRoot = Join-Path $root 'resources'
    New-Item -ItemType Directory -Path $resourceRoot | Out-Null
    Copy-Item (Join-Path $PSScriptRoot 'client_package_inventory.gd') (Join-Path $root 'inventory.gd')
    $inventoryPath = Join-Path $root 'inventory.json'
    $start = [Diagnostics.ProcessStartInfo]::new($GodotPath)
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in @('--headless', '--path', $resourceRoot, '--script', (Join-Path $root 'inventory.gd'), '--', $PackPath, $inventoryPath, $manifestPath, $ExpectedEngineVersion)) { $start.ArgumentList.Add($argument) }
    $start.Environment['APPDATA'] = Join-Path $root 'roaming'
    $start.Environment['LOCALAPPDATA'] = Join-Path $root 'local'
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    $started = $process.Start()
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) { throw 'Package inventory timed out' }
    $result.engine_exit_code = $process.ExitCode
    if (-not (Test-Path -LiteralPath $inventoryPath)) { throw 'Native package inventory evidence is missing' }
    $result.inventory = Get-Content -LiteralPath $inventoryPath -Raw | ConvertFrom-Json
    if ($process.ExitCode -ne 0 -or -not $result.inventory.passed) { throw "Native package boundary rejected: $($result.inventory.failures -join '; ')" }
    if (-not $stdout.Wait(5000) -or -not $stderr.Wait(5000)) { throw 'Native inventory output capture timed out' }
    $diagnostics = $stdout.GetAwaiter().GetResult() + "`n" + $stderr.GetAwaiter().GetResult()
    if ($diagnostics -match '(?m)^\s*(USER SCRIPT ERROR|SCRIPT ERROR|USER ERROR|ERROR)\s*:|leaked at exit|resources still in use') { throw 'Native inventory reported engine/script diagnostics' }
    if ((Get-FileHash -LiteralPath $PackPath).Hash -ne $result.pack_sha256) { throw 'Package changed during inspection' }
    $result.passed = $true
}
catch { $result.failure = $_.Exception.Message }
finally {
    $cleanupFailures = @()
    try {
        if ($started -and -not $process.HasExited) {
            $process.Kill($true)
            if (-not $process.WaitForExit(10000)) { throw 'Owned inspector did not stop' }
        }
    }
    catch { $cleanupFailures += $_.Exception.Message }
    try {
        if ($stdout -and $stderr) {
            if (-not $stdout.Wait(5000) -or -not $stderr.Wait(5000)) { throw 'Inspector log capture did not finish' }
            [IO.File]::WriteAllText(($OutputPath + '.stdout.log'), $stdout.Result)
            [IO.File]::WriteAllText(($OutputPath + '.stderr.log'), $stderr.Result)
        }
    }
    catch { $cleanupFailures += $_.Exception.Message }
    try {
        if ($process) { $process.Dispose() }
    }
    catch { $cleanupFailures += $_.Exception.Message }
    try {
        if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        $result.cleanup = -not (Test-Path -LiteralPath $root)
    }
    catch { $cleanupFailures += $_.Exception.Message }
    if ($cleanupFailures.Count -ne 0) { $result.cleanup_failures = $cleanupFailures; $result.passed = $false }
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding utf8
    Write-Output "Windows package boundary: passed=$($result.passed); evidence=$OutputPath"
}
exit $(if ($result.passed -and $result.cleanup) { 0 } else { 1 })