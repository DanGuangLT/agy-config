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
    It 'install is idempotent with -Reinstall' {
        $repo = New-InstallFixture
        Invoke-Install -RepoRoot $repo -ProfileName again -Language en -ProjectMapTool graphify -Yes | Should -Be 0
        $before = (Get-ChildItem (Join-Path $repo 'profiles')).Count
        Invoke-Install -RepoRoot $repo -Reinstall -Yes | Should -Be 0
        (Get-ChildItem (Join-Path $repo 'profiles')).Count | Should -Be $before
        (Get-MachineState).profile | Should -Be 'again'
        Should -Invoke Unregister-AgyTasks -Times 2 -Exactly
    }
    It 'a second run on a set-up machine only reports the setup' {
        $repo = New-InstallFixture
        Invoke-Install -RepoRoot $repo -ProfileName lianharman -Yes | Should -Be 0
        Set-AppliedState @{ sources = @{} }
        $en = Read-JsonFile (Join-Path $repo 'scripts\i18n\en.json') @{}
        Mock Install-LocalPlugin { $true }
        Invoke-Install -RepoRoot $repo | Should -Be 0
        Should -Invoke Invoke-Apply -Times 1 -Exactly
        Should -Invoke Read-Host -Times 0 -Exactly
        # apply is mocked, so the plugin is missing: the check reinstalls it.
        Should -Invoke Install-LocalPlugin -Times 1 -Exactly
        Should -Invoke Write-Host -ParameterFilter { $Object -eq ($en.msgAlreadyInstalled -f 'lianharman', 'owner', $en.msgBackupOrigin) }
    }
    It 'adopts this folder when the recorded clone was moved away' {
        $repo = New-InstallFixture
        Set-MachineState @{ profile = 'lianharman'; role = 'owner'; repoPath = (Join-Path $TestDrive 'gone-folder') }
        Set-AppliedState @{ sources = @{} }
        Mock Install-LocalPlugin { $true }
        Invoke-Install -RepoRoot $repo | Should -Be 0
        (Get-MachineState).repoPath | Should -Be $repo
        Should -Invoke Invoke-Apply -Times 0 -Exactly
    }
    It 'keeps another existing clone unless -Reinstall is given' {
        $other = New-InstallFixture
        $repo = Join-Path $TestDrive ('r' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $repo | Out-Null
        foreach ($d in 'core', 'profiles', 'scripts') { Copy-Item -Recurse (Join-Path $script:src $d) (Join-Path $repo $d) }
        Set-MachineState @{ profile = 'lianharman'; role = 'owner'; repoPath = $other }
        Invoke-Install -RepoRoot $repo | Should -Be 0
        (Get-MachineState).repoPath | Should -Be $other
        Invoke-Install -RepoRoot $repo -Reinstall -Yes | Should -Be 0
        (Get-MachineState).repoPath | Should -Be $repo
    }
    It 'finishes an install that stopped before anything was applied' {
        $repo = New-InstallFixture
        Set-MachineState @{ profile = 'lianharman'; role = 'owner'; repoPath = $repo }
        Invoke-Install -RepoRoot $repo | Should -Be 0
        Should -Invoke Invoke-Apply -Times 1 -Exactly
    }
    It 'tells where the agy folder is' {
        $repo = New-InstallFixture
        $en = Read-JsonFile (Join-Path $repo 'scripts\i18n\en.json') @{}
        Invoke-Install -RepoRoot $repo -ProfileName lianharman -Yes | Should -Be 0
        Should -Invoke Write-Host -ParameterFilter { $Object -eq ($en.msgAgyFolder -f (Get-AgyPaths).AgyDir) }
    }
    It 'returns 1 when apply fails, keeping what was installed' {
        $repo = New-InstallFixture
        Mock Invoke-Apply { 1 }
        Invoke-Install -RepoRoot $repo -ProfileName lianharman -Yes | Should -Be 1
        (Get-MachineState).profile | Should -Be 'lianharman'
    }
}

