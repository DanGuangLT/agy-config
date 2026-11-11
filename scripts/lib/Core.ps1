# Core helpers: machine paths, UTF-8 text/JSON IO, logging, external commands, tool lookup.
# Windows PowerShell 5.1 compatible. Keep this file ASCII-only.

function Get-AgyPaths {
    $h = if ($env:AGYCFG_HOME) { $env:AGYCFG_HOME } else { $HOME }
    $state = Join-Path $h '.agy-config-state'
    @{
        Home        = $h
        GeminiMd    = Join-Path $h '.gemini\GEMINI.md'
        CliSettings = Join-Path $h '.gemini\antigravity-cli\settings.json'
        SkillsDir   = Join-Path $h '.gemini\config\skills'
        PluginsDir  = Join-Path $h '.gemini\config\plugins'
        McpConfig   = Join-Path $h '.gemini\config\mcp_config.json'
        SkillLock   = Join-Path $h '.agents\.skill-lock.json'
        StateDir    = $state
        LogDir      = Join-Path $state 'logs'
        SnapshotDir = Join-Path $state 'snapshots'
        StagingDir  = Join-Path $state 'staging'
        CacheDir    = Join-Path $state 'cache'
        BackupRoot  = Join-Path $h '.agy-config-backup'
        DefaultRepo = Join-Path $h '.agy-config'
    }
}

$script:Utf8NoBom = New-Object System.Text.UTF8Encoding $false

function Read-TextFile([string]$Path) {
    [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
}

function Write-TextFile([string]$Path, [string]$Text) {
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [IO.File]::WriteAllText($Path, $Text, $script:Utf8NoBom)
}

function ConvertTo-PlainObject($Value) {
    # PSCustomObject -> hashtable, arrays stay arrays (also with one element), recursively.
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $h = @{}
        foreach ($p in $Value.PSObject.Properties) { $h[$p.Name] = ConvertTo-PlainObject $p.Value }
        return $h
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $h = @{}
        foreach ($k in $Value.Keys) { $h[$k] = ConvertTo-PlainObject $Value[$k] }
        return $h
    }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        $list = New-Object System.Collections.ArrayList
        foreach ($item in $Value) { [void]$list.Add((ConvertTo-PlainObject $item)) }
        return , ($list.ToArray())
    }
    return $Value
}

function Read-JsonFile([string]$Path, $Default) {
    # Objects come back as hashtables. A top-level JSON array is emitted item by item:
    # wrap the call in @() when the file holds an array.
    if (-not (Test-Path $Path)) { return $Default }
    $text = Read-TextFile $Path
    if ([string]::IsNullOrWhiteSpace($text)) { return $Default }
    $value = ConvertTo-PlainObject (ConvertFrom-Json $text)
    return $value
}

function ConvertTo-JsonString([string]$s) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    foreach ($c in $s.ToCharArray()) {
        switch ($c) {
            '"' { [void]$sb.Append('\"'); continue }
            '\' { [void]$sb.Append('\\'); continue }
            "`n" { [void]$sb.Append('\n'); continue }
            "`r" { [void]$sb.Append('\r'); continue }
            "`t" { [void]$sb.Append('\t'); continue }
            default {
                if ([int]$c -lt 0x20) { [void]$sb.Append(('\u{0:x4}' -f [int]$c)) }
                else { [void]$sb.Append($c) }
            }
        }
    }
    [void]$sb.Append('"')
    $sb.ToString()
}

