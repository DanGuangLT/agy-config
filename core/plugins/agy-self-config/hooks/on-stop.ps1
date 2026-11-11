# agy Stop hook: start a background sync on owner machines, then answer immediately.
# Runs from the installed plugin folder, so it is self-contained (no repo libraries). ASCII-only.
# Contract: read JSON on stdin (ignored), print a JSON object on stdout, exit 0.
try {
    if ([Console]::IsInputRedirected) { [void][Console]::In.ReadToEnd() }
} catch { }

try {
    $h = if ($env:AGYCFG_HOME) { $env:AGYCFG_HOME } else { $HOME }
    $statePath = Join-Path $h '.agy-config-state\machine.json'
    if (Test-Path $statePath) {
        $m = Get-Content -Raw -Path $statePath | ConvertFrom-Json
        if ($m.role -eq 'owner' -and $m.repoPath) {
            $sync = Join-Path $m.repoPath 'scripts\sync.ps1'
            if (Test-Path $sync) {
                # sync.ps1 debounces and locks itself, so starting it after every turn is cheap.
                $argLine = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $sync + '"'
                Start-Process -FilePath 'powershell' -ArgumentList $argLine -WindowStyle Hidden
            }
        }
    }
} catch { }

Write-Output '{}'
exit 0
