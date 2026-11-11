[CmdletBinding()]
param(
    # Test files or folders to run. Defaults to the whole suite.
    [string[]]$Path
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

$pester = Get-Module -ListAvailable Pester | Where-Object { $_.Version -ge [version]'5.5' } |
    Sort-Object Version -Descending | Select-Object -First 1
if (-not $pester) {
    Write-Host 'Pester 5.5+ not found; installing for the current user...'
    try {
        # Windows PowerShell 5.1: PSGallery needs TLS 1.2 and the NuGet provider; install it without prompting.
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        if (-not (Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue | Where-Object { $_.Version -ge [version]'2.8.5.201' })) {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force -ErrorAction Stop | Out-Null
        }
        Install-Module Pester -MinimumVersion 5.5 -Scope CurrentUser -Force -SkipPublisherCheck -ErrorAction Stop
    } catch {
        Write-Error "Could not install Pester 5. Install it manually: Install-Module Pester -MinimumVersion 5.5 -Scope CurrentUser -Force -SkipPublisherCheck. Error: $_"
        exit 2
    }
    $pester = Get-Module -ListAvailable Pester | Where-Object { $_.Version -ge [version]'5.5' } |
        Sort-Object Version -Descending | Select-Object -First 1
}
Import-Module $pester.Path -Force

# powershell -File passes "a,b" as one string; split it.
$Path = @($Path | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
if (-not $Path) {
    $Path = @((Join-Path $root 'tests\unit'), (Join-Path $root 'tests\integration')) | Where-Object { Test-Path $_ }
}

$config = New-PesterConfiguration
$config.Run.Path = $Path
$config.Run.Exit = $true
$config.Output.Verbosity = 'Detailed'
$config.TestResult.Enabled = $false
Invoke-Pester -Configuration $config
