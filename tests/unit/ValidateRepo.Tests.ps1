BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\scripts\lib\All.ps1')
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:validator = Join-Path $script:repoRoot 'tests\Validate-Repo.ps1'

    function Invoke-RepoValidation([string]$Root) {
        Invoke-External 'powershell' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script:validator, '-Root', $Root)
    }
}

Describe 'Validate-Repo' {
    BeforeEach {
        $script:fixture = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        Write-TextFile (Join-Path $script:fixture 'core\sources.json') '[]'
        Write-TextFile (Join-Path $script:fixture 'THIRD_PARTY.md') '# Third-party sources'
    }

    It 'flags invalid json' {
        Write-TextFile (Join-Path $script:fixture 'broken.json') '{invalid'
        $r = Invoke-RepoValidation $script:fixture
        $r.ExitCode | Should -Be 1
        $r.StdOut | Should -Match 'broken\.json: invalid JSON'
    }

    It 'flags SKILL.md without description' {
        Write-TextFile (Join-Path $script:fixture 'skills\sample\SKILL.md') "---`nname: sample`n---`nBody"
        $r = Invoke-RepoValidation $script:fixture
        $r.ExitCode | Should -Be 1
        $r.StdOut | Should -Match 'SKILL\.md:.*description'
    }

    It 'flags source missing from THIRD_PARTY' {
        Write-JsonFile (Join-Path $script:fixture 'core\sources.json') @(@{
            id = 'sample'; type = 'github-skills'; repo = 'https://github.com/example/sample'; skills = @()
        })
        $r = Invoke-RepoValidation $script:fixture
        $r.ExitCode | Should -Be 1
        $r.StdOut | Should -Match 'sources\.json:.*THIRD_PARTY\.md.*https://github.com/example/sample'
    }

    It 'checks profile sources and pip packages in THIRD_PARTY' {
        Write-JsonFile (Join-Path $script:fixture 'profiles\sample\sources.json') @(@{
            id = 'map'; type = 'pip-tool'; package = 'sample-map-tool'
        })
        $r = Invoke-RepoValidation $script:fixture
        $r.ExitCode | Should -Be 1
        $r.StdOut | Should -Match 'profiles/sample/sources\.json:.*THIRD_PARTY\.md.*sample-map-tool'
        Write-TextFile (Join-Path $script:fixture 'THIRD_PARTY.md') 'https://pypi.org/project/sample-map-tool/'
        (Invoke-RepoValidation $script:fixture).ExitCode | Should -Be 0
    }

    It 'flags non-ASCII ps1' {
        Write-TextFile (Join-Path $script:fixture 'script.ps1') ('# ' + [char]0x1EBF)
        $r = Invoke-RepoValidation $script:fixture
        $r.ExitCode | Should -Be 1
        $r.StdOut | Should -Match 'script\.ps1:.*ASCII'
    }

    It 'flags plugin.json without version' {
        Write-TextFile (Join-Path $script:fixture 'plugin.json') '{"name":"sample"}'
        $r = Invoke-RepoValidation $script:fixture
        $r.ExitCode | Should -Be 1
        $r.StdOut | Should -Match 'plugin\.json:.*version'
    }

    It 'reports secrets without printing their values' {
        $token = 'ghp_' + ('Ab12' * 8)
        Write-TextFile (Join-Path $script:fixture 'config.txt') $token
        $r = Invoke-RepoValidation $script:fixture
        $r.ExitCode | Should -Be 1
        $r.StdOut | Should -Match 'config\.txt:1:.*github-token'
        $r.StdOut | Should -Not -Match $token
    }

    It 'skips tests and .superpowers only for secret and personal-data checks' {
        $fake = ('ghp_' + ('Ab12' * 8)) + '`nC:\Users\sample\file`nsomeone@sample.invalid'
        Write-TextFile (Join-Path $script:fixture 'tests\fixtures\fake.txt') $fake
        Write-TextFile (Join-Path $script:fixture '.superpowers\ledger.md') $fake
        (Invoke-RepoValidation $script:fixture).ExitCode | Should -Be 0
        Write-TextFile (Join-Path $script:fixture 'tests\broken.json') '{invalid'
        Write-TextFile (Join-Path $script:fixture '.superpowers\script.ps1') ('# ' + [char]0x1EBF)
        $r = Invoke-RepoValidation $script:fixture
        $r.ExitCode | Should -Be 1
        $r.StdOut | Should -Match 'tests/broken\.json: invalid JSON'
        $r.StdOut | Should -Match '\.superpowers/script\.ps1:.*ASCII'
    }

    It 'flags personal data outside the excluded directories' {
        Write-TextFile (Join-Path $script:fixture 'personal.txt') "C:\Users\sample\file`nsomeone@sample.invalid"
        $r = Invoke-RepoValidation $script:fixture
        $r.ExitCode | Should -Be 1
        $r.StdOut | Should -Match 'user-path'
        $r.StdOut | Should -Match 'email'
    }

    It 'flags files over 1 MB including test fixtures' {
        Write-TextFile (Join-Path $script:fixture 'tests\large.txt') ('x' * (1MB + 1))
        $r = Invoke-RepoValidation $script:fixture
        $r.ExitCode | Should -Be 1
        $r.StdOut | Should -Match 'tests/large\.txt:.*1 MB'
    }

    It 'reports multiple problems as separate lines' {
        Write-TextFile (Join-Path $script:fixture 'bad.json') '{invalid'
        Write-TextFile (Join-Path $script:fixture 'bad.ps1') ('# ' + [char]0x1EBF)
        $r = Invoke-RepoValidation $script:fixture
        $r.ExitCode | Should -Be 1
        @($r.StdOut.Trim() -split '\r?\n').Count | Should -Be 2
    }

    It 'checks nested .agy-tmp directories' {
        Write-TextFile (Join-Path $script:fixture 'tests\.agy-tmp\broken.json') '{invalid'
        $r = Invoke-RepoValidation $script:fixture
        $r.ExitCode | Should -Be 1
        $r.StdOut | Should -Match 'tests/\.agy-tmp/broken\.json: invalid JSON'
    }

    It 'checks tracked files in ignored scratch directories' {
        Write-TextFile (Join-Path $script:fixture '.gitignore') '.agy-tmp/'
        Write-TextFile (Join-Path $script:fixture '.agy-tmp\script.ps1') ('# ' + [char]0x1EBF)
        Write-TextFile (Join-Path $script:fixture '.agy-tmp\token.txt') ('ghp_' + ('Ab12' * 8))
        $git = Resolve-Tool git
        (Invoke-External $git @('init', '--quiet') $script:fixture).ExitCode | Should -Be 0
        (Invoke-External $git @('add', '-f', '--', '.agy-tmp/script.ps1', '.agy-tmp/token.txt') $script:fixture).ExitCode | Should -Be 0
        $r = Invoke-RepoValidation $script:fixture
        $r.ExitCode | Should -Be 1
        $r.StdOut | Should -Match '\.agy-tmp/script\.ps1:.*ASCII'
        $r.StdOut | Should -Match '\.agy-tmp/token\.txt:1:.*github-token'
    }

    It 'passes valid metadata and documented sources' {
        Write-TextFile (Join-Path $script:fixture 'skills\sample\SKILL.md') "---`nname: sample`ndescription: A sample skill.`n---`nBody"
        Write-JsonFile (Join-Path $script:fixture 'plugin.json') @{ name = 'sample'; version = '1.0.0' }
        Write-JsonFile (Join-Path $script:fixture 'core\sources.json') @(@{
            id = 'sample'; type = 'github-skills'; repo = 'https://github.com/example/sample'
        }, @{ id = 'map'; type = 'pip-tool'; package = 'sample-map-tool' })
        Write-TextFile (Join-Path $script:fixture 'THIRD_PARTY.md') "https://github.com/example/sample`nhttps://pypi.org/project/sample-map-tool/"
        $r = Invoke-RepoValidation $script:fixture
        $r.ExitCode | Should -Be 0
        $r.StdErr | Should -BeNullOrEmpty
    }

    It 'passes on the real repo' {
        $r = Invoke-RepoValidation $script:repoRoot
        $r.StdOut | Should -BeNullOrEmpty
        $r.StdErr | Should -BeNullOrEmpty
        $r.ExitCode | Should -Be 0
    }

    It 'defaults to the real repo when Root is omitted' {
        $r = Invoke-External 'powershell' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script:validator)
        $r.StdOut | Should -BeNullOrEmpty
        $r.StdErr | Should -BeNullOrEmpty
        $r.ExitCode | Should -Be 0
    }
}