function Format-Json($Value, [int]$Indent = 0) {
    # Deterministic JSON: 2-space indent, object keys sorted, non-ASCII kept as-is.
    $pad = ' ' * ($Indent * 2)
    $pad2 = ' ' * (($Indent + 1) * 2)
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { if ($Value) { return 'true' } else { return 'false' } }
    if ($Value -is [string] -or $Value -is [char]) { return ConvertTo-JsonString ([string]$Value) }
    if ($Value -is [datetime]) { return ConvertTo-JsonString ($Value.ToString('o')) }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal] -or $Value -is [single]) {
        return ([string]::Format([Globalization.CultureInfo]::InvariantCulture, '{0}', $Value))
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) { $Value = ConvertTo-PlainObject $Value }
    if ($Value -is [System.Collections.IDictionary]) {
        if ($Value.Count -eq 0) { return '{}' }
        $parts = foreach ($k in ($Value.Keys | Sort-Object)) {
            $pad2 + (ConvertTo-JsonString ([string]$k)) + ': ' + (Format-Json $Value[$k] ($Indent + 1))
        }
        return "{`n" + ($parts -join ",`n") + "`n$pad}"
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        $items = @($Value)
        if ($items.Count -eq 0) { return '[]' }
        $parts = foreach ($i in $items) { $pad2 + (Format-Json $i ($Indent + 1)) }
        return "[`n" + ($parts -join ",`n") + "`n$pad]"
    }
    return ConvertTo-JsonString ([string]$Value)
}

function Write-JsonFile([string]$Path, $Object) {
    Write-TextFile $Path ((Format-Json $Object) + "`n")
}

function Write-AgyLog {
    param(
        [string]$Script,
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )
    $dir = (Get-AgyPaths).LogDir
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $file = Join-Path $dir ($Script + '-' + (Get-Date -Format 'yyyyMMdd') + '.log')
    $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + " [$Level] $Message" + [Environment]::NewLine
    [IO.File]::AppendAllText($file, $line, $script:Utf8NoBom)
}

function ConvertTo-CommandLineArg([string]$Arg) {
    # Windows argv quoting rules (CommandLineToArgvW).
    if ($Arg -eq '') { return '""' }
    if ($Arg -notmatch '[\s"]') { return $Arg }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    $backslashes = 0
    foreach ($c in $Arg.ToCharArray()) {
        if ($c -eq '\') { $backslashes++; continue }
        if ($c -eq '"') {
            [void]$sb.Append('\' * ($backslashes * 2 + 1)); [void]$sb.Append('"'); $backslashes = 0; continue
        }
        if ($backslashes) { [void]$sb.Append('\' * $backslashes); $backslashes = 0 }
        [void]$sb.Append($c)
    }
    if ($backslashes) { [void]$sb.Append('\' * ($backslashes * 2)) }
    [void]$sb.Append('"')
    $sb.ToString()
}

function Invoke-External([string]$Exe, [string[]]$Arguments = @(), [string]$WorkingDirectory) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.Arguments = (@($Arguments) | ForEach-Object { ConvertTo-CommandLineArg $_ }) -join ' '
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [Text.Encoding]::UTF8
    if ($WorkingDirectory) { $psi.WorkingDirectory = $WorkingDirectory }
    try {
        $p = [System.Diagnostics.Process]::Start($psi)
        $out = $p.StandardOutput.ReadToEndAsync()
        $err = $p.StandardError.ReadToEndAsync()
        $p.WaitForExit()
        return @{ ExitCode = $p.ExitCode; StdOut = $out.Result; StdErr = $err.Result }
    } catch {
        return @{ ExitCode = -1; StdOut = ''; StdErr = $_.Exception.Message }
    }
}

function Invoke-Http([string]$Uri) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Invoke-RestMethod -Uri $Uri -UseBasicParsing -ErrorAction Stop
}

function Resolve-Tool {
    param([ValidateSet('git', 'agy', 'python', 'node')][string]$Name)
    $cmd = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue |
        Where-Object { $_.Source -notmatch '\\WindowsApps\\' } | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    $candidates = switch ($Name) {
        'agy' { @(Join-Path $env:LOCALAPPDATA 'agy\bin\agy.exe') }
        'git' { @(Join-Path $env:ProgramFiles 'Git\cmd\git.exe') }
        'node' { @(Join-Path $env:ProgramFiles 'nodejs\node.exe') }
        'python' {
            $found = @()
            foreach ($pattern in @((Join-Path $env:LOCALAPPDATA 'Programs\Python\Python3*\python.exe'), 'C:\Python3*\python.exe')) {
                $found += @(Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue |
                    Sort-Object { [int](($_.Directory.Name -replace '\D', '') + '0') } -Descending |
                    ForEach-Object { $_.FullName })
            }
            $found
        }
    }
    foreach ($c in $candidates) { if ($c -and (Test-Path $c)) { return $c } }
    return $null
}
