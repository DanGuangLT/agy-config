# Repo -> machine. Spec section 6.2. ASCII-only file.
# Return codes: 0 done; 1 something failed (logged). Failed sources keep their previous version;
# everything else is still applied.

function Install-LocalPlugin([string]$Dir) {
    # `agy plugin install` fails while agy has the plugin open (weekly maintenance runs while agy is
    # running), so fall back to copying the folder in place; agy discovers plugin folders by plugin.json.
    $agy = Resolve-Tool agy
    if ($agy -and (Invoke-External $agy @('plugin', 'install', $Dir)).ExitCode -eq 0) { return $true }
    $manifest = Read-JsonFile (Join-Path $Dir 'plugin.json') @{}
    $name = if ($manifest.name) { $manifest.name } else { Split-Path -Leaf $Dir }
    try { Copy-Folder $Dir (Join-Path (Get-AgyPaths).PluginsDir $name); return $true } catch { return $false }
}

function Test-SourceWarning([string]$Err) {
    # Problems the user fixes on their own machine; the source is skipped, not counted as a failure.
    return ($Err -eq 'python-missing') -or ($Err -like 'python-too-old*')
}

function Merge-McpServerKeepingSecrets($Expanded, $Current) {
    # A field that still holds an unresolved ${VAR} keeps the value this machine already has.
    if (-not ($Current -is [hashtable])) { return $Expanded }
    $out = ConvertTo-PlainObject $Expanded
    foreach ($field in @($out.Keys)) {
        $v = $out[$field]
        if ($v -is [hashtable]) {
            foreach ($k in @($v.Keys)) {
                if ([string]$v[$k] -match '\$\{[A-Za-z0-9_]+\}' -and $Current[$field] -is [hashtable] -and $Current[$field].ContainsKey($k)) {
                    $v[$k] = $Current[$field][$k]
                }
            }
        } elseif ((Format-Json $v) -match '\$\{[A-Za-z0-9_]+\}' -and $Current.ContainsKey($field)) {
            $out[$field] = $Current[$field]
        }
    }
    return $out
}

