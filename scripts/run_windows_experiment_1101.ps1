param(
    [ValidatePattern('^[0-9a-f]{40}$')]
    [string]$BackendCommit = "318dd8ddcdb25333db8f85dd64f2eebbe5ac96b4",
    [ValidatePattern('^/(data/code|tmp)/[a-zA-Z0-9_/-]+$')]
    [string]$BackendRepository = "/data/code/project0",
    [ValidateSet("MissingSession", "Offline", "Transport", "VersionRPC", "VersionSignal")]
    [string]$ProbeMode = "MissingSession",
    [ValidateRange(1, 45)]
    [int]$ClientTimeoutSeconds = 45,
    [ValidatePattern('^(|[0-9]+\.[0-9]+\.[0-9]+)$')]
    [string]$BackendRequiredVersion = ""
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$runId = [Guid]::NewGuid().ToString("N")
$evidence = Join-Path $repo "logs\experiments\exp_1101_$runId"
New-Item -ItemType Directory -Path $evidence | Out-Null
$root = Join-Path ([IO.Path]::GetTempPath()) "project0-1101-$runId"
$backend = $null
$ready = $null
$client = $null
$clientStarted = $false
$stdout = $null
$stderr = $null
$backendOutput = $null
$ownedSsh = [Collections.Generic.List[object]]::new()
$result = [ordered]@{ experiment_id = "1101"; phase = "missing_session_probe"; full_matrix = $false; status = "failed"; host_name = $env:COMPUTERNAME; source_commit = $null; backend = $null; failure = $null; client = $null; local_cleanup = $false; remote_cleanup = $false }
$result.probe_mode = $ProbeMode
$result.local_root = $root
$result.client_pid = $null
$result.probe_sha256 = $null
$result.runner_sha256 = (Get-FileHash $PSCommandPath -Algorithm SHA256).Hash
if ($ProbeMode -ne "MissingSession") { $result.phase = "lifecycle_diagnostic" }
$exitCode = 1

function Start-RemotePython([string]$Code) {
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = "$env:WINDIR\System32\OpenSSH\ssh.exe"
    $start.Arguments = "-o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=10 -o ServerAliveCountMax=2 vic@192.168.1.254 python3 -"
    $start.UseShellExecute = $false
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    [void]$process.Start()
    $ownedSsh.Add(@{ Process = $process; Id = $process.Id; ErrorRead = $process.StandardError.ReadToEndAsync() })
    $process.StandardInput.Write($Code)
    $process.StandardInput.Close()
    return $process
}

try {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw "Windows required." }
    if ([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw "Standard-user execution required." }
    if (@(Get-Process | Where-Object { $_.ProcessName -match '^(Project0($|-)|windows_launcher$)' }).Count -ne 0) { throw "Conflicting Project0 process; no process was terminated." }
    $result.source_commit = (git -C $repo rev-parse HEAD | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $result.source_commit -notmatch '^[0-9a-f]{40}$') { throw "Cannot identify probe source revision." }
    $result.source_tree_dirty = [bool](git -C $repo status --porcelain --untracked-files=normal)
    $artifactRoot = Join-Path $repo "dist\current"
    $deployment = Get-Content (Join-Path $artifactRoot "deployment-manifest.json") -Raw | ConvertFrom-Json
    $result.payload_source_commit = $deployment.source_commit
    $result.payload_version = $deployment.version
    $result.backend_required_version = if ($BackendRequiredVersion) { $BackendRequiredVersion } else { $deployment.version }
    $result.payload_sha256 = @{}
    if ($deployment.version -notmatch '^\d+\.\d+\.\d+$') { throw "Invalid baseline version." }
    New-Item -ItemType Directory -Path $root | Out-Null
    foreach ($name in @("Project0.exe", "Project0.pck")) {
        $path = Join-Path $artifactRoot $name
        $entry = @($deployment.artifacts | Where-Object { $_.name -eq $name })
        if ($entry.Count -ne 1 -or (Get-FileHash $path -Algorithm SHA256).Hash -ne $entry[0].sha256) { throw "Baseline hash mismatch: $name" }
        $result.payload_sha256[$name] = $entry[0].sha256
        Copy-Item $path $root
        $copied = Join-Path $root $name
        if ((Get-FileHash $copied -Algorithm SHA256).Hash -ne $entry[0].sha256 -or (Get-Item $copied).Length -ne $entry[0].bytes) { throw "Copied baseline changed: $name" }
    }
    $probePath = Join-Path $root "experiment_1101_client.gd"
    Copy-Item (Join-Path $PSScriptRoot "experiment_1101_client.gd") $probePath
    $result.probe_sha256 = (Get-FileHash $probePath -Algorithm SHA256).Hash
    $remoteCode = @'
import hashlib, json, os, pathlib, shutil, signal, socket, subprocess, tempfile, time
root = tempfile.mkdtemp(prefix="project0-1101-")
process = None
log = None
def interrupted(signum, frame):
    raise SystemExit(128 + signum)
for signum in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT):
    signal.signal(signum, interrupted)
try:
    repository = "__REPOSITORY__"
    commit = "__COMMIT__"
    snapshot = root + "/source"
    os.mkdir(snapshot)
    shared_status = subprocess.check_output(["git", "--no-optional-locks", "-C", repository, "status", "--porcelain"], text=True, timeout=10)
    subprocess.run(["git", "-C", repository, "archive", "--format=tar", "--output=" + root + "/source.tar", commit], check=True, timeout=20)
    subprocess.run(["tar", "-xf", root + "/source.tar", "-C", snapshot], check=True, timeout=20)
    native_hashes = {}
    for directory in ("addons/godot-sqlite/bin", "native/wgnetstack/gdext/build"):
        for source in pathlib.Path(repository, directory).glob("*.so"):
            relative = source.relative_to(repository)
            target = pathlib.Path(snapshot, relative)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
            native_hashes[str(relative)] = hashlib.sha256(target.read_bytes()).hexdigest()
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    probe.bind(("192.168.1.254", 0))
    port = probe.getsockname()[1]
    probe.close()
    env = {key: value for key, value in os.environ.items() if not key.startswith("PROJECT0_")}
    env.update({"XDG_DATA_HOME": root + "/data", "XDG_CONFIG_HOME": root + "/config", "PROJECT0_ACCOUNTS_DB_PATH": "accounts.db", "PROJECT0_CANON_DB_PATH": "canon.db", "PROJECT0_HEALTH_FILE": root + "/health.json", "PROJECT0_OPERATOR_CONTROL_PORT": "0", "PROJECT0_REQUIRED_CLIENT_VERSION": "__VERSION__", "PROJECT0_E2E_DISABLE_TOWN_COLLISION": "1"})
    log = open(root + "/server.log", "w")
    subprocess.run(["/usr/local/bin/godot", "--headless", "--editor", "--import", "--path", snapshot, "--quit"], env=env, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=45)
    process = subprocess.Popen(["/usr/local/bin/godot", "--headless", "--path", snapshot, "-s", "server/server_main.gd", "--", "--server-port=" + str(port), "--server-bind-address=192.168.1.254"], env=env, stdout=log, stderr=subprocess.STDOUT)
    deadline = time.monotonic() + 40
    while time.monotonic() < deadline and process.poll() is None:
        try:
            with open(root + "/health.json") as health:
                if json.load(health).get("status") == "healthy":
                    break
        except (OSError, ValueError):
            pass
        try:
            process.wait(timeout=0.1)
        except subprocess.TimeoutExpired:
            pass
    else:
        raise RuntimeError("isolated server did not become healthy")
    print(json.dumps({"event": "ready", "port": port, "pid": process.pid, "root": root, "source_commit": commit, "source_isolated": True, "shared_checkout_dirty": bool(shared_status.strip()), "native_sha256": native_hashes}), flush=True)
    process.wait(timeout=90)
except Exception as error:
    print(json.dumps({"event": "failure", "reason": str(error)}), flush=True)
finally:
    for signum in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT):
        signal.signal(signum, signal.SIG_IGN)
    if process is not None and process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
    diagnostics = ""
    log_bytes = 0
    if log is not None:
        log.close()
        log_bytes = os.path.getsize(root + "/server.log")
        with open(root + "/server.log", "rb") as saved_log:
            saved_log.seek(max(0, log_bytes - 65536))
            diagnostics = saved_log.read(65536).decode("utf-8", errors="replace")
    shutil.rmtree(root)
    print(json.dumps({"event": "cleanup", "root_removed": not os.path.exists(root), "server_stopped": process is None or process.poll() is not None, "diagnostics": diagnostics, "log_bytes": log_bytes, "log_truncated": log_bytes > 65536}), flush=True)
