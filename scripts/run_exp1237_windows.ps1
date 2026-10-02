#requires -Version 7.0
# Experiment #1237 coordinator (SETSUJOKU). Runs the #1234/#1235-derived owned
# server orchestrators on okami from an isolated clone of this commit and answers
# each published client phase with two packaged Windows clients (Godot 4.7.2
# editor hosting the immutable package PCK; the release exe ignores --script).
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$GodotPath,
    [Parameter(Mandatory)][string]$PackageRoot,
    [ValidateRange(60, 600)][int]$ClientTimeoutSeconds = 150,
    [ValidateRange(300, 3600)][int]$RunTimeoutSeconds = 1800
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$runId = [Guid]::NewGuid().ToString('N').Substring(0, 12)
$evidence = Join-Path $repo "build/validation/exp1237-windows-$runId"
$root = Join-Path ([IO.Path]::GetTempPath()) "project0-exp1237-$runId"
$remoteRoot = "/tmp/v1237-$runId"
$sshHost = 'vic@192.168.1.254'
$remoteHelper = Join-Path $PSScriptRoot 'remote.ps1'
$clients = @{}
$result = [ordered]@{
    issue = 1237; harness_issue = 1350; host = $env:COMPUTERNAME; run_id = $runId; status = 'failed'; failure = $null
    client_mode = 'godot-4.7.2-editor-hosting-package-pck'; remote_root = $remoteRoot; phases = @(); runs = @()
    timeouts_seconds = @{ client = $ClientTimeoutSeconds; run = $RunTimeoutSeconds }
    user_review = 'pending'; local_cleanup = $false; remote_cleanup = $false
}

function Invoke-Remote([string]$script) {
    $output = $script | & $remoteHelper
    if ($LASTEXITCODE -ne 0) { throw "remote command failed ($LASTEXITCODE)" }
    return ($output -join "`n")
}

function Copy-From([string]$remotePath, [string]$localPath) {
    & scp.exe -q -B -o BatchMode=yes "${sshHost}:$remotePath" $localPath
    return $LASTEXITCODE -eq 0
}

function Copy-To([string]$localPath, [string]$remotePath) {
    & scp.exe -q -B -o BatchMode=yes $localPath "${sshHost}:$remotePath"
    if ($LASTEXITCODE -ne 0) { throw "upload failed: $remotePath" }
}

function Start-Client([string]$role, [hashtable]$paths, [string]$pack, [string]$probe, [int]$index) {
    $resources = Join-Path $root "resources-$role"
    New-Item -ItemType Directory -Force -Path $resources, (Join-Path $root "temp-$role") | Out-Null
    $start = [Diagnostics.ProcessStartInfo]::new($GodotPath)
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in @('--path', $resources, '--main-pack', $pack, '--script', $probe, '--rendering-method', 'gl_compatibility',
            '--audio-driver', 'Dummy', '--resolution', '480x270', '--position', "$(40 + 500 * $index),40", '--',
            $paths.request, $role, $paths.tokens, $paths.observation, $paths.$role, $pack)) { $start.ArgumentList.Add($argument) }
    foreach ($key in @($start.Environment.Keys)) { if ($key -like 'PROJECT0_*') { [void]$start.Environment.Remove($key) } }
    foreach ($key in @('PROJECT0_CLIENT_HTTPS_LOGIN', 'PROJECT0_CLIENT_NAKAMA_LOGIN', 'PROJECT0_CLIENT_NAKAMA_GAMEPLAY', 'PROJECT0_CLIENT_LOGIN_SPLIT')) { $start.Environment[$key] = '0' }
    $start.Environment['APPDATA'] = Join-Path $root "appdata-$role"
    $start.Environment['LOCALAPPDATA'] = Join-Path $root "localappdata-$role"
    $start.Environment['TEMP'] = Join-Path $root "temp-$role"
    $start.Environment['TMP'] = $start.Environment['TEMP']
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    if (-not $process.Start()) { throw "client $role did not start" }
    return @{ process = $process; stdout = $process.StandardOutput.ReadToEndAsync(); stderr = $process.StandardError.ReadToEndAsync() }
}

