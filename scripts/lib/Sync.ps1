# Machine -> repo. Spec section 6.3. ASCII-only file.
# Return codes: 0 done/skipped, 2 secret found (nothing committed, edits kept), 3 conflict (sync/* branch),
# 4 push failed, 5 repo busy (merge/rebase in progress, not on main, or unmerged paths).

function Merge-ThreeWayText([string]$Repo, [string]$Base, [string]$Current) {
    # Returns @{ Text; Changed; Conflict }.
    if ($Current -eq $Repo) { return @{ Text = $Repo; Changed = $false; Conflict = $false } }
    if ($null -ne $Base -and $Current -eq $Base) { return @{ Text = $Repo; Changed = $false; Conflict = $false } }
    if ($null -eq $Base -or $Repo -eq $Base) { return @{ Text = $Current; Changed = $true; Conflict = $false } }
    return @{ Text = $Current; Changed = $true; Conflict = $true }
}

function Get-RepoChangedFiles([string]$RepoRoot) {
    $out = Invoke-Git $RepoRoot @('-c', 'core.quotepath=false', 'status', '--porcelain=v1', '--untracked-files=all')
    foreach ($line in ($out -split "`n")) {
        if ($line.Length -lt 4) { continue }
        $path = $line.Substring(3).Trim()
        if ($path -match ' -> ') { $path = ($path -split ' -> ')[1] }
        @{ Status = $line.Substring(0, 2); Path = $path.Trim('"') }
    }
}

function Get-ManagedPaths([string]$ProfileName, [bool]$IsOwner) {
    # The only paths sync ever stages. Anything else in the clone (scripts, graphify-out, notes) is left alone.
    $paths = @('profiles/' + $ProfileName + '/')
    if ($IsOwner) { $paths += @('core/GEMINI.core.md', 'core/permissions.json', 'core/sources.json', 'core/sources.lock.json', 'THIRD_PARTY.md') }
    return $paths
}

function Test-ManagedPath([string]$Path, [string[]]$Managed) {
    foreach ($m in $Managed) {
        if ($m.EndsWith('/')) { if ($Path.StartsWith($m)) { return $true } }
        elseif ($Path -eq $m) { return $true }
    }
    return $false
}

function Get-RepoBusyReason([string]$RepoRoot) {
    # Sync must never touch a clone that a person (or agy) is working in.
    $branch = ''
    try { $branch = (Invoke-Git $RepoRoot @('symbolic-ref', '--quiet', '--short', 'HEAD')).Trim() } catch { }
    if ($branch -ne 'main') { return "the clone is on '$branch', not main" }
    foreach ($marker in 'MERGE_HEAD', 'CHERRY_PICK_HEAD', 'REVERT_HEAD', 'rebase-merge', 'rebase-apply') {
        $gp = ''
        try { $gp = (Invoke-Git $RepoRoot @('rev-parse', '--git-path', $marker)).Trim() } catch { }
        if ($gp -and (Test-Path (Join-Path $RepoRoot $gp))) { return "a $marker is in progress" }
    }
    $unmerged = ''
    try { $unmerged = (Invoke-Git $RepoRoot @('diff', '--name-only', '--diff-filter=U')).Trim() } catch { }
    if ($unmerged) { return 'there are unmerged files' }
    return $null
}

