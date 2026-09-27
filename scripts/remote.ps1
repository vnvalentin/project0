<#
.SYNOPSIS
Runs a bash script on the Linux host over SSH without nested quoting.

.DESCRIPTION
The script text is sent to `bash -s` on the remote host through stdin, so it
is never re-quoted by ssh or the remote login shell. Write it exactly as you
would in a bash terminal; the only quoting layer is the PowerShell string you
pass in (use single quotes so `$`, braces and double quotes stay literal).
Line endings are normalized to LF and the text is sent as UTF-8 without a BOM.
Remote stderr is merged into stdout so output stays in order, and the remote
exit code becomes this script's exit code ($LASTEXITCODE).

.EXAMPLE
scripts/remote.ps1 'cd /data/code/project0 && git status --short --branch'

.EXAMPLE
scripts/remote.ps1 'docker inspect --format "{{.Name}} {{json .State.Health}}" project0-game-server'

.EXAMPLE
Get-Content scripts/some_job.sh -Raw | scripts/remote.ps1
#>
param(
    [Parameter(Position = 0, ValueFromPipeline = $true)]
    [string]$Script,
    [string]$Target = $(if ($env:PROJECT0_SSH_TARGET) { $env:PROJECT0_SSH_TARGET } else { "vic@192.168.1.254" }),
    [int]$ConnectTimeout = 10
)

begin {
    $ErrorActionPreference = "Stop"
    $parts = New-Object System.Collections.Generic.List[string]
    # Bind an argument here, not in `process`: under `powershell -File` with
    # redirected stdin, `process` runs once per stdin line, possibly zero times.
    $fromArgument = $PSBoundParameters.ContainsKey("Script")
    if ($fromArgument) { $parts.Add($Script) }
}

process {
    if (-not $fromArgument -and $null -ne $Script) { $parts.Add($Script) }
}

end {
    $text = ($parts -join "`n") -replace "`r`n", "`n"
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw "remote.ps1: no script given. Pass it as an argument or pipe it in."
    }
    if (-not $text.EndsWith("`n")) { $text += "`n" }

    $sshPath = Join-Path $env:WINDIR "System32\OpenSSH\ssh.exe"
    if (-not (Test-Path -LiteralPath $sshPath)) { $sshPath = (Get-Command ssh -ErrorAction Stop).Source }

    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $sshPath
    $start.Arguments = "-T -o BatchMode=yes -o ConnectTimeout=$ConnectTimeout -o ServerAliveInterval=15 $Target `"bash -s 2>&1`""
    $start.UseShellExecute = $false
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $start.StandardErrorEncoding = New-Object System.Text.UTF8Encoding($false)

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $start
    # Windows PowerShell 5.1 (.NET Framework) opens the child's stdin with
    # Console.InputEncoding and writes its BOM up front; bash then fails on the
    # first command. Use BOM-less UTF-8 while the process starts.
    $savedInputEncoding = [Console]::InputEncoding
    try {
        try { [Console]::InputEncoding = New-Object System.Text.UTF8Encoding($false) } catch {}
        [void]$process.Start()
    } finally {
        try { [Console]::InputEncoding = $savedInputEncoding } catch {}
    }
    # ssh's own errors (auth, host key, timeout) arrive on local stderr.
    $sshErrors = $process.StandardError.ReadToEndAsync()

    $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($text)
    $process.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
    $process.StandardInput.Close()

    while ($null -ne ($line = $process.StandardOutput.ReadLine())) { $line }
    $process.WaitForExit()

    $errText = $sshErrors.Result.Trim()
    if ($errText) { [Console]::Error.WriteLine($errText) }
    exit $process.ExitCode
}
