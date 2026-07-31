Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Autopilot model configuration' {
    BeforeAll {
        $script:pluginRoot = Join-Path $PSScriptRoot '../../plugins/autopilot'
        $script:example = Get-Content -LiteralPath (Join-Path $pluginRoot '.autopilot.json.example') -Raw | ConvertFrom-Json
        $script:schema = Get-Content -LiteralPath (Join-Path $pluginRoot 'schemas/autopilot.schema.json') -Raw | ConvertFrom-Json
        $script:hostLauncher = Get-Content -LiteralPath (Join-Path $pluginRoot 'scripts/launch-host.ps1') -Raw
        $script:containerEntrypoint = Get-Content -LiteralPath (Join-Path $pluginRoot 'scripts/container-entrypoint.sh') -Raw
        $script:sandboxLauncher = Get-Content -LiteralPath (Join-Path $pluginRoot 'scripts/launch-sandbox.ps1') -Raw
        $script:agent = Get-Content -LiteralPath (Join-Path $pluginRoot 'agents/autopilot.agent.md') -Raw
    }

    It 'defaults to Claude Opus 5 with high reasoning and long context' {
        $example.model | Should -Be 'claude-opus-5'
        $example.context | Should -Be 'long_context'
        $example.reasoningEffort | Should -Be 'high'
        $agent | Should -Match '(?m)^model: claude-opus-5$'
    }

    It 'requires and constrains context and reasoning settings in the schema' {
        $schema.required | Should -Contain 'context'
        $schema.required | Should -Contain 'reasoningEffort'
        $schema.properties.context.enum | Should -Contain 'long_context'
        $schema.properties.reasoningEffort.enum | Should -Contain 'high'
    }

    It 'passes context and effort explicitly in host mode' {
        $hostLauncher | Should -Match "ArgumentList\.Add\('--context'\)"
        $hostLauncher | Should -Match "ArgumentList\.Add\('--effort'\)"
        $hostLauncher | Should -Match 'ConvertTo-CmdQuotedToken -Token \$ContextTier'
        $hostLauncher | Should -Match 'ConvertTo-PowerShellQuotedToken -Token \$ReasoningEffort'
    }

    It 'passes context and effort explicitly in container mode' {
        $containerEntrypoint | Should -Match '--context "\$\{COPILOT_CONTEXT\}"'
        $containerEntrypoint | Should -Match '--effort "\$\{COPILOT_REASONING_EFFORT\}"'
    }

    It 'passes context and effort explicitly in sandbox mode' {
        $sandboxLauncher.Contains("--context '`$(`$Config.context)'") | Should -BeTrue
        $sandboxLauncher.Contains("--effort '`$(`$Config.reasoningEffort)'") | Should -BeTrue
    }
}