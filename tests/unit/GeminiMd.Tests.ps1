BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\scripts\lib\All.ps1')
    $script:core = "# How to work`n`nCore rule."
    $script:vi = '## Ng' + [char]0x00F4 + 'n ng' + [char]0x1EEF + "`n`nTr" + [char]0x1EA3 + ' l' + [char]0x1EDD + 'i b' + [char]0x1EB1 + 'ng ti' + [char]0x1EBF + 'ng Vi' + [char]0x1EC7 + 't.'
}

Describe 'Build-GeminiMd' {
    It 'places markers in order' {
        $t = Build-GeminiMd $script:core 'Profile rule.' 'graphify'
        $a = $t.IndexOf('<!-- agy-config:core:start -->')
        $b = $t.IndexOf('<!-- agy-config:core:end -->')
        $c = $t.IndexOf('<!-- agy-config:profile:start -->')
        $d = $t.IndexOf('<!-- agy-config:profile:end -->')
        $a | Should -Be 0
        ($a -lt $b -and $b -lt $c -and $c -lt $d) | Should -BeTrue
    }
    It 'writes the project map line at the top of the profile region' {
        $t = Build-GeminiMd $script:core 'Profile rule.' 'graphify'
        $t | Should -Match '<!-- agy-config:profile:start -->\nProject map tool: graphify\n\nProfile rule\.'
    }
    It 'omits project map line for none' {
        $t = Build-GeminiMd $script:core 'Profile rule.' 'none'
        $t | Should -Not -Match 'Project map tool'
    }
}

Describe 'Split-GeminiMd' {
    It 'inverts Build-GeminiMd' {
        $s = Split-GeminiMd (Build-GeminiMd $script:core 'Profile rule.' 'graphify')
        $s.Core | Should -BeExactly $script:core
        $s.Profile | Should -BeExactly 'Profile rule.'
    }
    It 'round-trips Vietnamese text' {
        $p = Join-Path $TestDrive 'GEMINI.md'
        Write-TextFile $p (Build-GeminiMd $script:core $script:vi 'graphify')
        $s = Split-GeminiMd (Read-TextFile $p)
        $s.Profile | Should -BeExactly $script:vi
    }
    It 'accepts CRLF line endings' {
        $t = (Build-GeminiMd $script:core 'Profile rule.' 'graphify') -replace "`n", "`r`n"
        $s = Split-GeminiMd $t
        $s.Core | Should -BeExactly $script:core
        $s.Profile | Should -BeExactly 'Profile rule.'
    }
    It 'appends text outside markers to profile' {
        $t = (Build-GeminiMd $script:core 'Profile rule.' 'graphify') + "`nAdded by hand."
        $s = Split-GeminiMd $t
        $s.Core | Should -BeExactly $script:core
        $s.Profile | Should -BeExactly "Profile rule.`n`nAdded by hand."
    }
    It 'keeps all text when markers are missing' {
        $original = "# My rules`n`nDo things."
        $s = Split-GeminiMd $original
        $s.Core | Should -BeNullOrEmpty
        $s.Profile | Should -BeExactly $original
    }
    It 'keeps all text when markers are out of order' {
        $original = "<!-- agy-config:profile:start -->`nA`n<!-- agy-config:core:start -->`nB"
        $s = Split-GeminiMd $original
        $s.Core | Should -BeNullOrEmpty
        $s.Profile | Should -BeExactly $original
    }
}
