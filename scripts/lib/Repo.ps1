# git operations on the config repo itself. ASCII-only file.

function Invoke-RepoGit([string]$RepoRoot, [string[]]$GitArgs) { Invoke-Git $RepoRoot $GitArgs }

function Update-ConfigRepo([string]$RepoRoot) {
    try {
        # A brand-new remote with no main yet has nothing to pull.
        $heads = ''
        try { $heads = (Invoke-Git $RepoRoot @('ls-remote', '--heads', 'origin', 'main')).Trim() } catch { throw }
        if (-not $heads) { return @{ Ok = $true; Error = '' } }
        Invoke-Git $RepoRoot @('pull', '--quiet', '--rebase', '--autostash', 'origin', 'main') | Out-Null
        return @{ Ok = $true; Error = '' }
    } catch {
        $err = $_.Exception.Message
        # Abort only a rebase that is actually in progress (never another process's, never on lock errors).
        $inRebase = $false
        foreach ($d in 'rebase-merge', 'rebase-apply') {
            try {
                $gp = (Invoke-Git $RepoRoot @('rev-parse', '--git-path', $d)).Trim()
                if ($gp -and (Test-Path (Join-Path $RepoRoot $gp))) { $inRebase = $true }
            } catch { }
        }
        $git = Resolve-Tool git
        if ($inRebase -and $git) { Invoke-External $git @('rebase', '--abort') $RepoRoot | Out-Null }
        return @{ Ok = $false; Error = $err }
    }
}

function Test-PushAccess([string]$RepoRoot) {
    $git = Resolve-Tool git
    if (-not $git) { return $false }
    $ref = 'HEAD'
    if ((Invoke-External $git @('rev-parse', '--verify', '--quiet', 'HEAD') $RepoRoot).ExitCode -ne 0) {
        # A clone of an empty repository has no commit to offer: probe with a throwaway empty commit object.
        $probe = Invoke-External $git @('-c', 'user.name=agy-config', '-c', 'user.email=agy-config@users.noreply.github.com',
            'commit-tree', '4b825dc642cb6eb9a060e54bf8d69288fbee4904', '-m', 'probe') $RepoRoot
        if ($probe.ExitCode -ne 0) { return $false }
        $ref = $probe.StdOut.Trim()
    }
    (Invoke-External $git @('push', '--dry-run', '--quiet', 'origin', ($ref + ':refs/heads/agy-config-probe')) $RepoRoot).ExitCode -eq 0
}

function Get-RepoOwnerName([string]$Url) {
    # https://github.com/Alice/backup.git (or the ssh form github.com:Alice/backup.git) -> alice, a valid profile name.
    $u = ([string]$Url).Trim() -replace '\.git$', '' -replace '[/\\]+$', ''
    $parts = @($u -split '[/:\\]' | Where-Object { $_ })
    $owner = if ($parts.Count -ge 2) { $parts[$parts.Count - 2] } else { '' }
    $name = (($owner.ToLowerInvariant()) -replace '[^a-z0-9_-]', '-').Trim('-', '_')
    if ($name -notmatch '^[a-z0-9][a-z0-9_-]*$' -or $name -eq '_template') { $name = 'me' }
    return $name
}

function Initialize-PersonalRepo([string]$Url, [string]$Dir) {
    # Clone (or reuse) the user's own backup repository at $Dir, on branch main, able to commit.
    # Returns @{ Ok; Error; HasProfile }. Error 'folder-in-use' means $Dir holds something else.
    $git = Resolve-Tool git
    if (-not $git) { return @{ Ok = $false; Error = 'git not found'; HasProfile = $false } }
    $Url = $Url.Trim()
    if (Test-Path (Join-Path $Dir '.git')) {
        $current = (Invoke-External $git @('remote', 'get-url', 'origin') $Dir).StdOut.Trim()
        $norm = { param($u) ([string]$u).Trim().ToLowerInvariant() -replace '[/\\]+$', '' -replace '\.git$', '' }
        if ((& $norm $current) -ne (& $norm $Url)) { return @{ Ok = $false; Error = 'folder-in-use'; HasProfile = $false } }
    } elseif ((Test-Path $Dir) -and @(Get-ChildItem -LiteralPath $Dir -Force).Count -gt 0) {
        return @{ Ok = $false; Error = 'folder-in-use'; HasProfile = $false }
    } else {
        $parent = Split-Path -Parent $Dir
        if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
        $r = Invoke-External $git @('clone', '--quiet', $Url, $Dir) $parent
        if ($r.ExitCode -ne 0) { return @{ Ok = $false; Error = $r.StdErr.Trim(); HasProfile = $false } }
    }
    $hasCommit = (Invoke-External $git @('rev-parse', '--verify', '--quiet', 'HEAD') $Dir).ExitCode -eq 0
    if (-not $hasCommit) {
        # Empty repository: the first backup commit creates main.
        Invoke-External $git @('symbolic-ref', 'HEAD', 'refs/heads/main') $Dir | Out-Null
    } else {
        $branch = (Invoke-External $git @('symbolic-ref', '--quiet', '--short', 'HEAD') $Dir).StdOut.Trim()
        if ($branch -ne 'main') { return @{ Ok = $false; Error = "the repository's branch is '$branch'; the backup uses 'main'"; HasProfile = $false } }
        $pull = Update-ConfigRepo $Dir
        if (-not $pull.Ok) { return @{ Ok = $false; Error = $pull.Error; HasProfile = $false } }
    }
    if (-not (Invoke-External $git @('config', 'user.email') $Dir).StdOut.Trim()) {
        # Backup commits must never fail for want of a git identity.
        Invoke-External $git @('config', 'user.name', 'agy-config') $Dir | Out-Null
        Invoke-External $git @('config', 'user.email', 'agy-config@users.noreply.github.com') $Dir | Out-Null
    }
    return @{ Ok = $true; Error = ''; HasProfile = (Test-Path (Join-Path $Dir 'profile.json')) }
}
