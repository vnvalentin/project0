$ErrorActionPreference = "Stop"
$root = Join-Path ([IO.Path]::GetTempPath()) ("project0-fixture-" + [Guid]::NewGuid().ToString("N"))
$scripts = Join-Path $root "scripts"
$artifacts = Join-Path $root "dist\current"
$fixtureRoot = Join-Path $root "build\validation\exp_1100"
try {
    New-Item -ItemType Directory -Path $scripts, $artifacts, $fixtureRoot -Force | Out-Null
    Copy-Item (Join-Path $PSScriptRoot "prepare_windows_experiment_1100.ps1") $scripts
    Copy-Item (Join-Path $PSScriptRoot "generate_1100_fixture.go") $scripts
    $entries = foreach ($name in @("Project0.exe", "Project0.pck", "Project0-Launcher-0.13.0.exe")) {
        $path = Join-Path $artifacts $name
        [IO.File]::WriteAllText($path, "fixture-$name")
        @{ name = $name; sha256 = (Get-FileHash $path -Algorithm SHA256).Hash }
    }
    @{ version = "0.13.0"; artifacts = @($entries) } | ConvertTo-Json -Depth 4 |
        Set-Content (Join-Path $artifacts "deployment-manifest.json") -Encoding UTF8
    $prepare = Join-Path $scripts "prepare_windows_experiment_1100.ps1"
    & $prepare | Out-Null
    $completed = @(Get-ChildItem $fixtureRoot -Directory)
    if ($completed.Count -ne 1 -or $completed[0].Name.StartsWith(".pending-")) {
        throw "Successful fixture was not published as one complete directory."
    }
    $files = @(Get-ChildItem $completed[0].FullName -File)
    if ($files.Count -ne 3) { throw "Unexpected signing outputs." }
    $result = Get-Content (Join-Path $fixtureRoot ($completed[0].Name + ".result.json")) -Raw | ConvertFrom-Json
    if ($result.status -ne "prepared" -or -not $result.staging_removed -or $result.experiment_status -ne "not_executed") {
        throw "Successful preparation evidence is missing or incorrect."
    }
    $before = @($files | Get-FileHash -Algorithm SHA256 | Select-Object Path, Hash) | ConvertTo-Json
    foreach ($scenario in @("version", "hash", "missing", "signing")) {
        $pack = Join-Path $artifacts "Project0.pck"
        $originalPack = [IO.File]::ReadAllBytes($pack)
        try {
            $version = "0.13.0"
            switch ($scenario) {
                "version" { $version = "0.14.0" }
                "hash" { [IO.File]::WriteAllText($pack, "tampered") }
                "missing" { Remove-Item $pack }
                "signing" { [IO.File]::WriteAllText((Join-Path $scripts "generate_1100_fixture.go"), 'package main; func main() { panic("injected signing failure") }') }
            }
            $rejected = $false
            try { & $prepare -Version $version 2>$null | Out-Null }
            catch { $rejected = $true }
            if (-not $rejected) { throw "$scenario failure was accepted." }
            if (@(Get-ChildItem $fixtureRoot -Directory -Force).Count -ne 1) {
                throw "$scenario left a partial fixture or staging directory."
            }
            $after = @($files | Get-FileHash -Algorithm SHA256 | Select-Object Path, Hash) | ConvertTo-Json
            if ($before -ne $after) { throw "$scenario changed the previous complete fixture." }
            $results = @(Get-ChildItem $fixtureRoot -Filter "*.result.json" | ForEach-Object { Get-Content $_.FullName -Raw | ConvertFrom-Json })
            $failed = @($results | Where-Object { $_.status -eq "failed" })
            $expectedFailures = @("version", "hash", "missing", "signing").IndexOf($scenario) + 1
            if ($failed.Count -ne $expectedFailures -or @($failed | Where-Object { -not $_.failure -or -not $_.staging_removed -or $_.cleanup_failure }).Count -ne 0) {
                throw "$scenario lacks accurate durable failure/cleanup evidence."
            }
        }
        finally {
            [IO.File]::WriteAllBytes($pack, $originalPack)
        }
    }
    Write-Output "Fixture lifecycle PASS: publication, version/hash/missing/signing rejection, prior evidence preserved, staging removed."
}
finally {
    if (Test-Path $root) { Remove-Item $root -Recurse -Force }
}