try {
    if (-not $IsWindows) { throw 'Windows execution required' }
    New-Item -ItemType Directory -Path $evidence, $root | Out-Null
    $acl = [Security.AccessControl.DirectorySecurity]::new()
    $acl.SetAccessRuleProtection($true, $false)
    $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.WindowsIdentity]::GetCurrent().User, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
    Set-Acl -LiteralPath $root -AclObject $acl
    $manifest = Get-Content (Join-Path $PackageRoot 'deployment-manifest.json') -Raw | ConvertFrom-Json
    $zip = Join-Path $PackageRoot $manifest.archive.name
    if (-not $manifest.release_eligible -or (Get-FileHash $zip).Hash -ne $manifest.archive.sha256) { throw 'Package archive is not release eligible or its hash mismatches' }
    Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $root 'package')
    foreach ($entry in $manifest.archive_contents) {
        if ((Get-FileHash (Join-Path $root "package/$($entry.name)")).Hash -ne $entry.sha256) { throw "Extracted $($entry.name) hash mismatch" }
    }
    $pack = Join-Path $root 'package/Project0.pck'
    $packSha = (Get-FileHash $pack).Hash.ToLowerInvariant()
    $probe = Join-Path $root 'exp1237_windows_client.gd'
    Copy-Item (Join-Path $PSScriptRoot 'exp1237_windows_client.gd') $probe
    $engineVersion = (& $GodotPath --version | Out-String).Trim()
    if ($engineVersion -notmatch '^4\.7\.2\.stable') { throw "Unqualified client engine: $engineVersion" }
    $sourceCommit = (git -C $repo rev-parse HEAD).Trim()
    if (@(git -C $repo status --porcelain --untracked-files=no).Count -ne 0) { throw 'Coordinator requires a clean committed source tree' }
    $result.source_commit = $sourceCommit
    $result.package = @{ version = $manifest.version; source_commit = $manifest.source_commit; archive_sha256 = $manifest.archive.sha256
        exe_sha256 = ($manifest.archive_contents | Where-Object name -eq 'Project0.exe').sha256; pck_sha256 = $packSha; godot_version = $manifest.godot_version }
    $result.client_engine = @{ path = $GodotPath; version = $engineVersion; sha256 = (Get-FileHash $GodotPath).Hash }
    $result.probe_sha256 = (Get-FileHash $probe).Hash

    $bundle = Join-Path $root 'source.bundle'
    git -C $repo bundle create $bundle HEAD 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'git bundle failed' }
    Copy-To $bundle "$remoteRoot.bundle"
    $prepare = @"
