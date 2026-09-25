param(
    [string]$ArtifactDirectory = (Join-Path $PSScriptRoot "..\dist\current")
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$runId = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssfffZ") + "-" + [Guid]::NewGuid().ToString("N")
$evidence = Join-Path $repo "logs\experiments\exp_1100_version_tuple_persistence_$runId"
New-Item -ItemType Directory -Path $evidence | Out-Null
$summary = [ordered]@{
    experiment_id = "exp_1100_version_tuple_persistence"
    run_id = $runId
    host_name = $env:COMPUTERNAME
    os = [Environment]::OSVersion.VersionString
    status = "failed"
    scope = "Explicit test-CA fresh-install path; isolated state on developer Windows; not pristine OS or gameplay authentication proof"
    fixture_transport = "In-process loopback HTTPS protocol fixture; no deployed server changes"
    source_commit = $null
    payload_source_commit = $null
    baseline_version = $null
    source_tree_dirty = $null
    failure = $null
    started_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    completed_at_utc = $null
    preconditions = @{}
    cases = @()
    outer_cleanup = @{}
}
$saved = @{}
$workRoot = $null
$exitCode = 1
try {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw "Windows execution required." }
    $elevated = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($elevated) { throw "Run as a standard user, not elevated." }
    $conflicts = @(Get-Process | Where-Object { $_.ProcessName -match '^(Project0($|-)|windows_launcher$)' })
    $summary.preconditions = @{ elevated = $elevated; conflicting_process_count = $conflicts.Count }
    if ($conflicts.Count -ne 0) { throw "Conflicting Project0 process found; no processes were terminated." }
    $deployment = Get-Content (Join-Path $ArtifactDirectory "deployment-manifest.json") -Raw | ConvertFrom-Json
    $summary.baseline_version = $deployment.version
    if ($deployment.version -notmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') { throw "Invalid baseline version." }
    foreach ($name in @("Project0.exe", "Project0.pck")) {
        $entry = @($deployment.artifacts | Where-Object { $_.name -eq $name })
        $path = Join-Path $ArtifactDirectory $name
        if ($entry.Count -ne 1 -or (Get-Item $path).Length -ne $entry[0].bytes -or (Get-FileHash $path -Algorithm SHA256).Hash -ne $entry[0].sha256) {
            throw "Baseline artifact is missing or changed: $name"
        }
    }
    $summary.source_commit = (git -C $repo rev-parse HEAD | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw "Cannot determine launcher source commit." }
    $summary.source_tree_dirty = [bool](git -C $repo status --porcelain --untracked-files=normal)
    $summary.payload_source_commit = $deployment.source_commit
    foreach ($name in @("PROJECT0_1100_ENGINE", "PROJECT0_1100_PACK", "PROJECT0_1100_EVIDENCE", "PROJECT0_1100_WORK_ROOT", "GOTMPDIR")) {
        $saved[$name] = [Environment]::GetEnvironmentVariable($name, "Process")
    }
    $env:PROJECT0_1100_ENGINE = (Resolve-Path (Join-Path $ArtifactDirectory "Project0.exe")).Path
    $env:PROJECT0_1100_PACK = (Resolve-Path (Join-Path $ArtifactDirectory "Project0.pck")).Path
    $env:PROJECT0_1100_EVIDENCE = $evidence
    $workRoot = Join-Path ([IO.Path]::GetTempPath()) ("project0-experiment-1100-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $workRoot | Out-Null
    $env:PROJECT0_1100_WORK_ROOT = $workRoot
    $env:GOTMPDIR = $workRoot
    Push-Location (Join-Path $repo "native\windows_launcher")
    try {
        & go test -count=1 -ldflags "-X project0/windows-launcher.launcherClientVersion=$($deployment.version)" -run '^(TestPackagedVerifiedAdmissionPersistsBeforeSpawn|TestExperiment1100RealEngine)$' -timeout 5m . 2>&1 |
            Tee-Object -FilePath (Join-Path $evidence "command.log")
        $exitCode = $LASTEXITCODE
    }
    finally { Pop-Location }
    $summary.cases = @(Get-ChildItem $evidence -Filter "*.json" | ForEach-Object { Get-Content $_.FullName -Raw | ConvertFrom-Json })
    if ($exitCode -ne 0) { throw "Experiment matrix failed with exit code $exitCode." }
    if ($summary.cases.Count -ne 17 -or @($summary.cases | Where-Object { -not $_.passed -or -not $_.cleanup_succeeded }).Count -ne 0) {
        throw "Missing case or cleanup evidence."
    }
    $realValid = @($summary.cases | Where-Object { -not $_.probe -and $_.scenario -eq "valid" })
    if ($realValid.Count -ne 1 -or $realValid[0].events[0].semver -ne $deployment.version) {
        throw "Persisted engine tuple does not match baseline $($deployment.version); observed $($realValid[0].events[0].semver)."
    }
    $remaining = @(Get-Process | Where-Object { $_.ProcessName -match '^(Project0($|-)|windows_launcher$)' })
    if ($remaining.Count -ne 0) { throw "Project0 process remains after experiment; inspect before cleanup." }
    $summary.status = "passed"
    $exitCode = 0
}
catch {
    $summary.failure = $_.Exception.Message
    $exitCode = 1
    Write-Warning $summary.failure
}
finally {
    if ($workRoot) {
        try {
            $owned = @(Get-Process | Where-Object { $_.Path -and $_.Path.StartsWith($workRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) })
            $summary.outer_cleanup = @{ root = $workRoot; remaining_owned_processes = $owned.Count; succeeded = $false }
            foreach ($process in $owned) {
                Stop-Process -InputObject $process -Force -ErrorAction Stop
                if (-not $process.WaitForExit(5000)) { throw "Owned process did not stop: $($process.Id)" }
            }
            Remove-Item $workRoot -Recurse -Force
            $summary.outer_cleanup.succeeded = -not (Test-Path $workRoot)
            if ($owned.Count -ne 0) { throw "Outer teardown recovered leaked experiment processes; run is failed." }
        }
        catch {
            $summary.status = "failed"
            $summary.outer_cleanup.error = $_.Exception.Message
            $exitCode = 1
        }
    }
    foreach ($entry in $saved.GetEnumerator()) { [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, "Process") }
    $summary.completed_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    $summary | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $evidence "result.json") -Encoding UTF8
    Write-Output "Experiment evidence: $evidence"
}
exit $exitCode