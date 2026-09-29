#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$GodotPath,
    [Parameter(Mandatory)][string]$PackageRoot,
    [Parameter(Mandatory)][ValidatePattern('^/data/[A-Za-z0-9_./-]+$')][string]$ServerRoot,
    [Parameter(Mandatory)][ValidatePattern('^/data/[A-Za-z0-9_./-]+$')][string]$Artifact,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$ArtifactSha,
    [string]$PythonPath = 'python',
    [ValidateRange(1, 60)][int]$TransportTimeoutSeconds = 15
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$runId = [Guid]::NewGuid().ToString('N')
$evidence = Join-Path $repo "build/validation/shared-exploration-windows-$runId"
$root = Join-Path ([IO.Path]::GetTempPath()) "project0-shared-exploration-$runId"
$remoteRun = "$ServerRoot/build/validation/windows-$runId"
$remoteHelper = Join-Path $repo 'scripts/remote.ps1'
$processes = @{}
$remoteStarted = $false
$server = $null
$result = [ordered]@{ issue = 477; scenario = 'shared-exploration-v1'; correlation_id = $runId; status = 'failed'; paired_acceptance = $false; local_cleanup = $false; remote_cleanup = $false; clients = @{}; phases = @{}; failure = $null; transport = @() }
. (Join-Path $PSScriptRoot 'windows_validation_transport.ps1')

function Invoke-Remote([string]$script) {
    $output = Invoke-Transport $remoteHelper @() 'server-lifecycle' @{ Target = 'okami'; ConnectTimeout = 5; Script = $script }
    return ($output -join [Environment]::NewLine | ConvertFrom-Json -AsHashtable)
}