function Save-SyncCapture {
    param([string]$RepoRoot, $Machine, $Prof, $Applied)
    $paths = Get-AgyPaths
    $isOwner = $Machine.role -eq 'owner'
    $profDir = $Prof.Path
    $conflict = $false

    # GEMINI.md regions (only once apply has generated the file).
    if ($Applied.geminiManaged -and (Test-Path $paths.GeminiMd)) {
        $split = Split-GeminiMd (Read-TextFile $paths.GeminiMd)
        $profFile = Join-Path $profDir 'GEMINI.profile.md'
        $baseProfile = if ($Applied.ContainsKey('geminiProfileText')) { $Applied.geminiProfileText } else { $null }
        $m = Merge-ThreeWayText $Prof.GeminiProfileText $baseProfile $split.Profile
        if ($m.Changed) { Update-TextFile $profFile ($m.Text + "`n") | Out-Null }
        if ($m.Conflict) { $conflict = $true }
        if ($isOwner -and $null -ne $split.Core) {
            $coreFile = Join-Path $RepoRoot 'core\GEMINI.core.md'
            $repoCore = (Read-TextFile $coreFile).TrimEnd("`r", "`n")
            $baseCore = if ($Applied.ContainsKey('geminiCoreText')) { $Applied.geminiCoreText } else { $null }
            $mc = Merge-ThreeWayText $repoCore $baseCore $split.Core
            if ($mc.Changed) { Update-TextFile $coreFile ($mc.Text + "`n") | Out-Null }
            if ($mc.Conflict) { $conflict = $true }
        }
    }

    # Permissions (profile part = machine minus core), three-way against the last apply.
    $core = @(Read-JsonFile (Join-Path $RepoRoot 'core\permissions.json') @())
    $current = @(Get-MachinePermissions $paths.CliSettings | Where-Object { $core -notcontains $_ })
    $base = @(@($Applied.permissions) | Where-Object { $_ -and $core -notcontains $_ })
    $newPerms = @(Merge-ThreeWaySet -Repo @($Prof.Permissions) -Base $base -Current $current)
    Update-JsonFile (Join-Path $profDir 'permissions.json') $newPerms | Out-Null

    # Sources: skills installed with the skills CLI and marketplace plugins installed by hand.
    $inv = Get-MachineInventory
    $profSources = [System.Collections.ArrayList]@(@($Prof.Sources) | Where-Object { $_ })
    $profLock = if ($Prof.Lock -is [hashtable]) { $Prof.Lock } else { @{} }
    $known = @(Get-SourceList $RepoRoot $Prof)
    $knownNames = @($known | ForEach-Object { @($_.provides) + @($_.skills | ForEach-Object { $_.name }) + @($_.plugin) })
    # Names apply already managed or already saw in the skills CLI lock: never re-import them (a removal
    # in progress must not come back).
    $managedNames = @()
    if ($Applied.sourceDefs -is [hashtable]) {
        foreach ($d in $Applied.sourceDefs.Values) { if ($d) { $managedNames += @($d.provides) + @($d.skills | ForEach-Object { $_.name }) + @($d.plugin) } }
    }
    $seenSkillLock = @($Applied.skillLockNames)
    foreach ($entry in @(ConvertFrom-SkillLock $inv.SkillLock $null)) {
        $newSkills = @($entry.skills | Where-Object { $knownNames -notcontains $_.name -and $managedNames -notcontains $_.name -and $seenSkillLock -notcontains $_.name -and $inv.Skills -contains $_.name })
        if ($newSkills.Count -eq 0) { continue }
        $existing = $profSources | Where-Object { $_.id -eq $entry.id } | Select-Object -First 1
        if ($existing) {
            $existing.skills = @(@($existing.skills) + $newSkills | Sort-Object { $_.name })
            $existing.provides = @($existing.skills | ForEach-Object { $_.name })
        } else {
            $entry.skills = $newSkills
            $entry.provides = @($newSkills | ForEach-Object { $_.name })
            [void]$profSources.Add($entry)
        }
        $profLock[$entry.id] = Get-GitHeadSha $entry.repo
    }
    foreach ($pl in @($inv.Plugins)) {
        if (-not $pl.source -or $pl.source -eq 'antigravity' -or $knownNames -contains $pl.name -or $managedNames -contains $pl.name) { continue }
        [void]$profSources.Add(@{ id = $pl.name; type = 'marketplace'; plugin = $pl.name; marketplace = $pl.source; provides = @($pl.name) })
        $profLock[$pl.name] = $pl.version
    }
    # Drop profile sources this machine uninstalled since the last apply.
    $installedPlugins = @($inv.Plugins | ForEach-Object { $_.name })
    foreach ($s in @($profSources)) {
        if (-not $Applied.sources.ContainsKey($s.id)) { continue }
        if ($s.type -eq 'github-skills') {
            $keep = @($s.skills | Where-Object { $inv.Skills -contains $_.name })
            if ($keep.Count -eq 0) { $profSources.Remove($s); $profLock.Remove($s.id) }
            else { $s.skills = $keep; $s.provides = @($keep | ForEach-Object { $_.name }) }
        } elseif ($s.plugin -and $installedPlugins -notcontains $s.plugin) {
            $profSources.Remove($s); $profLock.Remove($s.id)
        }
    }
    Update-JsonFile (Join-Path $profDir 'sources.json') @($profSources.ToArray()) | Out-Null
    Update-JsonFile (Join-Path $profDir 'sources.lock.json') $profLock | Out-Null

    # Own skills and plugins: copied into the profile. Classification uses the updated sources.
    $Prof.Sources = @($profSources.ToArray())
    $allSources = @(Get-SourceList $RepoRoot $Prof)
    $cls = Get-Classification $inv $allSources $Prof @('agy-self-config')
    $pluginNames = @($inv.Plugins | ForEach-Object { $_.name })
    foreach ($n in $cls.Own) {
        if ($pluginNames -contains $n) {
            $dst = Join-Path $profDir ('plugins\' + $n)
            Copy-Folder (Join-Path $paths.PluginsDir $n) $dst
            Remove-Item (Join-Path $dst '.git') -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            Copy-Folder (Join-Path $paths.SkillsDir $n) (Join-Path $profDir ('skills\' + $n))
        }
    }
    $profJsonPath = Join-Path $profDir 'profile.json'
    $profJson = Read-JsonFile $profJsonPath @{}
    $changedOwn = $false
    foreach ($kind in 'ownSkills', 'ownPlugins') {
        $sub = if ($kind -eq 'ownSkills') { 'skills' } else { 'plugins' }
        foreach ($n in @($Applied[$kind])) {
            if ($n -and $cls.Own -notcontains $n) {
                Remove-Item (Join-Path $profDir ($sub + '\' + $n)) -Recurse -Force -ErrorAction SilentlyContinue
                $profJson[$kind] = @(@($profJson[$kind]) | Where-Object { $_ -ne $n })
                $changedOwn = $true
            }
        }
    }
    if ($changedOwn) { Update-JsonFile $profJsonPath $profJson | Out-Null }

    # Unknown items stay local.
    $unknown = @($cls.Unknown | ForEach-Object {
            @{ name = $_; kind = $(if ($pluginNames -contains $_) { 'plugin' } else { 'skill' }); detectedAt = (Get-Date).ToString('o') }
        })
    Write-JsonFile (Join-Path $paths.StateDir 'unknown.json') $unknown

    # MCP servers, secrets replaced by ${VARS}.
    if (Test-Path $paths.McpConfig) {
        $machineCfg = Read-JsonFile $paths.McpConfig @{}
        $machineServers = if ($machineCfg.mcpServers -is [hashtable]) { $machineCfg.mcpServers } else { @{} }
        $profMcpPath = Join-Path $profDir 'mcp.json'
        $repoCfg = Read-JsonFile $profMcpPath @{ mcpServers = @{} }
        $repoServers = if ($repoCfg.mcpServers -is [hashtable]) { $repoCfg.mcpServers } else { @{} }
        $names = @(Merge-ThreeWaySet -Repo @($repoServers.Keys) -Base @($Applied.mcpServers) -Current @($machineServers.Keys))
        if ($names.Count -gt 0 -or (Test-Path $profMcpPath)) {
            $protected = (Protect-McpConfig @{ mcpServers = $machineServers }).Config.mcpServers
            $out = @{}
            foreach ($n in $names) { $out[$n] = if ($protected.ContainsKey($n)) { $protected[$n] } else { $repoServers[$n] } }
            Update-JsonFile $profMcpPath @{ mcpServers = $out } | Out-Null
        }
    }
    return @{ Conflict = $conflict }
}

function Invoke-Sync {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [switch]$CaptureOnly,
        [switch]$Force
    )
    $log = { param($m, $l = 'INFO') Write-AgyLog -Script 'sync' -Message $m -Level $l }
    $machine = Get-MachineState
    if (-not $machine.profile) { & $log 'no profile configured for this machine' 'WARN'; return 0 }
    $isOwner = $machine.role -eq 'owner'
    if (-not (Enter-RunLock 'config')) { & $log 'another apply/sync is running; skipped'; return 0 }
    try {
        $prof = Get-Profile $RepoRoot $machine.profile
        if (-not $Force -and -not $CaptureOnly -and -not (Test-Debounce 'sync' ([int]$prof.sync.debounceMinutes))) { return 0 }
        $busy = Get-RepoBusyReason $RepoRoot
        if ($busy) { & $log "skipped: $busy" 'WARN'; return 5 }

        $publish = $isOwner -and -not $CaptureOnly
        if ($publish) {
            $pull = Update-ConfigRepo $RepoRoot
            if (-not $pull.Ok) { & $log "pull before sync failed: $($pull.Error)" 'WARN' }
            $prof = Get-Profile $RepoRoot $machine.profile
        }
        $cap = Save-SyncCapture -RepoRoot $RepoRoot -Machine $machine -Prof $prof -Applied (Get-AppliedState)
        if (-not $publish) { & $log 'captured local changes (no commit on this machine)'; return 0 }

        $managed = Get-ManagedPaths $prof.name $isOwner
        $changes = @(Get-RepoChangedFiles $RepoRoot | Where-Object { Test-ManagedPath $_.Path $managed })
        if ($changes.Count -eq 0) {
            # Nothing new, but an earlier commit may still be waiting to be pushed (offline last time).
            $ahead = 0
            try { $ahead = [int](Invoke-Git $RepoRoot @('rev-list', '--count', 'origin/main..HEAD')).Trim() } catch { }
            if ($ahead -gt 0) {
                try { Invoke-Git $RepoRoot @('push', '--quiet', 'origin', 'HEAD:main') | Out-Null; & $log "pushed $ahead earlier commit(s)" }
                catch { & $log "push failed: $($_.Exception.Message)" 'ERROR'; Register-Run 'sync'; return 4 }
            }
            Register-Run 'sync'
            return 0
        }

        $allowFile = Join-Path $RepoRoot 'tests\fixtures\allowed-emails.txt'
        $allowed = if (Test-Path $allowFile) { @(Get-Content $allowFile | Where-Object { $_ -and -not $_.StartsWith('#') }) } else { @() }
        $files = @($changes | Where-Object { $_.Status -notmatch 'D' } | ForEach-Object { Join-Path $RepoRoot $_.Path })
        $hits = @(Find-Secrets $files -AllowedEmails $allowed)
        if ($hits.Count -gt 0) {
            # Keep the captured edits (never lose the user's text); just do not publish them.
            foreach ($h in $hits) { & $log ("possible secret ({0}) in {1}:{2}; nothing committed" -f $h.Rule, $h.Path, $h.Line) 'ERROR' }
            Register-Run 'sync'
            return 2
        }

        # A conflict already pushed for exactly this text is not pushed again.
        $conflictState = Join-Path (Get-AgyPaths).StateDir 'sync-conflict.json'
        $conflictHash = $null
        if ($cap.Conflict) {
            $sha = [Security.Cryptography.SHA256]::Create()
            $blob = ($changes | Sort-Object { $_.Path } | ForEach-Object { $_.Path + "`n" + (Read-TextFile (Join-Path $RepoRoot $_.Path)) }) -join "`n--`n"
            $conflictHash = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($blob))) -replace '-', ''
            $prev = Read-JsonFile $conflictState @{}
            if ($prev.hash -eq $conflictHash) {
                & $log "conflict still waiting for review on $($prev.branch); not pushed again" 'WARN'
                Register-Run 'sync'
                return 3
            }
        }

        $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm'
        Invoke-Git $RepoRoot (@('add', '-A', '--') + @($changes | ForEach-Object { $_.Path })) | Out-Null
        $git = Resolve-Tool git
        if ((Invoke-External $git @('diff', '--cached', '--quiet') $RepoRoot).ExitCode -eq 0) { Register-Run 'sync'; return 0 }
        Invoke-Git $RepoRoot @('commit', '--quiet', '-m', "sync($($prof.name)): $stamp") | Out-Null

        $conflictBranch = $null
        if ($cap.Conflict) { $conflictBranch = 'sync/' + $prof.name + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss') }
        else {
            $again = Update-ConfigRepo $RepoRoot
            if (-not $again.Ok) { $conflictBranch = 'sync/' + $prof.name + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss') }
        }
        if ($conflictBranch) {
            Invoke-Git $RepoRoot @('push', '--quiet', 'origin', ('HEAD:refs/heads/' + $conflictBranch)) | Out-Null
            Invoke-Git $RepoRoot @('fetch', '--quiet', 'origin') | Out-Null
            # --keep moves main back without touching unrelated uncommitted work in the clone.
            Invoke-Git $RepoRoot @('reset', '--quiet', '--keep', 'origin/main') | Out-Null
            if ($conflictHash) { Write-JsonFile $conflictState @{ hash = $conflictHash; branch = $conflictBranch } }
            & $log "changes conflict with main; pushed them to branch $conflictBranch for review" 'WARN'
            Register-Run 'sync'
            return 3
        }
        try { Invoke-Git $RepoRoot @('push', '--quiet', 'origin', 'HEAD:main') | Out-Null }
        catch { & $log "push failed: $($_.Exception.Message)" 'ERROR'; Register-Run 'sync'; return 4 }
        Remove-Item $conflictState -Force -ErrorAction SilentlyContinue
        Register-Run 'sync'
        & $log "synced: $($changes.Count) changed file(s)"
        return 0
    } finally {
        Exit-RunLock 'config'
    }
}
