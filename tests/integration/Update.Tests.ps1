BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\scripts\lib\All.ps1')
    $script:src = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:oldHome = $env:AGYCFG_HOME

    function Invoke-TestGit([string]$Dir, [string[]]$GitArgs) {
        $r = Invoke-External 'git' $GitArgs $Dir
        if ($r.ExitCode -ne 0) { throw "git $($GitArgs -join ' ') failed: $($r.StdErr)" }
        $r.StdOut.Trim()
    }
    function New-UpdateWorld([string]$Role = 'owner') {
        $w = Join-Path $TestDrive ('w' + [guid]::NewGuid().ToString('N'))
        $origin = Join-Path $w 'origin.git'
        $seed = Join-Path $w 'seed'
        New-Item -ItemType Directory -Force -Path $seed | Out-Null
        Invoke-TestGit $w @('init', '-q', '--bare', '-b', 'main', $origin) | Out-Null
        Invoke-TestGit $seed @('init', '-q', '-b', 'main') | Out-Null
        foreach ($d in 'core', 'profiles', 'scripts') { Copy-Item -Recurse (Join-Path $script:src $d) (Join-Path $seed $d) }
        Invoke-TestGit $seed @('add', '-A') | Out-Null
        Invoke-TestGit $seed @('-c', 'user.name=t', '-c', 'user.email=t@example.invalid', 'commit', '-q', '-m', 'seed') | Out-Null
        Invoke-TestGit $seed @('remote', 'add', 'origin', $origin) | Out-Null
        Invoke-TestGit $seed @('push', '-q', 'origin', 'main') | Out-Null
        $repo = Join-Path $w 'clone'
        Invoke-TestGit $w @('clone', '-q', $origin, $repo) | Out-Null
        Invoke-TestGit $repo @('config', 'user.name', 'owner') | Out-Null
        Invoke-TestGit $repo @('config', 'user.email', 'owner@example.invalid') | Out-Null
        $env:AGYCFG_HOME = Join-Path $w 'home'
        Set-MachineState @{ profile = 'lianharman'; role = $Role; repoPath = $repo }
        @{ Root = $w; Origin = $origin; Repo = $repo }
    }
    $script:sp = @{ id = 'superpowers'; type = 'git-plugin'; repo = 'https://github.com/obra/superpowers'; plugin = 'superpowers'; provides = @('superpowers') }
    $script:design = @{ id = 'design'; type = 'packaged-plugin'; repo = 'https://github.com/anthropics/knowledge-work-plugins'; plugin = 'design'; paths = @('design'); provides = @('design') }
}
AfterAll {
    $env:AGYCFG_HOME = $script:oldHome
    Get-ChildItem -LiteralPath $TestDrive -Recurse -Force -File -ErrorAction SilentlyContinue | ForEach-Object { $_.IsReadOnly = $false }
}

Describe 'Get-CompareUrl' {
    It 'builds the compare link from https and ssh remotes' {
        Get-CompareUrl 'https://github.com/DanGuangLT/Pre-configured-skills-for-the-antigravity-agent.git' | Should -Be 'https://github.com/DanGuangLT/Pre-configured-skills-for-the-antigravity-agent/compare/main...update/sources?expand=1'
        Get-CompareUrl 'git@github.com:a/b.git' | Should -Be 'https://github.com/a/b/compare/main...update/sources?expand=1'
    }
}

Describe 'Invoke-Update' {
    BeforeEach {
        Mock Get-SourceList { @($script:sp, $script:design) }
        Mock Get-EffectiveLock { @{ superpowers = 'old-sp'; design = 'old-design' } }
        Mock Get-LatestVersion { 'new-' + $Source.id }
        Mock Install-Source { @{ Ok = $true; Error = '' } }
        Mock Test-Source { @{ Ok = $true; Error = '' } }
        Mock Restore-MarketplaceSnapshot { $true }
    }

    It 'follower exits without changes' {
        $w = New-UpdateWorld -Role follower
        Invoke-Update -RepoRoot $w.Repo | Should -Be 0
        Should -Invoke Install-Source -Times 0 -Exactly
    }
    It 'writes pending lock' {
        $w = New-UpdateWorld
        Invoke-Update -RepoRoot $w.Repo -NoPush | Should -Be 0
        $p = Get-PendingLock
        $p.versions.superpowers | Should -Be 'new-superpowers'
        $p.versions.design | Should -Be 'new-design'
    }
    It 'rolls back failing source and keeps others' {
        $w = New-UpdateWorld
        Mock Test-Source { @{ Ok = $false; Error = 'broken skill' } } -ParameterFilter { $Source.id -eq 'superpowers' }
        Invoke-Update -RepoRoot $w.Repo -NoPush | Should -Be 0
        Should -Invoke Install-Source -Times 1 -Exactly -ParameterFilter { $Source.id -eq 'superpowers' -and $Version -eq 'old-sp' }
        $p = Get-PendingLock
        $p.versions.ContainsKey('superpowers') | Should -BeFalse
        $p.versions.design | Should -Be 'new-design'
    }
    It 'does nothing when everything is current' {
        $w = New-UpdateWorld
        Mock Get-LatestVersion { if ($Source.id -eq 'superpowers') { 'old-sp' } else { 'old-design' } }
        Invoke-Update -RepoRoot $w.Repo | Should -Be 0
        Should -Invoke Install-Source -Times 0 -Exactly
        Get-PendingLock | Should -BeNullOrEmpty
        { Invoke-TestGit $w.Origin @('rev-parse', '--verify', 'update/sources') } | Should -Throw
    }
    It 'pushes update/sources with summary table in commit body' {
        $w = New-UpdateWorld
        Invoke-Update -RepoRoot $w.Repo | Should -Be 0
        $body = Invoke-TestGit $w.Origin @('log', '-1', '--format=%B', 'update/sources')
        $body | Should -Match 'chore\(sources\): weekly update \d{4}-\d{2}-\d{2}'
        $body | Should -Match '\| source \| old \| new \| result \|'
        $body | Should -Match '\| superpowers \| old-sp \| new-superpowers \| updated \|'
        $lock = Invoke-TestGit $w.Origin @('show', 'update/sources:core/sources.lock.json')
        $lock | Should -Match '"superpowers": "new-superpowers"'
        # The main working tree is untouched.
        Invoke-TestGit $w.Repo @('branch', '--show-current') | Should -Be 'main'
        Invoke-TestGit $w.Repo @('status', '--porcelain') | Should -BeNullOrEmpty
    }
    It 'logs compare url' {
        $w = New-UpdateWorld
        Invoke-Update -RepoRoot $w.Repo | Out-Null
        $log = Get-Content (Join-Path (Get-AgyPaths).LogDir ('update-' + (Get-Date -Format 'yyyyMMdd') + '.log')) -Raw
        $log | Should -Match 'update/sources'
    }
}
