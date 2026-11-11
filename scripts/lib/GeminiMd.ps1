# Assemble ~/.gemini/GEMINI.md from core + profile text, and split it back. ASCII-only file.

$script:GmCoreStart = '<!-- agy-config:core:start -->'
$script:GmCoreEnd = '<!-- agy-config:core:end -->'
$script:GmProfileStart = '<!-- agy-config:profile:start -->'
$script:GmProfileEnd = '<!-- agy-config:profile:end -->'
$script:GmMapPrefix = 'Project map tool: '

function Build-GeminiMd([string]$CoreText, [string]$ProfileText, [string]$ProjectMapTool) {
    $core = ($CoreText -replace "`r`n", "`n").TrimEnd("`n")
    $prof = ($ProfileText -replace "`r`n", "`n").TrimEnd("`n")
    $map = ''
    if ($ProjectMapTool -and $ProjectMapTool -ne 'none') { $map = $script:GmMapPrefix + $ProjectMapTool + "`n`n" }
    return $script:GmCoreStart + "`n" + $core + "`n" + $script:GmCoreEnd + "`n" +
        $script:GmProfileStart + "`n" + $map + $prof + "`n" + $script:GmProfileEnd + "`n"
}

function Split-GeminiMd([string]$Text) {
    $t = $Text -replace "`r`n", "`n"
    $a = $t.IndexOf($script:GmCoreStart)
    $b = $t.IndexOf($script:GmCoreEnd)
    $c = $t.IndexOf($script:GmProfileStart)
    $d = $t.IndexOf($script:GmProfileEnd)
    $valid = ($a -ge 0) -and ($a -lt $b) -and ($b -lt $c) -and ($c -lt $d)
    if (-not $valid) { return @{ Core = $null; Profile = $t } }

    $core = $t.Substring($a + $script:GmCoreStart.Length, $b - $a - $script:GmCoreStart.Length).Trim("`n")
    $prof = $t.Substring($c + $script:GmProfileStart.Length, $d - $c - $script:GmProfileStart.Length).Trim("`n")
    if ($prof.StartsWith($script:GmMapPrefix)) {
        $nl = $prof.IndexOf("`n")
        $prof = if ($nl -lt 0) { '' } else { $prof.Substring($nl + 1).TrimStart("`n") }
    }
    $outside = @(
        $t.Substring(0, $a),
        $t.Substring($b + $script:GmCoreEnd.Length, $c - $b - $script:GmCoreEnd.Length),
        $t.Substring($d + $script:GmProfileEnd.Length)
    ) | ForEach-Object { $_.Trim("`n") } | Where-Object { $_ -ne '' }
    foreach ($o in $outside) {
        $prof = if ($prof -eq '') { $o } else { $prof + "`n`n" + $o }
    }
    return @{ Core = $core; Profile = $prof }
}
