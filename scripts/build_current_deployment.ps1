[CmdletBinding()]
param(
    [ValidatePattern('^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$')]
    [string]$Version,
    [string]$GodotPath,
    [string]$PackageInspectorPath,
    [string]$RceditPath
)

# #1213: builds the standalone Windows client package only. It needs no Go,
# launcher build, or launcher tests, and never deletes dist/current or the
# launcher payload. Output is published to dist/standalone/<version>/ by a single
# directory rename and an existing version is refused, never overwritten. The
# launcher can still be built separately with scripts/build_windows_oneclick.ps1
# from the extracted package. Servers are deployed from published container
# images by scripts/deploy_containers.sh on the host (Slice 108).

$ErrorActionPreference = "Stop"
if (-not $Version) { throw "An explicit -Version is required; it must differ from any published package version." }
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$output = Join-Path $repo "dist\standalone\$Version"
$runId = [Guid]::NewGuid().ToString("N")
$work = Join-Path $repo "build\standalone-$runId"
$exportSource = Join-Path $work "export-source"
$clientStage = Join-Path $work "client"
$packageStage = Join-Path $repo "dist\standalone\.pending-$runId"
$evidence = Join-Path $repo "build\validation\standalone-build-$Version-$runId"
$zipName = "Project0-client-windows-x64-$Version.zip"
if (-not $GodotPath) { $GodotPath = (Get-Command godot -ErrorAction Stop).Source }
if (-not $PackageInspectorPath) { $PackageInspectorPath = $GodotPath }
if (-not $RceditPath) { $RceditPath = Join-Path $repo "build\tools\rcedit\node_modules\rcedit\bin\rcedit-x64.exe" }

function Test-RequiredFile([string]$Path, [string]$Description) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing $Description`: $Path"
    }
    if ((Get-Item -LiteralPath $Path).Length -le 0) {
        throw "Empty $Description`: $Path"
    }
}

function Get-FileRecord([string]$Path) {
    $item = Get-Item -LiteralPath $Path
    return [ordered]@{
        name = $item.Name
        bytes = $item.Length
        sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    }
}

if (Test-Path -LiteralPath $output) { throw "Package output already exists and will not be overwritten: $output" }
Test-RequiredFile $GodotPath "Godot executable"
Test-RequiredFile $RceditPath "rcedit executable (pass -RceditPath)"
$sourceCommit = (& git -C $repo rev-parse HEAD | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $sourceCommit -notmatch '^[0-9a-f]{40}$') { throw "Unable to resolve the full source commit." }
$sourceStatus = @(& git -C $repo status --porcelain)
if ($LASTEXITCODE -ne 0) { throw "Unable to read the source tree status." }

