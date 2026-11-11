# Weekly maintenance, started by the agy SessionStart hook (no Windows scheduled tasks). ASCII-only file.
# Owner: apply (which first backs this machine up, then pulls and installs) and update.
# Follower: apply only. The week counts as done only when everything succeeded.

function Invoke-Maintenance {
    param([Parameter(Mandatory)][string]$RepoRoot)
    Register-Run 'weekly-attempt'
    $machine = Get-MachineState
    $code = Invoke-Apply -RepoRoot $RepoRoot
    if ($machine.role -eq 'owner') {
        $u = Invoke-Update -RepoRoot $RepoRoot
        if ($u -ne 0) { $code = $u }
    }
    if ($code -eq 0) {
        Register-Run 'weekly'
        Write-AgyLog -Script 'maintain' -Message 'weekly maintenance done; next check in 7 days'
    } else {
        Write-AgyLog -Script 'maintain' -Message "weekly maintenance finished with errors (code $code); retry at the next agy start after 24 h" -Level WARN
    }
    return $code
}
