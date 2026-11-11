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

function Enter-RunLock([string]$Name, [int]$StaleMinutes = 30) {
    $p = Get-StateFile ($Name + '.lock')
    if (Test-Path $p) {
        $lock = Read-JsonFile $p @{}
        $t = [datetime]::MinValue
        $fresh = [datetime]::TryParse([string]$lock.time, [ref]$t) -and $t -gt (Get-Date).AddMinutes(-$StaleMinutes)
        if ($fresh) { return $false }
    }
    Write-JsonFile $p @{ pid = $PID; time = (Get-Date).ToString('o') }
    return $true
}
function Exit-RunLock([string]$Name) { Remove-Item (Get-StateFile ($Name + '.lock')) -Force -ErrorAction SilentlyContinue }

function Test-Debounce([string]$Name, [int]$Minutes) {
    $p = Get-StateFile ($Name + '.last')
    if (-not (Test-Path $p)) { return $true }
    $t = [datetime]::MinValue
    if (-not [datetime]::TryParse((Read-TextFile $p).Trim(), [ref]$t)) { return $true }
    return $t -lt (Get-Date).AddMinutes(-$Minutes)
}
function Register-Run([string]$Name) { Write-TextFile (Get-StateFile ($Name + '.last')) ((Get-Date).ToString('o')) }
