# Stop or resume following the shared repository (new skills, versions and shared rules).
#   follow.ps1          show whether this machine follows it
#   follow.ps1 -Stop    keep everything as it is now and manage it yourself (profile's shared/ folder)
#   follow.ps1 -Resume  follow the shared repository again and install its current list right away
[CmdletBinding()]
param(
    [string]$RepoRoot,
    [switch]$Stop,
    [switch]$Resume
)
# $PSScriptRoot is empty inside param() on Windows PowerShell 5.1, so resolve the default here.
if (-not $RepoRoot) { $RepoRoot = Split-Path -Parent $PSScriptRoot }
. (Join-Path $PSScriptRoot 'lib\All.ps1')
try {
    $code = Invoke-Follow -RepoRoot $RepoRoot -Stop:$Stop -Resume:$Resume
} catch {
    Write-AgyLog -Script 'follow' -Message ("unexpected error: " + $_.Exception.Message) -Level ERROR
    Write-Host ("Unexpected error: " + $_.Exception.Message)
    $code = 1
}
exit $code
