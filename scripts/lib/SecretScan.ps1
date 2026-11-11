# Pre-commit scan for secrets and personal data in files about to be published. ASCII-only file.

$script:SecretRules = @(
    @{ Rule = 'github-token'; Pattern = 'ghp_[A-Za-z0-9]{20,}|gho_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}' },
    @{ Rule = 'openai-key'; Pattern = 'sk-[A-Za-z0-9_\-]{20,}' },
    @{ Rule = 'google-key'; Pattern = 'AIza[0-9A-Za-z_\-]{30,}' },
    @{ Rule = 'private-key'; Pattern = '-----BEGIN [A-Z ]*PRIVATE KEY-----' },
    @{ Rule = 'password'; Pattern = '(?i)password\s*[=:]\s*(?!\$\{)\S+' },
    @{ Rule = 'email'; Pattern = '[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}' },
    @{ Rule = 'user-path'; Pattern = '(?i)[A-Z]:\\{1,2}Users\\{1,2}(?![<{%$])[^\\\s"''<>]+' }
)
$script:AlwaysAllowedEmail = '(?i)@(example\.(com|org|net|invalid)|users\.noreply\.github\.com)$'

function Find-Secrets([string[]]$Paths, [string[]]$AllowedEmails = @()) {
    foreach ($path in $Paths) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        $bytes = [IO.File]::ReadAllBytes($path)
        if ($bytes -contains 0) { continue }  # binary
        $lines = ([Text.Encoding]::UTF8.GetString($bytes) -replace "`r`n", "`n") -split "`n"
        for ($i = 0; $i -lt $lines.Count; $i++) {
            foreach ($r in $script:SecretRules) {
                foreach ($m in [regex]::Matches($lines[$i], $r.Pattern)) {
                    if ($r.Rule -eq 'email' -and ($m.Value -match $script:AlwaysAllowedEmail -or $AllowedEmails -contains $m.Value)) { continue }
                    @{ Path = $path; Line = $i + 1; Rule = $r.Rule }
                }
            }
        }
    }
}
