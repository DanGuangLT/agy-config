BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\scripts\lib\All.ps1')
    $script:src = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:oldHome = $env:AGYCFG_HOME

    function Invoke-TestGit([string]$Dir, [string[]]$GitArgs) {
        $r = Invoke-External 'git' $GitArgs $Dir
        if ($r.ExitCode -ne 0) { throw "git $($GitArgs -join ' ') failed: $($r.StdErr)" }
        $r.StdOut.Trim()
    }
    # A shared clone (a git repo with one commit) and a follower machine using profile 'pat' in it.
    function New-FollowFixture([string]$Role = 'follower') {
        $env:AGYCFG_HOME = Join-Path $TestDrive ('h' + [guid]::NewGuid().ToString('N'))
        $repo = Join-Path $TestDrive ('r' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $repo | Out-Null
        foreach ($d in 'core', 'profiles', 'scripts') { Copy-Item -Recurse (Join-Path $script:src $d) (Join-Path $repo $d) }
        Invoke-TestGit $repo @('init', '-q', '-b', 'main') | Out-Null
        Invoke-TestGit $repo @('add', '-A') | Out-Null
        Invoke-TestGit $repo @('-c', 'user.name=t', '-c', 'user.email=t@example.invalid', 'commit', '-q', '-m', 'seed') | Out-Null
        New-ProfileFromTemplate $repo 'pat' 'auto' 'graphify' | Out-Null
        Set-MachineState @{ profile = 'pat'; role = $Role; repoPath = $repo }
        return $repo
    }
}
AfterAll { $env:AGYCFG_HOME = $script:oldHome }

