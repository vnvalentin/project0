param(
    [string]$ServerHost = $(if ($env:PROJECT0_SERVER_HOST) { $env:PROJECT0_SERVER_HOST } else { "okami" }),
    [string]$RemotePath = $(if ($env:PROJECT0_SERVER_PATH) { $env:PROJECT0_SERVER_PATH } else { "/data/code/project0" }),
    [ValidateSet("native", "docker-candidate", "docker-split")]
    [string]$Mode = $(if ($env:PROJECT0_SERVER_MODE) { $env:PROJECT0_SERVER_MODE } else { "native" }),
    [switch]$SkipCleanCheck
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$archive = Join-Path $repo "build\server-deployment.tar.gz"
$commit = (& git -C $repo rev-parse --verify HEAD).Trim()
$dirty = @(& git -C $repo status --short)

if (-not $SkipCleanCheck -and $dirty.Count -gt 0) {
    throw "Server deployment requires a clean worktree. Commit or explicitly use -SkipCleanCheck."
}

$sshArgs = @("-o", "BatchMode=yes", "-o", "ConnectTimeout=10", $ServerHost)
$remote = "$((Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss'))-$commit"
$remoteBackup = "$RemotePath.backup.$remote"

New-Item -ItemType Directory -Force -Path (Split-Path $archive) | Out-Null
if (Test-Path $archive) { Remove-Item $archive -Force }

Write-Output "Creating source archive for commit $commit..."
& git -C $repo archive --format=tar.gz --output=$archive HEAD
if ($LASTEXITCODE -ne 0) { throw "git archive failed with exit code $LASTEXITCODE" }

Write-Output "Creating remote backup at $remoteBackup..."
& ssh @sshArgs "set -eu; if [ -d '$RemotePath' ]; then mv '$RemotePath' '$remoteBackup'; fi; mkdir -p '$RemotePath'"
if ($LASTEXITCODE -ne 0) { throw "Remote backup/preparation failed with exit code $LASTEXITCODE" }

Write-Output "Uploading source archive..."
& scp -o BatchMode=yes -o ConnectTimeout=10 $archive "$ServerHost`:/tmp/project0-server-$commit.tar.gz"
if ($LASTEXITCODE -ne 0) { throw "Source upload failed with exit code $LASTEXITCODE" }

Write-Output "Extracting and validating remote source..."
& ssh @sshArgs "set -eu; tar -xzf '/tmp/project0-server-$commit.tar.gz' -C '$RemotePath'; rm -f '/tmp/project0-server-$commit.tar.gz'; test -f '$RemotePath/server/server_main.gd'; test -f '$RemotePath/server/login_server_main.gd'; printf 'REMOTE_COMMIT=%s\n' '$commit'"
if ($LASTEXITCODE -ne 0) { throw "Remote source validation failed with exit code $LASTEXITCODE" }

switch ($Mode) {
    "native" {
        Write-Output "Restarting native game and login services..."
        & ssh @sshArgs "set -eu; sudo -n systemctl restart project0-server project0-login; systemctl is-active project0-server project0-login"
    }
    "docker-candidate" {
        Write-Output "Building and starting Docker candidate game server..."
        & ssh @sshArgs "set -eu; cd '$RemotePath/deploy/game-server'; docker compose up -d --build game-server; docker inspect -f '{{.State.Health.Status}}' project0-game-server-candidate"
    }
    "docker-split" {
        Write-Output "Building and starting Docker split candidate..."
        & ssh @sshArgs "set -eu; cd '$RemotePath/deploy/game-server'; ./run-split.sh up"
    }
}
if ($LASTEXITCODE -ne 0) { throw "Server mode '$Mode' deployment failed with exit code $LASTEXITCODE" }

Write-Output "Server deployment complete. Commit $commit, mode $Mode, backup $remoteBackup"
Remove-Item $archive -Force
