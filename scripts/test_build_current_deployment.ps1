[CmdletBinding()]
param(
    [string]$GodotPath,
    [ValidateSet('pwsh', 'powershell')][string]$BuildShell = 'pwsh'
)

$ErrorActionPreference = "Stop"
# #1213: standalone Windows client packaging must not need Go or the launcher,
# must package a fresh export with full provenance, and must never replace or
# delete existing outputs. Runs the real build script in a throwaway fixture
# repository with fake export/rcedit/go/launcher tools and a real native PCK audit.
$runId = [Guid]::NewGuid().ToString("N")
$root = Join-Path ([IO.Path]::GetTempPath()) ("project0 package fixture-" + $runId)
$repo = Join-Path $root "repo"
$bin = Join-Path $root "bin"
$toolLog = Join-Path $root "tools.log"
$build = Join-Path $repo "scripts\build_current_deployment.ps1"
$godot = Join-Path $bin "godot.cmd"
$rcedit = Join-Path $bin "rcedit.cmd"
$savedPath = $env:PATH
$savedGodotMode = $env:FAKE_GODOT_MODE
$savedRceditFail = $env:FAKE_RCEDIT_FAIL
$savedGodotVersion = $env:FAKE_GODOT_VERSION
$evidence = Join-Path $PSScriptRoot "..\build\validation\standalone-packaging-tests-$runId.json"
$evidenceRoot = [IO.Path]::GetFullPath([IO.Path]::ChangeExtension($evidence, $null))
$sourceRepo = Split-Path $PSScriptRoot -Parent
$activeCase = $null
$testResult = [ordered]@{ issue = 1244; host_name = $env:COMPUTERNAME; status = "failed"; failure = $null; cleanup = $false; failure_cases = 0; runtime_acceptance = $false; dependencies = @('godot-client', 'powershell', 'git') }
$testResult.build_shell = $BuildShell
$testResult.command = @((Get-Process -Id $PID).Path, '-NoProfile', '-File', $PSCommandPath, '-GodotPath', $GodotPath, '-BuildShell', $BuildShell)
$testResult.evidence_root = $evidenceRoot
$testResult.fixture_root = $root
$testResult.expected_cases = 12
$testResult.cases = @('success', 'unqualified-engine', 'export-exit', 'export-diagnostics', 'missing-exe', 'missing-pck', 'empty-exe', 'empty-pck', 'package-persistence', 'rcedit-exit', 'rcedit-missing', 'version-collision') | ForEach-Object {
    [ordered]@{ name = $_; status = 'not-run'; expected_acceptance = ($_ -eq 'success'); command = $null; exit_code = $null; artifacts = @() }
}

function Invoke-Build([string]$Version, [string]$Rcedit = $rcedit, [string]$CaseName) {
    $record = $testResult.cases | Where-Object { $_.name -eq $CaseName }
    $record.status = 'running'
    $caseEvidence = Join-Path $evidenceRoot $CaseName
    New-Item -ItemType Directory -Path $caseEvidence | Out-Null
    $validationRoot = Join-Path $repo 'build/validation'
    $before = @(Get-ChildItem $validationRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object Name)
    $arguments = @('-NoProfile', '-NonInteractive', '-File', $build, '-Version', $Version, '-GodotPath', $godot, '-PackageInspectorPath', $GodotPath, '-RceditPath', $Rcedit)
    $record.command = @($testResult.tools.build_shell.path) + $arguments
    $record.environment = [ordered]@{
        FAKE_GODOT_MODE = $env:FAKE_GODOT_MODE
        FAKE_RCEDIT_FAIL = $env:FAKE_RCEDIT_FAIL
        FAKE_GODOT_VERSION = $env:FAKE_GODOT_VERSION
    }
    $output = ''
    try {
        $output = & $BuildShell @arguments 2>&1 | Out-String
        $record.exit_code = $LASTEXITCODE
    }
    finally {
        [IO.File]::WriteAllText((Join-Path $caseEvidence 'build.log'), $output)
        if (Test-Path $toolLog) { Copy-Item $toolLog (Join-Path $caseEvidence 'tool-invocations.log') }
        foreach ($directory in @(Get-ChildItem $validationRoot -Directory -ErrorAction SilentlyContinue | Where-Object Name -NotIn $before)) {
            Copy-Item $directory.FullName (Join-Path $caseEvidence $directory.Name) -Recurse
        }
        $packageManifest = Join-Path $repo "dist/standalone/$Version/deployment-manifest.json"
        if (Test-Path $packageManifest) { Copy-Item $packageManifest (Join-Path $caseEvidence 'observed-package-manifest.json') }
        $record.artifacts = @(Get-ChildItem $caseEvidence -Recurse -File | ForEach-Object {
            @{ path = $_.FullName; bytes = $_.Length; sha256 = (Get-FileHash $_.FullName).Hash }
        })
    }
    return @{ ExitCode = $record.exit_code; Output = $output; Case = $record }
}

