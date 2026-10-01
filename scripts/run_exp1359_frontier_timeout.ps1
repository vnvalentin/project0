#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$GodotPath,
    [Parameter(Mandatory)][string]$PackageRoot,
    [Parameter(Mandatory)][ValidatePattern('^/data/[A-Za-z0-9_./-]+$')][string]$ServerRoot,
    [Parameter(Mandatory)][ValidatePattern('^/data/[A-Za-z0-9_./-]+$')][string]$Artifact,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$ArtifactSha,
    [ValidatePattern('^\d+x\d+$')][string]$Resolution = '1280x720',
    [ValidateRange(1, 60)][int]$TransportTimeoutSeconds = 15
)

# Experiment 1359: one packaged client crosses an unexplored frontier while the
# server's LLM endpoint never answers, so the real generation cutoff and fallback run.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$runId = [Guid]::NewGuid().ToString('N')
$evidence = Join-Path $repo "build/validation/exp1359-frontier-timeout-$runId"
$root = Join-Path ([IO.Path]::GetTempPath()) "project0-exp1359-$runId"
$remoteRun = "$ServerRoot/build/validation/exp1359-$runId"
$remoteHelper = Join-Path $repo 'scripts/remote.ps1'
$process = $null
$logs = $null
$remoteStarted = $false
$budgets = [ordered]@{ generation_cutoff_ms = 3000; fallback_validation_ms = 200; canon_commit_ms = 300; presentation_ms = 500; total_ms = 4000; frame_ms = 16.6 }
$result = [ordered]@{ issue = 1359; scenario_id = 'frontier-timeout-v1'; correlation_id = $runId; host = [Environment]::MachineName
    resolution = $Resolution; budgets = $budgets; status = 'failed'; local_cleanup = $false; remote_cleanup = $false
    failure = $null; client = $null; server_observation = $null; verdict = $null; transport = @() }
. (Join-Path $PSScriptRoot 'windows_validation_transport.ps1')

function Invoke-Remote([string]$script) {
    $output = Invoke-Transport $remoteHelper @() 'server-lifecycle' @{ Target = 'okami'; ConnectTimeout = 5; Script = $script }
    return ($output -join [Environment]::NewLine | ConvertFrom-Json -AsHashtable)
}

