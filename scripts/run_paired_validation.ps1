#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$GodotPath,
    [string]$PackageRoot,
    [ValidatePattern('^/data/[A-Za-z0-9_./-]+$')][string]$ServerRoot,
    [ValidatePattern('^/data/[A-Za-z0-9_./-]+$')][string]$Artifact,
    [ValidatePattern('^[a-f0-9]{64}$')][string]$ArtifactSha,
    [string]$PythonPath = 'python',
    [ValidateRange(1, 60)][int]$TransportTimeoutSeconds = 15,
    [switch]$DisconnectBeforeFinish,
    [ValidateSet('authenticated-input-ack-v1', 'shared-exploration-v1')][string]$Scenario = 'authenticated-input-ack-v1'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$runId = [Guid]::NewGuid().ToString('N')
$evidence = Join-Path $repo "build/validation/paired-windows-$runId"
$root = Join-Path ([IO.Path]::GetTempPath()) "project0-paired-client-$runId"
$remoteRun = "$ServerRoot/build/validation/windows-$runId"
$remoteHelper = Join-Path $repo 'scripts/remote.ps1'
$client = $null
$clientStarted = $false
$remoteRequested = $false
$token = ''
$stdout = $null
$stderr = $null
$server = $null
$stopFile = Join-Path $root 'stop'
$result = [ordered]@{
    issue = 1244; scenario = 'authenticated-input-ack-v1'; correlation_id = $runId
    host = [Environment]::MachineName; command_sha256 = (Get-FileHash $PSCommandPath).Hash
    client_mode = 'Windows editor hosting immutable compiled client PCK'
    dependencies = @('powershell-7', 'windows-powershell-5.1', 'godot-client-4.7.2', 'python', 'ssh', 'scp', 'approved-linux-server-artifact')
    status = 'failed'; paired_acceptance = $false; player_acceptance = $false
    expected_outcome = $(if ($DisconnectBeforeFinish) { 'reject-disconnected-client' } else { 'paired-pass' })
    failure = $null; client_exit_code = $null; local_cleanup = $false; remote_cleanup = $false
    remote_run = $remoteRun; client = $null; server = $null; transport = @()
}
. (Join-Path $PSScriptRoot 'windows_validation_transport.ps1')
if ($Scenario -eq 'shared-exploration-v1') {
    $sharedArgs = @('-GodotPath', $GodotPath, '-PackageRoot', $PackageRoot, '-ServerRoot', $ServerRoot,
        '-Artifact', $Artifact, '-ArtifactSha', $ArtifactSha, '-PythonPath', $PythonPath,
        '-TransportTimeoutSeconds', $TransportTimeoutSeconds)
    & (Join-Path $PSScriptRoot 'run_shared_exploration_validation.ps1') @sharedArgs
    exit $LASTEXITCODE
}
New-Item -ItemType Directory -Path $evidence | Out-Null

function Invoke-Server([string]$Arguments) {
    $response = Invoke-Transport $remoteHelper @() 'server-lifecycle' @{ Target = 'okami'; ConnectTimeout = 5; Script = "cd '$ServerRoot' && python3 scripts/paired_server.py $Arguments" }
    return ($response | ConvertFrom-Json -AsHashtable)
}

function Copy-Remote([string]$Source, [string]$Destination) {
    $executable = (Get-Command scp -CommandType Application | Select-Object -First 1).Source
    $null = Invoke-Transport $executable @('-B', '-q', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes', '-o', 'ConnectTimeout=5', '-o', 'ServerAliveInterval=5', '-o', 'ServerAliveCountMax=1', $Source, $Destination) 'artifact-transfer'
}

function Read-Client([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable) }
    catch { return $null }
}

