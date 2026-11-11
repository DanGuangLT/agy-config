# pip-tool (Python CLI that installs its own agy skill) and marketplace (agy plugin store) sources. ASCII-only file.

function Get-PythonVersion([string]$Python) {
    $r = Invoke-External $Python @('-X', 'utf8', '-c', "import sys;print('%d.%d' % sys.version_info[:2])")
    if ($r.ExitCode -ne 0) { return $null }
    $v = $null
    if ([version]::TryParse($r.StdOut.Trim(), [ref]$v)) { return $v }
    return $null
}

function Install-PipTool($Source, [string]$Version) {
    $py = Resolve-Tool python
    if (-not $py) { return @{ Ok = $false; Error = 'python-missing' } }
    $pv = Get-PythonVersion $py
    if (-not $pv -or $pv -lt [version]'3.10') { return @{ Ok = $false; Error = "python-too-old ($pv); need 3.10+" } }

    $spec = if ($Version -and $Version -ne 'latest') { $Source.package + '==' + $Version } else { $Source.package }
    $r = Invoke-External $py @('-X', 'utf8', '-m', 'pip', 'install', '--user', '--upgrade', '--disable-pip-version-check', '-q', $spec)
    if ($r.ExitCode -ne 0) { return @{ Ok = $false; Error = "pip install $spec failed: $($r.StdErr)" } }

    $s = Invoke-External $py @('-X', 'utf8', '-c', "import sysconfig;print(sysconfig.get_path('scripts','nt_user'))")
    if ($s.ExitCode -ne 0) { return @{ Ok = $false; Error = "python sysconfig failed: $($s.StdErr)" } }
    $scripts = $s.StdOut.Trim()
    $cmd = if ($Source.command) { $Source.command } else { @($Source.provides)[0] }

    if ($Source.postInstall) {
        # Prefer `python -m <module>`: python.exe is trusted even where Smart App Control blocks pip's launcher exe.
        $r2 = if ($Source.module) { Invoke-External $py (@('-X', 'utf8', '-m', $Source.module) + @($Source.postInstall)) }
              else { Invoke-External (Join-Path $scripts ($cmd + '.exe')) @($Source.postInstall) }
        if ($r2.ExitCode -ne 0) { return @{ Ok = $false; Error = "$cmd $(@($Source.postInstall) -join ' ') failed: $($r2.StdErr)" } }
    }

    # A launcher blocked by Application Control is replaced by a .cmd shim that runs the module,
    # so the skill's `graphify ...` commands keep working.
    if ($Source.module) {
        $exe = Join-Path $scripts ($cmd + '.exe')
        if (Test-Path $exe) {
            $probe = Invoke-External $exe @('--help') -TimeoutSeconds 60
            if ($probe.ExitCode -eq -1 -and $probe.StdErr -match 'Application Control|blocked') {
                Remove-Item $exe -Force
                Write-TextFile (Join-Path $scripts ($cmd + '.cmd')) ("@echo off`r`n`"$py`" -X utf8 -m " + $Source.module + " %*`r`n")
            }
        }
    }
    return @{ Ok = $true; Error = '' }
}

function Get-PipLatestVersion($Source) {
    (Invoke-Http ('https://pypi.org/pypi/' + $Source.package + '/json')).info.version
}

function Uninstall-PipTool($Source) {
    # Remove only the agy skills this tool provides. The Python package may serve other agents, so it stays.
    foreach ($n in @($Source.provides)) {
        Remove-Item (Join-Path (Get-AgyPaths).SkillsDir $n) -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-AgyPluginList {
    $agy = Resolve-Tool agy
    if (-not $agy) { return @() }
    $r = Invoke-External $agy @('plugin', 'list', '--json')
    if ($r.ExitCode -ne 0 -or -not $r.StdOut.Trim()) { return @() }
    # Emit plugins one by one (callers wrap with @()).
    $list = ConvertTo-PlainObject (ConvertFrom-Json $r.StdOut)
    return $list
}

function Get-MarketplaceVersion($Source) {
    $hit = @(Get-AgyPluginList) | Where-Object { $_.name -eq $Source.plugin } | Select-Object -First 1
    if ($hit) { return $hit.version }
    return $null
}

function Install-Marketplace($Source, [string]$Version) {
    # agy cannot install a chosen version, so keep a copy of what works for rollback.
    $p = Get-AgyPaths
    $current = Join-Path $p.PluginsDir $Source.plugin
    if (Test-Path $current) {
        $snap = Join-Path $p.SnapshotDir $Source.plugin
        Remove-Item $snap -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Force -Path $p.SnapshotDir | Out-Null
        Copy-Item -Recurse -Force $current $snap
    }
    $agy = Resolve-Tool agy
    if (-not $agy) { return @{ Ok = $false; Error = 'agy-missing' } }
    $r = Invoke-External $agy @('plugin', 'install', ($Source.plugin + '@' + $Source.marketplace))
    if ($r.ExitCode -ne 0) { return @{ Ok = $false; Error = "agy plugin install failed: $($r.StdErr)$($r.StdOut)" } }
    return @{ Ok = $true; Error = ''; Version = (Get-MarketplaceVersion $Source) }
}

function Restore-MarketplaceSnapshot($Source) {
    $p = Get-AgyPaths
    $snap = Join-Path $p.SnapshotDir $Source.plugin
    if (-not (Test-Path $snap)) { return $false }
    $dst = Join-Path $p.PluginsDir $Source.plugin
    Remove-Item $dst -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $p.PluginsDir | Out-Null
    Copy-Item -Recurse -Force $snap $dst
    return $true
}