$result = [ordered]@{
    issue = 1213
    host_name = $env:COMPUTERNAME
    version = $Version
    source_commit = $sourceCommit
    status = "failed"
    failure = $null
    export_exit_code = $null
    godot_version = $null
    export_error_lines = @()
    quarantined_package = $null
    staging_removed = $false
}
New-Item -ItemType Directory -Path $evidence | Out-Null
try {
    New-Item -ItemType Directory -Path $work, $clientStage, $packageStage | Out-Null
    $versionProcess = Start-Process -FilePath $GodotPath -ArgumentList @("--version") -Wait -PassThru -NoNewWindow -RedirectStandardOutput (Join-Path $evidence "engine-version.txt") -RedirectStandardError (Join-Path $evidence "engine-version.stderr.log")
    $versionExitCode = $versionProcess.ExitCode
    $versionProcess.Dispose()
    $result.godot_version = [IO.File]::ReadAllText((Join-Path $evidence "engine-version.txt")).Trim()
    $versionErrors = [IO.File]::ReadAllText((Join-Path $evidence "engine-version.stderr.log")).Trim()
    if ($versionExitCode -ne 0 -or $versionErrors -or $result.godot_version -notmatch '^4[.]7[.]2[.]stable([.]|$)') {
        throw "Unqualified Godot engine '$($result.godot_version)'; use the verified 4.7.2 stable editor and matching Windows release template."
    }
    Write-Output "Exporting Godot Windows client $Version from $sourceCommit..."
    $excludedDirectories = @(
        (Join-Path $repo ".git"),
        (Join-Path $repo ".godot"),
        (Join-Path $repo ".scratch"),
        (Join-Path $repo ".venv"),
        (Join-Path $repo "build"),
        (Join-Path $repo "dashboard"),
        (Join-Path $repo "deploy"),
        (Join-Path $repo "docs"),
        (Join-Path $repo "dist"),
        (Join-Path $repo "infra"),
        (Join-Path $repo "logs"),
        (Join-Path $repo "native"),
        (Join-Path $repo "operator_console"),
        (Join-Path $repo "scripts"),
        (Join-Path $repo "server"),
        (Join-Path $repo "tests"),
        (Join-Path $repo "addons\godot-sqlite"),
        (Join-Path $repo "addons\gut")
    )
    $robocopyArgs = @($repo, $exportSource, "/E", "/NFL", "/NDL", "/NJH", "/NJS", "/NP", "/XD") + $excludedDirectories
    & robocopy @robocopyArgs | Out-Null
    if ($LASTEXITCODE -gt 7) {
        throw "Failed to stage the Windows client export source with robocopy (exit code $LASTEXITCODE)."
    }
    $fixtureDirectory = Join-Path $exportSource "server"
    New-Item -ItemType Directory -Path $fixtureDirectory | Out-Null
    Copy-Item -LiteralPath (Join-Path $repo "server\starting_town_hub_fixture.gd") -Destination $fixtureDirectory
    $presetsPath = Join-Path $exportSource "export_presets.cfg"
    $presetsSource = [IO.File]::ReadAllText($presetsPath)
    $exclusionPattern = '(?m)^exclude_filter="server/\*\*,'
    if ([regex]::Matches($presetsSource, $exclusionPattern).Count -ne 1) {
        throw "Standalone server exclusion is missing or ambiguous."
    }
    $presetsSource = [regex]::Replace($presetsSource, $exclusionPattern, 'exclude_filter="')
    [IO.File]::WriteAllText($presetsPath, $presetsSource, [Text.UTF8Encoding]::new($false))
    $versionScript = Join-Path $exportSource "shared\client_build_version.gd"
    $versionSource = [IO.File]::ReadAllText($versionScript)
    $versionPattern = '(?m)^const CLIENT_BUILD_VERSION: String = "[^"]*"'
    if ([regex]::Matches($versionSource, $versionPattern).Count -ne 1) {
        throw "Client version assignment is missing or ambiguous."
    }
    $versionSource = [regex]::Replace($versionSource, $versionPattern, ('const CLIENT_BUILD_VERSION: String = "{0}"' -f $Version))
    [IO.File]::WriteAllText($versionScript, $versionSource, [Text.UTF8Encoding]::new($false))
    $clientExe = Join-Path $clientStage "Project0.exe"
    $clientPck = Join-Path $clientStage "Project0.pck"
    $godotProcess = Start-Process -FilePath $GodotPath -ArgumentList @(
        "--headless", "--path", "`"$exportSource`"", "--export-release", '"Windows Desktop"', "`"$clientExe`""
    ) -Wait -PassThru -NoNewWindow -RedirectStandardOutput (Join-Path $evidence "export.stdout.log") -RedirectStandardError (Join-Path $evidence "export.stderr.log")
    $exportExitCode = $godotProcess.ExitCode
    $result.export_exit_code = $exportExitCode
    $godotProcess.Dispose()
    $exportLog = [IO.File]::ReadAllText((Join-Path $evidence "export.stdout.log")) + "`n" + [IO.File]::ReadAllText((Join-Path $evidence "export.stderr.log"))
    $result.export_error_lines = @([regex]::Matches($exportLog, '(?m)^\s*(USER SCRIPT ERROR|SCRIPT ERROR|USER ERROR|ERROR)\s*:.*$|^.*(leaked at exit|resources still in use).*$') | ForEach-Object { $_.Value.Trim() })
    if ($exportExitCode -ne 0) { throw "Godot export failed: $exportExitCode" }
    Test-RequiredFile $clientExe "Godot client executable"
    Test-RequiredFile $clientPck "Godot client PCK"
    $boundaryEvidence = Join-Path $evidence "package-boundary.json"
    & pwsh -NoProfile -NonInteractive -File (Join-Path $PSScriptRoot "check_windows_client_package.ps1") -PackPath $clientPck -GodotPath $PackageInspectorPath -OutputPath $boundaryEvidence
    if ($LASTEXITCODE -ne 0) { throw "Standalone package dependency boundary failed: $boundaryEvidence" }
    $rceditVersion = "$Version.0"
    & $RceditPath $clientExe --set-file-version $rceditVersion --set-product-version $rceditVersion
    if ($LASTEXITCODE -ne 0) { throw "rcedit failed with exit code $LASTEXITCODE." }
    Test-RequiredFile $clientExe "resource-edited client executable"

    Write-Output "Creating portable client archive..."
    $zipPath = Join-Path $packageStage $zipName
    Compress-Archive -Path $clientExe, $clientPck -DestinationPath $zipPath -CompressionLevel Optimal
    Test-RequiredFile $zipPath "client archive"
    $manifest = [ordered]@{
        package = "standalone-windows-client"
        version = $Version
        built_at_utc = (Get-Date).ToUniversalTime().ToString("o")
        source_commit = $sourceCommit
        source_tree_dirty = $sourceStatus.Count -gt 0
        godot_export_exit_code = $exportExitCode
        godot_version = $result.godot_version
        release_eligible = $result.export_error_lines.Count -eq 0
        export_error_lines = $result.export_error_lines
        archive = Get-FileRecord $zipPath
        archive_contents = @((Get-FileRecord $clientExe), (Get-FileRecord $clientPck))
    }
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $packageStage "deployment-manifest.json") -Encoding utf8

    Remove-Item -LiteralPath $work -Recurse -Force
    if ($result.export_error_lines.Count -ne 0) {
        $result.quarantined_package = Join-Path $evidence "quarantined-package"
        [IO.Directory]::Move($packageStage, $result.quarantined_package)
        throw "Godot export reported error diagnostics; package quarantined at $($result.quarantined_package)."
    }
    # Directory.Move refuses an existing destination, so a concurrent build cannot be replaced.
    [IO.Directory]::Move($packageStage, $output)
    $result.status = "packaged"
    Write-Output "Standalone package ready: $output"
    Get-ChildItem -LiteralPath $output -File | Select-Object Name, Length
}
catch {
    $result.failure = $_.Exception.Message
    throw
}
finally {
    try {
        foreach ($path in @($work, $packageStage)) {
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force }
        }
        $result.staging_removed = $true
    }
    catch {
        $result.status = "failed"
        $result.failure = "Staging cleanup failed: $($_.Exception.Message)"
        throw
    }
    finally {
        $result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $evidence "result.json") -Encoding utf8
    }
}
