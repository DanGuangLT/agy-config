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
    $vars = @()
    $servers = $copy.mcpServers
    if ($servers -is [hashtable]) {
        foreach ($name in @($servers.Keys)) {
            $srv = $servers[$name]
            foreach ($section in 'env', 'headers') {
                if ($srv[$section] -is [hashtable]) {
                    foreach ($k in @($srv[$section].Keys)) {
                        $v = [string]$srv[$section][$k]
                        if ($v -match '^\$\{[A-Za-z0-9_]+\}$') { continue }
                        $var = ConvertTo-McpVariableName $name $k
                        $srv[$section][$k] = '${' + $var + '}'
                        $vars += $var
                    }
                }
            }
        }
    }
    return @{ Config = $copy; Variables = $vars }
}

function Expand-McpConfig($Config) {
    $copy = ConvertTo-PlainObject $Config
    $missing = New-Object System.Collections.ArrayList
    $servers = $copy.mcpServers
    if ($servers -is [hashtable]) {
        foreach ($name in @($servers.Keys)) {
            $srv = $servers[$name]
            foreach ($section in 'env', 'headers') {
                if ($srv[$section] -is [hashtable]) {
                    foreach ($k in @($srv[$section].Keys)) {
                        $v = [string]$srv[$section][$k]
                        $srv[$section][$k] = [regex]::Replace($v, '\$\{([A-Za-z0-9_]+)\}', {
                                param($m)
                                $val = [Environment]::GetEnvironmentVariable($m.Groups[1].Value)
                                if ($null -eq $val) {
                                    if (-not $missing.Contains($m.Groups[1].Value)) { [void]$missing.Add($m.Groups[1].Value) }
                                    return $m.Value
                                }
                                return $val
                            })
                    }
                }
            }
        }
    }
    return @{ Config = $copy; Missing = @($missing.ToArray()) }
}
