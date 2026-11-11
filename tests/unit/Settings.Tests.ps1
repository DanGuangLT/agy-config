BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\scripts\lib\All.ps1')
    function New-Settings([string]$Json) {
        $p = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.json')
        Write-TextFile $p $Json
        $p
    }
}

Describe 'Merge-Permissions' {
    It 'adds missing permissions and keeps other keys' {
        $p = New-Settings '{"model":"Gemini 4 Argon (Medium)","trustedWorkspaces":["D:\\Coding\\A","C:\\Users\\x"],"permissions":{"allow":["command(git status)"]},"futureKey":{"a":1}}'
        $added = Merge-Permissions $p @('command(git status)', 'command(git diff)')
        @($added) | Should -Be @('command(git diff)')
        $s = Read-JsonFile $p @{}
        $s.model | Should -Be 'Gemini 4 Argon (Medium)'
        $s.trustedWorkspaces | Should -Be @('D:\Coding\A', 'C:\Users\x')
        $s.futureKey.a | Should -Be 1
        $s.permissions.allow | Should -Be @('command(git status)', 'command(git diff)')
    }
    It 'does not duplicate' {
        $p = New-Settings '{"permissions":{"allow":["command(git status)"]}}'
        Merge-Permissions $p @('command(git status)') | Out-Null
        @((Read-JsonFile $p @{}).permissions.allow).Count | Should -Be 1
    }
    It 'creates permissions block when absent' {
        $p = New-Settings '{"model":"m"}'
        Merge-Permissions $p @('command(git status)') | Out-Null
        (Read-JsonFile $p @{}).permissions.allow | Should -Be @('command(git status)')
    }
    It 'creates the settings file when missing' {
        $p = Join-Path $TestDrive 'missing\settings.json'
        Merge-Permissions $p @('command(git status)') | Out-Null
        (Read-JsonFile $p @{}).permissions.allow | Should -Be @('command(git status)')
    }
}

Describe 'Get-MachinePermissions / Remove-Permissions' {
    It 'reads and removes entries' {
        $p = New-Settings '{"permissions":{"allow":["a","b","c"]}}'
        Get-MachinePermissions $p | Should -Be @('a', 'b', 'c')
        Remove-Permissions $p @('b')
        Get-MachinePermissions $p | Should -Be @('a', 'c')
    }
    It 'returns empty when no settings' {
        @(Get-MachinePermissions (Join-Path $TestDrive 'none.json')).Count | Should -Be 0
    }
}

Describe 'MCP' {
    It 'protects env secrets' {
        $cfg = @{ mcpServers = @{ gh = @{ command = 'npx'; env = @{ GITHUB_TOKEN = 'ghp_x' } } } }
        $r = Protect-McpConfig $cfg
        $r.Config.mcpServers.gh.env.GITHUB_TOKEN | Should -Be '${GH_GITHUB_TOKEN}'
        $r.Config.mcpServers.gh.command | Should -Be 'npx'
        $r.Variables | Should -Contain 'GH_GITHUB_TOKEN'
    }
    It 'protects headers and keeps existing placeholders' {
        $cfg = @{ mcpServers = @{ 'my-api' = @{ url = 'https://x'; headers = @{ Authorization = 'Bearer abc' }; env = @{ K = '${ALREADY}' } } } }
        $r = Protect-McpConfig $cfg
        $r.Config.mcpServers['my-api'].headers.Authorization | Should -Be '${MY_API_AUTHORIZATION}'
        $r.Config.mcpServers['my-api'].env.K | Should -Be '${ALREADY}'
    }
    It 'does not modify the input object' {
        $cfg = @{ mcpServers = @{ gh = @{ env = @{ T = 'secret' } } } }
        Protect-McpConfig $cfg | Out-Null
        $cfg.mcpServers.gh.env.T | Should -Be 'secret'
    }
    It 'expands from environment and reports missing' {
        $env:AGYCFG_TEST_TOKEN = 'tok123'
        try {
            $cfg = @{ mcpServers = @{ gh = @{ env = @{ A = '${AGYCFG_TEST_TOKEN}'; B = '${AGYCFG_NOT_SET_XYZ}' } } } }
            $r = Expand-McpConfig $cfg
            $r.Config.mcpServers.gh.env.A | Should -Be 'tok123'
            $r.Config.mcpServers.gh.env.B | Should -Be '${AGYCFG_NOT_SET_XYZ}'
            $r.Missing | Should -Be @('AGYCFG_NOT_SET_XYZ')
        } finally { Remove-Item Env:\AGYCFG_TEST_TOKEN -ErrorAction SilentlyContinue }
    }
}
