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
        $body | Should -Match '(?m)^\|---\|---\|---\|---\|$'
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

Describe 'Update publication regressions' {
    BeforeEach {
        $script:fixture = Join-Path $TestDrive ('publication-' + [guid]::NewGuid().ToString('N'))
        $env:AGYCFG_HOME = Join-Path $script:fixture 'home'
        $script:repo = Join-Path $script:fixture 'repo'
        Write-JsonFile (Join-Path $script:repo 'profiles\p\profile.json') @{ language = 'en' }
        Write-JsonFile (Join-Path $script:repo 'profiles\p\sources.json') @()
        Write-JsonFile (Join-Path $script:repo 'profiles\p\sources.lock.json') @{}
        Write-JsonFile (Join-Path $script:repo 'core\sources.lock.json') @{ superpowers = 'old-sp'; design = 'old-design' }
        Set-MachineState @{ profile = 'p'; role = 'owner'; repoPath = $script:repo }
        $script:pushedCore = $null
        $script:pushedProfile = $null
        $script:commitBody = $null
        Mock Resolve-Tool { 'git.exe' }
        Mock Get-SourceList { @($script:sp, $script:design) }
        Mock Get-LatestVersion { 'new-' + $Source.id }
        Mock Install-Source { @{ Ok = $true; Error = '' } }
        Mock Test-Source { @{ Ok = $true; Error = '' } }
        # Only the git process boundary is faked: locks, messages, state and logs use real files.
        Mock Invoke-External { @{ ExitCode = 0; StdOut = ''; StdErr = '' } }
        Mock Invoke-Git {
            if ($GitArgs[0] -eq 'worktree' -and $GitArgs[1] -eq 'add') {
                $wt = $GitArgs[-2]
                New-Item -ItemType Directory -Force -Path $wt | Out-Null
                foreach ($d in 'core', 'profiles') { Copy-Item -Recurse (Join-Path $script:repo $d) (Join-Path $wt $d) }
            } elseif ($GitArgs[0] -eq 'commit') {
                $script:commitBody = Read-TextFile $GitArgs[-1]
            } elseif ($GitArgs[0] -eq 'push') {
                $script:pushedCore = Read-JsonFile (Join-Path $Dir 'core\sources.lock.json') @{}
                $script:pushedProfile = Read-JsonFile (Join-Path $Dir 'profiles\p\sources.lock.json') @{}
            } elseif ($GitArgs[0] -eq 'remote') { return 'https://github.com/example/config.git' }
            return ''
        }
    }

    It 'carries previous pending <Scope> versions into the pushed lock and table' -TestCases @(
        @{ Scope = 'core' }, @{ Scope = 'profile' }
    ) {
        param($Scope)
        if ($Scope -eq 'profile') {
            Write-JsonFile (Join-Path $script:repo 'profiles\p\sources.json') @($script:design)
            Write-JsonFile (Join-Path $script:repo 'profiles\p\sources.lock.json') @{ design = 'old-design' }
        }
        Write-JsonFile (Get-StateFile 'pending.lock.json') @{ createdAt = (Get-Date).AddDays(-7).ToString('o'); versions = @{ design = 'prev-design' } }
        Mock Get-LatestVersion { if ($Source.id -eq 'design') { 'prev-design' } else { 'new-superpowers' } }
        Invoke-Update -RepoRoot $script:repo | Should -Be 0
        $script:pushedCore.superpowers | Should -Be 'new-superpowers'
        if ($Scope -eq 'core') { $script:pushedCore.design | Should -Be 'prev-design' }
        else { $script:pushedProfile.design | Should -Be 'prev-design' }
        $script:commitBody | Should -Match '\| design \| old-design \| prev-design \| carried over \|'
    }

    It 'keeps <Failure> errors local and publishes only <Reason>' -TestCases @(
        @{ Failure = 'check'; Reason = 'check failed' },
        @{ Failure = 'install'; Reason = 'install failed' },
        @{ Failure = 'validate'; Reason = 'rolled back' }
    ) {
        param($Failure, $Reason)
        $script:privateError = 'failed at C:\Users\someone\x | details' + "`nmore detail"
        if ($Failure -eq 'check') {
            Mock Get-LatestVersion { throw $script:privateError } -ParameterFilter { $Source.id -eq 'design' }
        } elseif ($Failure -eq 'install') {
            Mock Install-Source { @{ Ok = $false; Error = $script:privateError } } -ParameterFilter { $Source.id -eq 'design' }
        } else {
            Mock Test-Source { @{ Ok = $false; Error = $script:privateError } } -ParameterFilter { $Source.id -eq 'design' }
        }
        Invoke-Update -RepoRoot $script:repo | Should -Be 0
        $script:pushedCore.superpowers | Should -Be 'new-superpowers'
        $script:commitBody | Should -Not -Match 'C:\\Users\\someone|details|more detail'
        $script:commitBody | Should -Match ('\| design \| old-design \| .* \| ' + $Reason + ' \|')
        $log = Read-TextFile (Join-Path (Get-AgyPaths).LogDir ('update-' + (Get-Date -Format 'yyyyMMdd') + '.log'))
        $log | Should -Match ([regex]::Escape($script:privateError))
    }

    It 'blocks commit and push when the commit message scan finds a secret' {
        Mock Find-Secrets { @{ Path = $Paths[0]; Line = 1; Rule = 'generic-token' } }
        Invoke-Update -RepoRoot $script:repo | Should -Be 2
        Should -Invoke Find-Secrets -Times 1 -Exactly -ParameterFilter { $Paths[0] -eq (Join-Path (Get-AgyPaths).StateDir 'update-commit-msg.txt') }
        Should -Invoke Invoke-Git -Times 0 -Exactly -ParameterFilter { $GitArgs[0] -in @('commit', 'push') }
        $script:pushedCore | Should -BeNullOrEmpty
        $log = Read-TextFile (Join-Path (Get-AgyPaths).LogDir ('update-' + (Get-Date -Format 'yyyyMMdd') + '.log'))
        $log | Should -Match '\[ERROR\]'
        Test-Path (Get-StateFile 'update.lock') | Should -BeFalse
    }

    It 'escapes pipes and newlines in published table cells' {
        Mock Get-SourceList { @(@{ id = "super|powers`nid"; type = 'git-plugin' }) }
        Write-JsonFile (Join-Path $script:repo 'core\sources.lock.json') @{ "super|powers`nid" = "old|sp`nline" }
        Mock Get-LatestVersion { "new|sp`r`ncandidate" }
        Invoke-Update -RepoRoot $script:repo | Should -Be 0
        $script:commitBody | Should -Match ([regex]::Escape('| super\|powers<br>id | old\|sp<br>line | new\|sp<br>candidate | updated |'))
    }
}
