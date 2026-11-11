BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\scripts\lib\All.ps1')
    $script:src = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:oldHome = $env:AGYCFG_HOME
    function New-InstallFixture {
        $env:AGYCFG_HOME = Join-Path $TestDrive ('h' + [guid]::NewGuid().ToString('N'))
        $repo = Join-Path $TestDrive ('r' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $repo | Out-Null
        foreach ($d in 'core', 'profiles', 'scripts') { Copy-Item -Recurse (Join-Path $script:src $d) (Join-Path $repo $d) }
        $p = Get-AgyPaths
        Write-TextFile $p.GeminiMd 'my old rules'
        Write-JsonFile $p.CliSettings @{ model = 'm'; trustedWorkspaces = @('D:\A') }
        New-Item -ItemType Directory -Force -Path (Join-Path $p.SkillsDir 'old-skill') | Out-Null
        return $repo
    }
}
AfterAll { $env:AGYCFG_HOME = $script:oldHome }

Describe 'Invoke-Install' {
    BeforeEach {
        Mock Resolve-Tool { $Name + '.exe' }
        Mock Test-PushAccess { $true }
        Mock Invoke-Apply { 0 }
        Mock Unregister-AgyTasks { }
        Mock Read-Host { 'y' }
        Mock Write-Host { }
    }

    It 'stops when agy is missing, before touching anything' {
        $repo = New-InstallFixture
        Mock Resolve-Tool { if ($Name -eq 'agy') { $null } else { $Name + '.exe' } }
        Invoke-Install -RepoRoot $repo -ProfileName lianharman -Yes | Should -Be 1
        Test-Path (Get-AgyPaths).BackupRoot | Should -BeFalse
        Should -Invoke Invoke-Apply -Times 0 -Exactly
    }
    It 'install backs up before apply' {
        $repo = New-InstallFixture
        $script:backupSeen = $false
        Mock Invoke-Apply {
            $b = Get-ChildItem (Get-AgyPaths).BackupRoot -Directory | Select-Object -First 1
            $script:backupSeen = [bool]$b -and (Test-Path (Join-Path $b.FullName 'GEMINI.md')) -and (Test-Path (Join-Path $b.FullName 'settings.json')) -and (Test-Path (Join-Path $b.FullName 'skills\old-skill'))
            0
        }
        Invoke-Install -RepoRoot $repo -ProfileName lianharman -Yes | Should -Be 0
        $script:backupSeen | Should -BeTrue
    }
    It 'records role and profile' {
        $repo = New-InstallFixture
        Invoke-Install -RepoRoot $repo -ProfileName lianharman -Yes | Should -Be 0
        $m = Get-MachineState
        $m.role | Should -Be 'owner'
        $m.profile | Should -Be 'lianharman'
        $m.repoPath | Should -Be $repo
    }
    It 'makes a follower when push access is missing' {
        $repo = New-InstallFixture
        Mock Test-PushAccess { $false }
        Invoke-Install -RepoRoot $repo -ProfileName lianharman -Yes | Should -Be 0
        (Get-MachineState).role | Should -Be 'follower'
    }
    It 'creates a new profile with the given language and project map tool' {
        $repo = New-InstallFixture
        Invoke-Install -RepoRoot $repo -ProfileName newbie -Language en -ProjectMapTool none -Yes | Should -Be 0
        $p = Get-Profile $repo 'newbie'
        $p.language | Should -Be 'en'
        $p.projectMap.tool | Should -Be 'none'
    }
    It 'uses English prompts whatever the computer language' {
        $repo = New-InstallFixture
        Mock Get-Culture { [pscustomobject]@{ Name = 'vi-VN' } }
        $en = Read-JsonFile (Join-Path $repo 'scripts\i18n\en.json') @{}
        Mock Read-Host { 'n' }
        Invoke-Install -RepoRoot $repo -ProfileName lianharman | Should -Be 1
        Should -Invoke Read-Host -ParameterFilter { $Prompt -eq $en.promptConfirm }
        Should -Invoke Invoke-Apply -Times 0 -Exactly
    }
    It 'stores an absolute repo path' {
        $repo = New-InstallFixture
        Push-Location (Split-Path -Parent $repo)
        try { Invoke-Install -RepoRoot ('.\' + (Split-Path -Leaf $repo)) -ProfileName lianharman -Yes | Should -Be 0 }
        finally { Pop-Location }
        (Get-MachineState).repoPath | Should -Be $repo
    }
    It 'asks for language and project map when creating a profile interactively' {
        $repo = New-InstallFixture
        Mock Get-Culture { [pscustomobject]@{ Name = 'en-US' } }
        $en = Read-JsonFile (Join-Path $repo 'scripts\i18n\en.json') @{}
        Mock Read-Host { 'vi' } -ParameterFilter { $Prompt -eq $en.promptLanguage }
        Mock Read-Host { '' } -ParameterFilter { $Prompt -eq $en.promptProjectMap }
        Mock Read-Host { 'y' } -ParameterFilter { $Prompt -eq $en.promptConfirm }
        Invoke-Install -RepoRoot $repo -ProfileName fresh | Should -Be 0
        $p = Get-Profile $repo 'fresh'
        $p.language | Should -Be 'vi'
        $p.projectMap.tool | Should -Be 'graphify'
    }
    It 'new profiles reply in the user''s language unless a language is given' {
        $repo = New-InstallFixture
        Invoke-Install -RepoRoot $repo -ProfileName autouser -Yes | Should -Be 0
        (Get-Profile $repo 'autouser').language | Should -Be 'auto'
    }
    It 'install is idempotent' {
        $repo = New-InstallFixture
        Invoke-Install -RepoRoot $repo -ProfileName again -Language en -ProjectMapTool graphify -Yes | Should -Be 0
        $before = (Get-ChildItem (Join-Path $repo 'profiles')).Count
        Invoke-Install -RepoRoot $repo -ProfileName again -Yes | Should -Be 0
        (Get-ChildItem (Join-Path $repo 'profiles')).Count | Should -Be $before
        Should -Invoke Unregister-AgyTasks -Times 2 -Exactly
    }
    It 'returns 1 when apply fails, keeping what was installed' {
        $repo = New-InstallFixture
        Mock Invoke-Apply { 1 }
        Invoke-Install -RepoRoot $repo -ProfileName lianharman -Yes | Should -Be 1
        (Get-MachineState).profile | Should -Be 'lianharman'
    }
}

Describe 'Invoke-Uninstall' {
    BeforeEach {
        Mock Unregister-AgyTasks { }
        Mock Uninstall-AgyPlugin { }
        Mock Write-Host { }
    }
    It 'removes tasks and the repo plugin, leaving skills in place' {
        $repo = New-InstallFixture
        Invoke-Uninstall -Yes | Should -Be 0
        Should -Invoke Unregister-AgyTasks -Times 1 -Exactly
        Should -Invoke Uninstall-AgyPlugin -Times 1 -Exactly -ParameterFilter { $Name -eq 'agy-self-config' }
        Test-Path (Join-Path (Get-AgyPaths).SkillsDir 'old-skill') | Should -BeTrue
    }
    It 'restores GEMINI.md and settings from a backup' {
        $repo = New-InstallFixture
        $p = Get-AgyPaths
        $stamp = '20260101-000000'
        Write-TextFile (Join-Path $p.BackupRoot "$stamp\GEMINI.md") 'restored rules'
        Write-JsonFile (Join-Path $p.BackupRoot "$stamp\settings.json") @{ model = 'restored' }
        Invoke-Uninstall -RestoreBackup $stamp -Yes | Should -Be 0
        Read-TextFile $p.GeminiMd | Should -Be 'restored rules'
        (Read-JsonFile $p.CliSettings @{}).model | Should -Be 'restored'
    }
}
