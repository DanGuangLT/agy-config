# agy CLI settings (permissions.allow) and MCP config secret handling. ASCII-only file.

function Get-MachinePermissions([string]$SettingsPath) {
    $s = Read-JsonFile $SettingsPath @{}
    if ($s.permissions -is [hashtable] -and $s.permissions.allow) { return @($s.permissions.allow) }
    return @()
}

function Merge-Permissions([string]$SettingsPath, [string[]]$Allow) {
    $s = Read-JsonFile $SettingsPath @{}
    if (-not ($s.permissions -is [hashtable])) { $s.permissions = @{} }
    $current = New-Object System.Collections.ArrayList
    foreach ($a in @($s.permissions.allow)) { if ($a) { [void]$current.Add($a) } }
    $added = @()
    foreach ($a in $Allow) {
        if ($a -and -not $current.Contains($a)) { [void]$current.Add($a); $added += $a }
    }
    $hadBlock = $s.permissions.ContainsKey('allow')
    if ($added.Count -gt 0 -or -not $hadBlock -or -not (Test-Path $SettingsPath)) {
        $s.permissions.allow = $current.ToArray()
        Write-JsonFile $SettingsPath $s
    }
    return , $added
}

function Remove-Permissions([string]$SettingsPath, [string[]]$Remove) {
    if (-not (Test-Path $SettingsPath)) { return }
    $s = Read-JsonFile $SettingsPath @{}
    if (-not ($s.permissions -is [hashtable])) { return }
    $s.permissions.allow = @(@($s.permissions.allow) | Where-Object { $Remove -notcontains $_ })
    Write-JsonFile $SettingsPath $s
}

function ConvertTo-McpVariableName([string]$Server, [string]$Key) {
    (($Server + '_' + $Key).ToUpperInvariant() -replace '[^A-Z0-9]', '_')
}

function Protect-McpConfig($Config) {
    $copy = ConvertTo-PlainObject $Config
    $vars = New-Object System.Collections.ArrayList
    $protectValue = {
        param([string]$Value, [string]$Key)
        if ($Value -match '^\$\{[A-Za-z0-9_]+\}$') { return $Value }
        $var = ConvertTo-McpVariableName $name $Key
        if (-not $vars.Contains($var)) { [void]$vars.Add($var) }
        return '${' + $var + '}'
    }
    $protectUrl = {
        param([string]$Value)
        [regex]::Replace($Value, '([?&])([^?&#=]+)=([^&#]*)', {
            param($m)
            $key = [Uri]::UnescapeDataString($m.Groups[2].Value)
            if ($key -notmatch '(?i)(key|token|secret|password|auth)') { return $m.Value }
            return $m.Groups[1].Value + $m.Groups[2].Value + '=' + (& $protectValue $m.Groups[3].Value $key)
        })
    }
    $servers = $copy.mcpServers
    if ($servers -is [hashtable]) {
        foreach ($name in @($servers.Keys)) {
            $srv = $servers[$name]
            foreach ($section in 'env', 'headers') {
                if ($srv[$section] -is [hashtable]) {
                    foreach ($k in @($srv[$section].Keys)) {
                        $v = [string]$srv[$section][$k]
                        if ($v -match '^\$\{[A-Za-z0-9_]+\}$') { continue }
                        $srv[$section][$k] = & $protectValue $v $k
                    }
                }
            }
            foreach ($key in 'url', 'serverUrl') {
                if ($srv[$key] -is [string]) { $srv[$key] = & $protectUrl $srv[$key] }
            }
            if ($srv.ContainsKey('args')) {
                $flagPattern = '(?i)^(--(?:token|access-token|api-key|apikey|key|secret|password)|-k)(?:=(.*))?$'
                $nextKey = $null
                $srv.args = @(foreach ($arg in @($srv.args)) {
                    if ($nextKey) {
                        & $protectValue $arg $nextKey
                        $nextKey = $null
                    } elseif ($arg -match $flagPattern) {
                        $flag = $Matches[1]
                        if ($Matches.ContainsKey(2)) {
                            $flag + '=' + (& $protectValue $Matches[2] $flag.TrimStart('-'))
                        } else { $nextKey = $flag.TrimStart('-'); $arg }
                    } else {
                        $value = [regex]::Replace($arg, '(?i)(Authorization|Bearer)(:\s*|\s+)(Bearer\s+)?(\$\{[A-Za-z0-9_]+\}|[^\s"'';,]+)', {
                            param($m)
                            $m.Groups[1].Value + $m.Groups[2].Value + $m.Groups[3].Value + (& $protectValue $m.Groups[4].Value $m.Groups[1].Value)
                        })
                        if ($value -match '^[A-Za-z][A-Za-z0-9+.-]*://') { $value = & $protectUrl $value }
                        $value
                    }
                })
            }
        }
    }
    return @{ Config = $copy; Variables = @($vars.ToArray()) }
}

function Expand-McpConfig($Config) {
    $copy = ConvertTo-PlainObject $Config
    $missing = New-Object System.Collections.ArrayList
    $expand = {
        param([string]$Value)
        [regex]::Replace($Value, '\$\{([A-Za-z0-9_]+)\}', {
            param($m)
            $val = [Environment]::GetEnvironmentVariable($m.Groups[1].Value)
            if ($null -eq $val) {
                if (-not $missing.Contains($m.Groups[1].Value)) { [void]$missing.Add($m.Groups[1].Value) }
                return $m.Value
            }
            return $val
        })
    }
    $servers = $copy.mcpServers
    if ($servers -is [hashtable]) {
        foreach ($name in @($servers.Keys)) {
            $srv = $servers[$name]
            foreach ($section in 'env', 'headers') {
                if ($srv[$section] -is [hashtable]) {
                    foreach ($k in @($srv[$section].Keys)) {
                        $srv[$section][$k] = & $expand ([string]$srv[$section][$k])
                    }
                }
            }
            foreach ($key in 'url', 'serverUrl') {
                if ($srv[$key] -is [string]) { $srv[$key] = & $expand $srv[$key] }
            }
            if ($srv.ContainsKey('args')) { $srv.args = @($srv.args | ForEach-Object { & $expand ([string]$_) }) }
        }
    }
    return @{ Config = $copy; Missing = @($missing.ToArray()) }
}
