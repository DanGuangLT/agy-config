# Machine -> repo: capture this machine's agy configuration and (owner only) push it.
[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [switch]$CaptureOnly,
    [switch]$Force
)
. (Join-Path $PSScriptRoot 'lib\All.ps1')
try {
    $code = Invoke-Sync -RepoRoot $RepoRoot -CaptureOnly:$CaptureOnly -Force:$Force
} catch {
    Write-AgyLog -Script 'sync' -Message ("unexpected error: " + $_.Exception.Message) -Level ERROR
    $code = 1
}
exit $code
