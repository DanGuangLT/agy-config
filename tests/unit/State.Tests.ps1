BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\scripts\lib\All.ps1')
    $script:oldHome = $env:AGYCFG_HOME
}
AfterAll { $env:AGYCFG_HOME = $script:oldHome }
Describe 'State' {
    BeforeEach { $env:AGYCFG_HOME = Join-Path $TestDrive ('h' + [guid]::NewGuid().ToString('N')) }

    Describe 'Merge-ThreeWaySet' {
        It 'adds what this machine added' {
            Merge-ThreeWaySet -Repo @('a', 'b') -Base @('a') -Current @('a', 'c') | Should -Be @('a', 'b', 'c')
        }
        It 'removes what this machine removed' {
            Merge-ThreeWaySet -Repo @('a', 'b') -Base @('a', 'b') -Current @('b') | Should -Be @('b')
        }
        It 'keeps what another machine added' {
            Merge-ThreeWaySet -Repo @('a', 'b', 'x') -Base @('a', 'b') -Current @('a', 'b') | Should -Be @('a', 'b', 'x')
        }
        It 'handles empty inputs' {
            @(Merge-ThreeWaySet -Repo @() -Base @() -Current @()).Count | Should -Be 0
            Merge-ThreeWaySet -Repo @() -Base @() -Current @('z') | Should -Be @('z')
        }
    }

    Describe 'Machine and applied state' {
        It 'round-trips machine state' {
            Set-MachineState @{ profile = 'lianharman'; role = 'owner'; repoPath = 'D:\r' }
            $m = Get-MachineState
            $m.role | Should -Be 'owner'
            $m.profile | Should -Be 'lianharman'
        }
        It 'returns empty applied state when missing' {
            $a = Get-AppliedState
            $a.sources.Count | Should -Be 0
            @($a.permissions).Count | Should -Be 0
        }
        It 'round-trips applied state' {
            Set-AppliedState @{ sources = @{ superpowers = 'abc' }; ownSkills = @(); ownPlugins = @(); permissions = @('p'); mcpServers = @() }
            (Get-AppliedState).sources.superpowers | Should -Be 'abc'
        }
    }

    Describe 'Pending lock' {
        It 'returns versions while fresh' {
            Set-PendingLock @{ superpowers = 'def' }
            (Get-PendingLock).versions.superpowers | Should -Be 'def'
        }
        It 'drops pending lock after 14 days' {
            $p = Join-Path (Get-AgyPaths).StateDir 'pending.lock.json'
            Write-JsonFile $p @{ createdAt = (Get-Date).AddDays(-15).ToString('o'); versions = @{ a = '1' } }
            Get-PendingLock | Should -BeNullOrEmpty
            Test-Path $p | Should -BeFalse
        }
        It 'clears' {
            Set-PendingLock @{ a = '1' }
            Clear-PendingLock
            Get-PendingLock | Should -BeNullOrEmpty
        }
    }

    Describe 'Run lock' {
        BeforeAll {
            # A live process that is not us, standing in for another sync/apply run.
            $script:other = Start-Process powershell -ArgumentList '-NoProfile -Command Start-Sleep -Seconds 120' -WindowStyle Hidden -PassThru
        }
        AfterAll { Stop-Process -Id $script:other.Id -Force -ErrorAction SilentlyContinue }

        It 'second run exits while lock held' {
            Write-JsonFile (Join-Path (Get-AgyPaths).StateDir 'sync.lock') @{ pid = $script:other.Id; time = (Get-Date).ToString('o') }
            Enter-RunLock 'sync' | Should -BeFalse
        }
        It 'is reentrant for the same process' {
            Enter-RunLock 'sync' | Should -BeTrue
            Enter-RunLock 'sync' | Should -BeTrue
            Exit-RunLock 'sync'
        }
        It 'never deletes a lock owned by another process' {
            $p = Join-Path (Get-AgyPaths).StateDir 'sync.lock'
            Write-JsonFile $p @{ pid = $script:other.Id; time = (Get-Date).ToString('o') }
            Exit-RunLock 'sync'
            Test-Path $p | Should -BeTrue
        }
        It 'takes over a fresh lock whose process is gone' {
            Write-JsonFile (Join-Path (Get-AgyPaths).StateDir 'sync.lock') @{ pid = 999999; time = (Get-Date).ToString('o') }
            Enter-RunLock 'sync' | Should -BeTrue
            Exit-RunLock 'sync'
        }
        It 'waits for a lock to be released' {
            $p = Join-Path (Get-AgyPaths).StateDir 'sync.lock'
            Write-JsonFile $p @{ pid = $script:other.Id; time = (Get-Date).ToString('o') }
            $sw = [Diagnostics.Stopwatch]::StartNew()
            Enter-RunLock 'sync' -WaitSeconds 2 | Should -BeFalse
            $sw.Elapsed.TotalSeconds | Should -BeGreaterOrEqual 1.5
        }
        It 'takes over stale lock' {
            $p = Join-Path (Get-AgyPaths).StateDir 'sync.lock'
            Write-JsonFile $p @{ pid = 999999; time = (Get-Date).AddMinutes(-31).ToString('o') }
            Enter-RunLock 'sync' | Should -BeTrue
            Exit-RunLock 'sync'
        }
    }

    Describe 'Debounce' {
        It 'is true when never run' {
            Test-Debounce 'sync' 10 | Should -BeTrue
        }
        It 'is false within window' {
            Register-Run 'sync'
            Test-Debounce 'sync' 10 | Should -BeFalse
        }
        It 'is true after the window' {
            Write-TextFile (Join-Path (Get-AgyPaths).StateDir 'sync.last') ((Get-Date).AddMinutes(-11).ToString('o'))
            Test-Debounce 'sync' 10 | Should -BeTrue
        }
    }
}
