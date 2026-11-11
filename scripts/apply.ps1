# Repo -> machine: install everything the repo describes for this machine's profile.
[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [switch]$SkipPull,
    [switch]$SkipCapture
)
. (Join-Path $PSScriptRoot 'lib\All.ps1')
try {
    $code = Invoke-Apply -RepoRoot $RepoRoot -SkipPull:$SkipPull -SkipCapture:$SkipCapture
} catch {
    Write-AgyLog -Script 'apply' -Message ("unexpected error: " + $_.Exception.Message) -Level ERROR
    $code = 1
}
exit $code
