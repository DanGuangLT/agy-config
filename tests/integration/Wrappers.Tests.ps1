BeforeAll {
    $script:root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:oldHome = $env:AGYCFG_HOME
    # Run a wrapper script as a real process, exactly as the SessionStart hook does (no -RepoRoot).
    function Invoke-Wrapper([string]$Name) {
        $env:AGYCFG_HOME = Join-Path $TestDrive ('h' + [guid]::NewGuid().ToString('N'))
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'powershell'
        $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $script:root ('scripts\' + $Name)) + '"'
        $psi.UseShellExecute = $false
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.Environment['AGYCFG_HOME'] = $env:AGYCFG_HOME
        $p = [System.Diagnostics.Process]::Start($psi)
        $p.StandardInput.Close()
        $out = $p.StandardOutput.ReadToEndAsync(); $err = $p.StandardError.ReadToEndAsync()
        [void]$p.WaitForExit(120000)
        $logs = (Get-ChildItem (Join-Path $env:AGYCFG_HOME '.agy-config-state\logs') -File -ErrorAction SilentlyContinue | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"
        @{ ExitCode = $p.ExitCode; StdErr = $err.Result + $out.Result; Logs = $logs }
    }
}
AfterAll { $env:AGYCFG_HOME = $script:oldHome }

Describe 'wrapper scripts run without -RepoRoot (as the hook calls them)' {
    It '<Name> reaches its main function' -TestCases @(
        @{ Name = 'maintain.ps1'; Expect = 'no profile configured' },
        @{ Name = 'apply.ps1'; Expect = 'no profile configured' },
        @{ Name = 'sync.ps1'; Expect = 'no profile configured' },
        @{ Name = 'update.ps1'; Expect = 'not an owner machine' }
    ) {
        param($Name, $Expect)
        $r = Invoke-Wrapper $Name
        $r.StdErr | Should -Not -Match 'Cannot bind argument'
        $r.Logs | Should -Match $Expect
    }
}
