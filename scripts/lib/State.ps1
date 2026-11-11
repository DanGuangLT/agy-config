# Machine-local state in ~/.agy-config-state: role, last apply, pending lock, run locks. ASCII-only file.

function Get-StateFile([string]$Name) { Join-Path (Get-AgyPaths).StateDir $Name }

function Get-MachineState { Read-JsonFile (Get-StateFile 'machine.json') @{} }
function Set-MachineState($State) { Write-JsonFile (Get-StateFile 'machine.json') $State }

function Get-AppliedState {
    $a = Read-JsonFile (Get-StateFile 'applied.json') @{}
    foreach ($k in 'ownSkills', 'ownPlugins', 'permissions', 'mcpServers') { if (-not $a.ContainsKey($k)) { $a[$k] = @() } }
    if (-not ($a.sources -is [hashtable])) { $a.sources = @{} }
    return $a
}
function Set-AppliedState($State) {
    $State.appliedAt = (Get-Date).ToString('o')
    Write-JsonFile (Get-StateFile 'applied.json') $State
}

function Get-PendingLock {
    $p = Get-StateFile 'pending.lock.json'
    $lock = Read-JsonFile $p $null
    if ($null -eq $lock) { return $null }
    $created = [datetime]::MinValue
    if (-not [datetime]::TryParse([string]$lock.createdAt, [ref]$created) -or $created -lt (Get-Date).AddDays(-14)) {
        Remove-Item $p -Force -ErrorAction SilentlyContinue
        return $null
    }
    return $lock
}
function Set-PendingLock($Versions) {
    Write-JsonFile (Get-StateFile 'pending.lock.json') @{ createdAt = (Get-Date).ToString('o'); versions = $Versions }
}
function Clear-PendingLock { Remove-Item (Get-StateFile 'pending.lock.json') -Force -ErrorAction SilentlyContinue }

function Merge-ThreeWaySet([string[]]$Repo, [string[]]$Base, [string[]]$Current) {
    $repoSet = @($Repo | Where-Object { $_ })
    $baseSet = @($Base | Where-Object { $_ })
    $curSet = @($Current | Where-Object { $_ })
    $added = @($curSet | Where-Object { $baseSet -notcontains $_ })
    $removed = @($baseSet | Where-Object { $curSet -notcontains $_ })
    # Emits items on the pipeline; callers wrap with @() to get an array.
    @($repoSet + $added) | Where-Object { $removed -notcontains $_ } | Sort-Object -Unique
}

function Test-LockLive($Lock, [int]$StaleMinutes) {
    $t = [datetime]::MinValue
    if (-not [datetime]::TryParse([string]$Lock.time, [ref]$t) -or $t -lt (Get-Date).AddMinutes(-$StaleMinutes)) { return $false }
    if ($Lock.pid -and -not (Get-Process -Id ([int]$Lock.pid) -ErrorAction SilentlyContinue)) { return $false }
    return $true
}

$script:LockDepth = @{}

function Enter-RunLock([string]$Name, [int]$StaleMinutes = 30, [int]$WaitSeconds = 0) {
    # Atomic (CreateNew), reentrant for this process, stale when old or when its process is gone.
    $p = Get-StateFile ($Name + '.lock')
    $dir = Split-Path -Parent $p
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    while ($true) {
        if (Test-Path $p) {
            $lock = Read-JsonFile $p @{}
            if ([int]$lock.pid -eq $PID) { $script:LockDepth[$p] = 1 + [int]$script:LockDepth[$p]; return $true }
            if (-not (Test-LockLive $lock $StaleMinutes)) { Remove-Item $p -Force -ErrorAction SilentlyContinue }
        }
        try {
            $fs = [IO.File]::Open($p, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            $bytes = [Text.Encoding]::UTF8.GetBytes((Format-Json @{ pid = $PID; time = (Get-Date).ToString('o') }))
            $fs.Write($bytes, 0, $bytes.Length)
            $fs.Close()
            $script:LockDepth[$p] = 1
            return $true
        } catch [System.IO.IOException] { }
        if ((Get-Date) -ge $deadline) { return $false }
        Start-Sleep -Milliseconds 500
    }
}
function Exit-RunLock([string]$Name) {
    # Releases one level; the file goes away only when this process leaves its outermost hold.
    $p = Get-StateFile ($Name + '.lock')
    if (-not (Test-Path $p)) { return }
    $lock = Read-JsonFile $p @{}
    if ([int]$lock.pid -ne $PID) { return }
    $depth = [int]$script:LockDepth[$p] - 1
    if ($depth -gt 0) { $script:LockDepth[$p] = $depth; return }
    $script:LockDepth.Remove($p)
    Remove-Item $p -Force -ErrorAction SilentlyContinue
}

function Test-Debounce([string]$Name, [int]$Minutes) {
    $p = Get-StateFile ($Name + '.last')
    if (-not (Test-Path $p)) { return $true }
    $t = [datetime]::MinValue
    if (-not [datetime]::TryParse((Read-TextFile $p).Trim(), [ref]$t)) { return $true }
    return $t -lt (Get-Date).AddMinutes(-$Minutes)
}
function Register-Run([string]$Name) { Write-TextFile (Get-StateFile ($Name + '.last')) ((Get-Date).ToString('o')) }
