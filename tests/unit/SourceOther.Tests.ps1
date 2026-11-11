BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\scripts\lib\All.ps1')
    $script:oldHome = $env:AGYCFG_HOME
    $script:graphify = @{ id = 'graphify'; type = 'pip-tool'; package = 'graphifyy'; command = 'graphify'; postInstall = @('install', '--platform', 'antigravity-windows'); provides = @('graphify'); when = @{ projectMap = 'graphify' } }
    $script:mkt = @{ id = 'gemini-api'; type = 'marketplace'; plugin = 'gemini-api'; marketplace = 'antigravity-plugins-official'; provides = @('gemini-api') }
    $script:pluginListJson = '[{"name":"gemini-api","enabled":true,"version":"2.2.0","source":"antigravity-plugins-official","path":"C:\\x","skills":["a"]},{"name":"design","enabled":true,"version":"1.2.0","source":"antigravity","path":"C:\\y","skills":[]}]'
}
AfterAll { $env:AGYCFG_HOME = $script:oldHome }

Describe 'Other sources' {
    BeforeEach { $env:AGYCFG_HOME = Join-Path $TestDrive ('h' + [guid]::NewGuid().ToString('N')) }

    Describe 'pip-tool' {
        It 'reports python-missing' {
            Mock Resolve-Tool { $null }
            $r = Install-Source $script:graphify '0.9.100'
            $r.Ok | Should -BeFalse
            $r.Error | Should -Be 'python-missing'
        }
        It 'rejects python 3.9' {
            Mock Resolve-Tool { 'python.exe' }
            Mock Invoke-External { @{ ExitCode = 0; StdOut = "3.9`n"; StdErr = '' } } -ParameterFilter { $Arguments -contains '-c' -and ($Arguments -join ' ') -match 'version_info' }
            $r = Install-Source $script:graphify '0.9.100'
            $r.Ok | Should -BeFalse
            $r.Error | Should -Match 'python-too-old'
        }
        It 'installs pinned version then runs postInstall' {
            $scripts = Join-Path $TestDrive 'pyscripts'
            Mock Resolve-Tool { 'python.exe' }
            Mock Invoke-External { @{ ExitCode = 0; StdOut = "3.14`n"; StdErr = '' } } -ParameterFilter { ($Arguments -join ' ') -match 'version_info' }
            Mock Invoke-External { @{ ExitCode = 0; StdOut = "$scripts`n"; StdErr = '' } } -ParameterFilter { ($Arguments -join ' ') -match 'sysconfig' }
            Mock Invoke-External { @{ ExitCode = 0; StdOut = ''; StdErr = '' } } -ParameterFilter { $Arguments -contains 'pip' }
            Mock Invoke-External { @{ ExitCode = 0; StdOut = ''; StdErr = '' } } -ParameterFilter { $Exe -like '*graphify.exe' }
            $r = Install-Source $script:graphify '0.9.100'
            $r.Ok | Should -BeTrue
            Should -Invoke Invoke-External -Times 1 -ParameterFilter { $Arguments -contains 'pip' -and $Arguments -contains 'graphifyy==0.9.100' -and $Arguments -contains '--user' }
            Should -Invoke Invoke-External -Times 1 -ParameterFilter { $Exe -eq (Join-Path $scripts 'graphify.exe') -and ($Arguments -join ' ') -eq 'install --platform antigravity-windows' }
        }
        It 'reads latest version from PyPI' {
            Mock Invoke-Http { [pscustomobject]@{ info = [pscustomobject]@{ version = '1.2.3' } } }
            Get-LatestVersion $script:graphify | Should -Be '1.2.3'
            Should -Invoke Invoke-Http -Times 1 -ParameterFilter { $Uri -eq 'https://pypi.org/pypi/graphifyy/json' }
        }
        It 'uninstall removes only the provided skill folder' {
            $skill = Join-Path (Get-AgyPaths).SkillsDir 'graphify'
            New-Item -ItemType Directory -Force -Path $skill | Out-Null
            Mock Invoke-External { throw 'should not call external tools' }
            Uninstall-Source $script:graphify
            Test-Path $skill | Should -BeFalse
        }
    }

    Describe 'marketplace' {
        It 'snapshots before install' {
            $existing = Join-Path (Get-AgyPaths).PluginsDir 'gemini-api'
            New-Item -ItemType Directory -Force -Path $existing | Out-Null
            Write-TextFile (Join-Path $existing 'plugin.json') '{"name":"gemini-api","version":"2.1.0"}'
            Mock Resolve-Tool { 'agy.exe' }
            Mock Invoke-External { @{ ExitCode = 0; StdOut = $script:pluginListJson; StdErr = '' } }
            $r = Install-Source $script:mkt 'latest'
            $r.Ok | Should -BeTrue
            Test-Path (Join-Path (Get-AgyPaths).SnapshotDir 'gemini-api\plugin.json') | Should -BeTrue
            Should -Invoke Invoke-External -Times 1 -ParameterFilter { ($Arguments -join ' ') -eq 'plugin install gemini-api@antigravity-plugins-official' }
        }
        It 'version read from plugin list json' {
            Mock Resolve-Tool { 'agy.exe' }
            Mock Invoke-External { @{ ExitCode = 0; StdOut = $script:pluginListJson; StdErr = '' } } -ParameterFilter { ($Arguments -join ' ') -eq 'plugin list --json' }
            Get-MarketplaceVersion $script:mkt | Should -Be '2.2.0'
        }
        It 'restores the snapshot' {
            $snap = Join-Path (Get-AgyPaths).SnapshotDir 'gemini-api'
            New-Item -ItemType Directory -Force -Path $snap | Out-Null
            Write-TextFile (Join-Path $snap 'plugin.json') '{"version":"2.1.0"}'
            Restore-MarketplaceSnapshot $script:mkt
            Read-TextFile (Join-Path (Get-AgyPaths).PluginsDir 'gemini-api\plugin.json') | Should -Match '2.1.0'
        }
    }
}
