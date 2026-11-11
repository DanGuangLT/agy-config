BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\scripts\lib\All.ps1')
}

Describe 'Update-ConfigRepo' {
    It 'does not abort a rebase it did not start' {
        $repo = Join-Path $TestDrive 'plain'
        New-Item -ItemType Directory -Force -Path (Join-Path $repo '.git') | Out-Null
        Mock Invoke-Git { throw 'index.lock exists' } -ParameterFilter { $GitArgs[0] -eq 'pull' }
        Mock Invoke-Git { '' } -ParameterFilter { $GitArgs[0] -eq 'rev-parse' }
        Mock Invoke-External { @{ ExitCode = 0; StdOut = ''; StdErr = '' } }
        (Update-ConfigRepo $repo).Ok | Should -BeFalse
        Should -Invoke Invoke-External -Times 0 -Exactly -ParameterFilter { ($Arguments -join ' ') -eq 'rebase --abort' }
    }
}
