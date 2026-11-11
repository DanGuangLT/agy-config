# Weekly: move third-party sources to their newest versions (owner machines), push update/sources for review.
[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [switch]$NoPush
)
. (Join-Path $PSScriptRoot 'lib\All.ps1')
try {
    $code = Invoke-Update -RepoRoot $RepoRoot -NoPush:$NoPush
} catch {
    Write-AgyLog -Script 'update' -Message ("unexpected error: " + $_.Exception.Message) -Level ERROR
    $code = 1
}
exit $code