try {
    if (-not $IsWindows) { throw 'Windows execution required' }
    if (-not $GodotPath -or -not $PackageRoot -or -not $ServerRoot -or -not $Artifact -or -not $ArtifactSha) { throw 'GodotPath, PackageRoot, ServerRoot, Artifact and ArtifactSha are required' }
    if ($ServerRoot.Contains('..') -or $Artifact.Contains('..')) { throw 'Invalid server artifact path' }
    New-Item -ItemType Directory -Path $root | Out-Null
    $security = [Security.AccessControl.DirectorySecurity]::new()
    $security.SetAccessRuleProtection($true, $false)
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $security.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($identity, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
    Set-Acl -LiteralPath $root -AclObject $security
    $manifest = Get-Content (Join-Path $PackageRoot 'deployment-manifest.json') -Raw | ConvertFrom-Json
    if (-not $manifest.release_eligible -or $manifest.version -notmatch '^\d+\.\d+\.\d+$') { throw 'Package is not release eligible' }
    $zip = Join-Path $PackageRoot $manifest.archive.name
    if ((Get-FileHash $zip).Hash -ne $manifest.archive.sha256) { throw 'Immutable package archive hash mismatch' }
    $package = Join-Path $root 'package'
    Expand-Archive -LiteralPath $zip -DestinationPath $package
    if ((@(Get-ChildItem $package -Recurse -File | ForEach-Object Name | Sort-Object) -join ',') -ne 'Project0.exe,Project0.pck') { throw 'Unexpected package contents' }
    foreach ($entry in $manifest.archive_contents) {
        if ($entry.name -notin @('Project0.exe', 'Project0.pck') -or (Get-FileHash (Join-Path $package $entry.name)).Hash -ne $entry.sha256) { throw 'Extracted package hash mismatch' }
    }
    $pack = Join-Path $package 'Project0.pck'
    $packSha = (Get-FileHash $pack).Hash.ToLowerInvariant()
    $result.package_manifest = $manifest
    $result.engine_sha256 = (Get-FileHash $GodotPath).Hash
    $result.command = @('pwsh', '-NoProfile', '-File', $PSCommandPath, '-GodotPath', $GodotPath, '-PackageRoot', $PackageRoot, '-ServerRoot', $ServerRoot, '-Artifact', $Artifact, '-ArtifactSha', $ArtifactSha, '-PythonPath', $PythonPath, '-TransportTimeoutSeconds', [string]$TransportTimeoutSeconds)
    if ($DisconnectBeforeFinish) { $result.command += '-DisconnectBeforeFinish' }
    $plan = @{
        schema_version = 1; kind = 'paired-runtime'; scenario_id = 'authenticated-input-ack-v1'
        correlation_id = $runId; client_build = "$packSha/$($manifest.version)/4.7.2-editor"; server_build = $ArtifactSha
        setup = 'Verified native client PCK and committed Linux artifact; private state and restricted assertion transfer'
        cleanup = 'Linux supervisor finish/abort with verified teardown; Windows finally removes owned process and private files'
        steps = @(
            @{ suite = 'godot-server'; platform = 'linux'; host = '192.168.1.254'; dependencies = @('godot', 'sqlite', 'python', 'docker')
               command = "python3 $ServerRoot/scripts/paired_server.py start --artifact $Artifact --artifact-sha256 $ArtifactSha --run $remoteRun --correlation-id $runId --client-sha256 $packSha --client-version $($manifest.version) --client-engine 4.7.2-editor --deadline-seconds 180 --readiness-seconds 45"
               tests = @('scripts/paired_server_fixture.gd'); artifacts = @("$remoteRun/report.json", "$remoteRun/runtime.log") },
            @{ suite = 'windows-client'; platform = 'windows'; host = [Environment]::MachineName; dependencies = @('powershell', 'windows-powershell-5.1', 'godot-client', 'python', 'ssh', 'scp')
               command = ($result.command | ConvertTo-Json -Compress); tests = @('scripts/windows_paired_client.gd')
               artifacts = @((Join-Path $evidence 'client.json'), (Join-Path $evidence 'result.json')) }
        )
    }
    $planPath = Join-Path $evidence 'plan.json'
    $plan | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $planPath -Encoding utf8NoBOM
    & $PythonPath (Join-Path $PSScriptRoot 'check_validation_ownership.py') --plan $planPath --output (Join-Path $evidence 'preflight.json')
    if ($LASTEXITCODE -ne 0) { throw 'Paired ownership preflight failed' }
    & pwsh -NoProfile -NonInteractive -File (Join-Path $repo 'scripts/check_windows_client_package.ps1') -PackPath $pack -GodotPath $GodotPath -OutputPath (Join-Path $evidence 'package-boundary.json')
    if ($LASTEXITCODE -ne 0) { throw 'Package boundary preflight failed' }
    Copy-Remote "okami:$Artifact/manifest.json" (Join-Path $root 'server-manifest.json')
    if ((Get-FileHash (Join-Path $root 'server-manifest.json')).Hash.ToLowerInvariant() -ne $ArtifactSha) { throw 'Server manifest hash mismatch' }
    $serverManifest = Get-Content (Join-Path $root 'server-manifest.json') -Raw | ConvertFrom-Json
    Copy-Item (Join-Path $root 'server-manifest.json') $evidence
    $remoteRequested = $true
    $server = Invoke-Server "start --artifact '$Artifact' --artifact-sha256 $ArtifactSha --run '$remoteRun' --correlation-id $runId --client-sha256 $packSha --client-version $($manifest.version) --client-engine 4.7.2-editor --deadline-seconds 180 --readiness-seconds 45"
    $clock = [Diagnostics.Stopwatch]::StartNew()
    do {
        $server = Invoke-Server "status --run '$remoteRun'"
        if ($server.ContainsKey('finished_at')) { throw "Server readiness failed: $($server.reason)" }
    } while ($server.status -ne 'ready' -and $clock.Elapsed.TotalSeconds -lt 60)
    if ($server.status -ne 'ready' -or $server.host -ne '192.168.1.254' -or $server.correlation_id -ne $runId -or $server.supervisor_sha256 -ne $serverManifest.prepared_by_sha256) { throw 'Unqualified server readiness or identity' }
    $readyPath = Join-Path $root 'ready.json'
    $server | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $readyPath -Encoding utf8NoBOM
    Copy-Item $readyPath (Join-Path $evidence 'server-ready.json')
    $assertion = Join-Path $root 'assertion'
    Copy-Remote "okami:$remoteRun/private/assertion" $assertion
    $token = [IO.File]::ReadAllText($assertion).Trim()
    if (-not $token) { throw 'Private assertion handoff was empty' }
    $probe = Join-Path $root 'client_probe.gd'
    Copy-Item (Join-Path $PSScriptRoot 'windows_paired_client.gd') $probe
    $result.probe_sha256 = (Get-FileHash $probe).Hash
    $resourceRoot = Join-Path $root 'resources'
    New-Item -ItemType Directory -Path $resourceRoot | Out-Null
    $clientEvidence = Join-Path $root 'client.json'
    $start = [Diagnostics.ProcessStartInfo]::new($GodotPath)
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in @('--path', $resourceRoot, '--main-pack', $pack, '--script', $probe, '--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--resolution', '64x64', '--position', '-32000,-32000', '--', $readyPath, $assertion, $clientEvidence, $stopFile, $pack)) { $start.ArgumentList.Add($argument) }
    foreach ($key in @($start.Environment.Keys)) { if ($key -like 'PROJECT0_*') { [void]$start.Environment.Remove($key) } }
    $start.Environment['APPDATA'] = Join-Path $root 'roaming'
    $start.Environment['LOCALAPPDATA'] = Join-Path $root 'local'
    $start.Environment['TEMP'] = Join-Path $root 'temp'
    $start.Environment['TMP'] = Join-Path $root 'temp'
    New-Item -ItemType Directory -Path $start.Environment['TEMP'] | Out-Null
    $start.Environment['PROJECT0_SERVER_HOST'] = '192.168.1.254'
    $start.Environment['PROJECT0_SERVER_PORT'] = [string]$server.port
    foreach ($key in @('PROJECT0_CLIENT_HTTPS_LOGIN', 'PROJECT0_CLIENT_NAKAMA_LOGIN', 'PROJECT0_CLIENT_NAKAMA_GAMEPLAY', 'PROJECT0_CLIENT_LOGIN_SPLIT')) { $start.Environment[$key] = '0' }
    $client = [Diagnostics.Process]::new()
    $client.StartInfo = $start
    $clientStarted = $client.Start()
    $stdout = $client.StandardOutput.ReadToEndAsync()
    $stderr = $client.StandardError.ReadToEndAsync()
    $observed = $null
    do {
        $server = Invoke-Server "status --run '$remoteRun'"
        if ($server.ContainsKey('finished_at')) { throw "Server ended before paired finish: $($server.reason)" }
        $observed = Read-Client $clientEvidence
        if ($observed -and $observed.status -ne 'passed') { throw "Native client failed: $($observed.failure)" }
        if ($client.HasExited) { throw "Native client exited before finish: $($client.ExitCode)" }
    } while ((-not $observed -or -not $server.admission.authenticated -or $server.admission.input_ack_sequence -lt $observed.input_ack_sequence) -and $clock.Elapsed.TotalSeconds -lt 140)
    if (-not $observed -or -not $server.admission.authenticated -or $server.admission.input_ack_sequence -lt $observed.input_ack_sequence) { throw 'Correlated native admission/input evidence timed out' }
    Copy-Item $clientEvidence (Join-Path $evidence 'client.json')
    Copy-Remote $clientEvidence "okami:$remoteRun/client.json"
    if ($DisconnectBeforeFinish) {
        [IO.File]::WriteAllText($stopFile, 'stop')
        if (-not $client.WaitForExit(10000) -or $client.ExitCode -ne 0) { throw 'Disconnect control did not stop the real client cleanly' }
    }
    try { $null = Invoke-Server "finish --run '$remoteRun' --evidence '$remoteRun/client.json'" }
    catch {
        if (-not $DisconnectBeforeFinish) { throw }
        $result.finish_rejection = $_.Exception.Message
    }
    do { $server = Invoke-Server "status --run '$remoteRun'" } while (-not $server.ContainsKey('finished_at') -and $clock.Elapsed.TotalSeconds -lt 170)
    if ($DisconnectBeforeFinish) {
        if ($server.status -ne 'failed' -or $server.reason -notin @('client_disconnected', 'server_admission_missing', 'server_input_stale') -or -not $server.cleanup.passed) { throw 'Disconnected client evidence was not rejected correctly' }
    }
    elseif ($server.status -ne 'server_passed' -or -not $server.cleanup.passed -or -not $server.shutdown.passed -or -not $server.runtime_logs_complete) { throw "Server finish failed or lacks termination evidence: $($server.reason)" }
    [IO.File]::WriteAllText($stopFile, 'stop')
    if (-not $client.WaitForExit(10000)) { throw 'Native client did not finish' }
    $result.client_exit_code = $client.ExitCode
    if ($client.ExitCode -ne 0) { throw 'Native client exited unsuccessfully' }
    $result.client = $observed
    $result.status = if ($DisconnectBeforeFinish) { 'rejection_proved' } else { 'passed' }
}
catch { $result.failure = $_.Exception.Message }
finally {
    $cleanupFailures = @()
    try {
        if ($clientStarted -and -not $client.HasExited) {
            [IO.File]::WriteAllText($stopFile, 'stop')
            if (-not $client.WaitForExit(5000)) { $client.Kill($true); $result.client_forced_stop = $true }
            if (-not $client.WaitForExit(10000)) { throw 'Owned Windows process did not stop' }
        }
        if ($clientStarted) { $result.client_exit_code = $client.ExitCode }
    }
    catch { $cleanupFailures += $_.Exception.Message }
    try {
        if ($stdout -and $stderr) {
            if (-not $stdout.Wait(5000) -or -not $stderr.Wait(5000)) { throw 'Client log capture did not complete' }
            $logs = @{ stdout = $stdout.Result; stderr = $stderr.Result }
            $diagnosticErrors = $false
            foreach ($name in $logs.Keys) {
                $text = $logs[$name]
                if ($token) { $text = $text.Replace($token, '[REDACTED]') }
                $text = $text -replace '\b[A-Za-z0-9+/=]{40,}\.[A-Za-z0-9+/=]{20,}\b', '[REDACTED]'
                [IO.File]::WriteAllText((Join-Path $evidence "client.$name.log"), $text)
                if ($text -match '(?m)^\s*(USER SCRIPT ERROR|SCRIPT ERROR|USER ERROR|ERROR)\s*:|leaked at exit|resources still in use') { $diagnosticErrors = $true }
            }
            if ($diagnosticErrors) { throw 'Native client emitted error/leak diagnostics' }
        }
    }
    catch { $cleanupFailures += $_.Exception.Message }
    try { if ($client) { $client.Dispose() } }
    catch { $cleanupFailures += $_.Exception.Message }
    try {
        if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        $result.local_cleanup = -not (Test-Path -LiteralPath $root)
    }
    catch { $cleanupFailures += $_.Exception.Message }
    if ($remoteRequested) {
        try {
            $server = Invoke-Server "status --run '$remoteRun'"
            if (-not $server.ContainsKey('finished_at')) {
                try { $null = Invoke-Server "abort --run '$remoteRun'" } catch { $result.abort_request_error = $_.Exception.Message }
                $cleanupClock = [Diagnostics.Stopwatch]::StartNew()
                do { $server = Invoke-Server "status --run '$remoteRun'" } while (-not $server.ContainsKey('finished_at') -and $cleanupClock.Elapsed.TotalSeconds -lt 30)
            }
            $result.remote_cleanup = $server.ContainsKey('finished_at') -and $server.cleanup.passed
            $result.server = $server
            if (-not $result.remote_cleanup) { throw 'Linux cleanup not verified' }
        }
        catch { $cleanupFailures += $_.Exception.Message }
    }
    else { $result.remote_cleanup = $true }
    if ($cleanupFailures.Count -ne 0) { $result.cleanup_failures = $cleanupFailures; $result.status = 'failed' }
    $result.paired_acceptance = $result.status -eq 'passed' -and $result.local_cleanup -and $result.remote_cleanup
    $result.rejection_control_passed = $result.status -eq 'rejection_proved' -and $result.local_cleanup -and $result.remote_cleanup
    $result | ConvertTo-Json -Depth 25 | Set-Content -LiteralPath (Join-Path $evidence 'result.json') -Encoding utf8
    Write-Output "Paired validation: status=$($result.status); evidence=$evidence"
}
exit $(if ($result.paired_acceptance -or $result.rejection_control_passed) { 0 } else { 1 })