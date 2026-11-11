# First-time setup and removal. Spec section 6.1. ASCII-only file (texts live in scripts/i18n).

$script:ToolHints = @{
    git    = 'winget install Git.Git'
    agy    = 'https://antigravity.google'
    node   = 'winget install OpenJS.NodeJS.LTS'
    python = 'winget install Python.Python.3.13'
}

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

$script:PersonalReadme = @'
# agy configuration backup

This repository is the automatic backup of one person's agy configuration, written by
[agy-config](https://github.com/DanGuangLT/agy-config). Keep it private.

To restore it on another machine, install agy-config there and give this repository's URL when asked:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -BackupRepo <this repository's URL>
```
'@

function Show-InstalledSetup {
    # Install on a machine that is already set up: keep the setup, fix a moved clone, report, exit.
    param([string]$RepoRoot, $Machine, $Texts)
    $paths = Get-AgyPaths
    $recorded = [string]$Machine.repoPath
    if ($recorded -ne $RepoRoot) {
        if ($recorded -and (Test-Path (Join-Path $recorded 'core\sources.json'))) {
            Write-Host ($Texts.msgOtherClone -f $recorded, $RepoRoot)
            return 0
        }
        # The recorded folder is gone (moved or renamed): this clone takes over.
        $Machine.repoPath = $RepoRoot
        Set-MachineState $Machine
        Write-Host ($Texts.msgRepoMoved -f $recorded, $RepoRoot)
    }
    if ($Machine.profileRoot -and $Machine.backupRepo -and -not (Test-Path (Join-Path $Machine.profileRoot '.git'))) {
        # The local copy of the backup repository was deleted: bring it back from GitHub.
        $r = Initialize-PersonalRepo $Machine.backupRepo $Machine.profileRoot
        if ($r.Ok) { Write-Host ($Texts.msgPersonalRestored -f $Machine.profileRoot) }
        else { Write-Host ($Texts.msgPersonalMissing -f $Machine.profileRoot, $r.Error) }
    }
    $code = 0
    if (-not (Test-Path (Get-StateFile 'applied.json'))) {
        # An earlier install stopped before anything was applied: finish it now.
        $code = Invoke-Apply -RepoRoot $RepoRoot -SkipCapture
        if ($code -ne 0) { Write-Host ($Texts.msgApplyFailed -f $paths.LogDir) }
    } elseif (-not (Test-Path (Join-Path $paths.PluginsDir 'agy-self-config\plugin.json'))) {
        if (Install-LocalPlugin (Join-Path $RepoRoot 'core\plugins\agy-self-config')) { Write-Host $Texts.msgPluginRepaired }
    }
    $backup = if ($Machine.backupRepo) { $Machine.backupRepo } elseif ($Machine.role -eq 'owner') { $Texts.msgBackupOrigin } else { $Texts.msgBackupNone }
    Write-Host ($Texts.msgAlreadyInstalled -f $Machine.profile, $Machine.role, $backup)
    $loc = Get-ProfileLocation $RepoRoot $Machine
    if (Test-Path (Join-Path $loc.Dir 'profile.json')) {
        if (-not (Test-Following (Get-Profile $RepoRoot $Machine.profile $loc.Dir))) { Write-Host $Texts.msgNotFollowing }
    }
    Write-Host $Texts.msgReinstallHint
    return $code
}

function Invoke-Install {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [string]$ProfileName,
        [string]$Language,
        [string]$ProjectMapTool,
        [string]$BackupRepo,
        [switch]$Reinstall,
        [switch]$Yes
    )
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).ProviderPath
    $t = Get-I18nText $RepoRoot 'en'

    foreach ($tool in 'git', 'agy') {
        if (-not (Resolve-Tool $tool)) { Write-Host ($t.msgMissingTool -f $tool, $script:ToolHints[$tool]); return 1 }
    }
    if (-not (Resolve-Tool node)) { Write-Host ($t.msgWarnTool -f 'node', $script:ToolHints.node) }

    # agy keeps its configuration in ~/.gemini; report it so the user knows where things go.
    $paths = Get-AgyPaths
    if (Test-Path $paths.AgyDir) { Write-Host ($t.msgAgyFolder -f $paths.AgyDir) } else { Write-Host ($t.msgAgyFolderMissing -f $paths.AgyDir) }

    $machine = Get-MachineState
    if ($machine.profile -and -not $Reinstall) { return (Show-InstalledSetup $RepoRoot $machine $t) }
    if ($Reinstall) {
        if (-not $ProfileName -and $machine.profile -and -not $machine.profileRoot) { $ProfileName = $machine.profile }
        if (-not $BackupRepo -and $machine.backupRepo) { $BackupRepo = $machine.backupRepo }
    }

    $role = if (Test-PushAccess $RepoRoot) { 'owner' } else { 'follower' }

    # A personal backup repository: asked on a follower (an owner's clone already is its backup).
    $backupUrl = ([string]$BackupRepo).Trim()
    if (-not $backupUrl -and $role -eq 'follower' -and -not $Yes) { $backupUrl = ([string](Read-Host -Prompt $t.promptBackupRepo)).Trim() }
    if ($backupUrl -eq 'none') { $backupUrl = '' }

    $profileRoot = $null
    if ($backupUrl) {
        $profileRoot = $paths.PersonalDir
        Write-Host ($t.msgConnectingBackup -f $backupUrl, $profileRoot)
        $r = Initialize-PersonalRepo $backupUrl $profileRoot
        if (-not $r.Ok) {
            $why = if ($r.Error -eq 'folder-in-use') { $t.msgBackupFolderInUse -f $profileRoot } else { $r.Error }
            Write-Host ($t.msgBackupRepoFailed -f $backupUrl, $why)
            return 1
        }
        if (-not (Test-PushAccess $profileRoot)) { Write-Host ($t.msgBackupNoPush -f $backupUrl); return 1 }
        $profDir = $profileRoot
        if ($r.HasProfile) {
            $saved = Read-JsonFile (Join-Path $profileRoot 'profile.json') @{}
            $ProfileName = if ($saved.name) { [string]$saved.name } else { Get-RepoOwnerName $backupUrl }
            Write-Host ($t.msgRestoring -f $backupUrl)
        } elseif (-not $ProfileName) {
            $ProfileName = Get-RepoOwnerName $backupUrl
        }
    } elseif (-not $ProfileName) {
        if ($Yes) { Write-Host $t.msgNeedProfile; return 1 }
        $existing = @(Get-ChildItem (Join-Path $RepoRoot 'profiles') -Directory | Where-Object { $_.Name -ne '_template' } | ForEach-Object { $_.Name })
        $ProfileName = Read-Host -Prompt ($t.promptProfile -f ($existing -join ', '))
    }
    $ProfileName = ([string]$ProfileName).Trim().ToLowerInvariant()
    if ($ProfileName -notmatch '^[a-z0-9][a-z0-9_-]*$' -or $ProfileName -eq '_template') { Write-Host ($t.msgBadProfileName -f $ProfileName); return 1 }

    if (-not $profileRoot) { $profDir = Join-Path $RepoRoot ('profiles\' + $ProfileName) }
    $creating = -not (Test-Path (Join-Path $profDir 'profile.json'))
    if ($creating) {
        if (-not $Language) {
            $Language = 'auto'
            if (-not $Yes) { $a = Read-Host -Prompt $t.promptLanguage; if ($a) { $Language = $a.Trim().ToLowerInvariant() } }
        }
        if (-not $ProjectMapTool) {
            $ProjectMapTool = 'graphify'
            if (-not $Yes) { $a = Read-Host -Prompt $t.promptProjectMap; if ($a) { $ProjectMapTool = $a.Trim() } }
        }
    }
    $mapTool = if ($ProjectMapTool) { $ProjectMapTool } elseif (-not $creating) { (Get-Profile $RepoRoot $ProfileName $profDir).projectMap.tool } else { 'graphify' }
    if ($mapTool -eq 'graphify' -and -not (Resolve-Tool python)) { Write-Host ($t.msgWarnTool -f 'python', $script:ToolHints.python) }

    Write-Host ($t.msgPlan -f $ProfileName, $role)
    if ($backupUrl) { Write-Host ($t.msgPlanBackup -f $backupUrl) }
    elseif ($role -eq 'follower') { Write-Host $t.msgPlanNoBackup }
    if (-not $Yes) {
        if (-not (Test-YesAnswer (Read-Host -Prompt $t.promptConfirm) $t)) { Write-Host $t.msgCancelled; return 1 }
    }

    if ($creating) { New-ProfileFromTemplate $RepoRoot $ProfileName $Language $ProjectMapTool $profileRoot | Out-Null }
    if ($profileRoot -and -not (Test-Path (Join-Path $profileRoot 'README.md'))) {
        Write-TextFile (Join-Path $profileRoot 'README.md') ($script:PersonalReadme.Replace("`r`n", "`n") + "`n")
    }
    $backup = Backup-AgyConfig
    Write-Host ($t.msgBackup -f $backup)
    $state = @{ profile = $ProfileName; role = $role; repoPath = $RepoRoot }
    if ($profileRoot) { $state.backupRepo = $backupUrl; $state.profileRoot = $profileRoot }
    Set-MachineState $state

    $code = Invoke-Apply -RepoRoot $RepoRoot -SkipCapture
    if ($code -ne 0) { Write-Host ($t.msgApplyFailed -f (Get-AgyPaths).LogDir) }
    if ($profileRoot) {
        # Push the profile right away so the backup exists from the first minute.
        $s = Invoke-Sync -RepoRoot $RepoRoot -Force
        if ($s -eq 0) { Write-Host ($t.msgBackupPushed -f $backupUrl) }
        else { Write-Host ($t.msgBackupPushFailed -f (Get-AgyPaths).LogDir); $code = 1 }
    }

    # Older versions used Windows scheduled tasks; maintenance now runs from the agy SessionStart hook.
    Unregister-AgyTasks
    if (Test-Path (Join-Path $backup 'GEMINI.md')) { Write-Host ($t.msgOldGemini -f (Join-Path $profDir 'GEMINI.profile.md')) }
    Write-Host ($t.msgDone -f $ProfileName, $role)
    Write-Host ($t.msgUninstallHint -f (Join-Path $RepoRoot 'scripts\uninstall.ps1'))
    if ($code -ne 0) { return 1 }
    return 0
}

function Invoke-Uninstall {
    param(
        [string]$RepoRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
        [string]$RestoreBackup,
        [switch]$Yes
    )
    $t = Get-I18nText $RepoRoot 'en'
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
    # Forget the setup so the next install runs in full (the backup repository itself is kept).
    Remove-Item (Get-StateFile 'machine.json') -Force -ErrorAction SilentlyContinue
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