Describe 'Invoke-Follow' {
    BeforeEach {
        Mock Write-Host { }
        Mock Invoke-Apply { 0 }
    }

    It 'shows that a new setup follows the shared repository' {
        $repo = New-FollowFixture
        $en = Read-JsonFile (Join-Path $repo 'scripts\i18n\en.json') @{}
        Invoke-Follow -RepoRoot $repo | Should -Be 0
        Should -Invoke Write-Host -ParameterFilter { $Object -like ($en.msgFollowOn -f '*') }
        Test-Following (Get-Profile $repo 'pat') | Should -BeTrue
    }
    It 'refuses to stop on an owner machine' {
        $repo = New-FollowFixture -Role owner
        Invoke-Follow -RepoRoot $repo -Stop | Should -Be 1
        Test-Path (Join-Path $repo 'profiles\pat\shared') | Should -BeFalse
    }
    It 'stop copies the shared files into the profile and records the moment' {
        $repo = New-FollowFixture
        Invoke-Follow -RepoRoot $repo -Stop | Should -Be 0
        $dir = Join-Path $repo 'profiles\pat'
        foreach ($n in 'GEMINI.core.md', 'permissions.json', 'sources.json', 'sources.lock.json') {
            Read-TextFile (Join-Path $dir ('shared\' + $n)) | Should -BeExactly (Read-TextFile (Join-Path $repo ('core\' + $n)))
        }
        $p = Get-Profile $repo 'pat'
        Test-Following $p | Should -BeFalse
        $p.upstream.commit | Should -Be (Invoke-TestGit $repo @('rev-parse', 'HEAD'))
        $p.upstream.stoppedAt | Should -Not -BeNullOrEmpty
        Should -Invoke Invoke-Apply -Times 0 -Exactly
    }
    It 'after stop the scripts read the user''s copy, so an original skill can be removed' {
        $repo = New-FollowFixture
        Invoke-Follow -RepoRoot $repo -Stop | Should -Be 0
        $own = Join-Path $repo 'profiles\pat\shared\sources.json'
        Write-JsonFile $own @(@(Read-JsonFile $own @()) | Where-Object { $_.id -ne 'superpowers' })
        $p = Get-Profile $repo 'pat'
        @(Get-SourceList $repo $p | ForEach-Object { $_.id }) | Should -Not -Contain 'superpowers'
        @(Get-SourceList $repo (Get-Profile $repo 'lianharman') | ForEach-Object { $_.id }) | Should -Contain 'superpowers'
    }
    It 'stop twice is harmless' {
        $repo = New-FollowFixture
        Invoke-Follow -RepoRoot $repo -Stop | Should -Be 0
        Invoke-Follow -RepoRoot $repo -Stop | Should -Be 0
        Test-Following (Get-Profile $repo 'pat') | Should -BeFalse
    }
    It 'resume drops the copy (keeping a backup), follows again and installs right away' {
        $repo = New-FollowFixture
        Invoke-Follow -RepoRoot $repo -Stop | Should -Be 0
        Invoke-Follow -RepoRoot $repo -Resume | Should -Be 0
        $p = Get-Profile $repo 'pat'
        Test-Following $p | Should -BeTrue
        (Read-JsonFile (Join-Path $repo 'profiles\pat\profile.json') @{}).ContainsKey('upstream') | Should -BeFalse
        Test-Path (Join-Path $repo 'profiles\pat\shared') | Should -BeFalse
        @(Get-ChildItem (Get-AgyPaths).BackupRoot -Directory -Filter '*-shared').Count | Should -Be 1
        Should -Invoke Invoke-Apply -Times 1 -Exactly
    }
    It 'resume reports a failed apply' {
        $repo = New-FollowFixture
        Invoke-Follow -RepoRoot $repo -Stop | Should -Be 0
        Mock Invoke-Apply { 1 }
        Invoke-Follow -RepoRoot $repo -Resume | Should -Be 1
    }
    It 'needs a set-up machine' {
        $repo = New-FollowFixture
        Remove-Item (Join-Path (Get-AgyPaths).StateDir 'machine.json')
        Invoke-Follow -RepoRoot $repo -Stop | Should -Be 1
    }
}

Describe 'Invoke-Apply while not following' {
    BeforeEach {
        Mock Update-ConfigRepo { @{ Ok = $true; Error = '' } }
        Mock Install-Source { @{ Ok = $true; Error = '' } }
        Mock Uninstall-Source { }
        Mock Test-Source { @{ Ok = $true; Error = '' } }
        Mock Install-LocalPlugin { $true }
        Mock Get-AgyPluginList { @() }
        Mock Get-GitHeadSha { 'f' * 40 }
        Mock Write-Host { }
    }

    It 'does not pull the shared clone and uses the user''s copy of the rules' {
        $repo = New-FollowFixture
        Invoke-Follow -RepoRoot $repo -Stop | Should -Be 0
        $rules = Join-Path $repo 'profiles\pat\shared\GEMINI.core.md'
        Write-TextFile $rules ((Read-TextFile $rules) + "`nMy own shared rule.`n")
        Invoke-Apply -RepoRoot $repo -SkipCapture | Should -Be 0
        Should -Invoke Update-ConfigRepo -Times 0 -Exactly -ParameterFilter { $RepoRoot -eq $repo }
        Read-TextFile (Get-AgyPaths).GeminiMd | Should -Match 'My own shared rule\.'
    }
    It 'uninstalls an original skill the user removed from the copy' {
        $repo = New-FollowFixture
        Invoke-Apply -RepoRoot $repo -SkipCapture | Should -Be 0
        Invoke-Follow -RepoRoot $repo -Stop | Should -Be 0
        $own = Join-Path $repo 'profiles\pat\shared\sources.json'
        Write-JsonFile $own @(@(Read-JsonFile $own @()) | Where-Object { $_.id -ne 'superpowers' })
        Invoke-Apply -RepoRoot $repo -SkipCapture | Should -Be 0
        Should -Invoke Uninstall-Source -Times 1 -Exactly -ParameterFilter { $Source.id -eq 'superpowers' }
    }
    It 'pulls the shared clone again after resume' {
        $repo = New-FollowFixture
        Invoke-Follow -RepoRoot $repo -Stop | Should -Be 0
        Invoke-Follow -RepoRoot $repo -Resume | Should -Be 0
        Should -Invoke Update-ConfigRepo -ParameterFilter { $RepoRoot -eq $repo }
    }
}

Describe 'Invoke-Follow with a personal backup repository' {
    BeforeEach {
        Mock Write-Host { }
        Mock Get-AgyPluginList { @() }
        Mock Get-GitHeadSha { 'f' * 40 }
    }
    It 'stop is saved in the backup repository, so a new machine restores it' {
        $repo = New-FollowFixture
        $backup = Join-Path $TestDrive ('b' + [guid]::NewGuid().ToString('N') + '.git')
        Invoke-TestGit $TestDrive @('init', '-q', '--bare', '-b', 'main', $backup) | Out-Null
        $dir = (Get-AgyPaths).PersonalDir
        (Initialize-PersonalRepo $backup $dir).Ok | Should -BeTrue
        New-ProfileFromTemplate $repo 'pat' 'auto' 'graphify' $dir | Out-Null
        Set-MachineState @{ profile = 'pat'; role = 'follower'; repoPath = $repo; backupRepo = $backup; profileRoot = $dir }
        Invoke-Follow -RepoRoot $repo -Stop | Should -Be 0
        (Invoke-External 'git' @('show', 'main:shared/sources.json') $backup).ExitCode | Should -Be 0
        (Invoke-External 'git' @('show', 'main:profile.json') $backup).StdOut | Should -Match '"follow": false'
    }
}