set -e
R=$remoteRoot
test ! -e `$R
mkdir -p `$R/home `$R/tmp
git clone -q `$R.bundle `$R/src
rm -f `$R.bundle
cd `$R/src
git checkout -q $sourceCommit
mkdir -p native/wgnetstack/gdext/build
cp -a /data/code/project0-ci/native/wgnetstack/gdext/build/. native/wgnetstack/gdext/build/ 2>/dev/null || true
env -i PATH=/usr/local/bin:/usr/bin:/bin HOME=`$R/home TMPDIR=`$R/tmp timeout 600 godot --headless --import >/dev/null 2>&1 || true
nohup sh -c "for s in exp1237_return_experiment exp1237_crash_experiment; do env -i PATH=/usr/local/bin:/usr/bin:/bin HOME=`$R/home TMPDIR=`$R/tmp EXP1237_CLIENT_VERSION=$($manifest.version) EXP1237_CLIENT_SHA256=$packSha timeout 1200 godot --headless --path . -s scripts/\`$s.gd > `$R/\`$s.out 2>&1; echo \`$s=\`$? >> `$R/exp.exit; done; echo done >> `$R/exp.exit" > /dev/null 2>&1 &
echo started
"@
    $null = Invoke-Remote $prepare
    $handled = @{}
    $clock = [Diagnostics.Stopwatch]::StartNew()
    while ($clock.Elapsed.TotalSeconds -lt $RunTimeoutSeconds) {
        $listing = Invoke-Remote "ls $remoteRoot/src/logs/experiments/exp1237-*/*/phase-*.request.json 2>/dev/null; cat $remoteRoot/exp.exit 2>/dev/null; true"
        $requests = @($listing -split "`n" | Where-Object { $_ -like '*.request.json' -and -not $handled.ContainsKey($_) })
        if ($requests.Count -eq 0) {
            if ($listing -match '(?m)^done$') { break }
            Start-Sleep -Milliseconds 1000
            continue
        }
        $remoteRequest = $requests[0]
        $handled[$remoteRequest] = $true
        $local = Join-Path $root ("phase-" + $handled.Count)
        New-Item -ItemType Directory -Path $local | Out-Null
        $paths = @{ request = Join-Path $local 'request.json'; tokens = Join-Path $local 'tokens.json'; observation = Join-Path $local 'observation.json'
            actor = Join-Path $local 'actor.json'; occluder = Join-Path $local 'occluder.json' }
        if (-not (Copy-From $remoteRequest $paths.request)) { throw "request copy failed: $remoteRequest" }
        $request = Get-Content $paths.request -Raw | ConvertFrom-Json
        if (-not (Copy-From $request.tokens $paths.tokens)) { throw "token handoff failed for $($request.case)/$($request.phase)" }
        $phase = [ordered]@{ case = $request.case; phase = $request.phase; port = $request.port; clients = @{} }
        $clients = @{}
        $index = 0
        foreach ($role in @('occluder', 'actor')) { $clients[$role] = Start-Client $role $paths $pack $probe $index; $index++ }
        $phaseClock = [Diagnostics.Stopwatch]::StartNew()
        while (($clients.Values | Where-Object { -not $_.process.HasExited }).Count -gt 0 -and $phaseClock.Elapsed.TotalSeconds -lt $ClientTimeoutSeconds) {
            if (Copy-From $request.observation "$($paths.observation).tmp") { Move-Item -Force "$($paths.observation).tmp" $paths.observation }
            Start-Sleep -Milliseconds 500
        }
        Remove-Item -LiteralPath $paths.tokens -Force
        foreach ($role in @('occluder', 'actor')) {
            $client = $clients[$role]
            $forced = $false
            if (-not $client.process.HasExited) { $client.process.Kill($true); $null = $client.process.WaitForExit(10000); $forced = $true }
            $null = $client.stdout.Wait(5000); $null = $client.stderr.Wait(5000)
            $redact = { param([string]$text) $text -replace '\b[A-Za-z0-9+/=_-]{40,}\.[A-Za-z0-9+/=_-]{20,}\b', '[REDACTED]' }
            [IO.File]::WriteAllText((Join-Path $evidence "$($request.case)-$($request.phase)-$role.stdout.log"), (& $redact $client.stdout.Result))
            [IO.File]::WriteAllText((Join-Path $evidence "$($request.case)-$($request.phase)-$role.stderr.log"), (& $redact $client.stderr.Result))
            $phase.clients[$role] = @{ exit_code = $client.process.ExitCode; forced_stop = $forced }
            if (Test-Path $paths.$role) {
                Copy-Item $paths.$role (Join-Path $evidence "$($request.case)-$($request.phase)-$role.json")
                Copy-To $paths.$role $request.results.$role
            }
            $client.process.Dispose()
        }
        $clients = @{}
        $null = Invoke-Remote "touch '$($request.done)'"
        $result.phases += $phase
    }
    $final = Invoke-Remote "cat $remoteRoot/exp.exit 2>/dev/null; for d in $remoteRoot/src/logs/experiments/exp1237-*; do echo RUN `$d; done"
    $result.exit_codes = @($final -split "`n" | Where-Object { $_ -match '^exp1237_.*=\d+$' })
    if ($final -notmatch '(?m)^done$') { throw 'okami orchestrators did not finish within the run timeout' }
    foreach ($line in @($final -split "`n" | Where-Object { $_ -like 'RUN *' })) {
        $dir = $line.Substring(4)
        $name = Split-Path $dir -Leaf
        & scp.exe -q -r -B -o BatchMode=yes "${sshHost}:$dir" (Join-Path $evidence $name)
        $summary = Get-Content (Join-Path $evidence "$name/summary.json") -Raw | ConvertFrom-Json
        $result.runs += @{ run = $name; status = $summary.status; cases = @($summary.cases | ForEach-Object { @{ id = $_.id; outcome = $_.outcome; first_failing_stage = $_.first_failing_stage; failed = @($_.failed_assertions | ForEach-Object name) } }) }
    }
    $result.status = if ($result.runs.Count -eq 2 -and @($result.runs | Where-Object status -ne 'PASSED').Count -eq 0 -and @($result.exit_codes | Where-Object { $_ -notmatch '=0$' }).Count -eq 0) { 'passed' } else { 'failed' }
}
catch { $result.failure = $_.Exception.Message }
finally {
    foreach ($client in $clients.Values) { try { if (-not $client.process.HasExited) { $client.process.Kill($true); $null = $client.process.WaitForExit(5000) } } catch { } }
    try { if (Test-Path $root) { Remove-Item $root -Recurse -Force }; $result.local_cleanup = -not (Test-Path $root) } catch { $result.cleanup_failure = $_.Exception.Message }
    try {
        $cleanup = Invoke-Remote "pkill -f '$remoteRoot/src' 2>/dev/null; sleep 1; rm -rf '$remoteRoot' '$remoteRoot.bundle'; test -e '$remoteRoot' && echo still || echo removed"
        $result.remote_cleanup = $cleanup -match 'removed'
    } catch { $result.cleanup_failure = $_.Exception.Message }
    $result | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $evidence 'result.json') -Encoding utf8NoBOM
    Write-Output "EXP1237 Windows coordinator: status=$($result.status) evidence=$evidence"
}
exit $(if ($result.status -eq 'passed' -and $result.local_cleanup -and $result.remote_cleanup) { 0 } else { 1 })