function Copy-Remote([string]$source, [string]$destination) {
    $executable = (Get-Command scp -CommandType Application | Select-Object -First 1).Source
    $null = Invoke-Transport $executable @('-B', '-q', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes', '-o', 'ConnectTimeout=5', '-o', 'ServerAliveInterval=5', '-o', 'ServerAliveCountMax=1', $source, $destination) 'artifact-transfer'
}

function Read-Json([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try { return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable } catch { return $null }
}

function Start-Client([string]$clientId, [string]$assertion, [string]$output, [string]$stop, [string]$probe, [string]$pack, [string]$ready, [int]$port) {
    $resourceRoot = Join-Path $root "resources-$clientId"
    New-Item -ItemType Directory -Path $resourceRoot -Force | Out-Null
    $start = [Diagnostics.ProcessStartInfo]::new($GodotPath)
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in @('--path', $resourceRoot, '--main-pack', $pack, '--script', $probe, '--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--resolution', '64x64', '--position', '-32000,-32000', '--', $clientId, "$($result.client_ids[$clientId])", $output, $stop, $ready, $pack, $assertion)) { $start.ArgumentList.Add($argument) }
    foreach ($key in @('PROJECT0_CLIENT_HTTPS_LOGIN', 'PROJECT0_CLIENT_NAKAMA_LOGIN', 'PROJECT0_CLIENT_NAKAMA_GAMEPLAY', 'PROJECT0_CLIENT_LOGIN_SPLIT')) { $start.Environment[$key] = '0' }
    $start.Environment['PROJECT0_SERVER_HOST'] = '192.168.1.254'
    $start.Environment['PROJECT0_SERVER_PORT'] = [string]$port
    $start.Environment['APPDATA'] = Join-Path $root "appdata-$clientId"
    $start.Environment['LOCALAPPDATA'] = Join-Path $root "localappdata-$clientId"
    $start.Environment['TEMP'] = Join-Path $root "temp-$clientId"
    $start.Environment['TMP'] = $start.Environment['TEMP']
    New-Item -ItemType Directory -Path $start.Environment['TEMP'] -Force | Out-Null
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    if (-not $process.Start()) { throw "client $clientId did not start" }
    $process.BeginOutputReadLine()
    $process.BeginErrorReadLine()
    $processes[$clientId] = $process
}

function Stop-Client([string]$clientId, [string]$stopPath) {
    if (-not $processes.ContainsKey($clientId)) { return }
    [IO.File]::WriteAllText($stopPath, 'stop')
    $process = $processes[$clientId]
    if (-not $process.WaitForExit(10000)) {
        $process.Kill($true)
        if (-not $process.WaitForExit(5000)) { throw "client $clientId did not stop" }
    }
    if ($process.ExitCode -ne 0) { throw "client $clientId exited $($process.ExitCode)" }
}

try {
    if (-not $IsWindows) { throw 'Windows execution required' }
    New-Item -ItemType Directory -Path $evidence, $root | Out-Null
    $manifest = Get-Content (Join-Path $PackageRoot 'deployment-manifest.json') -Raw | ConvertFrom-Json
    $zip = Join-Path $PackageRoot $manifest.archive.name
    if (-not $manifest.release_eligible -or (Get-FileHash $zip).Hash -ne $manifest.archive.sha256) { throw 'Immutable package archive mismatch' }
    Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $root package)
    $pack = Join-Path $root 'package/Project0.pck'
    $probe = Join-Path $root 'shared_probe.gd'
    Copy-Item (Join-Path $PSScriptRoot 'windows_shared_exploration_client.gd') $probe
    $packSha = (Get-FileHash $pack).Hash.ToLowerInvariant()
    $result.client_build = @{ sha256 = $packSha; version = $manifest.version; engine = '4.7.2-editor' }
    $result.client_ids = @{ a = "shared-$runId-a"; b = "shared-$runId-b" }
    $readyPath = Join-Path $root ready.json
    $serverManifestPath = Join-Path $root server-manifest.json
    Copy-Remote "okami:$Artifact/manifest.json" $serverManifestPath
    if ((Get-FileHash $serverManifestPath).Hash.ToLowerInvariant() -ne $ArtifactSha) { throw 'Server manifest mismatch' }
    $server = Invoke-Remote "cd '$ServerRoot' && python3 scripts/paired_server.py start --scenario shared-exploration-v1 --artifact '$Artifact' --artifact-sha256 '$ArtifactSha' --run '$remoteRun' --correlation-id '$runId' --client-sha256 '$packSha' --client-version '$($manifest.version)' --client-engine 4.7.2-editor --deadline-seconds 180 --readiness-seconds 45"
    $remoteStarted = $true
    do {
        $server = Invoke-Remote "cd '$ServerRoot' && python3 scripts/paired_server.py status --run '$remoteRun'"
        if ($server.finished_at) { throw "server readiness failed: $($server.reason)" }
    } while ($server.status -ne 'ready')
    $server | ConvertTo-Json -Depth 20 | Set-Content $readyPath -Encoding utf8NoBOM
    $result.server = $server
    $result.client_ids = @{ a = "shared-$($server.run_id)-a"; b = "shared-$($server.run_id)-b" }
    foreach ($clientId in @('a', 'b')) {
        $assertionPath = Join-Path $root "assertion-$clientId"
        Copy-Remote "okami:$remoteRun/private/assertion-$clientId" $assertionPath
        if ([string]::IsNullOrWhiteSpace((Get-Content $assertionPath -Raw))) { throw "empty assertion $clientId" }
        Start-Client $clientId $assertionPath (Join-Path $root "$clientId.json") (Join-Path $root "stop-$clientId") $probe $pack $readyPath ([int]$server.port)
    }
    $clock = [Diagnostics.Stopwatch]::StartNew()
    do {
        $a = Read-Json (Join-Path $root a.json); $b = Read-Json (Join-Path $root b.json)
        if ($a -and $b -and $a.status -eq 'passed' -and $b.status -eq 'passed' -and $a.remote_players.b -and $b.remote_players.a) { break }
        if ($clock.Elapsed.TotalSeconds -gt 45) { throw 'two-client world entry timed out' }
        Start-Sleep -Milliseconds 100
    } while ($true)
    $baselineA = $a.remote_players.b.position; $baselineB = $b.remote_players.a.position
    $result.phases.initial = @{ a = $a; b = $b; baseline_a = $baselineA; baseline_b = $baselineB }
    Start-Sleep -Milliseconds 1200
    $a = Read-Json (Join-Path $root a.json); $b = Read-Json (Join-Path $root b.json)
    $result.phases.movement = @{ a = $a; b = $b }
    if (-not $a -or -not $b -or -not $a.remote_players.b.position -or -not $b.remote_players.a.position) { throw 'movement evidence missing' }
    Stop-Client 'a' (Join-Path $root stop-a)
    $clock.Restart()
    do { $b = Read-Json (Join-Path $root b.json); if ($b -and $b.remote_players.Count -eq 0) { break }; if ($clock.Elapsed.TotalSeconds -gt 20) { throw 'disconnect removal timed out' }; Start-Sleep -Milliseconds 100 } while ($true)
    $result.phases.disconnect = $b
    Remove-Item (Join-Path $root stop-a) -Force -ErrorAction SilentlyContinue
    Start-Client 'a' (Join-Path $root assertion-a) (Join-Path $root a-reconnect.json) (Join-Path $root stop-a-reconnect) $probe $pack $readyPath ([int]$server.port)
    $clock.Restart()
    do { $b = Read-Json (Join-Path $root b.json); if ($b -and $b.remote_players.a) { break }; if ($clock.Elapsed.TotalSeconds -gt 30) { throw 'reconnect presence timed out' }; Start-Sleep -Milliseconds 100 } while ($true)
    $aReconnect = Read-Json (Join-Path $root a-reconnect.json)
    $result.phases.reconnect = $aReconnect
    $result.clients.a = $aReconnect; $result.clients.b = $b
    Copy-Remote "$remoteRun/private/shared-observation.json" (Join-Path $root shared-observation.json)
    $result.server_observation = Read-Json (Join-Path $root shared-observation.json)
    $evidencePath = Join-Path $root evidence.json
    $result | ConvertTo-Json -Depth 30 | Set-Content $evidencePath -Encoding utf8NoBOM
    Copy-Remote $evidencePath "okami:$remoteRun/evidence.json"
    $server = Invoke-Remote "cd '$ServerRoot' && python3 scripts/paired_server.py finish --run '$remoteRun' --evidence '$remoteRun/evidence.json'"
    do { $server = Invoke-Remote "cd '$ServerRoot' && python3 scripts/paired_server.py status --run '$remoteRun'" } while (-not $server.finished_at)
    if ($server.status -ne 'server_passed' -or -not $server.cleanup.passed) { throw "server acceptance failed: $($server.reason)" }
    Stop-Client 'b' (Join-Path $root stop-b); Stop-Client 'a' (Join-Path $root stop-a-reconnect)
    $result.status = 'passed'; $result.paired_acceptance = $true
}
catch { $result.failure = $_.Exception.Message }
finally {
    foreach ($clientId in @('a', 'b')) {
        try {
            if ($processes.ContainsKey($clientId) -and -not $processes[$clientId].HasExited) { $processes[$clientId].Kill($true); $processes[$clientId].WaitForExit(5000) }
        } catch { $result.cleanup_failure = $_.Exception.Message }
    }
    try { if (Test-Path $root) { Remove-Item $root -Recurse -Force }; $result.local_cleanup = -not (Test-Path $root) } catch { $result.cleanup_failure = $_.Exception.Message }
    if ($remoteStarted) {
        try {
            $server = Invoke-Remote "cd '$ServerRoot' && python3 scripts/paired_server.py status --run '$remoteRun'"
            if (-not $server.finished_at) { Invoke-Remote "cd '$ServerRoot' && python3 scripts/paired_server.py abort --run '$remoteRun'" | Out-Null }
            $clock = [Diagnostics.Stopwatch]::StartNew()
            do { $server = Invoke-Remote "cd '$ServerRoot' && python3 scripts/paired_server.py status --run '$remoteRun'" } while (-not $server.finished_at -and $clock.Elapsed.TotalSeconds -lt 30)
            $result.remote_cleanup = $server.finished_at -and $server.cleanup.passed
        } catch { $result.cleanup_failure = $_.Exception.Message }
    } else { $result.remote_cleanup = $true }
    $result | ConvertTo-Json -Depth 30 | Set-Content (Join-Path $evidence result.json) -Encoding utf8NoBOM
}
Write-Output "Shared exploration validation: status=$($result.status); evidence=$evidence"
exit $(if ($result.paired_acceptance -and $result.local_cleanup -and $result.remote_cleanup) { 0 } else { 1 })