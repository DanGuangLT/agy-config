# git operations on the config repo itself. ASCII-only file.

function Invoke-RepoGit([string]$RepoRoot, [string[]]$GitArgs) { Invoke-Git $RepoRoot $GitArgs }

function Update-ConfigRepo([string]$RepoRoot) {
    try {
        Invoke-Git $RepoRoot @('pull', '--quiet', '--rebase', '--autostash', 'origin', 'main') | Out-Null
        return @{ Ok = $true; Error = '' }
    } catch {
        $git = Resolve-Tool git
        if ($git) { Invoke-External $git @('rebase', '--abort') $RepoRoot | Out-Null }
        return @{ Ok = $false; Error = $_.Exception.Message }
    }
}

function Test-PushAccess([string]$RepoRoot) {
    $git = Resolve-Tool git
    if (-not $git) { return $false }
    (Invoke-External $git @('push', '--dry-run', '--quiet', 'origin', 'HEAD:refs/heads/agy-config-probe') $RepoRoot).ExitCode -eq 0
}
