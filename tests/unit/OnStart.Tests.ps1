BeforeAll {
    $script:hook = (Resolve-Path (Join-Path $PSScriptRoot '..\..\core\plugins\agy-self-config\hooks\on-start.ps1')).Path
    $script:oldHome = $env:AGYCFG_HOME
    $script:utf8 = New-Object Text.UTF8Encoding $false
    function Set-Machine($State, [string]$WeeklyLast, [string]$AttemptLast) {
        $env:AGYCFG_HOME = Join-Path $TestDrive ('h' + [guid]::NewGuid().ToString('N'))
        $dir = Join-Path $env:AGYCFG_HOME '.agy-config-state'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        if ($State) { [IO.File]::WriteAllText((Join-Path $dir 'machine.json'), ($State | ConvertTo-Json), $script:utf8) }
        if ($WeeklyLast) { [IO.File]::WriteAllText((Join-Path $dir 'weekly.last'), $WeeklyLast, $script:utf8) }
        if ($AttemptLast) { [IO.File]::WriteAllText((Join-Path $dir 'weekly-attempt.last'), $AttemptLast, $script:utf8) }
    }
    function New-FakeRepo([string]$Name = 'repo') {
        $r = Join-Path $TestDrive ($Name + ' ' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path (Join-Path $r 'scripts') | Out-Null
        [IO.File]::WriteAllText((Join-Path $r 'scripts\maintain.ps1'), 'exit 0', $script:utf8)
        $r
    }
    function Get-Ago([double]$Days) { (Get-Date).AddDays(-$Days).ToString('o') }
}
AfterAll { $env:AGYCFG_HOME = $script:oldHome }

Describe 'on-start hook' {
    It 'prints {} and exits 0 when not installed (real process)' {
        $env:AGYCFG_HOME = Join-Path $TestDrive 'nothing-here'
        $out = '{"hookEventName":"SessionStart"}' | & powershell -NoProfile -ExecutionPolicy Bypass -File $script:hook
        $LASTEXITCODE | Should -Be 0
        ($out -join '').Trim() | Should -Be '{}'
    }
    It 'does not hang when stdin stays open' {
        $env:AGYCFG_HOME = Join-Path $TestDrive 'nothing-here-2'
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
    It 'starts weekly maintenance when it never ran' {
        $repo = New-FakeRepo
        Set-Machine @{ profile = 'p'; role = 'follower'; repoPath = $repo }
        Mock Start-Process { }
        ((& $script:hook) -join '').Trim() | Should -Be '{}'
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
            $FilePath -eq 'powershell' -and ($ArgumentList -join ' ') -match [regex]::Escape('-File "' + (Join-Path $repo 'scripts\maintain.ps1') + '"')
        }
    }
    It 'starts weekly maintenance when the last run is a week old' {
        $repo = New-FakeRepo
        Set-Machine @{ profile = 'p'; role = 'owner'; repoPath = $repo } (Get-Ago 7.1)
        Mock Start-Process { }
        & $script:hook | Out-Null
        Should -Invoke Start-Process -Times 1 -Exactly
    }
    It 'does nothing within the week' {
        $repo = New-FakeRepo
        Set-Machine @{ profile = 'p'; role = 'owner'; repoPath = $repo } (Get-Ago 3)
        Mock Start-Process { }
        ((& $script:hook) -join '').Trim() | Should -Be '{}'
        Should -Invoke Start-Process -Times 0 -Exactly
    }
    It 'retries a failed week at most once a day' {
        $repo = New-FakeRepo
        Set-Machine @{ profile = 'p'; role = 'owner'; repoPath = $repo } (Get-Ago 9) (Get-Ago 0.2)
        Mock Start-Process { }
        & $script:hook | Out-Null
        Should -Invoke Start-Process -Times 0 -Exactly
        Set-Machine @{ profile = 'p'; role = 'owner'; repoPath = $repo } (Get-Ago 9) (Get-Ago 1.1)
        & $script:hook | Out-Null
        Should -Invoke Start-Process -Times 1 -Exactly
    }
    It 'reads a non-ASCII repo path from UTF-8 state' {
        $repo = New-FakeRepo ('repo ' + [char]0x1EAD)
        Set-Machine @{ profile = 'p'; role = 'owner'; repoPath = $repo }
        Mock Start-Process { }
        & $script:hook | Out-Null
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { ($ArgumentList -join ' ') -match [regex]::Escape((Join-Path $repo 'scripts\maintain.ps1')) }
    }
    It 'still prints {} when Start-Process fails' {
        $repo = New-FakeRepo
        Set-Machine @{ profile = 'p'; role = 'owner'; repoPath = $repo }
        Mock Start-Process { throw 'nope' }
        ((& $script:hook) -join '').Trim() | Should -Be '{}'
    }
}

Describe 'plugin files' {
    It 'hooks.json registers only the SessionStart hook' {
        $h = Get-Content (Join-Path $PSScriptRoot '..\..\core\plugins\agy-self-config\hooks.json') -Raw | ConvertFrom-Json
        @($h.PSObject.Properties).Count | Should -Be 1
        $start = @($h.'agy-config-weekly'.SessionStart)
        $start.Count | Should -Be 1
        $start[0].command | Should -Match 'on-start\.ps1'
        $start[0].timeout | Should -BeLessOrEqual 30
        Test-Path (Join-Path $PSScriptRoot '..\..\core\plugins\agy-self-config\hooks\on-stop.ps1') | Should -BeFalse
    }
    It 'ships the agy-self-config skill with name and description' {
        $t = Get-Content (Join-Path $PSScriptRoot '..\..\core\plugins\agy-self-config\skills\agy-self-config\SKILL.md') -Raw
        $t | Should -Match '(?s)^---\s*\r?\nname: agy-self-config\r?\ndescription: .+?\r?\n---'
    }
}
