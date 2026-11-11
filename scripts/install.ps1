# Install this agy configuration on this machine. Safe to run again.
#   From a clone:  powershell -ExecutionPolicy Bypass -File scripts\install.ps1 [-ProfileName <name>]
#   One line:      irm https://raw.githubusercontent.com/DanGuangLT/agy-config/main/scripts/install.ps1 | iex
#                  (clones the repo to ~/.agy-config first; read the script before running it)
[CmdletBinding()]
param(
    [string]$ProfileName,
    [string]$Language,
    [string]$ProjectMapTool,
    [switch]$Yes,
    [string]$RepoPath,
    [string]$RepoUrl = 'https://github.com/DanGuangLT/agy-config.git'
)

$agyInstallCode = & {
    $here = $null
    if ($PSScriptRoot) { $here = Split-Path -Parent $PSScriptRoot }

    if ($RepoPath) { $root = $RepoPath }
    elseif ($here -and (Test-Path (Join-Path $here 'core\sources.json'))) { $root = $here }
    else {
        # Running from `irm | iex`: get a clone first.
        $userHome = if ($env:AGYCFG_HOME) { $env:AGYCFG_HOME } else { $HOME }
        $root = Join-Path $userHome '.agy-config'
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
            Write-Host 'git is required but was not found. Install it (winget install Git.Git) and run this again.'
            return 1
        }
        if (Test-Path (Join-Path $root '.git')) { & git -C $root pull --ff-only --quiet }
        else { & git clone --quiet $RepoUrl $root }
        if ($LASTEXITCODE -ne 0) { Write-Host "Could not get $RepoUrl into $root."; return 1 }
    }
    $lib = Join-Path $root 'scripts\lib\All.ps1'
    if (-not (Test-Path $lib)) { Write-Host "No agy config repo found at $root."; return 1 }
    . $lib
    return (Invoke-Install -RepoRoot $root -ProfileName $ProfileName -Language $Language -ProjectMapTool $ProjectMapTool -Yes:$Yes)
}

# Exit with a code when run as a file; when run through iex, only return so the user's window stays open.
if ($PSCommandPath) { exit $agyInstallCode }
