[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$')]
    [string]$Version,
    [string]$PackageRoot,
    [switch]$Windowed,
    [ValidateRange(10, 120)]
    [int]$TimeoutSeconds = 60,
    # Focused fail-closed checks: corrupt the owned archive copy or the extracted
    # PCK; either must be rejected before the client is launched.
    [ValidateSet("None", "ArchiveHash", "PckHash", "ProbeFlag")]
    [string]$FaultInjection = "None"
)

# #1213: verifies a built standalone Windows client package without the editor,
# launcher, servers, network, or credentials. The ZIP is copied into owned temp
# state, the archive and extracted EXE/PCK are checked against the manifest, then
# the extracted real EXE runs its fixed compiled package probe with
# isolated APPDATA/LOCALAPPDATA/TEMP and loopback-only backend settings. Passing
# proves the packaged compiled contract and client-side geometry readiness only;
# it is not gameplay acceptance. Evidence: build/validation/standalone-package-*.

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if (-not $PackageRoot) { $PackageRoot = Join-Path $repo "dist\standalone\$Version" }
$runId = [Guid]::NewGuid().ToString("N")
$evidence = Join-Path $repo "build\validation\standalone-package-$Version-$runId"
$root = Join-Path ([IO.Path]::GetTempPath()) "project0-package-verify-$runId"
$client = $null
$stdout = $null
$stderr = $null
$exitCode = 1
$result = [ordered]@{
    check = "standalone-package-verification"
    issue = 1213
    version = $Version
    fault_injection = $FaultInjection
    status = "failed"
    stage = "setup"
    failure = $null
    gameplay_acceptance = $false
    package_release_eligible = $false
    renderer = $(if ($Windowed) { "windows-gl_compatibility" } else { "headless" })
    package_root = $PackageRoot
    verifier_sha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash
    probe_entrypoint = "res://client/standalone_package_probe.gd"
    manifest = $null
    archive = $null
    archive_contents = @()
    client_launched = $false
    client = $null
    probe = $null
    runtime_error_lines = $null
    runtime_warning_lines = $null
    isolated_user_files = @()
    local_root = $root
    local_cleanup = $false
}

function Get-Record([string]$Path) {
    return [ordered]@{
        bytes = (Get-Item -LiteralPath $Path).Length
        sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    }
}

