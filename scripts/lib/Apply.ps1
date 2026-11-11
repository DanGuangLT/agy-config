# Repo -> machine. Spec section 6.2. ASCII-only file.

function Install-LocalPlugin([string]$Dir) {
    $agy = Resolve-Tool agy
    if (-not $agy) { return $false }
    (Invoke-External $agy @('plugin', 'install', $Dir)).ExitCode -eq 0
}

function Invoke-Apply {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [switch]$SkipPull,
        [switch]$SkipCapture
    )
    $log = { param($m, $l = 'INFO') Write-AgyLog -Script 'apply' -Message $m -Level $l }
    $paths = Get-AgyPaths
    $machine = Get-MachineState
    if (-not $machine.profile) { & $log 'no profile configured for this machine; run scripts/install.ps1' 'ERROR'; return 1 }
    $isOwner = $machine.role -eq 'owner'

    # 0. Save local edits into the repo working tree before regenerating anything.
    if (-not $SkipCapture -and (Get-Command Invoke-Sync -ErrorAction SilentlyContinue)) {
        if ($isOwner) { Invoke-Sync -RepoRoot $RepoRoot -Force | Out-Null }
        else { Invoke-Sync -RepoRoot $RepoRoot -CaptureOnly | Out-Null }
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

    # 2. Sources at their locked versions.
    $failures = @()
    $newSources = @{}
    $newDefs = @{}
    foreach ($s in $sources) {
        $target = $lock[$s.id]
        if (-not $target) {
            try { $target = Get-LatestVersion $s } catch { $failures += "$($s.id): no locked version and latest lookup failed: $($_.Exception.Message)"; continue }
        }
        $newDefs[$s.id] = $s
        if ($applied.sources[$s.id] -eq $target -and (Test-Source $s).Ok) { $newSources[$s.id] = $target; continue }
        $r = Install-Source $s $target
        if ($r.Ok) {
            $newSources[$s.id] = if ($r.Version) { $r.Version } else { $target }
            & $log "installed $($s.id) @ $($newSources[$s.id])"
        } else {
            $failures += "$($s.id): $($r.Error)"
        }
    }
    if ($failures.Count -gt 0) {
        foreach ($f in $failures) { & $log "source failed: $f" 'ERROR' }
        & $log 'apply stopped; applied state unchanged' 'ERROR'
        return 1
    }
    foreach ($id in @($applied.sources.Keys)) {
        if (-not $newSources.ContainsKey($id) -and $applied.sourceDefs[$id]) {
            Uninstall-Source $applied.sourceDefs[$id]
            & $log "uninstalled $id (no longer in the repo)"
        }
    }

    # 3. Repo-owned plugin and the profile's own plugins/skills.
    $ownPlugins = @()
    $ownSkills = @()
    $core = Join-Path $RepoRoot 'core\plugins\agy-self-config'
    if (Test-Path $core) { if (-not (Install-LocalPlugin $core)) { & $log 'could not install agy-self-config' 'WARN' } }
    $pp = Join-Path $prof.Path 'plugins'
    if (Test-Path $pp) {
        foreach ($d in Get-ChildItem $pp -Directory) { if (Install-LocalPlugin $d.FullName) { $ownPlugins += $d.Name } }
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

    # 6. MCP servers from the profile.
    $mcpNames = @()
    $profMcp = Join-Path $prof.Path 'mcp.json'
    if (Test-Path $profMcp) {
        $x = Expand-McpConfig (Read-JsonFile $profMcp @{})
        foreach ($v in $x.Missing) { & $log "MCP variable $v is not set in the environment" 'WARN' }
        $cfg = Read-JsonFile $paths.McpConfig @{ mcpServers = @{} }
        if (-not ($cfg.mcpServers -is [hashtable])) { $cfg.mcpServers = @{} }
        foreach ($n in @($x.Config.mcpServers.Keys)) { $cfg.mcpServers[$n] = $x.Config.mcpServers[$n]; $mcpNames += $n }
        foreach ($n in @($applied.mcpServers)) { if ($n -and $mcpNames -notcontains $n) { $cfg.mcpServers.Remove($n) } }
        Write-JsonFile $paths.McpConfig $cfg
    }

    # 7. Record what we installed.
    Set-AppliedState @{
        sources        = $newSources
        sourceDefs     = $newDefs
        ownSkills      = $ownSkills
        ownPlugins     = $ownPlugins
        permissions    = $wanted
        mcpServers     = $mcpNames
        geminiManaged  = $true
        # Base texts for sync's three-way merge of GEMINI.md regions.
        geminiCoreText    = $coreText
        geminiProfileText = $prof.GeminiProfileText
    }
    if ($isOwner -and $pending) {
        $repoLock = Get-EffectiveLock $RepoRoot $prof $null
        $caughtUp = $true
        foreach ($k in $pending.versions.Keys) { if ($repoLock[$k] -ne $pending.versions[$k]) { $caughtUp = $false } }
        if ($caughtUp) { Clear-PendingLock; & $log 'pending source versions are on main; cleared pending lock' }
    }
    & $log ("apply done: {0} sources, {1} own skills, {2} own plugins" -f $newSources.Count, $ownSkills.Count, $ownPlugins.Count)
    return 0
}