function Invoke-Apply {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [switch]$SkipPull,
        [switch]$SkipCapture,
        [int]$LockWaitSeconds = 120
    )
    $log = { param($m, $l = 'INFO') Write-AgyLog -Script 'apply' -Message $m -Level $l }
    $paths = Get-AgyPaths
    $machine = Get-MachineState
    if (-not $machine.profile) { & $log 'no profile configured for this machine; run scripts/install.ps1' 'ERROR'; return 1 }
    $isOwner = $machine.role -eq 'owner'

    if (-not (Enter-RunLock 'config' -WaitSeconds $LockWaitSeconds)) { & $log 'another apply/sync is still running; nothing changed' 'ERROR'; return 1 }
    try {
        # 0. Save local edits into the repo working tree before regenerating anything.
        if (-not $SkipCapture -and (Get-Command Invoke-Sync -ErrorAction SilentlyContinue)) {
            $cap = if ($isOwner) { Invoke-Sync -RepoRoot $RepoRoot -Force } else { Invoke-Sync -RepoRoot $RepoRoot -CaptureOnly }
            if ($cap -eq 5) { & $log 'the config repo is in the middle of a merge, rebase or branch switch; nothing changed' 'ERROR'; return 1 }
        }

        # 1. Pull. Offline or conflicted: change nothing.
        if (-not $SkipPull) {
            $pull = Update-ConfigRepo $RepoRoot
            if (-not $pull.Ok) { & $log "pull failed, nothing changed: $($pull.Error)" 'ERROR'; return 1 }
        }

        $prof = Get-Profile $RepoRoot $machine.profile
        $pending = if ($isOwner) { Get-PendingLock } else { $null }
        $sources = @(Get-SourceList $RepoRoot $prof)
        $lock = Get-EffectiveLock $RepoRoot $prof $pending
        $applied = Get-AppliedState
        if (-not ($applied.sourceDefs -is [hashtable])) { $applied.sourceDefs = @{} }

        # 2. Sources at their locked versions. A failing source keeps its previous version.
        $failures = @()
        $newSources = @{}
        $newDefs = @{}
        foreach ($s in $sources) {
            $newDefs[$s.id] = $s
            $target = $lock[$s.id]
            if (-not $target) {
                if (-not $isOwner) { $failures += "$($s.id): no locked version in the repo (an owner machine must lock it first)"; continue }
                try { $target = Get-LatestVersion $s } catch { $failures += "$($s.id): no locked version and latest lookup failed: $($_.Exception.Message)"; continue }
            }
            if ($applied.sources[$s.id] -eq $target -and (Test-Source $s).Ok) { $newSources[$s.id] = $target; continue }
            $r = Install-Source $s $target
            if ($r.Ok) {
                $newSources[$s.id] = if ($r.Version) { $r.Version } else { $target }
                & $log "installed $($s.id) @ $($newSources[$s.id])"
            } elseif (Test-SourceWarning $r.Error) {
                & $log "skipped $($s.id): $($r.Error)" 'WARN'
            } else {
                $failures += "$($s.id): $($r.Error)"
                if ($applied.sources.ContainsKey($s.id)) { $newSources[$s.id] = $applied.sources[$s.id] }
            }
        }
        foreach ($f in $failures) { & $log "source failed: $f" 'ERROR' }
        # Uninstall what the repo dropped, but never while sources are failing.
        if ($failures.Count -eq 0) {
            foreach ($id in @($applied.sources.Keys)) {
                if (-not $newDefs.ContainsKey($id) -and $applied.sourceDefs[$id]) {
                    Uninstall-Source $applied.sourceDefs[$id]
                    & $log "uninstalled $id (no longer in the repo)"
                }
            }
        } else {
            foreach ($id in @($applied.sources.Keys)) {
                if (-not $newDefs.ContainsKey($id)) { $newSources[$id] = $applied.sources[$id]; $newDefs[$id] = $applied.sourceDefs[$id] }
            }
        }

        # 3. Repo-owned plugin and the profile's own plugins/skills.
        $ownPlugins = @()
        $ownSkills = @()
        $core = Join-Path $RepoRoot 'core\plugins\agy-self-config'
        if (Test-Path $core) { if (-not (Install-LocalPlugin $core)) { & $log 'could not install agy-self-config' 'WARN' } }
        $pp = Join-Path $prof.Path 'plugins'
        if (Test-Path $pp) {
            foreach ($d in Get-ChildItem $pp -Directory) {
                if (Install-LocalPlugin $d.FullName) { $ownPlugins += $d.Name } else { & $log "could not install own plugin $($d.Name)" 'WARN'; $ownPlugins += $d.Name }
            }
        }
        $ps = Join-Path $prof.Path 'skills'
        if (Test-Path $ps) {
            foreach ($d in Get-ChildItem $ps -Directory) { Copy-Folder $d.FullName (Join-Path $paths.SkillsDir $d.Name); $ownSkills += $d.Name }
        }
        foreach ($n in @($applied.ownSkills)) { if ($n -and $ownSkills -notcontains $n) { Remove-Item (Join-Path $paths.SkillsDir $n) -Recurse -Force -ErrorAction SilentlyContinue } }
        foreach ($n in @($applied.ownPlugins)) { if ($n -and $ownPlugins -notcontains $n) { Uninstall-AgyPlugin $n } }

        # 4. GEMINI.md
        $coreText = (Read-TextFile (Join-Path $RepoRoot 'core\GEMINI.core.md')).TrimEnd("`r", "`n")
        Write-TextFile $paths.GeminiMd (Build-GeminiMd $coreText $prof.GeminiProfileText $prof.projectMap.tool)

        # 5. Permissions: add ours, drop the ones we added earlier that the repo no longer lists.
        $wanted = @(@(Read-JsonFile (Join-Path $RepoRoot 'core\permissions.json') @()) + @($prof.Permissions) | Where-Object { $_ } | Sort-Object -Unique)
        Merge-Permissions $paths.CliSettings $wanted | Out-Null
        $dropped = @(@($applied.permissions) | Where-Object { $_ -and $wanted -notcontains $_ })
        if ($dropped.Count -gt 0) { Remove-Permissions $paths.CliSettings $dropped }

        # 6. MCP servers from the profile. Unresolved ${VARS} never overwrite a working machine value.
        $mcpNames = @()
        $profMcp = Join-Path $prof.Path 'mcp.json'
        if (Test-Path $profMcp) {
            $x = Expand-McpConfig (Read-JsonFile $profMcp @{})
            $cfg = Read-JsonFile $paths.McpConfig @{ mcpServers = @{} }
            if (-not ($cfg.mcpServers -is [hashtable])) { $cfg.mcpServers = @{} }
            foreach ($n in @($x.Config.mcpServers.Keys)) {
                $cfg.mcpServers[$n] = Merge-McpServerKeepingSecrets $x.Config.mcpServers[$n] $cfg.mcpServers[$n]
                $mcpNames += $n
            }
            foreach ($v in $x.Missing) { & $log "MCP variable $v is not set; kept this machine's existing value where there was one" 'WARN' }
            foreach ($n in @($applied.mcpServers)) { if ($n -and $mcpNames -notcontains $n) { $cfg.mcpServers.Remove($n) } }
            Write-JsonFile $paths.McpConfig $cfg
        }

        # 7. Record what we installed (base for sync's three-way merges).
        $skillLock = Read-JsonFile $paths.SkillLock @{}
        $skillLockNames = if ($skillLock.skills -is [hashtable]) { @($skillLock.skills.Keys | Sort-Object) } else { @() }
        Set-AppliedState @{
            sources           = $newSources
            sourceDefs        = $newDefs
            ownSkills         = $ownSkills
            ownPlugins        = $ownPlugins
            permissions       = $wanted
            mcpServers        = $mcpNames
            skillLockNames    = $skillLockNames
            geminiManaged     = $true
            geminiCoreText    = $coreText
            geminiProfileText = $prof.GeminiProfileText
        }
        if ($isOwner -and $pending) {
            $repoLock = Get-EffectiveLock $RepoRoot $prof $null
            $caughtUp = $true
            foreach ($k in $pending.versions.Keys) { if ($repoLock[$k] -ne $pending.versions[$k]) { $caughtUp = $false } }
            if ($caughtUp) { Clear-PendingLock; & $log 'pending source versions are on main; cleared pending lock' }
        }
        if ($failures.Count -gt 0) { & $log ("apply finished with {0} failed source(s)" -f $failures.Count) 'ERROR'; return 1 }
        & $log ("apply done: {0} sources, {1} own skills, {2} own plugins" -f $newSources.Count, $ownSkills.Count, $ownPlugins.Count)
        return 0
    } finally {
        Exit-RunLock 'config'
    }
}