function Get-Fingerprint([string[]]$Paths) {
    return (@($Paths | ForEach-Object { "$_=" + (Get-FileHash $_ -Algorithm SHA256).Hash }) -join "`n")
}

try {
    New-Item -ItemType Directory -Path $evidenceRoot | Out-Null
    if (-not $GodotPath) { $GodotPath = (Get-Command godot -ErrorAction Stop).Source }
    $GodotPath = (Resolve-Path -LiteralPath $GodotPath).Path
    $testResult.command[5] = $GodotPath
    $testResult.source_commit = (& git -C $sourceRepo rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Unable to identify validation source commit' }
    $testResult.source_tree_dirty = @(& git -C $sourceRepo status --porcelain --untracked-files=no).Count -ne 0
    if ($LASTEXITCODE -ne 0) { throw 'Unable to identify validation source changes' }
    $testResult.source_files = @('scripts/test_build_current_deployment.ps1', 'scripts/build_current_deployment.ps1', 'scripts/check_windows_client_package.ps1', 'scripts/client_package_inventory.gd', 'scripts/validation_ownership.json', 'tests/fixtures/windows_client_packages.gd', 'shared/client_build_version.gd', 'server/starting_town_hub_fixture.gd', 'export_presets.cfg') | ForEach-Object {
        @{ path = $_; sha256 = (Get-FileHash (Join-Path $sourceRepo $_)).Hash }
    }
    $shellPath = (Get-Command $BuildShell -CommandType Application | Select-Object -First 1).Source
    $shellVersion = & $shellPath -NoProfile -NonInteractive -Command '$PSVersionTable.PSVersion.ToString()'
    if ($LASTEXITCODE -ne 0) { throw 'Unable to identify build shell version' }
    $testResult.tools = @{
        build_shell = @{ path = $shellPath; version = [string]$shellVersion; sha256 = (Get-FileHash $shellPath).Hash }
        package_inspector = @{ path = $GodotPath; sha256 = (Get-FileHash $GodotPath).Hash }
    }
    foreach ($toolName in @('runner', 'audit_pwsh')) {
        $toolPath = if ($toolName -eq 'runner') { (Get-Process -Id $PID).Path } else { (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source }
        $testResult.tools[$toolName] = @{ path = $toolPath; version = [Diagnostics.FileVersionInfo]::GetVersionInfo($toolPath).ProductVersion; sha256 = (Get-FileHash $toolPath).Hash }
    }
    Remove-Item Env:FAKE_GODOT_MODE, Env:FAKE_RCEDIT_FAIL, Env:FAKE_GODOT_VERSION -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path (Join-Path $repo "scripts"), (Join-Path $repo "shared"), (Join-Path $repo "server"), $bin,
        (Join-Path $repo "dist\current"), (Join-Path $repo "native\windows_launcher\payload") | Out-Null
    Copy-Item (Join-Path $PSScriptRoot "build_current_deployment.ps1") (Join-Path $repo "scripts")
    foreach ($name in @('check_windows_client_package.ps1', 'client_package_inventory.gd', 'validation_ownership.json')) {
        Copy-Item (Join-Path $PSScriptRoot $name) (Join-Path $repo 'scripts')
    }
    $packFixture = Join-Path $root 'pack-fixture.gd'
    Copy-Item (Join-Path $PSScriptRoot '../tests/fixtures/windows_client_packages.gd') $packFixture
    Copy-Item (Join-Path $PSScriptRoot "..\shared\client_build_version.gd") (Join-Path $repo "shared")
    Copy-Item (Join-Path $PSScriptRoot "..\server\starting_town_hub_fixture.gd") (Join-Path $repo "server")
    Copy-Item (Join-Path $PSScriptRoot "..\export_presets.cfg") $repo
    [IO.File]::WriteAllText((Join-Path $repo "server\server_only_sentinel.gd"), "server-only")
    [IO.File]::WriteAllText((Join-Path $repo "project.godot"), "config_version=5`n")
    [IO.File]::WriteAllText((Join-Path $repo ".gitignore"), "dist/`nbuild/`nnative/windows_launcher/payload/`n")
    [IO.File]::WriteAllText((Join-Path $repo "scripts\build_windows_oneclick.ps1"), "Add-Content '$toolLog' 'launcher invoked'; throw 'launcher must not run'")
    foreach ($tool in @("go", "npm")) {
        [IO.File]::WriteAllText((Join-Path $bin "$tool.cmd"), "@echo off`r`necho $tool invoked>>`"$toolLog`"`r`nexit /b 1`r`n")
    }
    # Fake Godot: args are --headless --path <source> --export-release "Windows Desktop" <exe>.
    # Native PCK fixtures contain the staged version script; the package gate stays real.
    [IO.File]::WriteAllText($godot, (@(
        '@echo off'
        'if "%~1"=="--version" ('
        '  if defined FAKE_GODOT_VERSION (echo %FAKE_GODOT_VERSION%) else (echo 4.7.2.stable.official.ed1daf0bf)'
        '  exit /b 0'
        ')'
        "echo godot %*>>`"$toolLog`""
        'if "%FAKE_GODOT_MODE%"=="fail" exit /b 7'
        'if not exist "%~3\server\starting_town_hub_fixture.gd" exit /b 12'
        'if exist "%~3\server\server_only_sentinel.gd" exit /b 13'
        'findstr /l /c:"server/**" "%~3\export_presets.cfg" >nul'
        'if not errorlevel 1 exit /b 14'
        'if not "%FAKE_GODOT_MODE%"=="noexe" echo fake-godot-exe>"%~6"'
        'if "%FAKE_GODOT_MODE%"=="emptyexe" type nul>"%~6"'
        "if not `"%FAKE_GODOT_MODE%`"==`"nopck`" `"$GodotPath`" --headless --path `"%~3`" --script `"$packFixture`" -- `"%~3`" `"%~dpn6.pck`" `"%FAKE_GODOT_MODE%`""
        'if not "%FAKE_GODOT_MODE%"=="nopck" if errorlevel 1 exit /b 15'
        'if "%FAKE_GODOT_MODE%"=="emptypck" type nul>"%~dpn6.pck"'
        'if "%FAKE_GODOT_MODE%"=="error" echo ERROR: injected export diagnostic 1>&2'
        'exit /b 0'
    ) -join "`r`n") + "`r`n")
    [IO.File]::WriteAllText($rcedit, (@(
        '@echo off'
        "echo rcedit %*>>`"$toolLog`""
        'if "%FAKE_RCEDIT_FAIL%"=="1" exit /b 5'
        'echo rcedit-stamped %3>>"%~1"'
        'exit /b 0'
    ) -join "`r`n") + "`r`n")
    [IO.File]::WriteAllText((Join-Path $repo "dist\current\Project0.pck"), "previous-current-pck")
    [IO.File]::WriteAllText((Join-Path $repo "native\windows_launcher\payload\Project0.pck"), "launcher-payload-pck")
    & git -C $repo init -q
    & git -C $repo add -A
    & git -C $repo -c user.name=fixture -c user.email=fixture@invalid commit -q -m fixture
    if ($LASTEXITCODE -ne 0) { throw "Fixture repository commit failed." }
    $commit = (& git -C $repo rev-parse HEAD).Trim()
    $generatedTools = Join-Path $evidenceRoot 'generated-tools'
    New-Item -ItemType Directory -Path $generatedTools | Out-Null
    $testResult.generated_tools = @(@($godot, $rcedit, $packFixture, (Join-Path $bin 'go.cmd'), (Join-Path $bin 'npm.cmd')) | ForEach-Object {
        $retained = Join-Path $generatedTools (Split-Path $_ -Leaf)
        Copy-Item $_ $retained
        @{ original_path = $_; retained_path = $retained; sha256 = (Get-FileHash $retained).Hash }
    })
    $protected = @((Join-Path $repo "dist\current\Project0.pck"), (Join-Path $repo "native\windows_launcher\payload\Project0.pck"))
    $protectedBefore = Get-Fingerprint $protected
    $env:PATH = "$bin;$savedPath"

    $activeCase = 'success'
    $result = Invoke-Build "0.14.0" -CaseName $activeCase
    if ($result.ExitCode -ne 0) { throw "Standalone build failed ($($result.ExitCode)):`n$($result.Output)" }
    $out = Join-Path $repo "dist\standalone\0.14.0"
    $zipName = "Project0-client-windows-x64-0.14.0.zip"
    $names = @(Get-ChildItem $out -Force | ForEach-Object Name | Sort-Object)
    if (($names -join ",") -ne "deployment-manifest.json,$zipName") { throw "Unexpected package output: $($names -join ',')" }
    $manifest = Get-Content (Join-Path $out "deployment-manifest.json") -Raw | ConvertFrom-Json
    if ($manifest.version -ne "0.14.0" -or $manifest.source_commit -ne $commit -or $manifest.source_tree_dirty -ne $false -or $manifest.godot_version -ne "4.7.2.stable.official.ed1daf0bf") {
        throw "Manifest identity/provenance is wrong: $($manifest | ConvertTo-Json -Depth 5)"
    }
    $zip = Get-Item (Join-Path $out $zipName)
    if ($manifest.archive.name -ne $zipName -or $manifest.archive.bytes -ne $zip.Length -or
        $manifest.archive.sha256 -ne (Get-FileHash $zip.FullName -Algorithm SHA256).Hash) {
        throw "Manifest archive entry does not match the ZIP."
    }
    $extracted = Join-Path $root "extracted"
    Expand-Archive $zip.FullName $extracted
    $files = @(Get-ChildItem $extracted -Recurse -File | Sort-Object Name)
    if ((($files | ForEach-Object Name) -join ",") -ne "Project0.exe,Project0.pck") { throw "ZIP payload is not exactly Project0.exe and Project0.pck." }
    foreach ($file in $files) {
        $entry = @($manifest.archive_contents | Where-Object name -eq $file.Name)
        if ($entry.Count -ne 1 -or $entry[0].bytes -ne $file.Length -or $file.Length -le 0 -or
            $entry[0].sha256 -ne (Get-FileHash $file.FullName -Algorithm SHA256).Hash) {
            throw "Manifest entry for $($file.Name) does not match the extracted ZIP."
        }
    }
    if (@($manifest.archive_contents).Count -ne 2) { throw "Manifest lists unexpected archive contents." }
    if (-not (Get-Content (Join-Path $extracted "Project0.pck") -Raw).Contains('const CLIENT_BUILD_VERSION: String = "0.14.0"')) {
        throw "Packaged PCK was not exported from source stamped with the requested version."
    }
    if (-not (Get-Content (Join-Path $extracted "Project0.exe") -Raw).Contains("rcedit-stamped")) {
        throw "Packaged EXE is not the resource-edited executable."
    }
    $checkClean = {
        param([string]$Case)
        if (@(& git -C $repo status --porcelain).Count -ne 0) { throw "$Case modified tracked source files." }
        if ((Test-Path (Join-Path $repo "build")) -and @(Get-ChildItem (Join-Path $repo "build") -Force | Where-Object Name -ne "validation").Count -ne 0) {
            throw "$Case left owned staging behind."
        }
        if (@(Get-ChildItem (Join-Path $repo "dist\standalone") -Filter ".pending-*" -Force -ErrorAction SilentlyContinue).Count -ne 0) { throw "$Case left package staging behind." }
        if ((Get-Fingerprint $protected) -ne $protectedBefore) { throw "$Case changed dist/current or the launcher payload." }
    }
    & $checkClean "success"
    $result.Case.status = 'passed'

    $package = @(Get-ChildItem $out -File | ForEach-Object FullName)
    $packageBefore = Get-Fingerprint $package
    $failures = [ordered]@{
        "unqualified-engine" = @{ EngineVersion = "4.3.stable.official.77dcf97d8"; Expect = "Unqualified Godot engine" }
        "export-exit" = @{ Mode = "fail"; Expect = "Godot export failed: 7" }
        "export-diagnostics" = @{ Mode = "error"; Expect = "Godot export reported error diagnostics" }
        "missing-exe" = @{ Mode = "noexe"; Expect = "Missing Godot client executable" }
        "missing-pck" = @{ Mode = "nopck"; Expect = "Missing Godot client PCK" }
        "empty-exe" = @{ Mode = "emptyexe"; Expect = "Empty Godot client executable" }
        "empty-pck" = @{ Mode = "emptypck"; Expect = "Empty Godot client PCK" }
        "package-persistence" = @{ Mode = "persistence"; Expect = "Standalone package dependency boundary failed" }
        "rcedit-exit" = @{ RceditFail = "1"; Expect = "rcedit failed with exit code 5" }
        "rcedit-missing" = @{ Rcedit = (Join-Path $bin "absent-rcedit.exe"); Expect = "Missing rcedit executable" }
        "version-collision" = @{ Version = "0.14.0"; Expect = "already exists and will not be overwritten" }
    }
    foreach ($case in $failures.Keys) {
        $activeCase = $case
        $spec = $failures[$case]
        ($testResult.cases | Where-Object { $_.name -eq $case }).expected_failure = $spec.Expect
        $env:FAKE_GODOT_MODE = $spec.Mode
        $env:FAKE_RCEDIT_FAIL = $spec.RceditFail
        $env:FAKE_GODOT_VERSION = $spec.EngineVersion
        try {
            $version = if ($spec.Version) { $spec.Version } else { "0.15.0" }
            $rceditArg = if ($spec.Rcedit) { $spec.Rcedit } else { $rcedit }
            $godotCallsBefore = @(Get-Content $toolLog | Where-Object { $_ -like "godot *" }).Count
            $result = Invoke-Build $version $rceditArg -CaseName $activeCase
        }
        finally {
            Remove-Item Env:FAKE_GODOT_MODE, Env:FAKE_RCEDIT_FAIL, Env:FAKE_GODOT_VERSION -ErrorAction SilentlyContinue
        }
        if ($result.ExitCode -eq 0) { throw "$case was accepted." }
        if (-not ($result.Output -replace '\s+', ' ').Contains($spec.Expect)) { throw "$case failed for the wrong reason:`n$($result.Output)" }
        if (Test-Path (Join-Path $repo "dist\standalone\0.15.0")) { throw "$case published a package." }
        if ((Get-Fingerprint $package) -ne $packageBefore -or @(Get-ChildItem $out -Force).Count -ne 2) {
            throw "$case changed the existing 0.14.0 package."
        }
        if ($case -in @("version-collision", "unqualified-engine") -and @(Get-Content $toolLog | Where-Object { $_ -like "godot *" }).Count -ne $godotCallsBefore) {
            throw "$case exported before refusing."
        }
        & $checkClean $case
        $result.Case.status = 'passed'
        $testResult.failure_cases++
    }
    $log = Get-Content $toolLog -Raw
    if ($log -match "go invoked|npm invoked|launcher invoked") { throw "Standalone build invoked Go, npm, or the launcher:`n$log" }

    Write-Output "Standalone packaging PASS: fresh export, no Go/npm/launcher, provenance manifest matches ZIP, protected outputs preserved; $($failures.Count) failure cases rejected without publishing or leaving staging."
    $testResult.status = "passed"
}
catch {
    $testResult.failure = $_.Exception.Message
    if ($activeCase) {
        $failedCase = $testResult.cases | Where-Object { $_.name -eq $activeCase }
        $failedCase.status = 'failed'
        $failedCase.failure = $_.Exception.Message
    }
    throw
}
finally {
    $env:PATH = $savedPath
    $env:FAKE_GODOT_MODE = $savedGodotMode
    $env:FAKE_RCEDIT_FAIL = $savedRceditFail
    $env:FAKE_GODOT_VERSION = $savedGodotVersion
    try {
        if (Test-Path $root) { Remove-Item $root -Recurse -Force }
        $testResult.cleanup = -not (Test-Path $root)
        foreach ($caseRecord in @($testResult.cases | Where-Object { $_.status -eq 'passed' })) {
            if ($caseRecord.artifacts.Count -eq 0) { throw "$($caseRecord.name) retained no evidence" }
            foreach ($artifact in $caseRecord.artifacts) {
                if (-not (Test-Path $artifact.path) -or (Get-FileHash $artifact.path).Hash -ne $artifact.sha256) { throw "$($caseRecord.name) retained evidence is missing or changed" }
            }
        }
        if ($testResult.status -eq 'passed') {
            if (@($testResult.cases | Where-Object { $_.status -eq 'passed' }).Count -ne $testResult.expected_cases) { throw 'Builder case accounting is incomplete' }
            foreach ($tool in $testResult.generated_tools) {
                if ((Get-FileHash $tool.retained_path).Hash -ne $tool.sha256) { throw 'Generated tool evidence is missing or changed' }
            }
            if ($testResult.command[4] -ne '-GodotPath' -or $testResult.command[5] -ne $GodotPath -or $testResult.command[6] -ne '-BuildShell' -or $testResult.command[7] -ne $BuildShell) { throw 'Recorded invocation is incorrect' }
            foreach ($auditCase in @('success', 'package-persistence')) {
                $audits = @(Get-ChildItem (Join-Path $evidenceRoot $auditCase) -Filter package-boundary.json -Recurse)
                if ($audits.Count -ne 1) { throw "$auditCase retained no unique native audit" }
                $audit = Get-Content $audits[0].FullName -Raw | ConvertFrom-Json
                if ($audit.passed -ne ($auditCase -eq 'success') -or -not $audit.cleanup) { throw "$auditCase retained incorrect native audit evidence" }
            }
        }
    }
    catch {
        $testResult.status = "failed"
        $testResult.cleanup_or_evidence_failure = $_.Exception.Message
        if (-not $testResult.failure) { $testResult.failure = "Fixture cleanup/evidence failed: $($_.Exception.Message)" }
        throw
    }
    finally {
        New-Item -ItemType Directory -Force -Path (Split-Path $evidence) | Out-Null
        if ($testResult.status -ne 'passed' -and -not $testResult.failure) { $testResult.failure = 'Validation interrupted before completing all cases' }
        foreach ($caseRecord in @($testResult.cases | Where-Object { $_.status -eq 'running' })) {
            $caseRecord.status = 'interrupted'
            $caseRecord.failure = $testResult.failure
        }
        $testResult.executed_cases = @($testResult.cases | Where-Object { $_.status -ne 'not-run' }).Count
        $testResult.passed_cases = @($testResult.cases | Where-Object { $_.status -eq 'passed' }).Count
        $testResult | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $evidence -Encoding utf8
        Write-Output "Builder evidence: $evidence"
    }
}
