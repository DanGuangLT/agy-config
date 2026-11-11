# Windows Task Scheduler tasks for the current user (no admin). ASCII-only file.

$script:AgyTaskPath = '\agy-config\'
$script:AgyTaskNames = @('agy-config-apply', 'agy-config-sync', 'agy-config-update')

function New-AgyTaskAction([string]$RepoRoot, [string]$Script) {
    $file = Join-Path $RepoRoot ('scripts\' + $Script)
    New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $file + '"')
}

function Register-AgyTasks {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][ValidateSet('owner', 'follower')][string]$Role,
        [string]$UpdateDay = 'Sunday'
    )
    $user = $env:USERDOMAIN + '\' + $env:USERNAME
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 1)
    $logon = New-ScheduledTaskTrigger -AtLogOn -User $user

    $tasks = @(@{ Name = 'agy-config-apply'; Script = 'apply.ps1'; Triggers = @($logon) })
    if ($Role -eq 'owner') {
        $tasks += @{ Name = 'agy-config-sync'; Script = 'sync.ps1'; Triggers = @((New-ScheduledTaskTrigger -Daily -At '12:00'), $logon) }
        $tasks += @{ Name = 'agy-config-update'; Script = 'update.ps1'; Triggers = @(New-ScheduledTaskTrigger -Weekly -DaysOfWeek $UpdateDay -At '10:00') }
    } else {
        foreach ($n in 'agy-config-sync', 'agy-config-update') {
            if (Get-ScheduledTask -TaskName $n -TaskPath $script:AgyTaskPath -ErrorAction SilentlyContinue) {
                Unregister-ScheduledTask -TaskName $n -TaskPath $script:AgyTaskPath -Confirm:$false
            }
        }
    }
    foreach ($t in $tasks) {
        Register-ScheduledTask -TaskName $t.Name -TaskPath $script:AgyTaskPath -Action (New-AgyTaskAction $RepoRoot $t.Script) `
            -Trigger $t.Triggers -Principal $principal -Settings $settings -Force | Out-Null
    }
}

function Unregister-AgyTasks {
    foreach ($n in $script:AgyTaskNames) {
        if (Get-ScheduledTask -TaskName $n -TaskPath $script:AgyTaskPath -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $n -TaskPath $script:AgyTaskPath -Confirm:$false
        }
    }
}
