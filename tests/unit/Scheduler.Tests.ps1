BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\scripts\lib\All.ps1')
}

Describe 'Unregister-AgyTasks' {
    It 'removes the scheduled tasks older versions created' {
        Mock Get-ScheduledTask { [pscustomobject]@{ TaskName = $TaskName } }
        Mock Unregister-ScheduledTask { }
        Unregister-AgyTasks
        Should -Invoke Unregister-ScheduledTask -Times 3 -Exactly
    }
    It 'does nothing when there are none' {
        Mock Get-ScheduledTask { $null }
        Mock Unregister-ScheduledTask { }
        Unregister-AgyTasks
        Should -Invoke Unregister-ScheduledTask -Times 0 -Exactly
    }
}
