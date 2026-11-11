# git operations on the config repo itself. ASCII-only file.

function Invoke-RepoGit([string]$RepoRoot, [string[]]$GitArgs) { Invoke-Git $RepoRoot $GitArgs }

function Update-ConfigRepo([string]$RepoRoot) {
    try {
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
    (Invoke-External $git @('push', '--dry-run', '--quiet', 'origin', 'HEAD:refs/heads/agy-config-probe') $RepoRoot).ExitCode -eq 0
}