function Copy-Remote([string]$source, [string]$destination) {
    $executable = (Get-Command scp -CommandType Application | Select-Object -First 1).Source
    $null = Invoke-Transport $executable @('-B', '-q', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes', '-o', 'ConnectTimeout=5', $source, $destination) 'artifact-transfer'
}

function Read-Json([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try { return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable } catch { return $null }
}

function Get-Verdict([hashtable]$client, [hashtable]$observation) {
    $ready = @($observation.frontier_ready_events | Where-Object { $_.sector_id -eq 'sector-0--2' -and $_.path -eq 'generated' }) | Select-Object -First 1
    $stages = $ready.stages
    $reloads = @($observation.canon_reload_events | Where-Object { $_.sector_id -eq 'sector-0--2' })
    $checks = [ordered]@{
        forced_timeout = $observation.generation.request_outcome -eq 'timeout' -and $observation.generation.fallback_selected -eq $true
        # One request each for the seeded sector and the frontier sector; more is a retry.
        zero_retries = $observation.llm_connections -eq 2
        generation_cutoff = [double]$stages.generation_duration_ms -le $budgets.generation_cutoff_ms
        fallback_validation = ([double]$stages.validation_duration_ms + [double]$stages.detail_ms) -le $budgets.fallback_validation_ms
        canon_commit = [double]$stages.canon_commit_ms -le $budgets.canon_commit_ms
        presentation = [double]$stages.presentation_ms -le $budgets.presentation_ms
        total = [double]$ready.total_ms -le $budgets.total_ms
        adjacent_frames = $client.frame_times.count -gt 0 -and $client.frame_times.over_budget -eq 0
        adjacent_motion = $client.adjacent_motion.moved -eq $true
        one_reentry_event = $reloads.Count -eq 1
    }
    return [ordered]@{ accepted = -not ($checks.Values -contains $false); checks = $checks; ready_record = $ready; reentry_events = $reloads.Count
        measured = [ordered]@{ generation_duration_ms = $stages.generation_duration_ms; deadline_overshoot_ms = $stages.deadline_overshoot_ms
            fallback_validation_ms = [double]$stages.validation_duration_ms + [double]$stages.detail_ms; canon_commit_ms = $stages.canon_commit_ms
            presentation_ms = $stages.presentation_ms; total_ms = $ready.total_ms; frame_times = $client.frame_times; llm_connections = $observation.llm_connections } }
}

try {
    if (-not $IsWindows) { throw 'Windows execution required' }
    New-Item -ItemType Directory -Path $evidence, $root | Out-Null
    $manifest = Get-Content (Join-Path $PackageRoot 'deployment-manifest.json') -Raw | ConvertFrom-Json
    $zip = Join-Path $PackageRoot $manifest.archive.name
    if (-not $manifest.release_eligible -or (Get-FileHash $zip).Hash -ne $manifest.archive.sha256) { throw 'Immutable package archive mismatch' }
    Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $root package)
    $pack = Join-Path $root 'package/Project0.pck'
    $probe = Join-Path $root 'frontier_probe.gd'
    Copy-Item (Join-Path $PSScriptRoot 'windows_frontier_timeout_client.gd') $probe
    $packSha = (Get-FileHash $pack).Hash.ToLowerInvariant()
    $result.client_build = @{ sha256 = $packSha; version = $manifest.version; engine = '4.7.2-editor' }
    $result.probe_sha256 = (Get-FileHash $probe).Hash
    $serverManifestPath = Join-Path $root server-manifest.json
    Copy-Remote "okami:$Artifact/manifest.json" $serverManifestPath
    if ((Get-FileHash $serverManifestPath).Hash.ToLowerInvariant() -ne $ArtifactSha) { throw 'Server manifest mismatch' }
    $server = Invoke-Remote "cd '$ServerRoot' && python3 scripts/paired_server.py start --scenario frontier-timeout-v1 --artifact '$Artifact' --artifact-sha256 '$ArtifactSha' --run '$remoteRun' --correlation-id '$runId' --client-sha256 '$packSha' --client-version '$($manifest.version)' --client-engine 4.7.2-editor --deadline-seconds 180 --readiness-seconds 45"
    $remoteStarted = $true
    $clock = [Diagnostics.Stopwatch]::StartNew()
    do {
        $server = Invoke-Remote "cd '$ServerRoot' && python3 scripts/paired_server.py status --run '$remoteRun'"
        if ($server.finished_at) { throw "server readiness failed: $($server.reason)" }
        if ($clock.Elapsed.TotalSeconds -gt 60) { throw 'server readiness timed out' }
    } while ($server.status -ne 'ready')
    $readyPath = Join-Path $root ready.json
    $server | ConvertTo-Json -Depth 20 | Set-Content $readyPath -Encoding utf8NoBOM
    $result.server = $server
    $assertionPath = Join-Path $root 'assertion-a'
    Copy-Remote "okami:$remoteRun/private/assertion-a" $assertionPath
    if ([string]::IsNullOrWhiteSpace((Get-Content $assertionPath -Raw))) { throw 'empty assertion' }
    $clientReport = Join-Path $root 'a.json'
    $stop = Join-Path $root 'stop-a'
    $start = [Diagnostics.ProcessStartInfo]::new($GodotPath)
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in @('--path', (New-Item -ItemType Directory -Path (Join-Path $root resources)).FullName, '--main-pack', $pack, '--script', $probe,
            '--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--resolution', $Resolution, '--',
            'a', "frontier-$($server.run_id)-a", $clientReport, $stop, $readyPath, $pack, $assertionPath)) { $start.ArgumentList.Add($argument) }
    foreach ($key in @('PROJECT0_CLIENT_HTTPS_LOGIN', 'PROJECT0_CLIENT_NAKAMA_LOGIN', 'PROJECT0_CLIENT_NAKAMA_GAMEPLAY', 'PROJECT0_CLIENT_LOGIN_SPLIT')) { $start.Environment[$key] = '0' }
    $start.Environment['PROJECT0_SERVER_HOST'] = '192.168.1.254'
    $start.Environment['PROJECT0_SERVER_PORT'] = [string]$server.port
    $start.Environment['APPDATA'] = Join-Path $root 'appdata'
    $start.Environment['LOCALAPPDATA'] = Join-Path $root 'localappdata'
    $start.Environment['TEMP'] = Join-Path $root 'temp'
    $start.Environment['TMP'] = $start.Environment['TEMP']
    New-Item -ItemType Directory -Path $start.Environment['TEMP'] -Force | Out-Null
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    if (-not $process.Start()) { throw 'client did not start' }
    $logs = @{ stdout = $process.StandardOutput.ReadToEndAsync(); stderr = $process.StandardError.ReadToEndAsync() }
    $clock.Restart()
    do {
        if ($process.HasExited) { throw "client exited $($process.ExitCode) before completing the journey" }
        $client = Read-Json $clientReport
        if ($client -and $client.status -eq 'passed') { break }
        if ($clock.Elapsed.TotalSeconds -gt 120) { throw 'frontier journey timed out' }
        Start-Sleep -Milliseconds 100
    } while ($true)
    # Let the server observer record the re-entry before finishing.
    Start-Sleep -Milliseconds 1500
    # The probe replaces its report every frame, so a single read can miss it.
    $clock.Restart()
    do { $client = Read-Json $clientReport; if ($client -and $client.status -eq 'passed') { break }; Start-Sleep -Milliseconds 50 } while ($clock.Elapsed.TotalSeconds -lt 5)
    if (-not $client -or $client.status -ne 'passed') { throw 'final client report unreadable' }
    $result.client = $client
    Copy-Remote "okami:$remoteRun/private/frontier-observation.json" (Join-Path $root 'frontier-observation.json')
    $observation = Read-Json (Join-Path $root 'frontier-observation.json')
    $result.server_observation = $observation
    $evidencePath = Join-Path $root evidence.json
    @{ scenario_id = 'frontier-timeout-v1'; correlation_id = $runId; client = $client } | ConvertTo-Json -Depth 30 | Set-Content $evidencePath -Encoding utf8NoBOM
    $executable = (Get-Command scp -CommandType Application | Select-Object -First 1).Source
    $null = Invoke-Transport $executable @('-B', '-q', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes', '-o', 'ConnectTimeout=5', $evidencePath, "okami:$remoteRun/evidence.json") 'artifact-upload'
    $server = Invoke-Remote "cd '$ServerRoot' && python3 scripts/paired_server.py finish --run '$remoteRun' --evidence '$remoteRun/evidence.json'"
    $clock.Restart()
    do { $server = Invoke-Remote "cd '$ServerRoot' && python3 scripts/paired_server.py status --run '$remoteRun'" } while (-not $server.finished_at -and $clock.Elapsed.TotalSeconds -lt 30)
    if ($server.status -ne 'server_passed' -or -not $server.cleanup.passed) { throw "server evidence rejected: $($server.reason)" }
    $result.server = $server
    $result.verdict = Get-Verdict $client $observation
    [IO.File]::WriteAllText($stop, 'stop')
    if (-not $process.WaitForExit(10000)) { throw 'client did not stop' }
    $result.status = 'completed'
}
catch { $result.failure = $_.Exception.Message }
finally {
    try {
        if ($process -and -not $process.HasExited) { $process.Kill($true); $null = $process.WaitForExit(5000) }
        if ($logs) {
            [IO.File]::WriteAllText((Join-Path $evidence 'client.stdout.log'), $logs.stdout.Result)
            [IO.File]::WriteAllText((Join-Path $evidence 'client.stderr.log'), $logs.stderr.Result)
        }
    } catch { $result.cleanup_failure = $_.Exception.Message }
    try {
        $clientReport = Join-Path $root 'a.json'
        if (Test-Path $clientReport) { Copy-Item $clientReport (Join-Path $evidence 'client-report.json') }
        if ($remoteStarted -and -not $result.server_observation) { Copy-Remote "okami:$remoteRun/private/frontier-observation.json" (Join-Path $evidence 'frontier-observation.json') }
    } catch { $result.retention_failure = $_.Exception.Message }
    try { if (Test-Path $root) { Remove-Item $root -Recurse -Force }; $result.local_cleanup = -not (Test-Path $root) } catch { $result.cleanup_failure = $_.Exception.Message }
    if ($remoteStarted) {
        try {
            $server = Invoke-Remote "cd '$ServerRoot' && python3 scripts/paired_server.py status --run '$remoteRun'"
            if (-not $server.finished_at) { Invoke-Remote "cd '$ServerRoot' && python3 scripts/paired_server.py abort --run '$remoteRun'" | Out-Null }
            $clock = [Diagnostics.Stopwatch]::StartNew()
            do { $server = Invoke-Remote "cd '$ServerRoot' && python3 scripts/paired_server.py status --run '$remoteRun'" } while (-not $server.finished_at -and $clock.Elapsed.TotalSeconds -lt 30)
            $result.remote_cleanup = [bool]($server.finished_at -and $server.cleanup.passed)
        } catch { $result.cleanup_failure = $_.Exception.Message }
    } else { $result.remote_cleanup = $true }
    $result | ConvertTo-Json -Depth 30 | Set-Content (Join-Path $evidence result.json) -Encoding utf8NoBOM
}
$accepted = if ($result.verdict) { $result.verdict.accepted } else { $false }
Write-Output "Experiment 1359: status=$($result.status); accepted=$accepted; evidence=$evidence"
exit $(if ($result.status -eq 'completed' -and $result.local_cleanup -and $result.remote_cleanup) { 0 } else { 1 })
