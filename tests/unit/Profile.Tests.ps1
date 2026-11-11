BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\scripts\lib\All.ps1')
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    function New-FakeRepo {
        $r = Join-Path $TestDrive ('repo' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path (Join-Path $r 'profiles'), (Join-Path $r 'scripts') | Out-Null
        Copy-Item -Recurse (Join-Path $script:repoRoot 'profiles\_template') (Join-Path $r 'profiles\_template')
        Copy-Item -Recurse (Join-Path $script:repoRoot 'scripts\i18n') (Join-Path $r 'scripts\i18n')
        $r
    }
}

Describe 'Get-Profile' {
    It 'applies defaults' {
        $r = New-FakeRepo
        $dir = Join-Path $r 'profiles\bob'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Write-TextFile (Join-Path $dir 'profile.json') '{"name":"bob","language":"en"}'
        $p = Get-Profile $r 'bob'
        $p.projectMap.tool | Should -Be 'graphify'
        $p.sync.debounceMinutes | Should -Be 10
        $p.update.day | Should -Be 'Sunday'
        @($p.Sources).Count | Should -Be 0
        $p.Lock.Count | Should -Be 0
        @($p.Permissions).Count | Should -Be 0
        $p.GeminiProfileText | Should -Be ''
    }
    It 'keeps values that are set' {
        $p = Get-Profile $script:repoRoot 'lianharman'
        $p.language | Should -Be 'vi'
        $p.GeminiProfileText | Should -Match 'Always reply to the user in Vietnamese'
    }
}

Describe 'New-ProfileFromTemplate' {
    It 'writes language rule' {
        $r = New-FakeRepo
        $path = New-ProfileFromTemplate $r 'an' 'vi' 'none'
        (Read-TextFile (Join-Path $path 'GEMINI.profile.md')) | Should -Match 'Always reply to the user in Vietnamese'
        Test-Path (Join-Path $r 'scripts\i18n\vi.json') | Should -BeFalse
        $p = Get-Profile $r 'an'
        $p.name | Should -Be 'an'
        $p.language | Should -Be 'vi'
        $p.projectMap.tool | Should -Be 'none'
    }
    It 'names any language in English' {
        $r = New-FakeRepo
        $path = New-ProfileFromTemplate $r 'kim' 'ko' 'graphify'
        (Read-TextFile (Join-Path $path 'GEMINI.profile.md')) | Should -Match 'Always reply to the user in Korean'
        $path2 = New-ProfileFromTemplate $r 'zz' 'not-a-language' 'graphify'
        (Read-TextFile (Join-Path $path2 'GEMINI.profile.md')) | Should -Match 'Always reply to the user in not-a-language'
    }
    It 'refuses to overwrite an existing profile' {
        $r = New-FakeRepo
        New-ProfileFromTemplate $r 'dup' 'en' 'graphify' | Out-Null
        { New-ProfileFromTemplate $r 'dup' 'en' 'graphify' } | Should -Throw
    }
}
