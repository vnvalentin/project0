#requires -Version 7.0
[CmdletBinding()]
param([switch]$PackagedWorkerNegativeControl, [switch]$DisableKillOnCloseNegativeControl)

$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$runId = [Guid]::NewGuid().ToString('N')
$root = Join-Path ([IO.Path]::GetTempPath()) "project0-transport-controls-$runId"
$evidence = Join-Path $repo "build/validation/windows-transport-$runId"
$savedPath = $env:PATH
$savedFixture = $env:P0_TRANSPORT_FIXTURE
$report = [ordered]@{
    issue = 1244; host = [Environment]::MachineName; check = 'windows-paired-transport-controls'
    source_sha256 = (Get-FileHash (Join-Path $PSScriptRoot 'run_paired_validation.ps1')).Hash
    test_sha256 = (Get-FileHash $PSCommandPath).Hash
    command = @('pwsh', '-NoProfile', '-File', $PSCommandPath)
    expected_outcome = $(if ($PackagedWorkerNegativeControl) { 'reject-packaged-worker' } elseif ($DisableKillOnCloseNegativeControl) { 'reject-missing-kill-on-close' } else { 'controls-pass' })
    fallback_terminated = @()
    runtime_acceptance = $false; passed = $false; cases = @(); cleanup = $false; failure = $null
}
New-Item -ItemType Directory -Path $evidence | Out-Null
try {
    if (-not $IsWindows) { throw 'Windows required' }
    if ($PackagedWorkerNegativeControl -and $DisableKillOnCloseNegativeControl) { throw 'Select only one negative control' }
    New-Item -ItemType Directory -Path $root | Out-Null
    $fixtureCode = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Threading;
class TransportFixture {
    static int Main(string[] args) {
        string root = Environment.GetEnvironmentVariable("P0_TRANSPORT_FIXTURE");
        File.AppendAllText(Path.Combine(root, "pids"), Process.GetCurrentProcess().Id + "\n");
        if (Array.IndexOf(args, "--wait") >= 0) { File.WriteAllText(Path.Combine(root, "child-ready"), "ready"); new ManualResetEvent(false).WaitOne(); return 0; }
        string mode = File.ReadAllText(Path.Combine(root, "mode")).Trim();
        string exe = Process.GetCurrentProcess().MainModule.FileName;
        if (Path.GetFileName(exe) == "scp.exe") {
            if (Array.IndexOf(args, "BatchMode=yes") < 0 || Array.IndexOf(args, "StrictHostKeyChecking=yes") < 0) return 73;
            string source = args[args.Length - 2], target = args[args.Length - 1];
            if (source.EndsWith("/manifest.json")) File.Copy(Path.Combine(root, "server-manifest.json"), target);
            if (source.EndsWith("/private/assertion")) {
                File.WriteAllText(target, "fixture-private-bearer");
                if (mode == "transfer-stall" || mode == "parent-exit" || mode == "outer-timeout") {
                    Process.Start(new ProcessStartInfo(exe, "--wait") { UseShellExecute = false });
                    if (mode == "parent-exit") return 0;
                    new ManualResetEvent(false).WaitOne();
                }
            }
            return 0;
        }
        int offset = Array.IndexOf(args, "--");
        File.WriteAllText(args[offset + 3], "{\"status\":\"passed\",\"input_ack_sequence\":2}");
        while (!File.Exists(args[offset + 4])) new ManualResetEvent(false).WaitOne(20);
        return 0;
    }
}
'@
    [IO.File]::WriteAllText((Join-Path $root 'fixture.cs'), $fixtureCode)
    $compile = Join-Path $root 'compile.ps1'
    $applicationManifest = Join-Path $root 'fixture.manifest'
    [IO.File]::WriteAllText($applicationManifest, '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0"><trustInfo xmlns="urn:schemas-microsoft-com:asm.v3"><security><requestedPrivileges><requestedExecutionLevel level="asInvoker" uiAccess="false" /></requestedPrivileges></security></trustInfo><compatibility xmlns="urn:schemas-microsoft-com:compatibility.v1"><application><supportedOS Id="{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}" /></application></compatibility></assembly>')
    [IO.File]::WriteAllText($compile, 'param([string]$Source, [string]$Output, [string]$Manifest); $ErrorActionPreference = "Stop"; $compiler = [CodeDom.Compiler.CompilerParameters]::new(); $compiler.GenerateExecutable = $true; $compiler.OutputAssembly = $Output; [void]$compiler.ReferencedAssemblies.Add("System.dll"); $compiler.CompilerOptions = ''/platform:x64 /win32manifest:"'' + $Manifest + ''"''; Add-Type -Path $Source -CompilerParameters $compiler')
    & powershell -NoProfile -NonInteractive -File $compile -Source (Join-Path $root 'fixture.cs') -Output (Join-Path $root 'fixture.exe') -Manifest $applicationManifest
    if ($LASTEXITCODE -ne 0) { throw 'Local transport fixture compilation failed' }
    $fixtureRemote = @'
param([string]$Script, [string]$Target, [int]$ConnectTimeout)
if ($Target -ne 'okami' -or $ConnectTimeout -ne 5 -or $Script -notlike "cd '/data/fixture' && python3 scripts/paired_server.py *") { throw 'Incorrect named transport parameters' }
$root = $env:P0_TRANSPORT_FIXTURE
$mode = (Get-Content (Join-Path $root 'mode') -Raw).Trim()
$countPath = Join-Path $root 'status-count'
if ($Script -match 'status --run') {
    $count = if (Test-Path $countPath) { 1 + [int](Get-Content $countPath -Raw) } else { 1 }
    [IO.File]::WriteAllText($countPath, [string]$count)
    if (($mode -eq 'status-stall' -and $count -ge 2) -or ($mode -eq 'cleanup-stall' -and (Test-Path (Join-Path $root 'finish')))) {
        [IO.File]::AppendAllText((Join-Path $root 'pids'), "$PID`n")
        $child = Start-Process (Join-Path $root 'scp.exe') -ArgumentList '--wait' -PassThru
        $child.WaitForExit()
    }
}
if ($Script -match 'finish --run') {
    [IO.File]::WriteAllText((Join-Path $root 'finish'), 'finish')
    if ($mode -eq 'cleanup-stall') { exit 7 }
}
if ($Script -match 'abort --run') { [IO.File]::WriteAllText((Join-Path $root 'aborted'), 'aborted') }
$correlation = [regex]::Match($Script, 'windows-([a-f0-9]{32})').Groups[1].Value
$reply = @{
    status = 'ready'; host = '192.168.1.254'; correlation_id = $correlation
    supervisor_sha256 = ('a' * 64); port = 9999
    admission = @{ authenticated = $true; input_ack_sequence = 2 }
}
if (Test-Path (Join-Path $root 'finish')) {
    $reply.status = 'server_passed'; $reply.finished_at = 'fixture'
    $reply.cleanup = @{ passed = $true }; $reply.shutdown = @{ passed = $true }
    $reply.runtime_logs_complete = $true
}
if (Test-Path (Join-Path $root 'aborted')) {
    $reply.status = 'aborted'; $reply.finished_at = 'fixture'
    $reply.cleanup = @{ passed = $true }
}
$reply | ConvertTo-Json -Depth 5 -Compress
'@
    $modes = if ($PackagedWorkerNegativeControl) { @('transfer-stall') } elseif ($DisableKillOnCloseNegativeControl) { @('outer-timeout') } else { @('success', 'transfer-stall', 'status-stall', 'cleanup-stall', 'parent-exit', 'outer-timeout') }
    if ($PackagedWorkerNegativeControl) { $report.command += '-PackagedWorkerNegativeControl' }
    if ($DisableKillOnCloseNegativeControl) { $report.command += '-DisableKillOnCloseNegativeControl' }
    foreach ($mode in $modes) {
        $caseRoot = Join-Path $root ($mode + ' ' + [char]0xE9)
        $scripts = Join-Path $caseRoot 'scripts'
        New-Item -ItemType Directory -Path $scripts | Out-Null
        Copy-Item (Join-Path $PSScriptRoot 'run_paired_validation.ps1') $scripts
        $coordinator = Join-Path $scripts 'run_paired_validation.ps1'
        if ($PackagedWorkerNegativeControl) {
            $original = Get-Content $coordinator -Raw
            $workerLine = '$workerPath = Join-Path $env:WINDIR ''System32/WindowsPowerShell/v1.0/powershell.exe'''
            if (-not $original.Contains($workerLine)) { throw 'Negative control cannot locate the pinned worker' }
            [IO.File]::WriteAllText($coordinator, $original.Replace($workerLine, '$workerPath = (Get-Process -Id $PID).Path'))
        }
        if ($DisableKillOnCloseNegativeControl) {
            $original = Get-Content $coordinator -Raw
            if (-not $original.Contains('limits.Basic.Flags = 0x2000;')) { throw 'Negative control cannot locate kill-on-close' }
            [IO.File]::WriteAllText($coordinator, $original.Replace('limits.Basic.Flags = 0x2000;', 'limits.Basic.Flags = 0;'))
        }
        $report.tested_source_sha256 = (Get-FileHash $coordinator).Hash
        Copy-Item (Join-Path $root 'fixture.exe') (Join-Path $caseRoot 'scp.exe')
        Copy-Item (Join-Path $root 'fixture.exe') (Join-Path $caseRoot 'engine.exe')
        [IO.File]::WriteAllText((Join-Path $caseRoot 'mode'), $mode)
        [IO.File]::WriteAllText((Join-Path $scripts 'remote.ps1'), $fixtureRemote)
        [IO.File]::WriteAllText((Join-Path $scripts 'check_windows_client_package.ps1'), 'exit 0')
        [IO.File]::WriteAllText((Join-Path $scripts 'windows_paired_client.gd'), 'fixture')
        [IO.File]::WriteAllText((Join-Path $caseRoot 'preflight.cmd'), "@echo off`r`nexit /b 0`r`n")
        $serverManifest = Join-Path $caseRoot 'server-manifest.json'
        @{ prepared_by_sha256 = ('a' * 64) } | ConvertTo-Json | Set-Content $serverManifest
        $payload = Join-Path $caseRoot 'payload'
        New-Item -ItemType Directory -Path $payload | Out-Null
        foreach ($name in @('Project0.exe', 'Project0.pck')) { [IO.File]::WriteAllText((Join-Path $payload $name), 'fixture') }
        $zip = Join-Path $caseRoot 'client.zip'
        Compress-Archive -Path (Join-Path $payload '*') -DestinationPath $zip
        @{
            release_eligible = $true; version = '0.0.1'
            archive = @{ name = 'client.zip'; sha256 = (Get-FileHash $zip).Hash }
            archive_contents = @(Get-ChildItem $payload | ForEach-Object { @{ name = $_.Name; sha256 = (Get-FileHash $_.FullName).Hash } })
        } | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $caseRoot 'deployment-manifest.json')
        $env:PATH = "$caseRoot;$savedPath"
        $env:P0_TRANSPORT_FIXTURE = $caseRoot
        $start = [Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
        $start.UseShellExecute = $false
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        $ownedTemp = Join-Path $caseRoot 'private'
        New-Item -ItemType Directory -Path $ownedTemp | Out-Null
        $start.Environment['TEMP'] = $ownedTemp
        $start.Environment['TMP'] = $ownedTemp
        $arguments = @('-NoProfile', '-NonInteractive', '-File', (Join-Path $scripts 'run_paired_validation.ps1'), '-GodotPath', (Join-Path $caseRoot 'engine.exe'), '-PackageRoot', $caseRoot, '-ServerRoot', '/data/fixture', '-Artifact', '/data/artifact', '-ArtifactSha', (Get-FileHash $serverManifest).Hash.ToLowerInvariant(), '-PythonPath', (Join-Path $caseRoot 'preflight.cmd'))
        $arguments += @('-TransportTimeoutSeconds', $(if ($mode -eq 'outer-timeout') { '10' } else { '2' }))
        foreach ($argument in $arguments) { $start.ArgumentList.Add($argument) }
        $process = [Diagnostics.Process]::new()
        $process.StartInfo = $start
        $clock = [Diagnostics.Stopwatch]::StartNew()
        try {
            [void]$process.Start()
            $stdout = $process.StandardOutput.ReadToEndAsync()
            $stderr = $process.StandardError.ReadToEndAsync()
            if ($mode -eq 'outer-timeout') {
                while (-not (Test-Path (Join-Path $caseRoot 'child-ready')) -and $clock.Elapsed.TotalSeconds -lt 15 -and -not $process.HasExited) { [void]$process.WaitForExit(20) }
                if (-not (Test-Path (Join-Path $caseRoot 'child-ready'))) { throw 'Driver timeout control never reached an active native descendant' }
            }
            $deadline = if ($mode -eq 'outer-timeout') { 1000 } else { 45000 }
            if (-not $process.WaitForExit($deadline)) {
                if ($mode -ne 'outer-timeout') { throw "$mode exceeded the outer regression deadline" }
                $report.cases += @{ name = $mode; passed = $true; elapsed_seconds = $clock.Elapsed.TotalSeconds; expected_driver_timeout = $true }
                continue
            }
            if ($mode -eq 'outer-timeout') { throw 'Driver timeout control did not time out' }
            if (-not $stdout.Wait(3000) -or -not $stderr.Wait(3000)) { throw 'Regression output capture timed out' }
            [IO.File]::WriteAllText((Join-Path $evidence "$mode.stdout.log"), $stdout.Result)
            [IO.File]::WriteAllText((Join-Path $evidence "$mode.stderr.log"), $stderr.Result)
            $native = @(Get-ChildItem (Join-Path $caseRoot 'build/validation') -Filter result.json -Recurse)
            if ($native.Count -ne 1) { throw "$mode emitted no unique native result" }
            $result = Get-Content $native[0].FullName -Raw | ConvertFrom-Json
            Copy-Item $native[0].Directory.FullName (Join-Path $evidence $mode) -Recurse
            $expectedPass = $mode -eq 'success'
            if (($process.ExitCode -eq 0) -ne $expectedPass -or $result.paired_acceptance -ne $expectedPass) { throw "$mode returned an unexpected verdict: $($result.failure)" }
            if (-not $result.local_cleanup) { throw "$mode did not clean local private state" }
            $privateRoot = Join-Path $ownedTemp "project0-paired-client-$($result.correlation_id)"
            if (Test-Path $privateRoot) { throw "$mode retained private files" }
            if (-not $expectedPass -and -not (($result | ConvertTo-Json -Depth 25).Contains('timed out'))) { throw "$mode did not reject the stalled operation by deadline" }
            if ($mode -in @('status-stall', 'cleanup-stall') -and $result.remote_cleanup) { throw "$mode fabricated remote cleanup" }
            $workerPath = Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
            foreach ($transport in $result.transport) {
                if ($transport.worker_path -ne $workerPath -or $transport.worker_sha256 -ne (Get-FileHash $workerPath).Hash -or -not $transport.job_assigned -or -not $transport.job_empty -or -not $transport.stopped) { throw "$mode used an unqualified worker or incomplete job teardown" }
            }
            foreach ($ownedId in @(Get-Content (Join-Path $caseRoot 'pids') | Sort-Object -Unique)) {
                if (Get-Process -Id ([int]$ownedId) -ErrorAction SilentlyContinue) { throw "$mode retained owned process $ownedId" }
            }
            $report.cases += @{ name = $mode; passed = $true; elapsed_seconds = $clock.Elapsed.TotalSeconds; exit_code = $process.ExitCode }
        }
        finally {
            $children = @()
            try {
                if (-not $process.HasExited) {
                    foreach ($metadata in @(Get-CimInstance Win32_Process -Filter "ParentProcessId = $($process.Id)")) {
                        $child = Get-Process -Id $metadata.ProcessId -ErrorAction SilentlyContinue
                        if ($child) { $null = $child.Handle; $children += $child }
                    }
                    $process.Kill()
                    if (-not $process.WaitForExit(5000)) { throw 'Coordinator-only termination did not finish' }
                }
                foreach ($child in $children) {
                    if (-not $child.WaitForExit(5000)) { throw "$mode coordinator exit did not terminate its worker" }
                }
                if (Test-Path (Join-Path $caseRoot 'pids')) {
                    foreach ($ownedId in @(Get-Content (Join-Path $caseRoot 'pids') | Sort-Object -Unique)) {
                        $owned = Get-Process -Id ([int]$ownedId) -ErrorAction SilentlyContinue
                        if ($owned) {
                            try { if (-not $owned.WaitForExit(5000)) { throw "$mode regression retained owned process $ownedId" } }
                            finally { $owned.Dispose() }
                        }
                    }
                }
            }
            finally {
                foreach ($child in $children) {
                    if (-not $child.HasExited) {
                        $report.fallback_terminated += $child.Id
                        $child.Kill($true)
                        if (-not $child.WaitForExit(5000)) { throw 'Independent worker cleanup failed' }
                    }
                    $child.Dispose()
                }
                $process.Dispose()
                $nativeRoot = Join-Path $caseRoot 'build/validation'
                if ((Test-Path $nativeRoot) -and -not (Test-Path (Join-Path $evidence $mode))) {
                    Copy-Item $nativeRoot (Join-Path $evidence $mode) -Recurse
                }
                if (Test-Path $ownedTemp) { Remove-Item $ownedTemp -Recurse -Force }
                if (Test-Path $ownedTemp) { throw "$mode regression cleanup failed" }
            }
        }
    }
    $report.passed = $report.cases.Count -eq 6
}
catch {
    $report.failure = $_.Exception.Message
    $failedCase = @($report.cases | Where-Object { $_.name -eq $mode })
    if ($failedCase.Count -ne 0) {
        $failedCase[0].passed = $false
        $failedCase[0].failure = $report.failure
    }
    elseif ($mode) { $report.cases += @{ name = $mode; passed = $false; failure = $report.failure } }
}
finally {
    $env:PATH = $savedPath
    $env:P0_TRANSPORT_FIXTURE = $savedFixture
    try {
        foreach ($metadata in @(Get-CimInstance Win32_Process -Filter "Name = 'scp.exe' OR Name = 'engine.exe'" | Where-Object { $_.ExecutablePath -like "$root\*" })) {
            $owned = Get-Process -Id $metadata.ProcessId -ErrorAction SilentlyContinue
            if ($owned) {
                if ($owned.Path -ne $metadata.ExecutablePath) { throw 'Fixture process identity changed before cleanup' }
                $report.fallback_terminated += $owned.Id
                $owned.Kill($true)
                if (-not $owned.WaitForExit(5000)) { throw 'Escaped fixture process did not stop' }
                $owned.Dispose()
            }
        }
        if ($report.fallback_terminated.Count -ne 0) {
            $report.passed = $false
            if (-not $report.failure) { $report.failure = 'Containment required independent fixture teardown' }
        }
        if (Test-Path $root) { Remove-Item $root -Recurse -Force }
        $report.cleanup = -not (Test-Path $root)
    }
    catch { $report.failure += "; cleanup: $($_.Exception.Message)"; $report.passed = $false }
    $report | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $evidence 'result.json')
    Write-Output "Windows transport controls: passed=$($report.passed); failure=$($report.failure); evidence=$evidence"
}
exit $(if ($report.passed -and $report.cleanup) { 0 } else { 1 })