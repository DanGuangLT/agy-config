# agy Stop hook: start a background sync on owner machines, then answer immediately.
# Runs from the installed plugin folder, so it is self-contained (no repo libraries). ASCII-only.
# Contract: read JSON on stdin (ignored), print a JSON object on stdout, exit 0.
try {
    # agy closes stdin after the payload; never wait more than 2 s in case a caller leaves it open.
    # Console.In's async methods run synchronously on .NET Framework, so read the raw stream instead.
    if ([Console]::IsInputRedirected) {
        $stdin = [Console]::OpenStandardInput()
        $buf = New-Object byte[] 65536
        [void]$stdin.ReadAsync($buf, 0, $buf.Length).Wait(2000)
    }
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
