# First-time setup and removal. Spec section 6.1. ASCII-only file (texts live in scripts/i18n).

$script:ToolHints = @{
    git    = 'winget install Git.Git'
    agy    = 'https://antigravity.google'
    node   = 'winget install OpenJS.NodeJS.LTS'
    python = 'winget install Python.Python.3.13'
}

function Get-UiLanguage { if ((Get-Culture).Name -like 'vi*') { 'vi' } else { 'en' } }

function Test-YesAnswer([string]$Answer, $Texts) {
    $a = ([string]$Answer).Trim().ToLowerInvariant()
    return @($Texts.yesAnswers) -contains $a
}

function Backup-AgyConfig {
    $p = Get-AgyPaths
    $dir = Join-Path $p.BackupRoot (Get-Date -Format 'yyyyMMdd-HHmmss')
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $items = @(
        @{ From = $p.GeminiMd; To = 'GEMINI.md' },
        @{ From = $p.CliSettings; To = 'settings.json' },
        @{ From = $p.McpConfig; To = 'mcp_config.json' },
        @{ From = $p.SkillsDir; To = 'skills' },
        @{ From = $p.PluginsDir; To = 'plugins' }
    )
    foreach ($i in $items) {
        if (Test-Path $i.From) { Copy-Item -Recurse -Force -Path $i.From -Destination (Join-Path $dir $i.To) }
    }
    return $dir
}

function Invoke-Install {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [string]$ProfileName,
        [string]$Language,
        [string]$ProjectMapTool,
        [switch]$Yes,
        [switch]$NoTasks
    )
    $ui = Get-UiLanguage
    $t = Get-I18nText $RepoRoot $ui

    foreach ($tool in 'git', 'agy') {
        if (-not (Resolve-Tool $tool)) { Write-Host ($t.msgMissingTool -f $tool, $script:ToolHints[$tool]); return 1 }
    }
    if (-not (Resolve-Tool node)) { Write-Host ($t.msgWarnTool -f 'node', $script:ToolHints.node) }

    if (-not $ProfileName) {
        if ($Yes) { Write-Host $t.msgNeedProfile; return 1 }
        $existing = @(Get-ChildItem (Join-Path $RepoRoot 'profiles') -Directory | Where-Object { $_.Name -ne '_template' } | ForEach-Object { $_.Name })
        $ProfileName = Read-Host -Prompt ($t.promptProfile -f ($existing -join ', '))
    }
    $ProfileName = ([string]$ProfileName).Trim().ToLowerInvariant()
    if ($ProfileName -notmatch '^[a-z0-9][a-z0-9_-]*$' -or $ProfileName -eq '_template') { Write-Host ($t.msgBadProfileName -f $ProfileName); return 1 }

    $profDir = Join-Path $RepoRoot ('profiles\' + $ProfileName)
    $creating = -not (Test-Path (Join-Path $profDir 'profile.json'))
    if ($creating) {
        if (-not $Language) {
            $Language = $ui
            if (-not $Yes) { $a = Read-Host -Prompt $t.promptLanguage; if ($a) { $Language = $a.Trim().ToLowerInvariant() } }
        }
        if (-not $ProjectMapTool) {
            $ProjectMapTool = 'graphify'
            if (-not $Yes) { $a = Read-Host -Prompt $t.promptProjectMap; if ($a) { $ProjectMapTool = $a.Trim() } }
        }
    }
    $mapTool = if ($ProjectMapTool) { $ProjectMapTool } elseif (-not $creating) { (Get-Profile $RepoRoot $ProfileName).projectMap.tool } else { 'graphify' }
    if ($mapTool -eq 'graphify' -and -not (Resolve-Tool python)) { Write-Host ($t.msgWarnTool -f 'python', $script:ToolHints.python) }

    $role = if (Test-PushAccess $RepoRoot) { 'owner' } else { 'follower' }
    $taskNames = if ($NoTasks) { '-' } elseif ($role -eq 'owner') { 'agy-config-apply, agy-config-sync, agy-config-update' } else { 'agy-config-apply' }
    Write-Host ($t.msgPlan -f $ProfileName, $role, $taskNames)
    if (-not $Yes) {
        if (-not (Test-YesAnswer (Read-Host -Prompt $t.promptConfirm) $t)) { Write-Host $t.msgCancelled; return 1 }
    }

    if ($creating) { New-ProfileFromTemplate $RepoRoot $ProfileName $Language $ProjectMapTool | Out-Null }
    $backup = Backup-AgyConfig
    Write-Host ($t.msgBackup -f $backup)
    Set-MachineState @{ profile = $ProfileName; role = $role; repoPath = $RepoRoot }

    $code = Invoke-Apply -RepoRoot $RepoRoot -SkipCapture
    if ($code -ne 0) { Write-Host ($t.msgApplyFailed -f (Get-AgyPaths).LogDir); return 1 }

    if (-not $NoTasks) {
        $prof = Get-Profile $RepoRoot $ProfileName
        Register-AgyTasks -RepoRoot $RepoRoot -Role $role -UpdateDay $prof.update.day
    }
    if (Test-Path (Join-Path $backup 'GEMINI.md')) { Write-Host ($t.msgOldGemini -f $ProfileName) }
    Write-Host ($t.msgDone -f $ProfileName, $role, $taskNames)
    Write-Host ($t.msgUninstallHint -f (Join-Path $RepoRoot 'scripts\uninstall.ps1'))
    return 0
}

function Invoke-Uninstall {
    param(
        [string]$RepoRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
        [string]$RestoreBackup,
        [switch]$Yes
    )
    $t = Get-I18nText $RepoRoot (Get-UiLanguage)
    if (-not $Yes) {
        if (-not (Test-YesAnswer (Read-Host -Prompt $t.promptUninstall) $t)) { Write-Host $t.msgCancelled; return 1 }
    }
    $p = Get-AgyPaths
    if ($RestoreBackup) {
        $dir = Join-Path $p.BackupRoot $RestoreBackup
        if (-not (Test-Path $dir)) { Write-Host ($t.msgNoBackup -f $RestoreBackup, $p.BackupRoot); return 1 }
    }
    Unregister-AgyTasks
    Uninstall-AgyPlugin 'agy-self-config'
    if ($RestoreBackup) {
        $map = @{ 'GEMINI.md' = $p.GeminiMd; 'settings.json' = $p.CliSettings; 'mcp_config.json' = $p.McpConfig; 'skills' = $p.SkillsDir; 'plugins' = $p.PluginsDir }
        foreach ($k in $map.Keys) {
            $from = Join-Path $dir $k
            if (-not (Test-Path $from)) { continue }
            if ((Get-Item $from).PSIsContainer) { Copy-Folder $from $map[$k] }
            else {
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $map[$k]) | Out-Null
                Copy-Item -Force $from $map[$k]
            }
        }
        Write-Host ($t.msgRestored -f $RestoreBackup)
    }
    Write-Host $t.msgUninstalled
    return 0
}
