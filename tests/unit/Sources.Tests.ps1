BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\scripts\lib\All.ps1')
    $script:oldHome = $env:AGYCFG_HOME
    function New-SourcesRepo($CoreSources, $CoreLock) {
        $r = Join-Path $TestDrive ('repo' + [guid]::NewGuid().ToString('N'))
        Write-JsonFile (Join-Path $r 'core\sources.json') $CoreSources
        Write-JsonFile (Join-Path $r 'core\sources.lock.json') $CoreLock
        $r
    }
}
AfterAll { $env:AGYCFG_HOME = $script:oldHome }

Describe 'Sources' {
    BeforeEach { $env:AGYCFG_HOME = Join-Path $TestDrive ('h' + [guid]::NewGuid().ToString('N')) }

    Describe 'Get-SourceList' {
        It 'drops graphify when projectMap is none' {
            $r = New-SourcesRepo @(
                @{ id = 'superpowers'; type = 'git-plugin'; repo = 'https://github.com/obra/superpowers'; plugin = 'superpowers'; provides = @('superpowers') },
                @{ id = 'graphify'; type = 'pip-tool'; package = 'graphifyy'; provides = @('graphify'); when = @{ projectMap = 'graphify' } }
            ) @{}
            $ids = @(Get-SourceList $r @{ projectMap = @{ tool = 'none' }; Sources = @() } | ForEach-Object { $_.id })
            $ids | Should -Be @('superpowers')
            $ids2 = @(Get-SourceList $r @{ projectMap = @{ tool = 'graphify' }; Sources = @() } | ForEach-Object { $_.id })
            $ids2 | Should -Contain 'graphify'
        }
        It 'profile entry overrides core entry' {
            $r = New-SourcesRepo @(@{ id = 'x'; type = 'git-plugin'; repo = 'https://a'; plugin = 'x'; provides = @('x') }) @{}
            $list = @(Get-SourceList $r @{ projectMap = @{ tool = 'none' }; Sources = @(@{ id = 'x'; type = 'git-plugin'; repo = 'https://b'; plugin = 'x'; provides = @('x') }) })
            $list.Count | Should -Be 1
            $list[0].repo | Should -Be 'https://b'
        }
    }

    Describe 'Get-EffectiveLock' {
        It 'prefers pending over profile over core' {
            $r = New-SourcesRepo @() @{ a = 'core-a'; b = 'core-b'; c = 'core-c' }
            $lock = Get-EffectiveLock $r @{ Lock = @{ b = 'prof-b'; c = 'prof-c' } } @{ versions = @{ c = 'pend-c' } }
            $lock.a | Should -Be 'core-a'
            $lock.b | Should -Be 'prof-b'
            $lock.c | Should -Be 'pend-c'
        }
        It 'works without pending' {
            $r = New-SourcesRepo @() @{ a = '1' }
            (Get-EffectiveLock $r @{ Lock = @{} } $null).a | Should -Be '1'
        }
    }

    Describe 'Install-PackagedPlugin' {
        It 'writes plugin.json with short sha version and installs the staging folder' {
            $cache = Join-Path $TestDrive ('cache' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Force -Path (Join-Path $cache 'engineering\skills\debug') | Out-Null
            Write-TextFile (Join-Path $cache 'engineering\skills\debug\SKILL.md') "---`nname: debug`ndescription: d`n---`n"
            Write-TextFile (Join-Path $cache 'LICENSE') 'Apache'
            Mock Sync-GitCache { $cache }
            Mock Resolve-Tool { 'agy.exe' }
            Mock Invoke-External { @{ ExitCode = 0; StdOut = ''; StdErr = '' } }
            $src = @{ id = 'engineering'; type = 'packaged-plugin'; repo = 'https://github.com/anthropics/knowledge-work-plugins'; plugin = 'engineering'; displayName = 'Engineering'; description = 'Eng skills'; author = 'Anthropic'; license = 'Apache-2.0'; paths = @('engineering'); provides = @('engineering') }
            $r = Install-Source $src '0123456789abcdef0123456789abcdef01234567'
            $r.Ok | Should -BeTrue
            $staging = Join-Path (Get-AgyPaths).StagingDir 'engineering'
            $pj = Read-JsonFile (Join-Path $staging 'plugin.json') @{}
            $pj.version | Should -Be '0123456'
            $pj.name | Should -Be 'engineering'
            $pj.license | Should -Be 'Apache-2.0'
            Test-Path (Join-Path $staging 'skills\debug\SKILL.md') | Should -BeTrue
            Test-Path (Join-Path $staging 'LICENSE') | Should -BeTrue
            Should -Invoke Invoke-External -Times 1 -ParameterFilter { $Arguments[0] -eq 'plugin' -and $Arguments[1] -eq 'install' -and $Arguments[2] -eq $staging }
        }
        It 'packs several skill folders into one plugin' {
            $cache = Join-Path $TestDrive ('cache' + [guid]::NewGuid().ToString('N'))
            foreach ($s in 'pdf', 'docx') {
                New-Item -ItemType Directory -Force -Path (Join-Path $cache "skills\$s") | Out-Null
                Write-TextFile (Join-Path $cache "skills\$s\SKILL.md") "---`nname: $s`ndescription: d`n---`n"
            }
            Mock Sync-GitCache { $cache }
            Mock Resolve-Tool { 'agy.exe' }
            Mock Invoke-External { @{ ExitCode = 0; StdOut = ''; StdErr = '' } }
            $src = @{ id = 'anthropic-dev-skills'; type = 'packaged-plugin'; repo = 'https://github.com/anthropics/skills'; plugin = 'anthropic-dev-skills'; paths = @('skills/pdf', 'skills/docx'); provides = @('anthropic-dev-skills') }
            (Install-Source $src 'abcdef0123456789').Ok | Should -BeTrue
            $staging = Join-Path (Get-AgyPaths).StagingDir 'anthropic-dev-skills'
            Test-Path (Join-Path $staging 'skills\pdf\SKILL.md') | Should -BeTrue
            Test-Path (Join-Path $staging 'skills\docx\SKILL.md') | Should -BeTrue
        }
        It 'reports failure when agy install fails' {
            $cache = Join-Path $TestDrive ('cache' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Force -Path (Join-Path $cache 'p\skills\a') | Out-Null
            Mock Sync-GitCache { $cache }
            Mock Resolve-Tool { 'agy.exe' }
            Mock Invoke-External { @{ ExitCode = 1; StdOut = ''; StdErr = 'boom' } }
            $r = Install-Source @{ id = 'p'; type = 'packaged-plugin'; repo = 'https://x'; plugin = 'p'; paths = @('p'); provides = @('p') } 'abcdef0'
            $r.Ok | Should -BeFalse
            $r.Error | Should -Match 'boom'
        }
    }

    Describe 'Install-Source' {
        It 'rejects unknown source types' {
            $r = Install-Source @{ id = 'z'; type = 'weird' } '1'
            $r.Ok | Should -BeFalse
            $r.Error | Should -Match 'weird'
        }
    }
}
