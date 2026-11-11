# Dot-source every library file in dependency order.
# Usage: . (Join-Path <repo> 'scripts\lib\All.ps1')
$order = @(
    'Core.ps1', 'GeminiMd.ps1', 'Settings.ps1', 'State.ps1', 'Profile.ps1',
    'Sources.ps1', 'Source.GitHub.ps1', 'Source.Other.ps1', 'Inventory.ps1',
    'SecretScan.ps1', 'Repo.ps1', 'Scheduler.ps1'
)
foreach ($f in $order) {
    $p = Join-Path $PSScriptRoot $f
    if (Test-Path $p) { . $p }
}
