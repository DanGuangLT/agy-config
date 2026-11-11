# agy SessionStart hook: at most once a week, start background maintenance (scripts/maintain.ps1).
# Nothing runs while agy is closed, and nothing is started on the other days. A failed week is
# retried at most once a day. Self-contained (runs from the installed plugin folder). ASCII-only.
# Contract: read JSON on stdin (ignored), print a JSON object on stdout, exit 0.
try {
    # Console.In's async methods run synchronously on .NET Framework, so read the raw stream instead.
    if ([Console]::IsInputRedirected) {
        $stdin = [Console]::OpenStandardInput()
        $buf = New-Object byte[] 65536
        [void]$stdin.ReadAsync($buf, 0, $buf.Length).Wait(2000)
    }
} catch { }

function Get-StampAgeDays([string]$Path) {
    if (-not (Test-Path $Path)) { return [double]::MaxValue }
    $t = [datetime]::MinValue
    if (-not [datetime]::TryParse(([IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)).Trim(), [ref]$t)) { return [double]::MaxValue }
    return ((Get-Date) - $t).TotalDays
}

$response = '{}'
try {
    $h = if ($env:AGYCFG_HOME) { $env:AGYCFG_HOME } else { $HOME }
    $stateDir = Join-Path $h '.agy-config-state'
    $statePath = Join-Path $stateDir 'machine.json'
    if (Test-Path $statePath) {
        $m = [IO.File]::ReadAllText($statePath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        $due = (Get-StampAgeDays (Join-Path $stateDir 'weekly.last')) -ge 7
        $retryOk = (Get-StampAgeDays (Join-Path $stateDir 'weekly-attempt.last')) -ge 1
        if ($m.repoPath -and $due -and $retryOk) {
            $script = Join-Path $m.repoPath 'scripts\maintain.ps1'
            if (Test-Path -LiteralPath $script -PathType Leaf) {
                $argLine = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $script + '"'
                Start-Process -FilePath 'powershell' -ArgumentList $argLine -WindowStyle Hidden
            } else {
                $message = 'agy-config repo folder was not found: "' + $m.repoPath + '". Run scripts\install.ps1 from the clone''s new folder to fix it.'
                $logDir = Join-Path $stateDir 'logs'
                if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir -ErrorAction Stop | Out-Null }
                $now = Get-Date
                $utf8 = New-Object Text.UTF8Encoding $false
                $log = Join-Path $logDir ('hook-' + $now.ToString('yyyyMMdd') + '.log')
                $line = $now.ToString('yyyy-MM-dd HH:mm:ss') + ' [WARN] ' + $message + [Environment]::NewLine
                [IO.File]::AppendAllText($log, $line, $utf8)
                [IO.File]::WriteAllText((Join-Path $stateDir 'weekly-attempt.last'), $now.ToString('o'), $utf8)
                # agy's SessionStart contract accepts nested system messages in injectSteps.
                $response = @{ injectSteps = @(@{ systemMessage = @{ systemMessage = $message } }) } | ConvertTo-Json -Depth 5 -Compress
            }
        }
    }
} catch { }

Write-Output $response
exit 0
