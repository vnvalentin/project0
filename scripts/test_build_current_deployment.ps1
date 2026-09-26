$ErrorActionPreference = "Stop"
# #1213: standalone Windows client packaging must not need Go or the launcher,
# must package a fresh export with full provenance, and must never replace or
# delete existing outputs. Runs the real build script in a throwaway fixture
# repository with fake Godot/rcedit/go/launcher tools.
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
$evidence = Join-Path $PSScriptRoot "..\build\validation\standalone-packaging-tests-$runId.json"
$testResult = [ordered]@{ issue = 1213; host_name = $env:COMPUTERNAME; status = "failed"; failure = $null; cleanup = $false; failure_cases = 0 }

function Invoke-Build([string]$Version, [string]$Rcedit = $rcedit) {
    $output = & pwsh -NoProfile -File $build -Version $Version -GodotPath $godot -RceditPath $Rcedit 2>&1 | Out-String
    return @{ ExitCode = $LASTEXITCODE; Output = $output }
}

function Get-Fingerprint([string[]]$Paths) {
    return (@($Paths | ForEach-Object { "$_=" + (Get-FileHash $_ -Algorithm SHA256).Hash }) -join "`n")
}

try {
    Remove-Item Env:FAKE_GODOT_MODE, Env:FAKE_RCEDIT_FAIL -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path (Join-Path $repo "scripts"), (Join-Path $repo "shared"), (Join-Path $repo "server"), $bin,
        (Join-Path $repo "dist\current"), (Join-Path $repo "native\windows_launcher\payload") | Out-Null
    Copy-Item (Join-Path $PSScriptRoot "build_current_deployment.ps1") (Join-Path $repo "scripts")
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
    # The PCK is the staged version script, proving a fresh export of stamped source.
    [IO.File]::WriteAllText($godot, (@(
        '@echo off'
        "echo godot %*>>`"$toolLog`""
        'if "%FAKE_GODOT_MODE%"=="fail" exit /b 7'
        'if not exist "%~3\server\starting_town_hub_fixture.gd" exit /b 12'
        'if exist "%~3\server\server_only_sentinel.gd" exit /b 13'
        'findstr /l /c:"server/**" "%~3\export_presets.cfg" >nul'
        'if not errorlevel 1 exit /b 14'
        'if not "%FAKE_GODOT_MODE%"=="noexe" echo fake-godot-exe>"%~6"'
        'if "%FAKE_GODOT_MODE%"=="emptyexe" type nul>"%~6"'
        'if not "%FAKE_GODOT_MODE%"=="nopck" copy /y "%~3\shared\client_build_version.gd" "%~dpn6.pck" >nul'
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
    $protected = @((Join-Path $repo "dist\current\Project0.pck"), (Join-Path $repo "native\windows_launcher\payload\Project0.pck"))
    $protectedBefore = Get-Fingerprint $protected
    $env:PATH = "$bin;$savedPath"

    $result = Invoke-Build "0.14.0"
    if ($result.ExitCode -ne 0) { throw "Standalone build failed ($($result.ExitCode)):`n$($result.Output)" }
    $out = Join-Path $repo "dist\standalone\0.14.0"
    $zipName = "Project0-client-windows-x64-0.14.0.zip"
    $names = @(Get-ChildItem $out -Force | ForEach-Object Name | Sort-Object)
    if (($names -join ",") -ne "deployment-manifest.json,$zipName") { throw "Unexpected package output: $($names -join ',')" }
    $manifest = Get-Content (Join-Path $out "deployment-manifest.json") -Raw | ConvertFrom-Json
    if ($manifest.version -ne "0.14.0" -or $manifest.source_commit -ne $commit -or $manifest.source_tree_dirty -ne $false) {
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

    $package = @(Get-ChildItem $out -File | ForEach-Object FullName)
    $packageBefore = Get-Fingerprint $package
    $failures = [ordered]@{
        "export-exit" = @{ Mode = "fail"; Expect = "Godot export failed: 7" }
        "export-diagnostics" = @{ Mode = "error"; Expect = "Godot export reported error diagnostics" }
        "missing-exe" = @{ Mode = "noexe"; Expect = "Missing Godot client executable" }
        "missing-pck" = @{ Mode = "nopck"; Expect = "Missing Godot client PCK" }
        "empty-exe" = @{ Mode = "emptyexe"; Expect = "Empty Godot client executable" }
        "empty-pck" = @{ Mode = "emptypck"; Expect = "Empty Godot client PCK" }
        "rcedit-exit" = @{ RceditFail = "1"; Expect = "rcedit failed with exit code 5" }
        "rcedit-missing" = @{ Rcedit = (Join-Path $bin "absent-rcedit.exe"); Expect = "Missing rcedit executable" }
        "version-collision" = @{ Version = "0.14.0"; Expect = "already exists and will not be overwritten" }
    }
    foreach ($case in $failures.Keys) {
        $spec = $failures[$case]
        $env:FAKE_GODOT_MODE = $spec.Mode
        $env:FAKE_RCEDIT_FAIL = $spec.RceditFail
        try {
            $version = if ($spec.Version) { $spec.Version } else { "0.15.0" }
            $rceditArg = if ($spec.Rcedit) { $spec.Rcedit } else { $rcedit }
            $godotCallsBefore = @(Get-Content $toolLog | Where-Object { $_ -like "godot *" }).Count
            $result = Invoke-Build $version $rceditArg
        }
        finally {
            Remove-Item Env:FAKE_GODOT_MODE, Env:FAKE_RCEDIT_FAIL -ErrorAction SilentlyContinue
        }
        if ($result.ExitCode -eq 0) { throw "$case was accepted." }
        if (-not ($result.Output -replace '\s+', ' ').Contains($spec.Expect)) { throw "$case failed for the wrong reason:`n$($result.Output)" }
        if (Test-Path (Join-Path $repo "dist\standalone\0.15.0")) { throw "$case published a package." }
        if ((Get-Fingerprint $package) -ne $packageBefore -or @(Get-ChildItem $out -Force).Count -ne 2) {
            throw "$case changed the existing 0.14.0 package."
        }
        if ($case -eq "version-collision" -and @(Get-Content $toolLog | Where-Object { $_ -like "godot *" }).Count -ne $godotCallsBefore) {
            throw "Version collision exported before refusing."
        }
        & $checkClean $case
        $testResult.failure_cases++
    }
    $log = Get-Content $toolLog -Raw
    if ($log -match "go invoked|npm invoked|launcher invoked") { throw "Standalone build invoked Go, npm, or the launcher:`n$log" }

    Write-Output "Standalone packaging PASS: fresh export, no Go/npm/launcher, provenance manifest matches ZIP, protected outputs preserved; $($failures.Count) failure cases rejected without publishing or leaving staging."
    $testResult.status = "passed"
}
catch {
    $testResult.failure = $_.Exception.Message
    throw
}
finally {
    $env:PATH = $savedPath
    $env:FAKE_GODOT_MODE = $savedGodotMode
    $env:FAKE_RCEDIT_FAIL = $savedRceditFail
    try {
        if (Test-Path $root) { Remove-Item $root -Recurse -Force }
        $testResult.cleanup = -not (Test-Path $root)
    }
    catch {
        $testResult.status = "failed"
        $testResult.failure = "Fixture cleanup failed: $($_.Exception.Message)"
        throw
    }
    finally {
        New-Item -ItemType Directory -Force -Path (Split-Path $evidence) | Out-Null
        $testResult | ConvertTo-Json | Set-Content -LiteralPath $evidence -Encoding utf8
    }
}
