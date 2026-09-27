# Validates scripts/remote.ps1 against the real Linux host (needs SSH key access).
# Run under both shells:
#   powershell.exe -NoProfile -File scripts/test_remote.ps1
#   pwsh -NoProfile -File scripts/test_remote.ps1
$ErrorActionPreference = "Stop"
$remote = Join-Path $PSScriptRoot "remote.ps1"
$failures = 0

function Check([string]$Name, [object]$Actual, [object]$Expected) {
    if ("$Actual" -ceq "$Expected") {
        Write-Host "PASS $Name"
    } else {
        Write-Host "FAIL $Name`n  expected: [$Expected]`n  actual:   [$Actual]"
        $script:failures++
    }
}

# Braces and double quotes reach the remote shell untouched (Docker/Go templates).
$out = & $remote 'printf "%s\n" "{{.Name}} {{json .State}}"'
Check "braces and double quotes" $out '{{.Name}} {{json .State}}'

# $variables expand remotely, not locally; && and || work.
$out = & $remote 'x=remote; echo "$x" && false || echo fallback'
Check "remote variables and && ||" ($out -join "|") 'remote|fallback'

# Single quotes inside the script.
$out = & $remote "echo 'it''s single'"
Check "single quotes" $out "its single"

# Piped multi-line script with CRLF endings runs as LF.
$crlf = "a=1`r`nb=2`r`necho `$((a+b))`r`n"
$out = $crlf | & $remote
Check "piped CRLF script" $out "3"

# Non-ASCII text survives the round trip (UTF-8 both ways).
$word = "caf" + [char]0x00E9
$out = & $remote "printf '%s\n' '$word'"
Check "non-ASCII round trip" $out $word

# Remote stderr is merged into output, in order.
$out = & $remote 'echo one; echo two >&2; echo three'
Check "stderr merged in order" ($out -join "|") 'one|two|three'

# Invoked as `<shell> -File remote.ps1 '<script>'` with redirected stdin, the way
# agent tools call it; the argument must not be dropped.
$shell = (Get-Process -Id $PID).Path
$out = "" | & $shell -NoProfile -File $remote 'echo file-mode'
Check "-File with redirected stdin" $out "file-mode"

# Remote exit code propagates.
& $remote 'exit 7' | Out-Null
Check "exit code propagates" $LASTEXITCODE 7
& $remote 'true' | Out-Null
Check "zero exit code" $LASTEXITCODE 0

Write-Host ("PowerShell {0}: {1} failure(s)" -f $PSVersionTable.PSVersion, $failures)
exit $failures
