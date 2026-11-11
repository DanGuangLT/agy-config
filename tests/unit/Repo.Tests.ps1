BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\scripts\lib\All.ps1')
}

Describe 'Update-ConfigRepo' {
    It 'treats a remote without main as nothing to pull' {
        $origin = Join-Path $TestDrive 'empty.git'
        $clone = Join-Path $TestDrive 'clone'
        & git init -q --bare $origin
        & git init -q -b main $clone
        & git -C $clone remote add origin $origin
        $r = Update-ConfigRepo $clone
        $r.Ok | Should -BeTrue
    }
    It 'does not abort a rebase it did not start' {
        $repo = Join-Path $TestDrive 'plain'
        New-Item -ItemType Directory -Force -Path (Join-Path $repo '.git') | Out-Null
        Mock Invoke-Git { "0123456789abcdef0123456789abcdef01234567`trefs/heads/main" } -ParameterFilter { $GitArgs[0] -eq 'ls-remote' }
        Mock Invoke-Git { throw 'index.lock exists' } -ParameterFilter { $GitArgs[0] -eq 'pull' }
        Mock Invoke-Git { '' } -ParameterFilter { $GitArgs[0] -eq 'rev-parse' }
        Mock Invoke-External { @{ ExitCode = 0; StdOut = ''; StdErr = '' } }
        (Update-ConfigRepo $repo).Ok | Should -BeFalse
        Should -Invoke Invoke-External -Times 0 -Exactly -ParameterFilter { ($Arguments -join ' ') -eq 'rebase --abort' }
    }
}

Describe 'Test-PushAccess' {
    It 'works on a clone of an empty repository (no commit yet)' {
        $origin = Join-Path $TestDrive 'push-empty.git'
        $clone = Join-Path $TestDrive 'push-empty-clone'
        & git init -q --bare $origin
        (Invoke-External 'git' @('clone', '-q', $origin, $clone) $TestDrive).ExitCode | Should -Be 0
        Test-PushAccess $clone | Should -BeTrue
    }
    It 'is false when origin cannot be reached' {
        $clone = Join-Path $TestDrive 'push-nowhere'
        & git init -q -b main $clone
        & git -C $clone remote add origin (Join-Path $TestDrive 'does-not-exist.git')
        Test-PushAccess $clone | Should -BeFalse
    }
}

Describe 'Get-RepoOwnerName' {
    It 'takes the owner from https and ssh URLs as a profile name' {
        Get-RepoOwnerName 'https://github.com/Alice-B/agy-backup.git' | Should -Be 'alice-b'
        Get-RepoOwnerName 'git@github.com:DanGuangLT/backup' | Should -Be 'danguanglt'
        Get-RepoOwnerName 'https://github.com/Some.User/x/' | Should -Be 'some-user'
    }
    It 'falls back to me' {
        Get-RepoOwnerName 'backup' | Should -Be 'me'
        Get-RepoOwnerName '' | Should -Be 'me'
    }
}

Describe 'Initialize-PersonalRepo' {
    It 'clones an empty repository onto main with a commit identity' {
        $origin = Join-Path $TestDrive 'personal-empty.git'
        & git init -q --bare $origin
        $dir = Join-Path $TestDrive 'home1\.agy-config-personal'
        $r = Initialize-PersonalRepo $origin $dir
        $r.Ok | Should -BeTrue
        $r.HasProfile | Should -BeFalse
        (& git -C $dir symbolic-ref --short HEAD) | Should -Be 'main'
        (& git -C $dir config user.email) | Should -Not -BeNullOrEmpty
    }
    It 'reports a saved profile and reuses an existing clone of the same URL' {
        $origin = Join-Path $TestDrive 'personal-full.git'
        $seed = Join-Path $TestDrive 'personal-seed'
        & git init -q --bare -b main $origin
        & git init -q -b main $seed
        Set-Content -Path (Join-Path $seed 'profile.json') -Value '{ "name": "alice" }'
        & git -C $seed add -A
        & git -C $seed -c user.name=t -c user.email=t@example.invalid commit -q -m seed
        & git -C $seed remote add origin $origin
        (Invoke-External 'git' @('push', '-q', 'origin', 'main') $seed).ExitCode | Should -Be 0
        $dir = Join-Path $TestDrive 'home2\.agy-config-personal'
        (Initialize-PersonalRepo $origin $dir).HasProfile | Should -BeTrue
        $again = Initialize-PersonalRepo ($origin + '/') $dir
        $again.Ok | Should -BeTrue
        $again.HasProfile | Should -BeTrue
    }
    It 'refuses a folder that holds something else' {
        $origin = Join-Path $TestDrive 'personal-other.git'
        & git init -q --bare $origin
        $dir = Join-Path $TestDrive 'home3\.agy-config-personal'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Set-Content -Path (Join-Path $dir 'notes.txt') -Value 'mine'
        $r = Initialize-PersonalRepo $origin $dir
        $r.Ok | Should -BeFalse
        $r.Error | Should -Be 'folder-in-use'
    }
    It 'fails with git''s message when the URL cannot be cloned' {
        $r = Initialize-PersonalRepo (Join-Path $TestDrive 'missing.git') (Join-Path $TestDrive 'home4\.agy-config-personal')
        $r.Ok | Should -BeFalse
        $r.Error | Should -Not -BeNullOrEmpty
    }
}
