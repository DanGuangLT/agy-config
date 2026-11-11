BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\scripts\lib\All.ps1')
    $script:src = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:oldHome = $env:AGYCFG_HOME
    $script:corePerms = @(Read-JsonFile (Join-Path $script:src 'core\permissions.json') @())

    function Invoke-TestGit([string]$Dir, [string[]]$GitArgs) {
        $r = Invoke-External 'git' $GitArgs $Dir
        if ($r.ExitCode -ne 0) { throw "git $($GitArgs -join ' ') failed: $($r.StdErr)" }
        $r.StdOut.Trim()
    }

    # A fresh "origin" with the repo content, and one clone per machine.
    function New-SyncWorld {
        $w = Join-Path $TestDrive ('w' + [guid]::NewGuid().ToString('N'))
        $origin = Join-Path $w 'origin.git'
        $seed = Join-Path $w 'seed'
        New-Item -ItemType Directory -Force -Path $seed | Out-Null
        Invoke-TestGit $w @('init', '-q', '--bare', '-b', 'main', $origin) | Out-Null
        Invoke-TestGit $seed @('init', '-q', '-b', 'main') | Out-Null
        foreach ($d in 'core', 'profiles', 'scripts') { Copy-Item -Recurse (Join-Path $script:src $d) (Join-Path $seed $d) }
        Invoke-TestGit $seed @('-c', 'user.name=t', '-c', 'user.email=t@example.invalid', 'add', '-A') | Out-Null
        Invoke-TestGit $seed @('-c', 'user.name=t', '-c', 'user.email=t@example.invalid', 'commit', '-q', '-m', 'seed') | Out-Null
        Invoke-TestGit $seed @('remote', 'add', 'origin', $origin) | Out-Null
        Invoke-TestGit $seed @('push', '-q', 'origin', 'main') | Out-Null
        @{ Root = $w; Origin = $origin }
    }

    function New-Machine($World, [string]$Name, [string]$Role = 'owner') {
        $repo = Join-Path $World.Root ('clone-' + $Name)
        Invoke-TestGit $World.Root @('clone', '-q', $World.Origin, $repo) | Out-Null
        Invoke-TestGit $repo @('config', 'user.name', "machine $Name") | Out-Null
        Invoke-TestGit $repo @('config', 'user.email', "$Name@example.invalid") | Out-Null
        $machine = @{ Name = $Name; Repo = $repo; Home = (Join-Path $World.Root ('home-' + $Name)) }
        Use-Machine $machine
        Set-MachineState @{ profile = 'lianharman'; role = $Role; repoPath = $repo }
        $prof = Get-Profile $repo 'lianharman'
        Write-TextFile (Get-AgyPaths).GeminiMd (Build-GeminiMd (Read-TextFile (Join-Path $repo 'core\GEMINI.core.md')) $prof.GeminiProfileText 'graphify')
        Write-JsonFile (Get-AgyPaths).CliSettings @{ model = 'secret-model-name'; trustedWorkspaces = @('D:\Private\Project'); permissions = @{ allow = $script:corePerms } }
        Set-AppliedState @{ sources = @{}; sourceDefs = @{}; ownSkills = @(); ownPlugins = @(); permissions = $script:corePerms; mcpServers = @(); geminiManaged = $true
            geminiProfileText = $prof.GeminiProfileText; geminiCoreText = (Read-TextFile (Join-Path $repo 'core\GEMINI.core.md')).TrimEnd("`r", "`n") }
        $machine
    }
    function Use-Machine($Machine) { $env:AGYCFG_HOME = $Machine.Home }
    function Get-OriginFile($World, [string]$Path) {
        $tmp = Join-Path $World.Root ('peek' + [guid]::NewGuid().ToString('N'))
        Invoke-TestGit $World.Root @('clone', '-q', $World.Origin, $tmp) | Out-Null
        $f = Join-Path $tmp $Path
        if (Test-Path $f) { Read-TextFile $f } else { $null }
    }
    function Add-MachinePermission([string]$Perm) { Merge-Permissions (Get-AgyPaths).CliSettings @($Perm) | Out-Null }
    function Set-ProfileRegion([string]$Text) {
        $p = (Get-AgyPaths).GeminiMd
        $s = Split-GeminiMd (Read-TextFile $p)
        Write-TextFile $p (Build-GeminiMd $s.Core $Text 'graphify')
    }
}
AfterAll {
    $env:AGYCFG_HOME = $script:oldHome
    Get-ChildItem -LiteralPath $TestDrive -Recurse -Force -File -ErrorAction SilentlyContinue | ForEach-Object { $_.IsReadOnly = $false }
}

