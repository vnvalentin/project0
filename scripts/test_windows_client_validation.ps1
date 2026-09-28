#requires -Version 7.0
[CmdletBinding()]
param([string]$GodotPath)

$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$runId = [Guid]::NewGuid().ToString('N')
$evidence = Join-Path $repo "build/validation/windows-client/$runId"
$root = Join-Path ([IO.Path]::GetTempPath()) "project0-client-boundary-$runId"
$result = [ordered]@{
    check = 'windows-client-package-boundary-controls'; host = [Environment]::MachineName
    command = @('pwsh', '-File', $PSCommandPath, '-GodotPath', $GodotPath)
    dependencies = @('powershell', 'godot-client'); runtime_acceptance = $false
    passed = $false; cases = @(); failure = $null; cleanup = $false
}
New-Item -ItemType Directory -Path $evidence | Out-Null

function Invoke-Bounded([string]$Executable, [string[]]$Arguments, [string]$Name) {
    $start = [Diagnostics.ProcessStartInfo]::new($Executable)
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    $start.Environment['APPDATA'] = Join-Path $root 'roaming'
    $start.Environment['LOCALAPPDATA'] = Join-Path $root 'local'
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    $started = $false
    $failure = $null
    $exitCode = $null
    $stdout = $null
    $stderr = $null
    try {
        $started = $process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(60000)) { throw "$Name timed out" }
        $exitCode = $process.ExitCode
    }
    catch { $failure = $_.Exception.Message }
    finally {
        try {
            if ($started -and -not $process.HasExited) {
                $process.Kill($true)
                if (-not $process.WaitForExit(10000)) { throw "$Name did not stop" }
            }
        }
        catch { $failure += "; $($_.Exception.Message)" }
        try {
            if ($stdout -and $stderr) {
                if (-not $stdout.Wait(5000) -or -not $stderr.Wait(5000)) { throw "$Name output capture timed out" }
                [IO.File]::WriteAllText((Join-Path $evidence "$Name.stdout.log"), $stdout.Result)
                [IO.File]::WriteAllText((Join-Path $evidence "$Name.stderr.log"), $stderr.Result)
            }
        }
        catch { $failure += "; $($_.Exception.Message)" }
        finally { $process.Dispose() }
    }
    if ($failure) { throw $failure }
    return $exitCode
}

try {
    if (-not $IsWindows) { throw 'Windows execution required' }
    if (-not $GodotPath) { $GodotPath = (Get-Command godot -ErrorAction Stop).Source }
    $checker = Join-Path $PSScriptRoot 'check_windows_client_package.ps1'
    if (-not (Test-Path $checker)) { throw 'Package boundary command is missing' }
    New-Item -ItemType Directory -Path $root | Out-Null
    [IO.File]::WriteAllText((Join-Path $root 'project.godot'), "config_version=5`n[application]`nconfig/name=`"Package boundary controls`"`n")
    Copy-Item (Join-Path $repo 'tests/fixtures/windows_client_packages.gd') (Join-Path $root 'fixtures.gd')
    $fixtureExit = Invoke-Bounded $GodotPath @('--headless', '--path', $root, '--script', (Join-Path $root 'fixtures.gd'), '--', $root) 'fixtures'
    if ($fixtureExit -ne 0) { throw "PCK fixture creation failed: $fixtureExit" }
    [IO.File]::WriteAllText((Join-Path $root 'invalid.pck'), 'not a PCK')
    Copy-Item (Join-Path $root 'valid.pck') (Join-Path $root 'wrong_engine.pck')
    Copy-Item (Join-Path $root 'persistence.pck') (Join-Path $root 'log_failure.pck')
    $cases = [ordered]@{ valid = $true; fallback = $true; persistence = $false; compiled_persistence = $false; sqlite = $false; unknown_native = $false; native_remap = $false; oversized = $false; no_client = $false; invalid = $false; missing = $false; wrong_engine = $false; log_failure = $false }
    foreach ($name in $cases.Keys) {
        $output = Join-Path $evidence "$name.json"
        if ($name -eq 'log_failure') { New-Item -ItemType Directory -Path ($output + '.stdout.log') | Out-Null }
        $arguments = @('-NoProfile', '-File', $checker, '-PackPath', (Join-Path $root "$name.pck"), '-GodotPath', $GodotPath, '-OutputPath', $output)
        if ($name -eq 'wrong_engine') { $arguments += @('-ExpectedEngineVersion', '0.0.0') }
        $exitCode = Invoke-Bounded (Get-Process -Id $PID).Path $arguments $name
        if (-not (Test-Path $output)) { throw "$name emitted no evidence" }
        $report = Get-Content $output -Raw | ConvertFrom-Json
        $pass = ($report.passed -eq $cases[$name]) -and (($exitCode -eq 0) -eq $cases[$name]) -and $report.cleanup
        $expectedFailure = switch ($name) {
            'persistence' { 'server/canon_repository.gd' }
            'compiled_persistence' { 'server/canon_repository.gd.remap' }
            'sqlite' { 'godot-sqlite' }
            'unknown_native' { 'store.dll' }
            'native_remap' { 'store.gdextension.remap' }
            'oversized' { 'inventory bound exceeded' }
            'no_client' { 'no client resources' }
            'invalid' { 'Unable to mount PCK' }
            'wrong_engine' { 'Inspector engine mismatch' }
            'log_failure' { 'server/canon_repository.gd' }
            default { $null }
        }
        if ($expectedFailure -and -not $report.failure.Contains($expectedFailure)) { $pass = $false }
        if ($name -eq 'log_failure' -and @($report.cleanup_failures).Count -eq 0) { $pass = $false }
        if ($name -in @('valid', 'fallback')) {
            $expectedFiles = if ($name -eq 'valid') { 'client/player.gd' } else { 'client/player.gd,server/starting_town_hub_fixture.gd' }
            if (($report.inventory.files | Sort-Object) -join ',' -cne $expectedFiles) { $pass = $false }
        }
        $result.cases += @{ name = $name; passed = $pass; expected_acceptance = $cases[$name]; exit_code = $exitCode; evidence = $output }
        if (-not $pass) { throw "$name produced unexpected acceptance or incomplete cleanup" }
    }
    $result.passed = $result.cases.Count -eq $cases.Count
}
catch { $result.failure = $_.Exception.Message }
finally {
    try {
        if (Test-Path $root) { Remove-Item $root -Recurse -Force }
        $result.cleanup = -not (Test-Path $root)
    }
    catch { $result.failure = "Cleanup failed: $($_.Exception.Message)"; $result.passed = $false }
    $result | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $evidence 'result.json') -Encoding utf8
    Write-Output "Windows package boundary controls: passed=$($result.passed); evidence=$evidence"
}
exit $(if ($result.passed -and $result.cleanup) { 0 } else { 1 })