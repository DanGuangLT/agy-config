# Repository hygiene checks for local use and CI. Windows PowerShell 5.1; ASCII-only.
[CmdletBinding()]
param([string]$Root)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\lib\All.ps1')
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }

function Get-ValidationFiles([string]$Directory, [string]$ScratchDirectory) {
    foreach ($item in Get-ChildItem -LiteralPath $Directory -Force) {
        # Git internals and disposable local test runs are not repository content.
        if ($item.Name -eq '.git' -or $item.FullName -eq $ScratchDirectory) { continue }
        if ($item.PSIsContainer) {
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) {
                Get-ValidationFiles $item.FullName $ScratchDirectory
            }
        } else { $item }
    }
}

try {
    $rootPath = (Resolve-Path -LiteralPath $Root).ProviderPath.TrimEnd('\', '/')
    if (-not (Test-Path -LiteralPath $rootPath -PathType Container)) { throw 'Root is not a directory.' }
    # Include untracked candidates so validation works before git add. Tracked
    # files must pass every check even if they are in an ignored scratch folder.
    $published = $null
    if (Test-Path -LiteralPath (Join-Path $rootPath '.git')) {
        $git = Resolve-Tool git
        if ($git) {
            $listed = Invoke-External $git @('ls-files', '--cached', '--others', '--exclude-standard', '-z') $rootPath
            if ($listed.ExitCode -eq 0) {
                $published = @{}
                foreach ($name in ($listed.StdOut -split "`0")) { if ($name) { $published[$name] = $true } }
            }
        }
    }
    $files = @(Get-ValidationFiles $rootPath (Join-Path $rootPath '.agy-tmp'))
    if ($null -ne $published) {
        foreach ($name in $published.Keys) {
            $path = Join-Path $rootPath $name
            if (Test-Path -LiteralPath $path -PathType Leaf) { $files += Get-Item -LiteralPath $path -Force }
        }
    }
    $files = @($files | Sort-Object FullName -Unique)
    $problems = New-Object 'System.Collections.Generic.List[string]'
    $relativePaths = @{}
    $jsonValues = @{}

    foreach ($file in $files) {
        $relative = $file.FullName.Substring($rootPath.Length + 1) -replace '\\', '/'
        $relativePaths[$file.FullName] = $relative
        if ($file.Length -gt 1MB) { $problems.Add($relative + ': exceeds 1 MB') }
        if ($file.Extension -eq '.ps1') {
            if (@([IO.File]::ReadAllBytes($file.FullName) | Where-Object { $_ -gt 127 }).Count -gt 0) {
                $problems.Add($relative + ': PowerShell files must be ASCII-only')
            }
        }
        if ($file.Extension -eq '.json') {
            try {
                if ([string]::IsNullOrWhiteSpace((Read-TextFile $file.FullName))) { throw 'Empty JSON.' }
                $jsonValues[$relative] = Read-JsonFile $file.FullName $null
            } catch { $problems.Add($relative + ': invalid JSON') }
        }
        if ($file.Name -eq 'SKILL.md' -and -not (Test-SkillFolder $file.DirectoryName)) {
            $problems.Add($relative + ': SKILL.md requires name and description in frontmatter')
        }
        if ($file.Name -eq 'plugin.json' -and $jsonValues.ContainsKey($relative)) {
            $manifest = $jsonValues[$relative]
            if ($manifest -isnot [hashtable] -or
                [string]::IsNullOrWhiteSpace([string]$manifest.name) -or
                [string]::IsNullOrWhiteSpace([string]$manifest.version)) {
                $problems.Add($relative + ': plugin.json requires name and version')
            }
        }
    }

    $attributionFile = Join-Path $rootPath 'THIRD_PARTY.md'
    $attribution = if (Test-Path -LiteralPath $attributionFile) { Read-TextFile $attributionFile } else { '' }
    foreach ($relative in @($jsonValues.Keys | Sort-Object)) {
        if ($relative -ne 'core/sources.json' -and $relative -notmatch '^profiles/[^/]+/sources\.json$') { continue }
        $lockRelative = $relative -replace 'sources\.json$', 'sources.lock.json'
        $locked = $jsonValues[$lockRelative]
        foreach ($source in @($jsonValues[$relative])) {
            if (-not $source) { continue }
            if ($locked -isnot [hashtable] -or -not $locked.ContainsKey([string]$source.id)) {
                $problems.Add($relative + ': missing locked version for ' + $source.id)
            }
            if ($relative -ne 'core/sources.json') { continue }
            $references = @()
            if ($source.repo) { $references += [string]$source.repo }
            if ($source.type -eq 'pip-tool' -and $source.package) { $references += [string]$source.package }
            foreach ($reference in $references) {
                if ($attribution.IndexOf($reference, [StringComparison]::Ordinal) -lt 0) {
                    $problems.Add($relative + ': missing from THIRD_PARTY.md: ' + $reference)
                }
            }
        }
    }

    # Non-git fixture roots are scanned in full. The two intentional secret
    # fixture locations remain subject to metadata, ASCII, and size checks.
    $scanPaths = @($files | Where-Object {
        $relative = $relativePaths[$_.FullName]
        $relative -notmatch '^(tests|\.superpowers)/' -and
            ($null -eq $published -or $published.ContainsKey($relative))
    } | ForEach-Object { $_.FullName })
    foreach ($hit in @(Find-Secrets $scanPaths)) {
        $problems.Add(('{0}:{1}: possible secret or personal data ({2})' -f $relativePaths[$hit.Path], $hit.Line, $hit.Rule))
    }

    # The project is English-only: flag Vietnamese letters (tests build such text from code points).
    $vietnamese = '[\u0102\u0103\u0110\u0111\u01a0\u01a1\u01af\u01b0\u1ea0-\u1ef9]'
    foreach ($file in $files) {
        $bytes = [IO.File]::ReadAllBytes($file.FullName)
        if ($bytes -contains 0) { continue }
        $lines = ([Text.Encoding]::UTF8.GetString($bytes) -replace "`r`n", "`n") -split "`n"
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match $vietnamese) {
                $problems.Add(('{0}:{1}: Vietnamese text (the project is English-only)' -f $relativePaths[$file.FullName], ($i + 1)))
                break
            }
        }
    }

    foreach ($problem in $problems) { Write-Output $problem }
    if ($problems.Count -gt 0) { exit 1 }
    exit 0
} catch {
    # Never echo file contents or an exception that might contain a secret.
    Write-Output 'Repository validation could not complete; check the root and file access.'
    exit 1
}
