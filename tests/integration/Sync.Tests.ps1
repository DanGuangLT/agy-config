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

Describe 'Invoke-Sync with a personal backup repository' {
    BeforeAll {
        # A follower of the shared origin whose profile lives in its own backup repository.
        function New-PersonalMachine($World, [string]$Name) {
            $m = New-Machine $World $Name 'follower'
            $backup = Join-Path $World.Root ('backup-' + $Name + '.git')
            Invoke-TestGit $World.Root @('init', '-q', '--bare', '-b', 'main', $backup) | Out-Null
            $dir = (Get-AgyPaths).PersonalDir
            (Initialize-PersonalRepo $backup $dir).Ok | Should -BeTrue
            New-ProfileFromTemplate $m.Repo $Name 'auto' 'graphify' $dir | Out-Null
            Set-MachineState @{ profile = $Name; role = 'follower'; repoPath = $m.Repo; backupRepo = $backup; profileRoot = $dir }
            $prof = Get-Profile $m.Repo $Name $dir
            Write-TextFile (Get-AgyPaths).GeminiMd (Build-GeminiMd (Read-TextFile (Join-Path $m.Repo 'core\GEMINI.core.md')) $prof.GeminiProfileText 'graphify')
            Set-AppliedState @{ sources = @{}; sourceDefs = @{}; ownSkills = @(); ownPlugins = @(); permissions = $script:corePerms; mcpServers = @(); geminiManaged = $true
                geminiProfileText = $prof.GeminiProfileText; geminiCoreText = (Read-TextFile (Join-Path $m.Repo 'core\GEMINI.core.md')).TrimEnd("`r", "`n") }
            $m.Backup = $backup
            $m.Dir = $dir
            $m
        }
        function Get-BackupFile([string]$Origin, [string]$Path) {
            $r = Invoke-External 'git' @('show', ('main:' + $Path)) $Origin
            if ($r.ExitCode -ne 0) { return $null }
            $r.StdOut
        }
    }
    BeforeEach {
        Mock Get-AgyPluginList { @() }
        Mock Get-GitHeadSha { 'f' * 40 }
    }

    It 'pushes the profile to the backup repository and leaves the shared clone alone' {
        $w = New-SyncWorld
        $p = New-PersonalMachine $w 'pat'
        $sharedBefore = Invoke-TestGit $p.Repo @('rev-parse', 'HEAD')
        Add-MachinePermission 'command(npm test)'
        Set-ProfileRegion "## Language`n`nAnswer in English.`n`nPat's rule."
        Invoke-Sync -RepoRoot $p.Repo -Force | Should -Be 0
        Get-BackupFile $p.Backup 'permissions.json' | Should -Match 'command\(npm test\)'
        Get-BackupFile $p.Backup 'GEMINI.profile.md' | Should -Match "Pat's rule\."
        Invoke-TestGit $p.Repo @('rev-parse', 'HEAD') | Should -Be $sharedBefore
        Invoke-TestGit $p.Repo @('status', '--porcelain') | Should -BeNullOrEmpty
    }
    It 'never captures core text into the shared clone' {
        $w = New-SyncWorld
        $p = New-PersonalMachine $w 'core-test'
        $gm = (Get-AgyPaths).GeminiMd
        $s = Split-GeminiMd (Read-TextFile $gm)
        Write-TextFile $gm (Build-GeminiMd ($s.Core + "`n`nLocal core edit.") $s.Profile 'graphify')
        Invoke-Sync -RepoRoot $p.Repo -Force | Should -Be 0
        Read-TextFile (Join-Path $p.Repo 'core\GEMINI.core.md') | Should -Not -Match 'Local core edit'
    }
    It 'a second machine with the same backup repository gets the first one''s changes' {
        $w = New-SyncWorld
        $a = New-PersonalMachine $w 'sam'
        Add-MachinePermission 'command(npm test)'
        Invoke-Sync -RepoRoot $a.Repo -Force | Should -Be 0
        $b = New-Machine $w 'sam-2' 'follower'
        $dir = (Get-AgyPaths).PersonalDir
        $r = Initialize-PersonalRepo $a.Backup $dir
        $r.Ok | Should -BeTrue
        $r.HasProfile | Should -BeTrue
        (Get-Profile $b.Repo 'sam' $dir).Permissions | Should -Contain 'command(npm test)'
    }
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
    It 'blocks publishing but keeps captured edits when a secret is found' {
        $w = New-SyncWorld
        $a = New-Machine $w 'a'
        $before = Invoke-TestGit $a.Repo @('rev-parse', 'HEAD')
        # An untracked file that existed before this sync must survive it.
        Write-TextFile (Join-Path $a.Repo 'profiles\lianharman\notes.md') 'my notes'
        Set-ProfileRegion ('token: ghp_' + ('Z9y8' * 8))
        Invoke-Sync -RepoRoot $a.Repo -Force | Should -Be 2
        Invoke-TestGit $a.Repo @('rev-parse', 'HEAD') | Should -Be $before
        Invoke-TestGit $w.Origin @('rev-parse', 'main') | Should -Be $before
        Read-TextFile (Join-Path $a.Repo 'profiles\lianharman\GEMINI.profile.md') | Should -Match 'token: ghp_'
        Test-Path (Join-Path $a.Repo 'profiles\lianharman\notes.md') | Should -BeTrue
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
        $other = Start-Process powershell -ArgumentList '-NoProfile -Command Start-Sleep -Seconds 60' -WindowStyle Hidden -PassThru
        try {
            Write-JsonFile (Join-Path (Get-AgyPaths).StateDir 'config.lock') @{ pid = $other.Id; time = (Get-Date).ToString('o') }
            Add-MachinePermission 'command(npm test)'
            Invoke-Sync -RepoRoot $a.Repo -Force | Should -Be 0
            Get-OriginFile $w 'profiles\lianharman\permissions.json' | Should -Not -Match 'npm test'
        } finally { Stop-Process -Id $other.Id -Force -ErrorAction SilentlyContinue }
    }
    It 'takes over stale lock' {
        $w = New-SyncWorld
        $a = New-Machine $w 'a'
        Write-JsonFile (Join-Path (Get-AgyPaths).StateDir 'config.lock') @{ pid = 1; time = (Get-Date).AddMinutes(-45).ToString('o') }
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
    It 'refuses while a merge is in progress' {
        $w = New-SyncWorld
        $a = New-Machine $w 'a'
        Write-TextFile (Join-Path $a.Repo '.git\MERGE_HEAD') ((Invoke-TestGit $a.Repo @('rev-parse', 'HEAD')) + "`n")
        Add-MachinePermission 'command(npm test)'
        Invoke-Sync -RepoRoot $a.Repo -Force | Should -Be 5
        Get-OriginFile $w 'profiles\lianharman\permissions.json' | Should -Not -Match 'npm test'
        Read-TextFile (Join-Path $a.Repo 'profiles\lianharman\permissions.json') | Should -Not -Match 'npm test'
    }
    It 'refuses when the clone is not on main' {
        $w = New-SyncWorld
        $a = New-Machine $w 'a'
        Invoke-TestGit $a.Repo @('checkout', '-q', '-b', 'topic') | Out-Null
        Add-MachinePermission 'command(npm test)'
        Invoke-Sync -RepoRoot $a.Repo -Force | Should -Be 5
        Get-OriginFile $w 'profiles\lianharman\permissions.json' | Should -Not -Match 'npm test'
    }
    It 'does not publish files outside managed paths' {
        $w = New-SyncWorld
        $a = New-Machine $w 'a'
        Write-TextFile (Join-Path $a.Repo 'graphify-out\graph.json') '{}'
        Write-TextFile (Join-Path $a.Repo 'scripts\half-done.ps1') 'work in progress'
        Add-MachinePermission 'command(npm test)'
        Invoke-Sync -RepoRoot $a.Repo -Force | Should -Be 0
        Get-OriginFile $w 'profiles\lianharman\permissions.json' | Should -Match 'npm test'
        Get-OriginFile $w 'scripts\half-done.ps1' | Should -BeNullOrEmpty
        Get-OriginFile $w 'graphify-out\graph.json' | Should -BeNullOrEmpty
        Test-Path (Join-Path $a.Repo 'scripts\half-done.ps1') | Should -BeTrue
    }
    It 'does not push another conflict branch for the same conflicting text' {
        $w = New-SyncWorld
        $a = New-Machine $w 'a'
        $b = New-Machine $w 'b'
        Use-Machine $a; Set-ProfileRegion "Rule from A."
        Invoke-Sync -RepoRoot $a.Repo -Force | Should -Be 0
        Use-Machine $b; Set-ProfileRegion "Rule from B."
        Invoke-Sync -RepoRoot $b.Repo -Force | Should -Be 3
        Invoke-Sync -RepoRoot $b.Repo -Force | Should -Be 3
        @((Invoke-TestGit $w.Origin @('branch', '--list', 'sync/*')) -split "`n" | Where-Object { $_.Trim() }).Count | Should -Be 1
    }
    It 'pushes local commits that were not pushed yet' {
        $w = New-SyncWorld
        $a = New-Machine $w 'a'
        Write-TextFile (Join-Path $a.Repo 'profiles\lianharman\permissions.json') "[`n  `"command(make)`"`n]`n"
        Invoke-TestGit $a.Repo @('commit', '-q', '-am', 'local only') | Out-Null
        $ap = Get-AppliedState; $ap.permissions = @($script:corePerms + 'command(make)'); Set-AppliedState $ap
        Add-MachinePermission 'command(make)'
        Invoke-Sync -RepoRoot $a.Repo -Force | Should -Be 0
        Get-OriginFile $w 'profiles\lianharman\permissions.json' | Should -Match 'command\(make\)'
    }
    It 'does not re-add a skills CLI source the user removed' {
        $w = New-SyncWorld
        $a = New-Machine $w 'a'
        Write-JsonFile (Get-AgyPaths).SkillLock @{ version = 3; skills = @{ 'cool-skill' = @{ source = 'someone/skills'; sourceType = 'github'; sourceUrl = 'https://github.com/someone/skills.git'; skillPath = 'skills/cool-skill/SKILL.md' } } }
        Write-TextFile (Join-Path (Get-AgyPaths).SkillsDir 'cool-skill\SKILL.md') "---`nname: cool-skill`ndescription: x`n---`n"
        $ap = Get-AppliedState; $ap.skillLockNames = @('cool-skill'); Set-AppliedState $ap
        Invoke-Sync -RepoRoot $a.Repo -Force | Should -Be 0
        Get-OriginFile $w 'profiles\lianharman\sources.json' | Should -Not -Match 'cool-skill'
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
