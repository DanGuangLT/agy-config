BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\scripts\lib\All.ps1')
    $script:oldHome = $env:AGYCFG_HOME

    function Invoke-TestGit([string]$Dir, [string[]]$GitArgs) {
        $r = Invoke-External 'git' (@('-c', 'user.name=t', '-c', 'user.email=t@example.invalid') + $GitArgs) $Dir
        if ($r.ExitCode -ne 0) { throw "git $($GitArgs -join ' ') failed: $($r.StdErr)" }
        $r.StdOut.Trim()
    }

    # Upstream bare repo with two commits: A (v1) and B (v2).
    $script:upstream = Join-Path $TestDrive 'upstream.git'
    $work = Join-Path $TestDrive 'work'
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    Invoke-TestGit $TestDrive @('init', '-q', '--bare', $script:upstream) | Out-Null
    Invoke-TestGit $work @('init', '-q', '-b', 'main') | Out-Null
    Write-TextFile (Join-Path $work 'skills\foo\SKILL.md') "---`nname: foo`ndescription: v1`n---`n"
    Write-TextFile (Join-Path $work '.antigravity-plugin\plugin.json') '{"name":"bar","version":"1.0.0","description":"d"}'
    Invoke-TestGit $work @('add', '-A') | Out-Null
    Invoke-TestGit $work @('commit', '-q', '-m', 'A') | Out-Null
    $script:shaA = Invoke-TestGit $work @('rev-parse', 'HEAD')
    Write-TextFile (Join-Path $work 'skills\foo\SKILL.md') "---`nname: foo`ndescription: v2`n---`n"
    Invoke-TestGit $work @('commit', '-q', '-am', 'B') | Out-Null
    $script:shaB = Invoke-TestGit $work @('rev-parse', 'HEAD')
    Invoke-TestGit $work @('remote', 'add', 'origin', $script:upstream) | Out-Null
    Invoke-TestGit $work @('push', '-q', 'origin', 'main') | Out-Null
    Invoke-TestGit $script:upstream @('symbolic-ref', 'HEAD', 'refs/heads/main') | Out-Null

    $script:skillSrc = @{ id = 'foo-src'; type = 'github-skills'; repo = $script:upstream; skills = @(@{ name = 'foo'; path = 'skills/foo' }); provides = @('foo') }
    $script:pluginSrc = @{ id = 'bar'; type = 'git-plugin'; repo = $script:upstream; plugin = 'bar'; provides = @('bar') }
}
AfterAll {
    $env:AGYCFG_HOME = $script:oldHome
    # git marks object files read-only; clear that so Pester can delete TestDrive.
    Get-ChildItem -LiteralPath $TestDrive -Recurse -Force -File -ErrorAction SilentlyContinue | ForEach-Object { $_.IsReadOnly = $false }
}

Describe 'GitHub sources (local upstream)' {
    BeforeEach { $env:AGYCFG_HOME = Join-Path $TestDrive ('h' + [guid]::NewGuid().ToString('N')) }

    It 'reports the latest sha' {
        Get-LatestVersion $script:skillSrc | Should -Be $script:shaB
    }
    It 'installs github skill at locked sha' {
        (Install-Source $script:skillSrc $script:shaA).Ok | Should -BeTrue
        Read-TextFile (Join-Path (Get-AgyPaths).SkillsDir 'foo\SKILL.md') | Should -Match 'description: v1'
        (Test-Source $script:skillSrc).Ok | Should -BeTrue
    }
    It 'upgrades to latest' {
        (Install-Source $script:skillSrc $script:shaA).Ok | Should -BeTrue
        (Install-Source $script:skillSrc (Get-LatestVersion $script:skillSrc)).Ok | Should -BeTrue
        Read-TextFile (Join-Path (Get-AgyPaths).SkillsDir 'foo\SKILL.md') | Should -Match 'description: v2'
    }
    It 'uninstalls github skills' {
        (Install-Source $script:skillSrc $script:shaB).Ok | Should -BeTrue
        Uninstall-Source $script:skillSrc
        Test-Path (Join-Path (Get-AgyPaths).SkillsDir 'foo') | Should -BeFalse
    }
    It 'git-plugin checks out locked sha in an existing clone' {
        (Install-Source $script:pluginSrc $script:shaB).Ok | Should -BeTrue
        (Install-Source $script:pluginSrc $script:shaA).Ok | Should -BeTrue
        $dir = Join-Path (Get-AgyPaths).PluginsDir 'bar'
        (Invoke-External 'git' @('rev-parse', 'HEAD') $dir).StdOut.Trim() | Should -Be $script:shaA
        Read-TextFile (Join-Path $dir 'skills\foo\SKILL.md') | Should -Match 'description: v1'
    }
    It 'fails cleanly for an unknown sha' {
        $r = Install-Source $script:skillSrc 'ffffffffffffffffffffffffffffffffffffffff'
        $r.Ok | Should -BeFalse
    }
}
