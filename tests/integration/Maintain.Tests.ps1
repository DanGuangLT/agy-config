BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\scripts\lib\All.ps1')
    $script:oldHome = $env:AGYCFG_HOME
    function Use-Machine([string]$Role) {
        $env:AGYCFG_HOME = Join-Path $TestDrive ('h' + [guid]::NewGuid().ToString('N'))
        Set-MachineState @{ profile = 'p'; role = $Role; repoPath = 'D:\cfg' }
    }
    function Get-Stamp([string]$Name) {
        $f = Join-Path (Get-AgyPaths).StateDir $Name
        if (Test-Path $f) { (Read-TextFile $f).Trim() } else { $null }
    }
}
AfterAll { $env:AGYCFG_HOME = $script:oldHome }

Describe 'Invoke-Maintenance' {
    BeforeEach {
        Mock Invoke-Apply { 0 }
        Mock Invoke-Update { 0 }
    }
    It 'owner: apply (which backs up first) then update, and the week is stamped' {
        Use-Machine owner
        Invoke-Maintenance -RepoRoot 'D:\cfg' | Should -Be 0
        Should -Invoke Invoke-Apply -Times 1 -Exactly
        Should -Invoke Invoke-Update -Times 1 -Exactly
        Get-Stamp 'weekly.last' | Should -Not -BeNullOrEmpty
        Get-Stamp 'weekly-attempt.last' | Should -Not -BeNullOrEmpty
    }
    It 'follower: apply only' {
        Use-Machine follower
        Invoke-Maintenance -RepoRoot 'D:\cfg' | Should -Be 0
        Should -Invoke Invoke-Apply -Times 1 -Exactly
        Should -Invoke Invoke-Update -Times 0 -Exactly
        Get-Stamp 'weekly.last' | Should -Not -BeNullOrEmpty
    }
    It 'does not stamp the week when something fails, but records the attempt' {
        Use-Machine owner
        Mock Invoke-Apply { 1 }
        Invoke-Maintenance -RepoRoot 'D:\cfg' | Should -Be 1
        Get-Stamp 'weekly.last' | Should -BeNullOrEmpty
        Get-Stamp 'weekly-attempt.last' | Should -Not -BeNullOrEmpty
        Should -Invoke Invoke-Update -Times 1 -Exactly
    }
}

Describe 'Install without scheduled tasks' {
    It 'install never registers Windows scheduled tasks and removes old ones' {
        $src = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
        $env:AGYCFG_HOME = Join-Path $TestDrive ('h' + [guid]::NewGuid().ToString('N'))
        $repo = Join-Path $TestDrive ('r' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $repo | Out-Null
        foreach ($d in 'core', 'profiles', 'scripts') { Copy-Item -Recurse (Join-Path $src $d) (Join-Path $repo $d) }
        Mock Resolve-Tool { $Name + '.exe' }
        Mock Test-PushAccess { $true }
        Mock Invoke-Apply { 0 }
        Mock Unregister-AgyTasks { }
        Mock Write-Host { }
        Invoke-Install -RepoRoot $repo -ProfileName lianharman -Yes | Should -Be 0
        Should -Invoke Unregister-AgyTasks -Times 1 -Exactly
        Get-Command Register-AgyTasks -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }
}
