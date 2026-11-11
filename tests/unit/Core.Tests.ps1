BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\scripts\lib\All.ps1')
    $script:oldHome = $env:AGYCFG_HOME
    $env:AGYCFG_HOME = Join-Path $TestDrive 'home'
    # "Tra loi bang tieng Viet" with Vietnamese diacritics, built from code points to keep this file ASCII.
    $script:vi = 'Tr' + [char]0x1EA3 + ' l' + [char]0x1EDD + 'i b' + [char]0x1EB1 + 'ng ti' + [char]0x1EBF + 'ng Vi' + [char]0x1EC7 + 't'
}
AfterAll { $env:AGYCFG_HOME = $script:oldHome }

Describe 'Get-AgyPaths' {
    It 'honors AGYCFG_HOME' {
        (Get-AgyPaths).SkillsDir | Should -Be (Join-Path $TestDrive 'home\.gemini\config\skills')
    }
    It 'exposes every documented key' {
        $p = Get-AgyPaths
        foreach ($k in 'Home','GeminiMd','CliSettings','SkillsDir','PluginsDir','McpConfig','SkillLock','StateDir','LogDir','SnapshotDir','StagingDir','CacheDir','BackupRoot','DefaultRepo') {
            $p.ContainsKey($k) | Should -BeTrue -Because $k
        }
        $p.CliSettings | Should -Be (Join-Path $TestDrive 'home\.gemini\antigravity-cli\settings.json')
        $p.LogDir | Should -Be (Join-Path $TestDrive 'home\.agy-config-state\logs')
    }
}

Describe 'Text IO' {
    It 'writes UTF-8 without BOM' {
        $p = Join-Path $TestDrive 'a\b\vi.txt'
        Write-TextFile $p $script:vi
        $bytes = [IO.File]::ReadAllBytes($p)
        @($bytes[0], $bytes[1], $bytes[2]) | Should -Not -Be @(0xEF, 0xBB, 0xBF)
        Read-TextFile $p | Should -BeExactly $script:vi
    }
}

Describe 'JSON IO' {
    It 'Read-JsonFile returns default when missing' {
        $d = Read-JsonFile (Join-Path $TestDrive 'nope.json') @{ x = 1 }
        $d.x | Should -Be 1
    }
    It 'Read-JsonFile returns hashtables' {
        $p = Join-Path $TestDrive 'settings.json'
        Write-TextFile $p '{"model":"m","permissions":{"allow":["command(git status)"]}}'
        $j = Read-JsonFile $p @{}
        $j | Should -BeOfType [hashtable]
        $j.permissions | Should -BeOfType [hashtable]
        $j.permissions.allow[0] | Should -Be 'command(git status)'
    }
    It 'keeps single-element arrays as arrays' {
        $p = Join-Path $TestDrive 'one.json'
        Write-TextFile $p '{"a":["x"]}'
        $j = Read-JsonFile $p @{}
        , $j.a | Should -BeOfType [object[]]
        $j.a.Count | Should -Be 1
    }
    It 'Write-JsonFile round-trips non-ASCII' {
        $p = Join-Path $TestDrive 'vi.json'
        Write-JsonFile $p @{ rule = $script:vi; list = @('a') }
        $j = Read-JsonFile $p @{}
        $j.rule | Should -BeExactly $script:vi
        $j.list.Count | Should -Be 1
        [IO.File]::ReadAllText($p) | Should -Match '  "'
    }
}

Describe 'Write-AgyLog' {
    It 'appends a timestamped line to the script log' {
        Write-AgyLog -Script 'unit' -Message 'hello' -Level WARN
        $f = Join-Path (Get-AgyPaths).LogDir ('unit-' + (Get-Date -Format 'yyyyMMdd') + '.log')
        (Get-Content $f -Raw) | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \[WARN\] hello'
    }
}

Describe 'Invoke-External' {
    It 'returns exit code without throwing' {
        (Invoke-External 'cmd.exe' @('/c', 'exit 3')).ExitCode | Should -Be 3
    }
    It 'captures stdout' {
        (Invoke-External 'cmd.exe' @('/c', 'echo hi')).StdOut.Trim() | Should -Be 'hi'
    }
}

Describe 'Resolve-Tool' {
    BeforeEach {
        $script:oldLad = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = Join-Path $TestDrive ('lad' + [guid]::NewGuid().ToString('N'))
    }
    AfterEach { $env:LOCALAPPDATA = $script:oldLad }

    It 'falls back to known locations' {
        Mock Get-Command { $null }
        $exe = Join-Path $env:LOCALAPPDATA 'agy\bin\agy.exe'
        New-Item -ItemType File -Force -Path $exe | Out-Null
        Resolve-Tool agy | Should -Be $exe
    }
    It 'returns null when nothing is found' {
        Mock Get-Command { $null }
        Resolve-Tool agy | Should -BeNullOrEmpty
    }
}
