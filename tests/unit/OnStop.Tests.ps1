BeforeAll {
    $script:hook = (Resolve-Path (Join-Path $PSScriptRoot '..\..\core\plugins\agy-self-config\hooks\on-stop.ps1')).Path
    $script:oldHome = $env:AGYCFG_HOME
    function Set-Machine($State) {
        $env:AGYCFG_HOME = Join-Path $TestDrive ('h' + [guid]::NewGuid().ToString('N'))
        if ($State) {
            $dir = Join-Path $env:AGYCFG_HOME '.agy-config-state'
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
            [IO.File]::WriteAllText((Join-Path $dir 'machine.json'), ($State | ConvertTo-Json), (New-Object Text.UTF8Encoding $false))
        }
    }
    function New-FakeRepo {
        $r = Join-Path $TestDrive ('repo with space ' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path (Join-Path $r 'scripts') | Out-Null
        [IO.File]::WriteAllText((Join-Path $r 'scripts\sync.ps1'), 'exit 0', (New-Object Text.UTF8Encoding $false))
        $r
    }
}
AfterAll { $env:AGYCFG_HOME = $script:oldHome }

Describe 'on-stop hook' {
    It 'prints {} and exits 0 when state missing (real process)' {
        Set-Machine $null
        $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $script:hook
        $LASTEXITCODE | Should -Be 0
        ($out -join '').Trim() | Should -Be '{}'
    }
    It 'does not hang when stdin stays open' {
        Set-Machine $null
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'powershell'
        $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $script:hook + '"'
        $psi.UseShellExecute = $false
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.Environment['AGYCFG_HOME'] = $env:AGYCFG_HOME
        $proc = [System.Diagnostics.Process]::Start($psi)
        $out = $proc.StandardOutput.ReadToEndAsync()
        $finished = $proc.WaitForExit(15000)
        if (-not $finished) { $proc.Kill() }
        $finished | Should -BeTrue
        $out.Result.Trim() | Should -Be '{}'
    }
    It 'prints {} when given the hook payload on stdin (real process)' {
        Set-Machine $null
        $out = '{"hookEventName":"Stop","executionNum":1}' | & powershell -NoProfile -ExecutionPolicy Bypass -File $script:hook
        $LASTEXITCODE | Should -Be 0
        ($out -join '').Trim() | Should -Be '{}'
    }
    It 'starts sync for owner' {
        $repo = New-FakeRepo
        Set-Machine @{ profile = 'p'; role = 'owner'; repoPath = $repo }
        Mock Start-Process { }
        $out = & $script:hook
        ($out -join '').Trim() | Should -Be '{}'
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
            $FilePath -eq 'powershell' -and ($ArgumentList -join ' ') -match [regex]::Escape('"' + (Join-Path $repo 'scripts\sync.ps1') + '"')
        }
    }
    It 'starts sync with the exact non-ASCII repoPath from UTF-8 without BOM state' {
        $repo = Join-Path $TestDrive ('repo ' + [char]0x1EAD)
        New-Item -ItemType Directory -Force -Path (Join-Path $repo 'scripts') | Out-Null
        [IO.File]::WriteAllText((Join-Path $repo 'scripts\sync.ps1'), 'exit 0', (New-Object Text.UTF8Encoding $false))
        Set-Machine @{ profile = 'p'; role = 'owner'; repoPath = $repo }
        Mock Start-Process { }
        ((& $script:hook) -join '').Trim() | Should -Be '{}'
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
            $FilePath -eq 'powershell' -and $WindowStyle -eq 'Hidden' -and
                ($ArgumentList -join ' ') -eq ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $repo 'scripts\sync.ps1') + '"')
        }
    }
    It 'does nothing for follower' {
        $repo = New-FakeRepo
        Set-Machine @{ profile = 'p'; role = 'follower'; repoPath = $repo }
        Mock Start-Process { }
        ((& $script:hook) -join '').Trim() | Should -Be '{}'
        Should -Invoke Start-Process -Times 0 -Exactly
    }
    It 'still prints {} when Start-Process fails' {
        $repo = New-FakeRepo
        Set-Machine @{ profile = 'p'; role = 'owner'; repoPath = $repo }
        Mock Start-Process { throw 'nope' }
        ((& $script:hook) -join '').Trim() | Should -Be '{}'
    }
}

Describe 'plugin files' {
    It 'hooks.json registers the Stop hook' {
        $h = Get-Content (Join-Path $PSScriptRoot '..\..\core\plugins\agy-self-config\hooks.json') -Raw | ConvertFrom-Json
        $stop = @($h.'agy-config-sync'.Stop)
        $stop.Count | Should -Be 1
        $stop[0].command | Should -Match 'on-stop\.ps1'
        $stop[0].timeout | Should -BeLessOrEqual 30
    }
    It 'ships the agy-self-config skill with name and description' {
        $t = Get-Content (Join-Path $PSScriptRoot '..\..\core\plugins\agy-self-config\skills\agy-self-config\SKILL.md') -Raw
        $t | Should -Match '(?s)^---\s*\r?\nname: agy-self-config\r?\ndescription: .+?\r?\n---'
    }
}
