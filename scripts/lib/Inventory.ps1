# What is installed on this machine, and where each item comes from. ASCII-only file.

function Get-MachineInventory {
    $p = Get-AgyPaths
    $skills = @()
    if (Test-Path $p.SkillsDir) { $skills = @(Get-ChildItem -Path $p.SkillsDir -Directory | ForEach-Object { $_.Name } | Sort-Object) }
    @{
        Skills    = $skills
        Plugins   = @(Get-AgyPluginList)
        SkillLock = Read-JsonFile $p.SkillLock @{}
    }
}

function ConvertFrom-SkillLock($SkillLock, [string[]]$OnlySources) {
    $skills = $SkillLock.skills
    if (-not ($skills -is [hashtable])) { return }
    $groups = @{}
    foreach ($name in $skills.Keys) {
        $e = $skills[$name]
        if (-not $e.source) { continue }
        if ($OnlySources -and $OnlySources -notcontains $e.source) { continue }
        if (-not $groups.ContainsKey($e.source)) { $groups[$e.source] = @() }
        $dir = ($e.skillPath -replace '\\', '/') -replace '/?SKILL\.md$', ''
        $groups[$e.source] += , @{ name = $name; path = $dir; url = $e.sourceUrl }
    }
    foreach ($src in ($groups.Keys | Sort-Object)) {
        $items = @($groups[$src] | Sort-Object { $_.name })
        $url = @($items | Where-Object { $_.url } | Select-Object -First 1 | ForEach-Object { $_.url })
        $repo = if ($url) { $url[0] -replace '\.git$', '' } else { 'https://github.com/' + $src }
        @{
            id       = $src -replace '/', '-'
            type     = 'github-skills'
            repo     = $repo
            skills   = @($items | ForEach-Object { @{ name = $_.name; path = $_.path } })
            provides = @($items | ForEach-Object { $_.name })
        }
    }
}

function Get-Classification($Inventory, $Sources, $ProfileData, [string[]]$RepoOwnedPlugins) {
    $provided = @()
    foreach ($s in @($Sources)) {
        $provided += @($s.provides)
        $provided += @($s.skills | ForEach-Object { $_.name })
        if ($s.plugin) { $provided += $s.plugin }
    }
    $provided += @($RepoOwnedPlugins)
    $own = @($ProfileData.ownSkills) + @($ProfileData.ownPlugins)
    $ignored = @($ProfileData.ignored)

    $names = @($Inventory.Skills) + @($Inventory.Plugins | ForEach-Object { $_.name })
    $result = @{ Sourced = @(); Own = @(); Ignored = @(); Unknown = @() }
    foreach ($n in ($names | Where-Object { $_ } | Sort-Object -Unique)) {
        if ($provided -contains $n) { $result.Sourced += $n }
        elseif ($own -contains $n) { $result.Own += $n }
        elseif ($ignored -contains $n) { $result.Ignored += $n }
        else { $result.Unknown += $n }
    }
    return $result
}