Describe 'Invoke-Sync' {
    BeforeEach {
        Mock Get-AgyPluginList { @() }
        Mock Get-GitHeadSha { 'f' * 40 }
    }

    It 'pushes a new permission from machine A' {
        $w = New-SyncWorld
        $a = New-Machine $w 'a'
        Add-MachinePermission 'command(npm test)'
        Invoke-Sync -RepoRoot $a.Repo -Force | Should -Be 0
        Get-OriginFile $w 'profiles\lianharman\permissions.json' | Should -Match 'command\(npm test\)'
    }
    It 'machine B with stale base does not remove A''s permission' {
        $w = New-SyncWorld
        $a = New-Machine $w 'a'
        $b = New-Machine $w 'b'
        Use-Machine $a; Add-MachinePermission 'command(npm test)'
        Invoke-Sync -RepoRoot $a.Repo -Force | Should -Be 0
        Use-Machine $b; Add-MachinePermission 'command(npm run lint)'
        Invoke-Sync -RepoRoot $b.Repo -Force | Should -Be 0
        $perms = Get-OriginFile $w 'profiles\lianharman\permissions.json'
        $perms | Should -Match 'command\(npm test\)'
        $perms | Should -Match 'command\(npm run lint\)'
    }
    It 'removes a permission this machine removed' {
        $w = New-SyncWorld
        $a = New-Machine $w 'a'
        Add-MachinePermission 'command(npm test)'
        Invoke-Sync -RepoRoot $a.Repo -Force | Should -Be 0
        $ap = Get-AppliedState; $ap.permissions = @($script:corePerms + 'command(npm test)'); Set-AppliedState $ap
        Remove-Permissions (Get-AgyPaths).CliSettings @('command(npm test)')
        Invoke-Sync -RepoRoot $a.Repo -Force | Should -Be 0
        Get-OriginFile $w 'profiles\lianharman\permissions.json' | Should -Not -Match 'npm test'
    }
    It 'never commits trustedWorkspaces or model' {
        $w = New-SyncWorld
        $a = New-Machine $w 'a'
        Add-MachinePermission 'command(npm test)'
        Invoke-Sync -RepoRoot $a.Repo -Force | Out-Null
        $all = (Get-ChildItem -Recurse -File $a.Repo | Where-Object { $_.FullName -notmatch '\\.git\\' } | ForEach-Object { Read-TextFile $_.FullName }) -join "`n"
        $all | Should -Not -Match 'secret-model-name'
        $all | Should -Not -Match 'D:\\\\Private'
    }
    It 'captures profile edits from GEMINI.md' {
        $w = New-SyncWorld
        $a = New-Machine $w 'a'
        Set-ProfileRegion "## Language`n`nAnswer in English.`n`nAlways use tabs."
        Invoke-Sync -RepoRoot $a.Repo -Force | Should -Be 0
        Get-OriginFile $w 'profiles\lianharman\GEMINI.profile.md' | Should -Match 'Always use tabs\.'
    }
    It 'does not capture a GEMINI.md it never generated' {
        $w = New-SyncWorld
        $a = New-Machine $w 'a'
        $ap = Get-AppliedState; $ap.geminiManaged = $false; Set-AppliedState $ap
        Write-TextFile (Get-AgyPaths).GeminiMd 'old hand-written rules'
        Invoke-Sync -RepoRoot $a.Repo -Force | Should -Be 0
        Get-OriginFile $w 'profiles\lianharman\GEMINI.profile.md' | Should -Not -Match 'old hand-written rules'
    }
    It 'aborts and discards when a secret is captured' {
        $w = New-SyncWorld
        $a = New-Machine $w 'a'
        $before = Invoke-TestGit $a.Repo @('rev-parse', 'HEAD')
        Set-ProfileRegion ('token: ghp_' + ('Z9y8' * 8))
        Invoke-Sync -RepoRoot $a.Repo -Force | Should -Be 2
        Invoke-TestGit $a.Repo @('rev-parse', 'HEAD') | Should -Be $before
        Invoke-TestGit $a.Repo @('status', '--porcelain') | Should -BeNullOrEmpty
        Invoke-TestGit $w.Origin @('rev-parse', 'main') | Should -Be $before
    }
    It 'follower captures but does not commit' {
        $w = New-SyncWorld
        $f = New-Machine $w 'f' 'follower'
        $before = Invoke-TestGit $f.Repo @('rev-parse', 'HEAD')
        Set-ProfileRegion "## Language`n`nAnswer in English.`n`nFollower rule."
        Invoke-Sync -RepoRoot $f.Repo -Force | Should -Be 0
        Invoke-TestGit $f.Repo @('rev-parse', 'HEAD') | Should -Be $before
        Read-TextFile (Join-Path $f.Repo 'profiles\lianharman\GEMINI.profile.md') | Should -Match 'Follower rule\.'
    }
    It 'second run exits while lock held' {
        $w = New-SyncWorld
        $a = New-Machine $w 'a'
        Enter-RunLock 'sync' | Should -BeTrue
        Add-MachinePermission 'command(npm test)'
        Invoke-Sync -RepoRoot $a.Repo -Force | Should -Be 0
        Get-OriginFile $w 'profiles\lianharman\permissions.json' | Should -Not -Match 'npm test'
        Exit-RunLock 'sync'
    }
    It 'takes over stale lock' {
        $w = New-SyncWorld
        $a = New-Machine $w 'a'
        Write-JsonFile (Join-Path (Get-AgyPaths).StateDir 'sync.lock') @{ pid = 1; time = (Get-Date).AddMinutes(-45).ToString('o') }
        Add-MachinePermission 'command(npm test)'
        Invoke-Sync -RepoRoot $a.Repo -Force | Should -Be 0
        Get-OriginFile $w 'profiles\lianharman\permissions.json' | Should -Match 'npm test'
    }
    It 'respects debounce unless forced' {
        $w = New-SyncWorld
        $a = New-Machine $w 'a'
        Register-Run 'sync'
        Add-MachinePermission 'command(npm test)'
        Invoke-Sync -RepoRoot $a.Repo | Should -Be 0
        Get-OriginFile $w 'profiles\lianharman\permissions.json' | Should -Not -Match 'npm test'
    }
    It 'conflict goes to sync branch' {
        $w = New-SyncWorld
        $a = New-Machine $w 'a'
        $b = New-Machine $w 'b'
        Use-Machine $a; Set-ProfileRegion "Rule from A."
        Invoke-Sync -RepoRoot $a.Repo -Force | Should -Be 0
        Use-Machine $b; Set-ProfileRegion "Rule from B."
        Invoke-Sync -RepoRoot $b.Repo -Force | Should -Be 3
        $branches = Invoke-TestGit $w.Origin @('branch', '--list', 'sync/*')
        $branches | Should -Match 'sync/lianharman-'
        Get-OriginFile $w 'profiles\lianharman\GEMINI.profile.md' | Should -Match 'Rule from A\.'
    }
    It 'unknown skill reported not pushed' {
        $w = New-SyncWorld
        $a = New-Machine $w 'a'
        New-Item -ItemType Directory -Force -Path (Join-Path (Get-AgyPaths).SkillsDir 'mystery') | Out-Null
        Write-TextFile (Join-Path (Get-AgyPaths).SkillsDir 'mystery\SKILL.md') "---`nname: mystery`ndescription: x`n---`n"
        Invoke-Sync -RepoRoot $a.Repo -Force | Should -Be 0
        $u = @(Read-JsonFile (Join-Path (Get-AgyPaths).StateDir 'unknown.json') @())
        @($u | ForEach-Object { $_.name }) | Should -Contain 'mystery'
        Test-Path (Join-Path $a.Repo 'profiles\lianharman\skills\mystery') | Should -BeFalse
    }
    It 'own skill is copied into the profile and pushed' {
        $w = New-SyncWorld
        $a = New-Machine $w 'a'
        $pj = Join-Path $a.Repo 'profiles\lianharman\profile.json'
        $p = Read-JsonFile $pj @{}; $p.ownSkills = @('my-skill'); Write-JsonFile $pj $p
        Write-TextFile (Join-Path (Get-AgyPaths).SkillsDir 'my-skill\SKILL.md') "---`nname: my-skill`ndescription: mine`n---`n"
        Invoke-Sync -RepoRoot $a.Repo -Force | Should -Be 0
        Get-OriginFile $w 'profiles\lianharman\skills\my-skill\SKILL.md' | Should -Match 'description: mine'
    }
    It 'records a skill installed with the skills CLI as a profile source' {
        $w = New-SyncWorld
        $a = New-Machine $w 'a'
        Write-JsonFile (Get-AgyPaths).SkillLock @{ version = 3; skills = @{ 'cool-skill' = @{ source = 'someone/skills'; sourceType = 'github'; sourceUrl = 'https://github.com/someone/skills.git'; skillPath = 'skills/cool-skill/SKILL.md' } } }
        Write-TextFile (Join-Path (Get-AgyPaths).SkillsDir 'cool-skill\SKILL.md') "---`nname: cool-skill`ndescription: x`n---`n"
        Invoke-Sync -RepoRoot $a.Repo -Force | Should -Be 0
        $srcs = Get-OriginFile $w 'profiles\lianharman\sources.json'
        $srcs | Should -Match 'someone/skills'
        $srcs | Should -Match 'cool-skill'
        Get-OriginFile $w 'profiles\lianharman\sources.lock.json' | Should -Match ('f' * 40)
    }
}