'@
    $backend = Start-RemotePython ($remoteCode.Replace("__VERSION__", $result.backend_required_version).Replace("__REPOSITORY__", $BackendRepository).Replace("__COMMIT__", $BackendCommit))
    $line = $backend.StandardOutput.ReadLineAsync()
    if (-not $line.Wait(140000)) { throw "Backend snapshot/readiness timed out." }
    $backendOutput = $backend.StandardOutput.ReadToEndAsync()
    $ready = $line.Result | ConvertFrom-Json
    if ($ready.event -ne "ready") { throw "Backend failed readiness: $($line.Result)" }
    $result.backend = $ready
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = Join-Path $root "Project0.exe"
    $start.Arguments = '--headless --main-pack "' + (Join-Path $root "Project0.pck") + '" --script "' + $probePath + '"'
    $start.WorkingDirectory = $root
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($key in @($start.EnvironmentVariables.Keys)) { if ($key -like "PROJECT0_*") { $start.EnvironmentVariables.Remove($key) } }
    $start.EnvironmentVariables["LOCALAPPDATA"] = Join-Path $root "local"
    $start.EnvironmentVariables["APPDATA"] = Join-Path $root "roaming"
    $start.EnvironmentVariables["PROJECT0_CLIENT_HTTPS_LOGIN"] = "0"
    $start.EnvironmentVariables["PROJECT0_CLIENT_NAKAMA_LOGIN"] = "0"
    $start.EnvironmentVariables["PROJECT0_1101_GAME_HOST"] = "192.168.1.254"
    $start.EnvironmentVariables["PROJECT0_1101_GAME_PORT"] = [string]$ready.port
    $statePath = Join-Path $evidence "client.json"
    $start.EnvironmentVariables["PROJECT0_1101_EVIDENCE"] = $statePath
    $start.EnvironmentVariables["PROJECT0_1101_PROBE_MODE"] = $ProbeMode
    $client = [Diagnostics.Process]::new()
    $client.StartInfo = $start
    [void]$client.Start()
    $clientStarted = $true
    $result.client_pid = $client.Id
    $stdout = $client.StandardOutput.ReadToEndAsync()
    $stderr = $client.StandardError.ReadToEndAsync()
    if (-not $client.WaitForExit($ClientTimeoutSeconds * 1000)) { throw "Client probe timed out." }
    [IO.File]::WriteAllText((Join-Path $evidence "client.log"), $stdout.Result + $stderr.Result)
    if (Test-Path $statePath) { $result.client = Get-Content $statePath -Raw | ConvertFrom-Json }
    if ($backend.HasExited) { throw "Backend exited before the probe completed." }
    if ($stderr.Result -match '(?m)^(SCRIPT ERROR|ERROR):') { throw "Client runtime error; inspect client.log." }
    if ($client.ExitCode -ne 0 -or -not $result.client.passed) { throw "Client $ProbeMode probe failed; inspect client.json/client.log." }
    $result.status = "probe_passed"
    $exitCode = 0
}
catch { $result.failure = $_.Exception.Message; Write-Warning $result.failure }
finally {
    $cleanupFailures = @()
    $result.ssh_pids = @($ownedSsh | ForEach-Object { $_.Id })
    try {
        if ($clientStarted -and -not $client.HasExited) { $client.Kill(); if (-not $client.WaitForExit(5000)) { throw "Owned client did not stop." } }
    }
    catch { $cleanupFailures += $_.Exception.Message }
    try {
        if ($stdout -and $stderr) {
            if (-not $stdout.Wait(5000) -or -not $stderr.Wait(5000)) { throw "Client output capture did not complete after termination." }
            [IO.File]::WriteAllText((Join-Path $evidence "client.log"), $stdout.Result + $stderr.Result)
        }
    }
    catch { $cleanupFailures += $_.Exception.Message }
    try {
        if ($backend -and -not $backend.HasExited -and $ready -and $ready.event -eq "ready") {
            if ($ready.root -notmatch '^/tmp/project0-1101-[a-zA-Z0-9_]+$' -or [int]$ready.pid -le 0) { throw "Invalid backend ownership record." }
            $stopCode = "import os,signal`npid=" + [int]$ready.pid + "`nroot='" + $ready.root + "'`ntry:`n data=open('/proc/%d/environ'%pid,'rb').read()`n assert (root+'/data').encode() in data`n os.kill(pid,signal.SIGTERM)`nexcept FileNotFoundError:`n pass`n"
            $stop = Start-RemotePython $stopCode
            if (-not $stop.WaitForExit(10000) -or $stop.ExitCode -ne 0) { throw "Owned backend termination could not be confirmed." }
        }
        if ($backend) {
            if (-not $backend.WaitForExit(100000)) { throw "Backend lifecycle deadline exceeded." }
            if (-not $backendOutput -or -not $backendOutput.Wait(5000)) { throw "Backend cleanup output unavailable." }
            $lines = $backendOutput.Result.Trim().Split("`n")
            $cleanup = $lines[-1] | ConvertFrom-Json
            [IO.File]::WriteAllText((Join-Path $evidence "backend.log"), [string]$cleanup.diagnostics)
            $result.backend_log_bytes = $cleanup.log_bytes
            $result.backend_log_truncated = $cleanup.log_truncated
            $result.remote_cleanup = $cleanup.event -eq "cleanup" -and $cleanup.root_removed -and $cleanup.server_stopped
            if (-not $result.remote_cleanup) { throw "Remote teardown evidence missing." }
        }
    }
    catch { $cleanupFailures += $_.Exception.Message }
    foreach ($owned in $ownedSsh) {
        try {
            if (-not $owned.Process.HasExited) {
                $owned.Process.Kill()
                if (-not $owned.Process.WaitForExit(5000)) { throw "Owned SSH helper did not stop: $($owned.Id)" }
            }
            if (-not $owned.ErrorRead.Wait(5000)) { throw "SSH diagnostic capture did not complete: $($owned.Id)" }
            [IO.File]::WriteAllText((Join-Path $evidence "ssh-$($owned.Id).log"), $owned.ErrorRead.Result)
        }
        catch { $cleanupFailures += $_.Exception.Message }
        finally {
            try { $owned.Process.Dispose() }
            catch { $cleanupFailures += $_.Exception.Message }
        }
    }
    try {
        if (Test-Path $root) { Remove-Item $root -Recurse -Force }
        $result.local_cleanup = -not (Test-Path $root)
    }
    catch { $cleanupFailures += $_.Exception.Message }
    if ($cleanupFailures.Count -ne 0) {
        $result.cleanup_failure = $cleanupFailures -join "; "
        $result.status = "failed"
        $exitCode = 1
    }
    $result | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $evidence "result.json") -Encoding UTF8
    Write-Output "Experiment evidence: $evidence"
}
exit $exitCode