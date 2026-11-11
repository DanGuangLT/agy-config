# Cleanup of Windows scheduled tasks created by earlier versions. Maintenance now runs from the
# agy SessionStart hook instead, so nothing runs while agy is closed. ASCII-only file.

$script:AgyTaskPath = '\agy-config\'
$script:AgyTaskNames = @('agy-config-apply', 'agy-config-sync', 'agy-config-update')

function Unregister-AgyTasks {
    foreach ($n in $script:AgyTaskNames) {
        if (Get-ScheduledTask -TaskName $n -TaskPath $script:AgyTaskPath -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $n -TaskPath $script:AgyTaskPath -Confirm:$false
        }
    }
}
