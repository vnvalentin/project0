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
$evidence = Join-Path $repo "build/validation/coop-combat-windows-$runId"
$root = Join-Path ([IO.Path]::GetTempPath()) "project0-coop-combat-$runId"
$remoteRun = "$ServerRoot/build/validation/windows-$runId"
$remoteHelper = Join-Path $repo 'scripts/remote.ps1'
$processes = @{}
$logs = @{}
$serverStarted = $false
$server = $null
$result = [ordered]@{ issue = 1221; scenario = 'coop-combat-v1'; correlation_id = $runId; status = 'failed'; paired_acceptance = $false; local_cleanup = $false; remote_cleanup = $false; clients = @{}; server = $null; failure = $null; transport = @() }
. (Join-Path $PSScriptRoot 'windows_validation_transport.ps1')

function Invoke-Remote([string]$Script) {
    $output = Invoke-Transport $remoteHelper @() 'server-lifecycle' @{ Target = 'okami'; ConnectTimeout = 5; Script = $Script }
    return ($output -join [Environment]::NewLine | ConvertFrom-Json -AsHashtable)
}

function Copy-Remote([string]$Source, [string]$Destination) {
    $scp = (Get-Command scp -CommandType Application | Select-Object -First 1).Source
    $null = Invoke-Transport $scp @('-B', '-q', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes', '-o', 'ConnectTimeout=5', '-o', 'ServerAliveInterval=5', '-o', 'ServerAliveCountMax=1', $Source, $Destination) 'artifact-transfer'
}

function Copy-To-Remote([string]$Source, [string]$Destination) {
    $scp = (Get-Command scp -CommandType Application | Select-Object -First 1).Source
    $null = Invoke-Transport $scp @('-B', '-q', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes', '-o', 'ConnectTimeout=5', '-o', 'ServerAliveInterval=5', '-o', 'ServerAliveCountMax=1', $Source, "okami:$Destination") 'evidence-upload'
}

function Read-Json([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable } catch { return $null }
}

function Start-Client([string]$ClientId, [string]$CharacterId, [string]$Assertion, [string]$Output, [string]$Stop, [string]$Probe, [string]$Pack, [string]$Ready, [int]$Port) {
    $resourceRoot = Join-Path $root "resources-$ClientId"
    New-Item -ItemType Directory -Path $resourceRoot -Force | Out-Null
    $start = [Diagnostics.ProcessStartInfo]::new($GodotPath)
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in @('--path', $resourceRoot, '--main-pack', $Pack, '--script', $Probe, '--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--resolution', '64x64', '--position', '-32000,-32000', '--', $ClientId, $CharacterId, $Output, $Stop, $Ready, $Pack, $Assertion)) { $start.ArgumentList.Add($argument) }
    foreach ($key in @('PROJECT0_CLIENT_HTTPS_LOGIN', 'PROJECT0_CLIENT_NAKAMA_LOGIN', 'PROJECT0_CLIENT_NAKAMA_GAMEPLAY', 'PROJECT0_CLIENT_LOGIN_SPLIT')) { $start.Environment[$key] = '0' }
    $start.Environment['PROJECT0_E2E_DISABLE_TOWN_COLLISION'] = '1'
    $start.Environment['PROJECT0_SERVER_HOST'] = '192.168.1.254'
    $start.Environment['PROJECT0_SERVER_PORT'] = [string]$Port
    $start.Environment['APPDATA'] = Join-Path $root "appdata-$ClientId"
    $start.Environment['LOCALAPPDATA'] = Join-Path $root "localappdata-$ClientId"
    $start.Environment['TEMP'] = Join-Path $root "temp-$ClientId"
    $start.Environment['TMP'] = $start.Environment['TEMP']
    New-Item -ItemType Directory -Path $start.Environment['TEMP'] -Force | Out-Null
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    if (-not $process.Start()) { throw "client $ClientId did not start" }
    $logs[$ClientId] = @{ stdout = $process.StandardOutput.ReadToEndAsync(); stderr = $process.StandardError.ReadToEndAsync() }
    $processes[$ClientId] = $process
}

try {
    if (-not $IsWindows) { throw 'Windows execution required' }
    New-Item -ItemType Directory -Path $evidence, $root -Force | Out-Null
    $manifest = Get-Content (Join-Path $PackageRoot 'deployment-manifest.json') -Raw | ConvertFrom-Json
    $zip = Join-Path $PackageRoot $manifest.archive.name
    if (-not $manifest.release_eligible -or (Get-FileHash $zip).Hash -ne $manifest.archive.sha256) { throw 'Immutable package archive mismatch' }
    Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $root package)
    $pack = Join-Path $root 'package/Project0.pck'
    $packSha = (Get-FileHash $pack).Hash.ToLowerInvariant()
    $probe = Join-Path $root 'coop_combat_probe.gd'
    Copy-Item (Join-Path $PSScriptRoot 'windows_coop_combat_client.gd') $probe
    $readyPath = Join-Path $root ready.json
    $serverManifestPath = Join-Path $root server-manifest.json
    Copy-Remote "okami:$Artifact/manifest.json" $serverManifestPath
    if ((Get-FileHash $serverManifestPath).Hash.ToLowerInvariant() -ne $ArtifactSha) { throw 'Server manifest mismatch' }
    $server = Invoke-Remote "cd '$ServerRoot' && python3 scripts/paired_server.py start --scenario coop-combat-v1 --artifact '$Artifact' --artifact-sha256 '$ArtifactSha' --run '$remoteRun' --correlation-id '$runId' --client-sha256 '$packSha' --client-version '$($manifest.version)' --client-engine 4.7.2-editor --deadline-seconds 180 --readiness-seconds 45"
    $serverStarted = $true
    $clock = [Diagnostics.Stopwatch]::StartNew()
    do {
        $server = Invoke-Remote "cd '$ServerRoot' && python3 scripts/paired_server.py status --run '$remoteRun'"
        if ($server.finished_at) { throw "server readiness failed: $($server.reason)" }
        if ($clock.Elapsed.TotalSeconds -gt 60) { throw 'server readiness timed out' }
    } while ($server.status -ne 'ready')
    $server | ConvertTo-Json -Depth 20 | Set-Content $readyPath -Encoding utf8NoBOM
    $result.server = $server
    $probeArgs = @{ a = 'assertion-a'; b = 'assertion-b' }
    foreach ($clientId in @('a', 'b')) { Copy-Remote "okami:$remoteRun/private/assertion-$clientId" (Join-Path $root $probeArgs[$clientId]) }
    $result.client_ids = @{ a = "coop-$($server.run_id)-a"; b = "coop-$($server.run_id)-b" }
    foreach ($clientId in @('a', 'b')) {
        Start-Client $clientId $result.client_ids[$clientId] (Join-Path $root $probeArgs[$clientId]) (Join-Path $root "$clientId.json") (Join-Path $root "stop-$clientId") $probe $pack $readyPath ([int]$server.port)
    }
    do {
        if ($processes.Values | Where-Object HasExited) { throw 'client exited before combat evidence' }
        $a = Read-Json (Join-Path $root 'a.json'); $b = Read-Json (Join-Path $root 'b.json')
        if ($a -and $b -and $a.status -eq 'passed' -and $b.status -eq 'passed') { break }
        if ($clock.Elapsed.TotalSeconds -gt 140) { throw 'two-client combat observation timed out' }
        Start-Sleep -Milliseconds 100
    } while ($true)
    $result.clients = @{ a = $a; b = $b }
    $observationPath = Join-Path $root combat-observation.json
    Copy-Remote "okami:$remoteRun/private/combat-observation.json" $observationPath
    $result.server_observation = Read-Json $observationPath
    $evidenceObject = [ordered]@{ scenario_id = 'coop-combat-v1'; correlation_id = $runId; clients = @{ a = $a; b = $b }; server_observation = $result.server_observation }
    $evidencePath = Join-Path $root evidence.json
    $evidenceObject | ConvertTo-Json -Depth 30 | Set-Content $evidencePath -Encoding utf8NoBOM
    Copy-To-Remote $evidencePath "$remoteRun/evidence.json"
    $null = Invoke-Remote "cd '$ServerRoot' && python3 scripts/paired_server.py finish --run '$remoteRun' --evidence '$remoteRun/evidence.json'"
    do { $server = Invoke-Remote "cd '$ServerRoot' && python3 scripts/paired_server.py status --run '$remoteRun'" } while (-not $server.finished_at)
    if ($server.status -ne 'server_passed' -or -not $server.cleanup.passed) { throw "server acceptance failed: $($server.reason)" }
    foreach ($clientId in @('a', 'b')) { [IO.File]::WriteAllText((Join-Path $root "stop-$clientId"), 'stop') }
    foreach ($clientId in @('a', 'b')) { if (-not $processes[$clientId].WaitForExit(10000) -or $processes[$clientId].ExitCode -ne 0) { throw "client $clientId did not stop cleanly" } }
    $result.clients = @{ a = $a; b = $b }; $result.server = $server; $result.status = 'passed'; $result.paired_acceptance = $true
}
catch { $result.failure = $_.Exception.Message }
finally {
    foreach ($clientId in $logs.Keys) {
        try { if (-not $logs[$clientId].stdout.Wait(5000) -or -not $logs[$clientId].stderr.Wait(5000)) { throw "client $clientId log capture timed out" }; [IO.File]::WriteAllText((Join-Path $evidence "client-$clientId.stdout.log"), $logs[$clientId].stdout.Result); [IO.File]::WriteAllText((Join-Path $evidence "client-$clientId.stderr.log"), $logs[$clientId].stderr.Result) } catch { $result.cleanup_failure = $_.Exception.Message }
    }
    foreach ($clientId in @('a', 'b')) { try { if ($processes.ContainsKey($clientId) -and -not $processes[$clientId].HasExited) { $processes[$clientId].Kill($true); $processes[$clientId].WaitForExit(5000) } } catch { $result.failure = $_.Exception.Message } }
    try { if (Test-Path $root) { Remove-Item $root -Recurse -Force }; $result.local_cleanup = -not (Test-Path $root) } catch { $result.failure = $_.Exception.Message }
    if ($serverStarted) { try { $server = Invoke-Remote "cd '$ServerRoot' && python3 scripts/paired_server.py status --run '$remoteRun'"; if (-not $server.finished_at) { $null = Invoke-Remote "cd '$ServerRoot' && python3 scripts/paired_server.py abort --run '$remoteRun'"; do { $server = Invoke-Remote "cd '$ServerRoot' && python3 scripts/paired_server.py status --run '$remoteRun'" } while (-not $server.finished_at) }; $result.server = $server; $result.remote_cleanup = $server.finished_at -and $server.cleanup.passed } catch { $result.failure = $_.Exception.Message } } else { $result.remote_cleanup = $true }
    $result | ConvertTo-Json -Depth 30 | Set-Content (Join-Path $evidence result.json) -Encoding utf8NoBOM
    Write-Output "Co-op combat validation: status=$($result.status); evidence=$evidence"
}
exit $(if ($result.paired_acceptance -and $result.local_cleanup -and $result.remote_cleanup) { 0 } else { 1 })