function Invoke-FlipByte([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $bytes[[int]($bytes.Length / 2)] = $bytes[[int]($bytes.Length / 2)] -bxor 0xFF
    [IO.File]::WriteAllBytes($Path, $bytes)
}

New-Item -ItemType Directory -Path $evidence | Out-Null
try {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw "Windows required." }
    New-Item -ItemType Directory -Path $root | Out-Null

    $result.stage = "integrity"
    $manifestPath = Join-Path $PackageRoot "deployment-manifest.json"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Missing package manifest: $manifestPath" }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $result.package_release_eligible = $manifest.release_eligible -eq $true
    $result.manifest = [ordered]@{ path = $manifestPath; sha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash; source_commit = $manifest.source_commit; source_tree_dirty = $manifest.source_tree_dirty }
    $zipName = "Project0-client-windows-x64-$Version.zip"
    if ($manifest.package -ne "standalone-windows-client" -or $manifest.version -ne $Version -or $manifest.archive.name -ne $zipName) {
        throw "Manifest identity does not match standalone package $Version."
    }
    $expectedNames = @($manifest.archive_contents | ForEach-Object name | Sort-Object)
    if (($expectedNames -join ",") -ne "Project0.exe,Project0.pck") { throw "Manifest must list exactly Project0.exe and Project0.pck." }

    $zipCopy = Join-Path $root $zipName
    Copy-Item -LiteralPath (Join-Path $PackageRoot $zipName) -Destination $zipCopy
    if ($FaultInjection -eq "ArchiveHash") { Invoke-FlipByte $zipCopy }
    $actual = Get-Record $zipCopy
    $result.archive = [ordered]@{ expected_bytes = $manifest.archive.bytes; expected_sha256 = $manifest.archive.sha256; actual_bytes = $actual.bytes; actual_sha256 = $actual.sha256 }
    if ($actual.bytes -ne $manifest.archive.bytes -or $actual.sha256 -ne $manifest.archive.sha256) { throw "Archive hash mismatch: $zipName" }

    $package = Join-Path $root "package"
    Expand-Archive -LiteralPath $zipCopy -DestinationPath $package
    $files = @(Get-ChildItem -LiteralPath $package -Recurse -Force | Sort-Object Name)
    if ((($files | ForEach-Object { $_.FullName.Substring($package.Length + 1) }) -join ",") -ne "Project0.exe,Project0.pck") {
        throw "Extracted archive is not exactly Project0.exe and Project0.pck at its root."
    }
    if ($FaultInjection -eq "PckHash") { Invoke-FlipByte (Join-Path $package "Project0.pck") }
    foreach ($entry in $manifest.archive_contents) {
        $actual = Get-Record (Join-Path $package $entry.name)
        $result.archive_contents += [ordered]@{ name = $entry.name; expected_bytes = $entry.bytes; expected_sha256 = $entry.sha256; actual_bytes = $actual.bytes; actual_sha256 = $actual.sha256 }
        if ($actual.bytes -le 0 -or $actual.bytes -ne $entry.bytes -or $actual.sha256 -ne $entry.sha256) { throw "Extracted $($entry.name) hash mismatch." }
    }

    $result.stage = "launch"
    $roaming = Join-Path $root "appdata\roaming"
    $local = Join-Path $root "appdata\local"
    $temp = Join-Path $root "tmp"
    New-Item -ItemType Directory -Path $roaming, $local, $temp | Out-Null
    $probeEvidence = Join-Path $evidence "probe.json"

    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = Join-Path $package "Project0.exe"
    # No --main-pack: the real EXE must mount its adjacent Project0.pck itself.
    $rendererArguments = if ($Windowed) { '--rendering-method gl_compatibility --audio-driver Dummy --resolution 64x64 --position -32000,-32000' } else { '--headless' }
    $start.Arguments = $rendererArguments + $(if ($FaultInjection -eq "ProbeFlag") { "" } else { " -- --verify-package" })
    $start.WorkingDirectory = $package
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($key in @($start.EnvironmentVariables.Keys)) { if ($key -like "PROJECT0_*") { $start.EnvironmentVariables.Remove($key) } }
    $start.EnvironmentVariables["APPDATA"] = $roaming
    $start.EnvironmentVariables["LOCALAPPDATA"] = $local
    $start.EnvironmentVariables["TEMP"] = $temp
    $start.EnvironmentVariables["TMP"] = $temp
    # Existing client config knobs, pinned to loopback/off; the probe never connects.
    $start.EnvironmentVariables["PROJECT0_SERVER_HOST"] = "127.0.0.1"
    $start.EnvironmentVariables["PROJECT0_ENROLLMENT_URL"] = "http://127.0.0.1:9"
    $start.EnvironmentVariables["PROJECT0_NAKAMA_URL"] = "http://127.0.0.1:9"
    $start.EnvironmentVariables["PROJECT0_CLIENT_HTTPS_LOGIN"] = "0"
    $start.EnvironmentVariables["PROJECT0_CLIENT_NAKAMA_LOGIN"] = "0"
    $start.EnvironmentVariables["PROJECT0_CLIENT_NAKAMA_GAMEPLAY"] = "0"
    $start.EnvironmentVariables["PROJECT0_CLIENT_LOGIN_SPLIT"] = "0"
    $start.EnvironmentVariables["PROJECT0_PACKAGE_PROBE_EXPECTED_VERSION"] = $Version
    $start.EnvironmentVariables["PROJECT0_PACKAGE_PROBE_EVIDENCE"] = $probeEvidence
    $client = [Diagnostics.Process]::new()
    $client.StartInfo = $start
    [void]$client.Start()
    $result.client_launched = $true
    $result.client = [ordered]@{ pid = $client.Id; exit_code = $null; timed_out = $false; killed = $false; arguments = $start.Arguments }
    $stdout = $client.StandardOutput.ReadToEndAsync()
    $stderr = $client.StandardError.ReadToEndAsync()
    if (-not $client.WaitForExit($TimeoutSeconds * 1000)) {
        $result.client.timed_out = $true
        throw "Packaged client probe timed out after $TimeoutSeconds seconds."
    }
    $client.WaitForExit()
    $result.client.exit_code = $client.ExitCode

    $result.stage = "evidence"
    if (-not $stdout.Wait(5000) -or -not $stderr.Wait(5000)) { throw "Client output capture did not complete." }
    [IO.File]::WriteAllText((Join-Path $evidence "client.stdout.log"), $stdout.Result)
    [IO.File]::WriteAllText((Join-Path $evidence "client.stderr.log"), $stderr.Result)
    $logText = $stdout.Result + "`n" + $stderr.Result
    foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $root "appdata") -Recurse -File -Force)) {
        $relative = $file.FullName.Substring($root.Length + 1)
        $result.isolated_user_files += $relative
        if ($file.Extension -eq ".log") {
            $copy = Join-Path $evidence ("user-" + ($relative -replace '[\\/:]', '_'))
            Copy-Item -LiteralPath $file.FullName -Destination $copy
            $logText += "`n" + [IO.File]::ReadAllText($file.FullName)
        }
    }
    $result.runtime_error_lines = @([regex]::Matches($logText, '(?m)^\s*(USER SCRIPT ERROR|SCRIPT ERROR|USER ERROR|ERROR)\s*:.*$|^.*(leaked at exit|resources still in use).*$') | ForEach-Object { $_.Value.Trim() } | Select-Object -Unique)
    $result.runtime_warning_lines = @([regex]::Matches($logText, '(?m)^\s*(USER )?WARNING\s*:.*$') | ForEach-Object { $_.Value.Trim() } | Select-Object -Unique)
    if (Test-Path -LiteralPath $probeEvidence) { $result.probe = Get-Content -LiteralPath $probeEvidence -Raw | ConvertFrom-Json }
    if ($null -eq $result.probe) { throw "Packaged client probe wrote no evidence." }
    if (-not $result.probe.passed) { throw "Packaged client probe failed: $($result.probe.failures -join '; ')" }
    if ($result.client.exit_code -ne 0) { throw "Packaged client exited with $($result.client.exit_code)." }
    if ($result.runtime_error_lines.Count -ne 0) { throw "Packaged client reported runtime errors: $($result.runtime_error_lines -join ' | ')" }
    $result.stage = "complete"
    $result.status = "passed"
    $exitCode = 0
}
catch {
    $result.failure = $_.Exception.Message
    Write-Warning $result.failure
}
finally {
    $cleanupFailures = @()
    try {
        # Only the process this script started is ever terminated.
        if ($null -ne $client -and $result.client_launched -and -not $client.HasExited) {
            $client.Kill($true)
            $result.client.killed = $true
            if (-not $client.WaitForExit(10000)) { throw "Owned client process $($client.Id) did not stop." }
        }
    }
    catch { $cleanupFailures += $_.Exception.Message }
    try {
        if ($stdout -and $stderr -and $result.stage -ne "complete" -and -not (Test-Path -LiteralPath (Join-Path $evidence "client.stderr.log"))) {
            if ($stdout.Wait(5000)) { [IO.File]::WriteAllText((Join-Path $evidence "client.stdout.log"), $stdout.Result) }
            if ($stderr.Wait(5000)) { [IO.File]::WriteAllText((Join-Path $evidence "client.stderr.log"), $stderr.Result) }
        }
    }
    catch { $cleanupFailures += $_.Exception.Message }
    try {
        if ($null -ne $client) { $client.Dispose() }
        if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        $result.local_cleanup = -not (Test-Path -LiteralPath $root)
    }
    catch { $cleanupFailures += $_.Exception.Message }
    if ($cleanupFailures.Count -ne 0) {
        $result.cleanup_failure = $cleanupFailures -join "; "
        $result.status = "failed"
        $exitCode = 1
    }
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $evidence "result.json") -Encoding utf8
    Write-Output "Standalone package verification $($result.status): $evidence"
}
exit $exitCode
