# Weekly upstream update, owner machines only. Spec sections 6.4 and 6.5. ASCII-only file.

function Get-CompareUrl([string]$OriginUrl) {
    $u = $OriginUrl.Trim()
    if ($u -match '^git@github\.com:(.+?)(\.git)?$') { $u = 'https://github.com/' + $Matches[1] }
    $u = $u -replace '\.git$', ''
    return $u + '/compare/main...update/sources?expand=1'
}

function Invoke-Update {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [switch]$NoPush
    )
    $log = { param($m, $l = 'INFO') Write-AgyLog -Script 'update' -Message $m -Level $l }
    $machine = Get-MachineState
    if ($machine.role -ne 'owner') { & $log 'not an owner machine; updates arrive through main'; return 0 }
    if (-not (Enter-RunLock 'update')) { & $log 'another update is running; skipped'; return 0 }
    try {
        $prof = Get-Profile $RepoRoot $machine.profile
        $pending = Get-PendingLock
        $sources = @(Get-SourceList $RepoRoot $prof)
        $lock = Get-EffectiveLock $RepoRoot $prof $pending
        $rows = @()
        $newVersions = @{}
        foreach ($s in $sources) {
            $old = [string]$lock[$s.id]
            try { $latest = [string](Get-LatestVersion $s) }
            catch {
                $rows += , @($s.id, $old, '?', 'check failed')
                & $log "check failed $($s.id): $($_.Exception.Message)" 'WARN'
                continue
            }
            if ($latest -eq $old) { continue }
            $r = Install-Source $s $latest
            $t = if ($r.Ok) { Test-Source $s } else { @{ Ok = $false; Error = $r.Error } }
            if ($r.Ok -and $t.Ok) {
                $new = if ($r.Version) { [string]$r.Version } else { $latest }
                if ($new -ne $old) { $newVersions[$s.id] = $new; $rows += , @($s.id, $old, $new, 'updated') }
                continue
            }
            # Roll back this source only.
            if ($s.type -eq 'marketplace') { Restore-MarketplaceSnapshot $s | Out-Null }
            elseif ($old) { Install-Source $s $old | Out-Null }
            $reason = if ($r.Ok) { 'rolled back' } else { 'install failed' }
            $rows += , @($s.id, $old, $latest, $reason)
            & $log "rolled back $($s.id): $($t.Error)" 'WARN'
        }
        if ($newVersions.Count -eq 0) {
            foreach ($row in $rows) { & $log ("{0}: {1}" -f $row[0], $row[3]) 'WARN' }
            & $log 'no source updates'
            return 0
        }

        # Use the new versions on this machine right away.
        $merged = @{}
        if ($pending) { foreach ($k in $pending.versions.Keys) { $merged[$k] = $pending.versions[$k] } }
        foreach ($k in $newVersions.Keys) { $merged[$k] = $newVersions[$k] }
        $baseLock = Get-EffectiveLock $RepoRoot $prof $null
        foreach ($k in @($merged.Keys | Sort-Object)) {
            if (-not $newVersions.ContainsKey($k)) { $rows += , @($k, [string]$baseLock[$k], [string]$merged[$k], 'carried over') }
        }
        Set-PendingLock $merged
        $applied = Get-AppliedState
        foreach ($k in $newVersions.Keys) { $applied.sources[$k] = $newVersions[$k] }
        Set-AppliedState $applied

        $table = @('| source | old | new | result |', '|---|---|---|') + @($rows | ForEach-Object {
            $cells = @($_ | ForEach-Object { ([string]$_).Replace('|', '\|') -replace '\r\n|\r|\n', '<br>' })
            '| ' + ($cells -join ' | ') + ' |'
        })
        foreach ($line in $table) { & $log $line }
        if ($NoPush) { return 0 }

        # Build update/sources from origin/main in a separate worktree, leaving the main checkout alone.
        $wt = Join-Path (Get-AgyPaths).StateDir 'update-worktree'
        $git = Resolve-Tool git
        Invoke-External $git @('worktree', 'remove', '--force', $wt) $RepoRoot | Out-Null
        Remove-Item $wt -Recurse -Force -ErrorAction SilentlyContinue
        Invoke-External $git @('worktree', 'prune') $RepoRoot | Out-Null
        Invoke-Git $RepoRoot @('fetch', '--quiet', 'origin') | Out-Null
        Invoke-Git $RepoRoot @('worktree', 'add', '--quiet', '--force', '-B', 'update/sources', $wt, 'origin/main') | Out-Null
        try {
            $profIds = @($prof.Sources | ForEach-Object { $_.id }) + @($prof.Lock.Keys)
            $coreLockPath = Join-Path $wt 'core\sources.lock.json'
            $profLockPath = Join-Path $wt ('profiles\' + $prof.name + '\sources.lock.json')
            $coreLock = Read-JsonFile $coreLockPath @{}
            $profLock = Read-JsonFile $profLockPath @{}
            foreach ($k in $merged.Keys) {
                if ($profIds -contains $k) { $profLock[$k] = $merged[$k] } else { $coreLock[$k] = $merged[$k] }
            }
            Write-JsonFile $coreLockPath $coreLock
            if (Test-Path (Split-Path -Parent $profLockPath)) { Write-JsonFile $profLockPath $profLock }
            $msgFile = Join-Path (Get-AgyPaths).StateDir 'update-commit-msg.txt'
            Write-TextFile $msgFile (("chore(sources): weekly update {0}`n`n" -f (Get-Date -Format 'yyyy-MM-dd')) + ($table -join "`n") + "`n")
            if (@(Find-Secrets @($msgFile)).Count -gt 0) {
                & $log 'commit message contains possible secrets or personal data; publication blocked' 'ERROR'
                return 2
            }
            Invoke-Git $wt @('add', '-A') | Out-Null
            Invoke-Git $wt @('commit', '--quiet', '-F', $msgFile) | Out-Null
            Invoke-Git $wt @('push', '--quiet', '--force', 'origin', 'update/sources') | Out-Null
        } finally {
            Invoke-External $git @('worktree', 'remove', '--force', $wt) $RepoRoot | Out-Null
        }
        $origin = (Invoke-Git $RepoRoot @('remote', 'get-url', 'origin')).Trim()
        & $log ("pushed update/sources; open or review the PR: " + (Get-CompareUrl $origin))
        return 0
    } finally {
        Exit-RunLock 'update'
    }
}
