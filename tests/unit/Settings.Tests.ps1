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
    It 'protects token flag <Flag> in separate and equals args' -TestCases @(
        @{ Flag = '--token'; Name = 'TOKEN' }, @{ Flag = '--ACCESS-TOKEN'; Name = 'ACCESS_TOKEN' },
        @{ Flag = '--api-key'; Name = 'API_KEY' }, @{ Flag = '--apikey'; Name = 'APIKEY' },
        @{ Flag = '--key'; Name = 'KEY' }, @{ Flag = '--secret'; Name = 'SECRET' },
        @{ Flag = '--password'; Name = 'PASSWORD' }, @{ Flag = '-K'; Name = 'K' }
    ) {
        param($Flag, $Name)
        $secret = 's' + ('a' * 24)
        $cfg = @{ mcpServers = @{ 'my-api' = @{ args = @($Flag, $secret, ($Flag + '=' + $secret), '--port', '8080') } } }
        $r = Protect-McpConfig $cfg
        $placeholder = '${MY_API_' + $Name + '}'
        $r.Config.mcpServers['my-api'].args | Should -Be @($Flag, $placeholder, ($Flag + '=' + $placeholder), '--port', '8080')
        $r.Variables | Should -Contain ('MY_API_' + $Name)
        $cfg.mcpServers['my-api'].args[1] | Should -Be $secret
    }
    It 'protects bearer and authorization values embedded in args' {
        $secret = 's' + ('b' * 24)
        $cfg = @{ mcpServers = @{ 'my-api' = @{ args = @(('header=Bearer ' + $secret), ('Authorization: ' + $secret), ('Authorization: Bearer ' + $secret)) } } }
        $r = Protect-McpConfig $cfg
        $r.Config.mcpServers['my-api'].args | Should -Be @('header=Bearer ${MY_API_BEARER}', 'Authorization: ${MY_API_AUTHORIZATION}', 'Authorization: Bearer ${MY_API_AUTHORIZATION}')
        $r.Variables | Should -Contain 'MY_API_BEARER'
        $r.Variables | Should -Contain 'MY_API_AUTHORIZATION'
    }
    It 'protects secret query values in urls serverUrls and url args' {
        $secret = 's' + ('c' * 24)
        $url = 'https://example.com/mcp?api-key=' + $secret + '&access_token=' + $secret + '&client_secret=' + $secret + '&password=' + $secret + '&auth=' + $secret + '&page=2#section'
        $safe = 'https://example.com/mcp?api-key=${MY_API_API_KEY}&access_token=${MY_API_ACCESS_TOKEN}&client_secret=${MY_API_CLIENT_SECRET}&password=${MY_API_PASSWORD}&auth=${MY_API_AUTH}&page=2#section'
        $r = Protect-McpConfig @{ mcpServers = @{ 'my-api' = @{ url = $url; serverUrl = $url; args = @($url) } } }
        $r.Config.mcpServers['my-api'].url | Should -Be $safe
        $r.Config.mcpServers['my-api'].serverUrl | Should -Be $safe
        $r.Config.mcpServers['my-api'].args | Should -Be @($safe)
        @($r.Variables | Sort-Object -Unique) | Should -Be @('MY_API_ACCESS_TOKEN', 'MY_API_API_KEY', 'MY_API_AUTH', 'MY_API_CLIENT_SECRET', 'MY_API_PASSWORD')
        $again = Protect-McpConfig $r.Config
        $again.Config.mcpServers['my-api'].url | Should -Be $safe
        @($again.Variables).Count | Should -Be 0
    }
    It 'expands placeholders inside args urls and serverUrls and reports missing' {
        $env:AGYCFG_TEST_TOKEN = 's' + ('d' * 24)
        try {
            $r = Expand-McpConfig @{ mcpServers = @{ api = @{
                args = @('--token=${AGYCFG_TEST_TOKEN}', 'Bearer ${AGYCFG_TEST_TOKEN}', '${AGYCFG_NOT_SET_XYZ}')
                url = 'https://example.com/?key=${AGYCFG_TEST_TOKEN}'
                serverUrl = 'https://example.com/?auth=${AGYCFG_NOT_SET_XYZ}'
            } } }
            $r.Config.mcpServers.api.args | Should -Be @(('--token=' + $env:AGYCFG_TEST_TOKEN), ('Bearer ' + $env:AGYCFG_TEST_TOKEN), '${AGYCFG_NOT_SET_XYZ}')
            $r.Config.mcpServers.api.url | Should -Be ('https://example.com/?key=' + $env:AGYCFG_TEST_TOKEN)
            $r.Config.mcpServers.api.serverUrl | Should -Be 'https://example.com/?auth=${AGYCFG_NOT_SET_XYZ}'
            $r.Missing | Should -Be @('AGYCFG_NOT_SET_XYZ')
        } finally { Remove-Item Env:\AGYCFG_TEST_TOKEN -ErrorAction SilentlyContinue }
    }
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
