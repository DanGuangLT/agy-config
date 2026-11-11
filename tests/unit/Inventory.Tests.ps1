BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\scripts\lib\All.ps1')
    $script:lock = @{
        version = 3
        skills  = @{
            'tdd'         = @{ source = 'mattpocock/skills'; sourceType = 'github'; sourceUrl = 'https://github.com/mattpocock/skills.git'; skillPath = 'skills/engineering/tdd/SKILL.md' }
            'grilling'    = @{ source = 'mattpocock/skills'; sourceType = 'github'; sourceUrl = 'https://github.com/mattpocock/skills.git'; skillPath = 'skills/productivity/grilling/SKILL.md' }
            'find-skills' = @{ source = 'vercel-labs/skills'; sourceType = 'github'; sourceUrl = 'https://github.com/vercel-labs/skills.git'; skillPath = 'skills/find-skills/SKILL.md' }
        }
    }
    $script:sources = @(
        @{ id = 'mattpocock-skills'; type = 'github-skills'; repo = 'https://github.com/mattpocock/skills'; skills = @(@{ name = 'tdd'; path = 'skills/engineering/tdd' }); provides = @('tdd') },
        @{ id = 'graphify'; type = 'pip-tool'; package = 'graphifyy'; provides = @('graphify') },
        @{ id = 'design'; type = 'packaged-plugin'; plugin = 'design'; provides = @('design') }
    )
}

Describe 'ConvertFrom-SkillLock' {
    It 'groups mattpocock skills' {
        $entries = @(ConvertFrom-SkillLock $script:lock @('mattpocock/skills'))
        $entries.Count | Should -Be 1
        $e = $entries[0]
        $e.id | Should -Be 'mattpocock-skills'
        $e.type | Should -Be 'github-skills'
        $e.repo | Should -Be 'https://github.com/mattpocock/skills'
        @($e.skills | ForEach-Object { $_.name }) | Should -Be @('grilling', 'tdd')
        ($e.skills | Where-Object { $_.name -eq 'tdd' }).path | Should -Be 'skills/engineering/tdd'
        $e.provides | Should -Be @('grilling', 'tdd')
    }
    It 'returns every source when no filter is given' {
        @(ConvertFrom-SkillLock $script:lock $null).Count | Should -Be 2
    }
}

Describe 'Get-Classification' {
    It 'classifies graphify as sourced via provides' {
        $inv = @{ Skills = @('graphify', 'tdd'); Plugins = @(@{ name = 'design' }, @{ name = 'agy-self-config' }) }
        $c = Get-Classification $inv $script:sources @{ ownSkills = @(); ownPlugins = @(); ignored = @() } @('agy-self-config')
        $c.Sourced | Should -Be @('agy-self-config', 'design', 'graphify', 'tdd')
        @($c.Unknown).Count | Should -Be 0
    }
    It 'classifies unlisted skill as unknown' {
        $inv = @{ Skills = @('tdd', 'mystery'); Plugins = @() }
        $c = Get-Classification $inv $script:sources @{ ownSkills = @(); ownPlugins = @(); ignored = @() } @()
        $c.Unknown | Should -Be @('mystery')
    }
    It 'own skill listed in profile is own; ignored is ignored' {
        $inv = @{ Skills = @('mine', 'skipme'); Plugins = @(@{ name = 'myplugin' }) }
        $c = Get-Classification $inv $script:sources @{ ownSkills = @('mine'); ownPlugins = @('myplugin'); ignored = @('skipme') } @()
        $c.Own | Should -Be @('mine', 'myplugin')
        $c.Ignored | Should -Be @('skipme')
        @($c.Unknown).Count | Should -Be 0
    }
}

Describe 'Find-Secrets' {
    BeforeAll {
        $script:fakeToken = 'ghp_' + ('A1b2' * 8)
        $script:dir = Join-Path $TestDrive 'scan'
        New-Item -ItemType Directory -Force -Path $script:dir | Out-Null
    }
    It 'flags ghp token and user path' {
        $f = Join-Path $script:dir 'a.json'
        Write-TextFile $f ("{`n  `"token`": `"$script:fakeToken`",`n  `"dir`": `"C:\\Users\\somebody\\x`"`n}")
        $hits = @(Find-Secrets @($f))
        @($hits | ForEach-Object { $_.Rule }) | Should -Contain 'github-token'
        @($hits | ForEach-Object { $_.Rule }) | Should -Contain 'user-path'
        ($hits | Where-Object { $_.Rule -eq 'github-token' }).Line | Should -Be 2
    }
    It 'flags emails and private keys' {
        $f = Join-Path $script:dir 'b.md'
        Write-TextFile $f ("contact: someone@" + "gmail.com`n-----BEGIN RSA PRIVATE KEY-----")
        $rules = @(Find-Secrets @($f) | ForEach-Object { $_.Rule })
        $rules | Should -Contain 'email'
        $rules | Should -Contain 'private-key'
    }
    It 'allows placeholders and documentation forms' {
        $f = Join-Path $script:dir 'c.md'
        Write-TextFile $f ("env: `${GH_GITHUB_TOKEN}`npassword = `${DB_PASSWORD}`nC:\Users\<name>\x`nbot@users.noreply.github.com`nme@example.com")
        @(Find-Secrets @($f)).Count | Should -Be 0
    }
    It 'respects the allowed email list' {
        $f = Join-Path $script:dir 'd.md'
        Write-TextFile $f ('author: jesse@' + 'fsck.com')
        @(Find-Secrets @($f) -AllowedEmails @('jesse@fsck.com')).Count | Should -Be 0
    }
}
