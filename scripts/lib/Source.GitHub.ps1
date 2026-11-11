# GitHub-hosted sources fetched with git at a pinned commit. ASCII-only file.

function Invoke-Git([string]$Dir, [string[]]$GitArgs) {
    $git = Resolve-Tool git
    if (-not $git) { throw 'git not found' }
    $r = Invoke-External $git $GitArgs $Dir
    if ($r.ExitCode -ne 0) { throw ("git " + ($GitArgs -join ' ') + " failed: " + $r.StdErr.Trim()) }
    return $r.StdOut
}

function Get-GitHeadSha([string]$Repo) {
    $out = Invoke-Git $null @('ls-remote', $Repo, 'HEAD')
    $sha = ($out.Trim() -split '\s+')[0]
    if ($sha -notmatch '^[0-9a-f]{40}$') { throw "could not read HEAD of $Repo" }
    return $sha
}

function Sync-GitCache($Source, [string]$Sha, [string[]]$SparsePaths) {
    # Partial clone of the source repo in the cache, checked out at $Sha, limited to $SparsePaths.
    $dir = Join-Path (Get-AgyPaths).CacheDir $Source.id
    if (-not (Test-Path (Join-Path $dir '.git'))) {
        Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dir) | Out-Null
        Invoke-Git $null @('clone', '--quiet', '--filter=blob:none', '--no-checkout', $Source.repo, $dir) | Out-Null
    } else {
        Invoke-Git $dir @('fetch', '--quiet', 'origin') | Out-Null
    }
    if ($SparsePaths -and $SparsePaths.Count -gt 0) {
        Invoke-Git $dir (@('sparse-checkout', 'set', '--cone') + $SparsePaths) | Out-Null
    }
    Invoke-Git $dir @('-c', 'advice.detachedHead=false', 'checkout', '--force', '--quiet', $Sha) | Out-Null
    return $dir
}

function Copy-Folder([string]$From, [string]$To) {
    if (-not (Test-Path $From)) { throw "missing folder $From" }
    Remove-Item $To -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $To) | Out-Null
    Copy-Item -Recurse -Force -Path $From -Destination $To
}

function Install-GitHubSkills($Source, [string]$Version) {
    $paths = @($Source.skills | ForEach-Object { $_.path })
    $cache = Sync-GitCache $Source $Version $paths
    foreach ($sk in @($Source.skills)) {
        Copy-Folder (Join-Path $cache ($sk.path -replace '/', '\')) (Join-Path (Get-AgyPaths).SkillsDir $sk.name)
    }
    return @{ Ok = $true; Error = '' }
}

function Install-GitPlugin($Source, [string]$Version) {
    $p = Get-AgyPaths
    $dst = Join-Path $p.PluginsDir $Source.plugin
    if (Test-Path (Join-Path $dst '.git')) {
        Invoke-Git $dst @('fetch', '--quiet', 'origin') | Out-Null
    } else {
        if (Test-Path $dst) {
            # Keep whatever was there before we take over the folder.
            $keep = Join-Path $p.SnapshotDir ($Source.plugin + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
            New-Item -ItemType Directory -Force -Path $p.SnapshotDir | Out-Null
            Move-Item $dst $keep
        }
        New-Item -ItemType Directory -Force -Path $p.PluginsDir | Out-Null
        Invoke-Git $null @('clone', '--quiet', $Source.repo, $dst) | Out-Null
    }
    Invoke-Git $dst @('-c', 'advice.detachedHead=false', 'checkout', '--force', '--quiet', $Version) | Out-Null
    return @{ Ok = $true; Error = '' }
}

function Install-PackagedPlugin($Source, [string]$Version) {
    $p = Get-AgyPaths
    $srcPaths = @($Source.paths)
    $cache = Sync-GitCache $Source $Version $srcPaths
    $staging = Join-Path $p.StagingDir $Source.plugin
    Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path (Join-Path $staging 'skills') | Out-Null

    $single = if ($srcPaths.Count -eq 1) { Join-Path $cache ($srcPaths[0] -replace '/', '\') } else { $null }
    if ($single -and (Test-Path (Join-Path $single 'skills'))) {
        Get-ChildItem -Path (Join-Path $single 'skills') -Directory | ForEach-Object {
            Copy-Folder $_.FullName (Join-Path $staging ('skills\' + $_.Name))
        }
    } else {
        foreach ($sp in $srcPaths) {
            $from = Join-Path $cache ($sp -replace '/', '\')
            Copy-Folder $from (Join-Path $staging ('skills\' + (Split-Path -Leaf $from)))
        }
    }
    foreach ($lic in 'LICENSE', 'LICENSE.txt', 'LICENSE.md') {
        $f = Join-Path $cache $lic
        if (Test-Path $f) { Copy-Item $f (Join-Path $staging $lic) -Force }
    }
    $manifest = @{
        name        = $Source.plugin
        displayName = if ($Source.displayName) { $Source.displayName } else { $Source.plugin }
        version     = $Version.Substring(0, [Math]::Min(7, $Version.Length))
        description = if ($Source.description) { $Source.description } else { "Packaged from $($Source.repo)" }
        author      = @{ name = if ($Source.author) { $Source.author } else { 'See repository' } }
        repository  = $Source.repo
    }
    if ($Source.license) { $manifest.license = $Source.license }
    Write-JsonFile (Join-Path $staging 'plugin.json') $manifest

    $agy = Resolve-Tool agy
    if (-not $agy) { return @{ Ok = $false; Error = 'agy-missing' } }
    $r = Invoke-External $agy @('plugin', 'install', $staging)
    if ($r.ExitCode -ne 0) { return @{ Ok = $false; Error = "agy plugin install failed: $($r.StdErr)$($r.StdOut)" } }
    return @{ Ok = $true; Error = '' }
}
