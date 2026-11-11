BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\scripts\lib\All.ps1')
}

Describe 'Register-AgyTasks' {
    BeforeEach {
        Mock Register-ScheduledTask { }
        Mock Unregister-ScheduledTask { }
        Mock Get-ScheduledTask { $null }
    }
    It 'follower registers only apply task' {
        Register-AgyTasks -RepoRoot 'D:\cfg' -Role follower
        Should -Invoke Register-ScheduledTask -Times 1 -Exactly
        Should -Invoke Register-ScheduledTask -Times 1 -Exactly -ParameterFilter { $TaskName -eq 'agy-config-apply' }
    }
    It 'owner registers three tasks with expected names' {
        Register-AgyTasks -RepoRoot 'D:\cfg' -Role owner
        foreach ($n in 'agy-config-apply', 'agy-config-sync', 'agy-config-update') {
            Should -Invoke Register-ScheduledTask -Times 1 -Exactly -ParameterFilter { $TaskName -eq $n }
        }
    }
    It 'points each task at its script with a quoted path' {
        Register-AgyTasks -RepoRoot 'D:\my cfg' -Role owner
        Should -Invoke Register-ScheduledTask -Times 1 -Exactly -ParameterFilter {
            $TaskName -eq 'agy-config-sync' -and $Action.Execute -eq 'powershell.exe' -and $Action.Arguments -match [regex]::Escape('-File "D:\my cfg\scripts\sync.ps1"')
        }
    }
    It 'sync runs daily only (owner apply already syncs at logon)' {
        Register-AgyTasks -RepoRoot 'D:\cfg' -Role owner
        Should -Invoke Register-ScheduledTask -Times 1 -Exactly -ParameterFilter { $TaskName -eq 'agy-config-sync' -and @($Trigger).Count -eq 1 }
    }
    It 'uses the profile update day for the weekly task' {
        Register-AgyTasks -RepoRoot 'D:\cfg' -Role owner -UpdateDay Monday
        Should -Invoke Register-ScheduledTask -Times 1 -Exactly -ParameterFilter {
            $TaskName -eq 'agy-config-update' -and @($Trigger)[0].DaysOfWeek -eq 2
        }
    }
    It 'removes owner tasks when the machine becomes a follower' {
        Mock Get-ScheduledTask { [pscustomobject]@{ TaskName = $TaskName } }
        Register-AgyTasks -RepoRoot 'D:\cfg' -Role follower
        Should -Invoke Unregister-ScheduledTask -ParameterFilter { $TaskName -eq 'agy-config-sync' }
        Should -Invoke Unregister-ScheduledTask -ParameterFilter { $TaskName -eq 'agy-config-update' }
    }
}

Describe 'Unregister-AgyTasks' {
    It 'removes all three tasks that exist' {
        Mock Get-ScheduledTask { [pscustomobject]@{ TaskName = $TaskName } }
        Mock Unregister-ScheduledTask { }
        Unregister-AgyTasks
        Should -Invoke Unregister-ScheduledTask -Times 3 -Exactly
    }
}
