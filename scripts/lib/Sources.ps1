# Source model: which third-party skills/plugins to install, at which locked version. ASCII-only file.
# Entry types: github-skills, git-plugin, packaged-plugin (Source.GitHub.ps1); pip-tool, marketplace (Source.Other.ps1).

function Get-SourceList([string]$RepoRoot, $ProfileData) {
    $core = @(Read-JsonFile (Join-Path $RepoRoot 'core\sources.json') @())
    $byId = [ordered]@{}
    foreach ($s in $core) { $byId[$s.id] = $s }
    foreach ($s in @($ProfileData.Sources)) { if ($s) { $byId[$s.id] = $s } }
    $tool = 'graphify'
    if ($ProfileData.projectMap -and $ProfileData.projectMap.tool) { $tool = $ProfileData.projectMap.tool }
    foreach ($s in $byId.Values) {
        if ($s.when -is [hashtable] -and $s.when.projectMap -and $s.when.projectMap -ne $tool) { continue }
        $s
    }
}

function Get-EffectiveLock([string]$RepoRoot, $ProfileData, $Pending) {
    $lock = @{}
    $core = Read-JsonFile (Join-Path $RepoRoot 'core\sources.lock.json') @{}
    foreach ($k in $core.Keys) { $lock[$k] = $core[$k] }
    if ($ProfileData.Lock -is [hashtable]) { foreach ($k in $ProfileData.Lock.Keys) { $lock[$k] = $ProfileData.Lock[$k] } }
    if ($Pending -and $Pending.versions -is [hashtable]) { foreach ($k in $Pending.versions.Keys) { $lock[$k] = $Pending.versions[$k] } }
    return $lock
}

function Install-Source($Source, [string]$Version) {
    try {
        switch ($Source.type) {
            'github-skills' { return Install-GitHubSkills $Source $Version }
            'git-plugin' { return Install-GitPlugin $Source $Version }
            'packaged-plugin' { return Install-PackagedPlugin $Source $Version }
            'pip-tool' { return Install-PipTool $Source $Version }
            'marketplace' { return Install-Marketplace $Source $Version }
            default { return @{ Ok = $false; Error = "unknown source type '$($Source.type)' for '$($Source.id)'" } }
        }
    } catch {
        return @{ Ok = $false; Error = "$($Source.id): $($_.Exception.Message)" }
    }
}

function Uninstall-Source($Source) {
    switch ($Source.type) {
        'github-skills' {
            foreach ($sk in @($Source.skills)) {
                Remove-Item (Join-Path (Get-AgyPaths).SkillsDir $sk.name) -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        'pip-tool' { Uninstall-PipTool $Source }
        default { Uninstall-AgyPlugin $Source.plugin }
    }
}

function Get-LatestVersion($Source) {
    switch ($Source.type) {
        'pip-tool' { return Get-PipLatestVersion $Source }
        'marketplace' { return 'latest' }
        default { return Get-GitHeadSha $Source.repo }
    }
}

function Test-SkillFolder([string]$Dir) {
    $f = Join-Path $Dir 'SKILL.md'
    if (-not (Test-Path $f)) { return $false }
    $t = (Read-TextFile $f) -replace "`r`n", "`n"
    if ($t -notmatch '(?s)^---\n(.*?)\n---') { return $false }
    $fm = $Matches[1]
    return ($fm -match '(?m)^name:\s*\S') -and ($fm -match '(?m)^description:\s*\S')
}

function Test-Source($Source) {
    $paths = Get-AgyPaths
    switch ($Source.type) {
        'github-skills' {
            foreach ($sk in @($Source.skills)) {
                if (-not (Test-SkillFolder (Join-Path $paths.SkillsDir $sk.name))) { return @{ Ok = $false; Error = "skill '$($sk.name)' missing or invalid SKILL.md" } }
            }
            return @{ Ok = $true; Error = '' }
        }
        'pip-tool' {
            foreach ($n in @($Source.provides)) {
                if (-not (Test-SkillFolder (Join-Path $paths.SkillsDir $n))) { return @{ Ok = $false; Error = "skill '$n' missing after install" } }
            }
            return @{ Ok = $true; Error = '' }
        }
        default {
            $agy = Resolve-Tool agy
            if (-not $agy) { return @{ Ok = $false; Error = 'agy-missing' } }
            $r = Invoke-External $agy @('plugin', 'validate', (Join-Path $paths.PluginsDir $Source.plugin))
            if ($r.ExitCode -ne 0) { return @{ Ok = $false; Error = "agy plugin validate failed: $($r.StdErr)$($r.StdOut)" } }
            return @{ Ok = $true; Error = '' }
        }
    }
}

function Uninstall-AgyPlugin([string]$Name) {
    if (-not $Name) { return }
    $agy = Resolve-Tool agy
    $ok = $false
    if ($agy) { $ok = (Invoke-External $agy @('plugin', 'uninstall', $Name)).ExitCode -eq 0 }
    if (-not $ok) { Remove-Item (Join-Path (Get-AgyPaths).PluginsDir $Name) -Recurse -Force -ErrorAction SilentlyContinue }
}
