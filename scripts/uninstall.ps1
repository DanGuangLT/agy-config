# Remove the scheduled tasks and the agy-self-config plugin; optionally restore a backup made by install.
#   powershell -ExecutionPolicy Bypass -File scripts\uninstall.ps1 [-RestoreBackup <yyyyMMdd-HHmmss>] [-Yes]
[CmdletBinding()]
param(
    [string]$RestoreBackup,
    [switch]$Yes
)
. (Join-Path $PSScriptRoot 'lib\All.ps1')
exit (Invoke-Uninstall -RepoRoot (Split-Path -Parent $PSScriptRoot) -RestoreBackup $RestoreBackup -Yes:$Yes)