Describe 'Invoke-Install with a personal backup repository' {
    BeforeAll {
        $script:realGit = Resolve-Tool git
        function New-BackupRepo([hashtable]$Seed) {
            $origin = Join-Path $TestDrive ('backup' + [guid]::NewGuid().ToString('N') + '.git')
            (Invoke-External 'git' @('init', '-q', '--bare', '-b', 'main', $origin) $TestDrive).ExitCode | Should -Be 0
            if ($Seed) {
                $dir = Join-Path $TestDrive ('seed' + [guid]::NewGuid().ToString('N'))
                (Invoke-External 'git' @('clone', '-q', $origin, $dir) $TestDrive).ExitCode | Should -Be 0
                Copy-Item -Recurse -Force (Join-Path $script:src 'profiles\_template\*') $dir
                $data = Read-JsonFile (Join-Path $dir 'profile.json') @{}
                foreach ($k in $Seed.Keys) { $data[$k] = $Seed[$k] }
                Write-JsonFile (Join-Path $dir 'profile.json') $data
                foreach ($a in @(, @('add', '-A')) + @(, @('-c', 'user.name=t', '-c', 'user.email=t@example.invalid', 'commit', '-q', '-m', 'seed')) + @(, @('push', '-q', 'origin', 'main'))) {
                    (Invoke-External 'git' $a $dir).ExitCode | Should -Be 0
                }
            }
            return $origin
        }
        function Get-BackupFile([string]$Origin, [string]$Path) {
            $r = Invoke-External 'git' @('show', ('main:' + $Path)) $Origin
            if ($r.ExitCode -ne 0) { return $null }
            return $r.StdOut
        }
    }
    BeforeEach {
        Mock Resolve-Tool { if ($Name -eq 'git') { $script:realGit } else { $Name + '.exe' } }
        # The shared clone is a follower; the personal clone (a local bare repo) is really pushed to.
        Mock Test-PushAccess { $true }
        Mock Test-PushAccess { $false } -ParameterFilter { $RepoRoot -notlike '*.agy-config-personal*' }
        Mock Invoke-Apply { 0 }
        Mock Unregister-AgyTasks { }
        Mock Get-AgyPluginList { @() }
        Mock Get-GitHeadSha { 'f' * 40 }
        Mock Read-Host { 'y' }
        Mock Write-Host { }
    }

    It 'creates the profile at the root of an empty backup repository and pushes it' {
        $repo = New-InstallFixture
        $origin = New-BackupRepo
        Invoke-Install -RepoRoot $repo -BackupRepo $origin -Language vi -ProjectMapTool none -Yes | Should -Be 0
        $m = Get-MachineState
        $m.role | Should -Be 'follower'
        $m.backupRepo | Should -Be $origin
        $m.profileRoot | Should -Be (Get-AgyPaths).PersonalDir
        $m.profile | Should -Be (Get-RepoOwnerName $origin)
        Test-Path (Join-Path $repo ('profiles\' + $m.profile)) | Should -BeFalse
        (Get-BackupFile $origin 'profile.json') | Should -Match '"language": "vi"'
        (Get-BackupFile $origin 'README.md') | Should -Match 'agy configuration backup'
        (Get-BackupFile $origin 'GEMINI.profile.md') | Should -Match 'Vietnamese'
    }
    It 'asks a follower for the backup repository' {
        $repo = New-InstallFixture
        $origin = New-BackupRepo
        $en = Read-JsonFile (Join-Path $repo 'scripts\i18n\en.json') @{}
        Mock Read-Host { $origin } -ParameterFilter { $Prompt -eq $en.promptBackupRepo }
        Mock Read-Host { '' } -ParameterFilter { $Prompt -eq $en.promptLanguage -or $Prompt -eq $en.promptProjectMap }
        Invoke-Install -RepoRoot $repo | Should -Be 0
        (Get-MachineState).backupRepo | Should -Be $origin
        (Get-BackupFile $origin 'profile.json') | Should -Match '"language": "auto"'
    }
    It 'Enter skips the backup repository' {
        $repo = New-InstallFixture
        $en = Read-JsonFile (Join-Path $repo 'scripts\i18n\en.json') @{}
        Mock Read-Host { '' } -ParameterFilter { $Prompt -eq $en.promptBackupRepo }
        Mock Read-Host { 'solo' } -ParameterFilter { $Prompt -like 'Profile name*' }
        Invoke-Install -RepoRoot $repo | Should -Be 0
        (Get-MachineState).profileRoot | Should -BeNullOrEmpty
        Test-Path (Join-Path $repo 'profiles\solo\profile.json') | Should -BeTrue
    }
    It 'does not ask an owner for a backup repository' {
        $repo = New-InstallFixture
        $en = Read-JsonFile (Join-Path $repo 'scripts\i18n\en.json') @{}
        Mock Test-PushAccess { $true } -ParameterFilter { $RepoRoot -notlike '*.agy-config-personal*' }
        Invoke-Install -RepoRoot $repo -ProfileName lianharman | Should -Be 0
        Should -Invoke Read-Host -Times 0 -Exactly -ParameterFilter { $Prompt -eq $en.promptBackupRepo }
    }
    It 'restores a saved configuration without asking the profile questions' {
        $repo = New-InstallFixture
        $origin = New-BackupRepo @{ name = 'alice'; language = 'ja'; projectMap = @{ tool = 'none' } }
        $en = Read-JsonFile (Join-Path $repo 'scripts\i18n\en.json') @{}
        Invoke-Install -RepoRoot $repo -BackupRepo $origin | Should -Be 0
        Should -Invoke Read-Host -Times 0 -Exactly -ParameterFilter { $Prompt -eq $en.promptLanguage }
        $m = Get-MachineState
        $m.profile | Should -Be 'alice'
        (Get-Profile $repo $m.profile $m.profileRoot).language | Should -Be 'ja'
    }
    It 'stops with a clear message when it cannot push to the backup repository' {
        $repo = New-InstallFixture
        $origin = New-BackupRepo
        Mock Test-PushAccess { $false }
        Invoke-Install -RepoRoot $repo -BackupRepo $origin -Yes | Should -Be 1
        (Get-MachineState).profile | Should -BeNullOrEmpty
        Should -Invoke Invoke-Apply -Times 0 -Exactly
    }
    It 'keeps the backup repository on -Reinstall' {
        $repo = New-InstallFixture
        $origin = New-BackupRepo
        Invoke-Install -RepoRoot $repo -BackupRepo $origin -Yes | Should -Be 0
        Invoke-Install -RepoRoot $repo -Reinstall -Yes | Should -Be 0
        (Get-MachineState).backupRepo | Should -Be $origin
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
    It 'forgets the setup so the next install runs in full' {
        $repo = New-InstallFixture
        Set-MachineState @{ profile = 'lianharman'; role = 'owner'; repoPath = $repo }
        Invoke-Uninstall -Yes | Should -Be 0
        (Get-MachineState).profile | Should -BeNullOrEmpty
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
