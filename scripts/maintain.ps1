# Weekly maintenance (started in the background by the agy SessionStart hook; safe to run by hand).
[CmdletBinding()]
param([string]$RepoRoot = (Split-Path -Parent $PSScriptRoot))
. (Join-Path $PSScriptRoot 'lib\All.ps1')
try {
    $code = Invoke-Maintenance -RepoRoot $RepoRoot
} catch {
    Write-AgyLog -Script 'maintain' -Message ("unexpected error: " + $_.Exception.Message) -Level ERROR
    $code = 1
}
exit $code
