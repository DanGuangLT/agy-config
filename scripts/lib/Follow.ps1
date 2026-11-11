# Stop or resume following the shared repository. Spec 2026-11-12, "Stop and resume following". ASCII-only file.
# Return codes: 0 done (or nothing to do), 1 not possible here or apply failed.

$script:SharedFileNames = @('GEMINI.core.md', 'permissions.json', 'sources.json', 'sources.lock.json')

function Set-ProfileUpstream([string]$ProfileDir, $Upstream) {
    # $Upstream = $null removes the field (the default: following).
    $path = Join-Path $ProfileDir 'profile.json'
    $data = Read-JsonFile $path @{}
    if ($null -eq $Upstream) { $data.Remove('upstream') } else { $data.upstream = $Upstream }
    Write-JsonFile $path $data
}

function Invoke-Follow {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [switch]$Stop,
        [switch]$Resume
    )
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).ProviderPath
    $t = Get-I18nText $RepoRoot 'en'
    $log = { param($m, $l = 'INFO') Write-AgyLog -Script 'follow' -Message $m -Level $l }
    if ($Stop -and $Resume) { Write-Host $t.msgFollowBoth; return 1 }
    $machine = Get-MachineState
    if (-not $machine.profile) { Write-Host $t.msgFollowNotInstalled; return 1 }
    $loc = Get-ProfileLocation $RepoRoot $machine
    $prof = Get-Profile $RepoRoot $machine.profile $loc.Dir
    $following = Test-Following $prof
    $origin = ''
    try { $origin = (Invoke-Git $RepoRoot @('remote', 'get-url', 'origin')).Trim() } catch { }

    if (-not $Stop -and -not $Resume) {
        if ($following) { Write-Host ($t.msgFollowOn -f $origin) }
        else { Write-Host ($t.msgFollowOff -f $origin, $prof.upstream.stoppedAt, (Join-Path $loc.Dir 'shared')) }
        return 0
    }
    if ($machine.role -eq 'owner') { Write-Host $t.msgFollowOwner; return 1 }
    $shared = Join-Path $loc.Dir 'shared'

    if ($Stop) {
        if (-not $following) { Write-Host ($t.msgFollowAlreadyOff -f $shared); return 0 }
        if (-not (Enter-RunLock 'config' -WaitSeconds 120)) { Write-Host $t.msgFollowBusy; return 1 }
        try {
            # Freeze the shared list as it is now; the copies become the user's to edit.
            New-Item -ItemType Directory -Force -Path $shared | Out-Null
            foreach ($n in $script:SharedFileNames) { Copy-Item -Force -LiteralPath (Join-Path $RepoRoot ('core\' + $n)) -Destination (Join-Path $shared $n) }
            $commit = ''
            try { $commit = (Invoke-Git $RepoRoot @('rev-parse', 'HEAD')).Trim() } catch { }
            Set-ProfileUpstream $loc.Dir @{ follow = $false; stoppedAt = (Get-Date).ToString('o'); commit = $commit }
        } finally {
            Exit-RunLock 'config'
        }
        & $log "stopped following the shared repository at $commit"
        Write-Host ($t.msgFollowStopped -f $shared)
        if ($loc.Personal) {
            $s = Invoke-Sync -RepoRoot $RepoRoot -Force
            if ($s -ne 0) { Write-Host ($t.msgFollowBackupFailed -f (Get-AgyPaths).LogDir) }
        }
        return 0
    }

    # Resume
    if ($following) { Write-Host $t.msgFollowAlreadyOn; return 0 }
    if (-not (Enter-RunLock 'config' -WaitSeconds 120)) { Write-Host $t.msgFollowBusy; return 1 }
    try {
        if (Test-Path $shared) {
            # Keep the user's edited copy outside the profile, then drop it.
            $keep = Join-Path (Get-AgyPaths).BackupRoot ((Get-Date -Format 'yyyyMMdd-HHmmss') + '-shared')
            Copy-Folder $shared $keep
            Remove-Item -LiteralPath $shared -Recurse -Force
            Write-Host ($t.msgFollowKeptCopy -f $keep)
        }
        Set-ProfileUpstream $loc.Dir $null
    } finally {
        Exit-RunLock 'config'
    }
    & $log 'resumed following the shared repository'
    Write-Host ($t.msgFollowResuming -f $origin)
    # Apply backs the change up first (personal mode), then pulls the shared repository and installs its list.
    $code = Invoke-Apply -RepoRoot $RepoRoot
    if ($code -ne 0) { Write-Host ($t.msgApplyFailed -f (Get-AgyPaths).LogDir); return 1 }
    Write-Host $t.msgFollowResumed
    return 0
}
