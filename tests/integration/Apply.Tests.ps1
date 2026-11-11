BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\scripts\lib\All.ps1')
    $script:src = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:oldHome = $env:AGYCFG_HOME

    function New-ApplyFixture([string]$Role = 'follower') {
        $env:AGYCFG_HOME = Join-Path $TestDrive ('h' + [guid]::NewGuid().ToString('N'))
        $repo = Join-Path $TestDrive ('r' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $repo | Out-Null
        foreach ($d in 'core', 'profiles', 'scripts') { Copy-Item -Recurse (Join-Path $script:src $d) (Join-Path $repo $d) }
        Set-MachineState @{ profile = 'lianharman'; role = $Role; repoPath = $repo }
        Write-JsonFile (Get-AgyPaths).CliSettings @{ model = 'Gemini 4 Argon (Medium)'; trustedWorkspaces = @('D:\Coding\A') }
        return $repo
    }
    function Get-LockedIds([string]$Repo) { @((Read-JsonFile (Join-Path $Repo 'core\sources.lock.json') @{}).Keys) }
}
AfterAll { $env:AGYCFG_HOME = $script:oldHome }

Describe 'Invoke-Apply' {
    BeforeEach {
        Mock Update-ConfigRepo { @{ Ok = $true; Error = '' } }
        Mock Install-Source { @{ Ok = $true; Error = '' } }
        Mock Uninstall-Source { }
        Mock Test-Source { @{ Ok = $true; Error = '' } }
        Mock Install-LocalPlugin { $true }
    }

    It 'installs every source on first run and records applied state' {
        $repo = New-ApplyFixture
        Invoke-Apply -RepoRoot $repo -SkipCapture | Should -Be 0
        $ids = @(Get-SourceList $repo (Get-Profile $repo 'lianharman') | ForEach-Object { $_.id })
        Should -Invoke Install-Source -Times $ids.Count -Exactly
        (Get-AppliedState).sources.superpowers | Should -Be (Read-JsonFile (Join-Path $repo 'core\sources.lock.json') @{}).superpowers
    }
    It 'installs only changed sources' {
        $repo = New-ApplyFixture
        Invoke-Apply -RepoRoot $repo -SkipCapture | Out-Null
        $a = Get-AppliedState
        $a.sources.superpowers = 'older'
        Set-AppliedState $a
        Invoke-Apply -RepoRoot $repo -SkipCapture | Should -Be 0
        # Mock calls are counted across both runs: superpowers = first run + changed, design = first run only.
        Should -Invoke Install-Source -Times 2 -Exactly -ParameterFilter { $Source.id -eq 'superpowers' }
        Should -Invoke Install-Source -Times 1 -Exactly -ParameterFilter { $Source.id -eq 'design' }
    }
    It 'uninstalls source removed from repo but only if previously applied' {
        $repo = New-ApplyFixture
        Invoke-Apply -RepoRoot $repo -SkipCapture | Out-Null
        $a = Get-AppliedState
        $a.sources['gone'] = 'v1'
        $a.sourceDefs['gone'] = @{ id = 'gone'; type = 'marketplace'; plugin = 'gone'; marketplace = 'm' }
        Set-AppliedState $a
        Invoke-Apply -RepoRoot $repo -SkipCapture | Should -Be 0
        Should -Invoke Uninstall-Source -Times 1 -Exactly -ParameterFilter { $Source.id -eq 'gone' }
        (Get-AppliedState).sources.ContainsKey('gone') | Should -BeFalse
    }
    It 'writes GEMINI.md with profile language rule' {
        $repo = New-ApplyFixture
        Invoke-Apply -RepoRoot $repo -SkipCapture | Out-Null
        $text = Read-TextFile (Get-AgyPaths).GeminiMd
        $s = Split-GeminiMd $text
        $s.Core | Should -BeExactly ((Read-TextFile (Join-Path $repo 'core\GEMINI.core.md')).TrimEnd("`n"))
        $s.Profile | Should -Match ([char]0x1EBF)
        $text | Should -Match 'Project map tool: graphify'
    }
    It 'keeps trustedWorkspaces and adds core permissions' {
        $repo = New-ApplyFixture
        Invoke-Apply -RepoRoot $repo -SkipCapture | Out-Null
        $s = Read-JsonFile (Get-AgyPaths).CliSettings @{}
        $s.trustedWorkspaces | Should -Be @('D:\Coding\A')
        $s.model | Should -Be 'Gemini 4 Argon (Medium)'
        $s.permissions.allow | Should -Contain 'command(git log --oneline -15)'
    }
    It 'installs the repo plugin agy-self-config' {
        $repo = New-ApplyFixture
        Invoke-Apply -RepoRoot $repo -SkipCapture | Out-Null
        Should -Invoke Install-LocalPlugin -ParameterFilter { $Dir -like '*core\plugins\agy-self-config' }
    }
    It 'leaves state untouched when a source fails' {
        $repo = New-ApplyFixture
        Invoke-Apply -RepoRoot $repo -SkipCapture | Out-Null
        $before = Read-TextFile (Join-Path (Get-AgyPaths).StateDir 'applied.json')
        $a = Get-AppliedState; $a.sources.superpowers = 'older'; $a.sources.design = 'older'; Set-AppliedState $a
        $before = Read-TextFile (Join-Path (Get-AgyPaths).StateDir 'applied.json')
        Mock Install-Source { @{ Ok = $false; Error = 'network down' } } -ParameterFilter { $Source.id -eq 'superpowers' }
        Invoke-Apply -RepoRoot $repo -SkipCapture | Should -Be 1
        Read-TextFile (Join-Path (Get-AgyPaths).StateDir 'applied.json') | Should -BeExactly $before
        $log = Get-Content (Join-Path (Get-AgyPaths).LogDir ('apply-' + (Get-Date -Format 'yyyyMMdd') + '.log')) -Raw
        $log | Should -Match 'superpowers'
        Should -Invoke Uninstall-Source -Times 0 -Exactly
    }
    It 'stops before changing anything when the pull fails' {
        $repo = New-ApplyFixture
        Mock Update-ConfigRepo { @{ Ok = $false; Error = 'offline' } }
        Invoke-Apply -RepoRoot $repo -SkipCapture | Should -Be 1
        Should -Invoke Install-Source -Times 0 -Exactly
        Test-Path (Get-AgyPaths).GeminiMd | Should -BeFalse
    }
    It 'pending versions win on owner' {
        $repo = New-ApplyFixture -Role owner
        Set-PendingLock @{ superpowers = 'pending-sha' }
        Invoke-Apply -RepoRoot $repo -SkipCapture | Should -Be 0
        Should -Invoke Install-Source -Times 1 -Exactly -ParameterFilter { $Source.id -eq 'superpowers' -and $Version -eq 'pending-sha' }
        (Get-PendingLock).versions.superpowers | Should -Be 'pending-sha'
    }
    It 'clears pending once main has the same versions' {
        $repo = New-ApplyFixture -Role owner
        $sha = (Read-JsonFile (Join-Path $repo 'core\sources.lock.json') @{}).superpowers
        Set-PendingLock @{ superpowers = $sha }
        Invoke-Apply -RepoRoot $repo -SkipCapture | Should -Be 0
        Get-PendingLock | Should -BeNullOrEmpty
    }
    It 'captures local edits first: capture-only on a follower, full sync on the owner' {
        Mock Invoke-Sync { 0 }
        $repo = New-ApplyFixture
        Invoke-Apply -RepoRoot $repo | Should -Be 0
        Should -Invoke Invoke-Sync -Times 1 -Exactly -ParameterFilter { $CaptureOnly }
        $repo2 = New-ApplyFixture -Role owner
        Invoke-Apply -RepoRoot $repo2 | Should -Be 0
        Should -Invoke Invoke-Sync -Times 1 -Exactly -ParameterFilter { $Force -and -not $CaptureOnly }
    }
    It 'ignores pending versions on a follower' {
        $repo = New-ApplyFixture
        Set-PendingLock @{ superpowers = 'pending-sha' }
        Invoke-Apply -RepoRoot $repo -SkipCapture | Out-Null
        Should -Invoke Install-Source -Times 0 -Exactly -ParameterFilter { $Version -eq 'pending-sha' }
    }
}
