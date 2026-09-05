Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Autopilot model configuration' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:pluginRoot = Join-Path $PSScriptRoot '../../plugins/autopilot'
        $script:repoConfig = Get-Content -LiteralPath (Join-Path $repoRoot '.autopilot.json') -Raw | ConvertFrom-Json
        $script:example = Get-Content -LiteralPath (Join-Path $pluginRoot '.autopilot.json.example') -Raw | ConvertFrom-Json
        $script:schemaPath = Join-Path $pluginRoot 'schemas/autopilot.schema.json'
        $script:schema = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json
        $script:launcher = Get-Content -LiteralPath (Join-Path $pluginRoot 'scripts/launch.ps1') -Raw
        $script:hostLauncher = Get-Content -LiteralPath (Join-Path $pluginRoot 'scripts/launch-host.ps1') -Raw
        $script:containerEntrypoint = Get-Content -LiteralPath (Join-Path $pluginRoot 'scripts/container-entrypoint.sh') -Raw
        $script:sandboxLauncher = Get-Content -LiteralPath (Join-Path $pluginRoot 'scripts/launch-sandbox.ps1') -Raw
        $script:environmentWriter = Get-Content -LiteralPath (Join-Path $pluginRoot 'scripts/prepare-env-file.ps1') -Raw
        $script:agent = Get-Content -LiteralPath (Join-Path $pluginRoot 'agents/autopilot.agent.md') -Raw
        $script:allowlist = Import-PowerShellDataFile -LiteralPath (
            Join-Path $repoRoot 'tools/model-allowlist.psd1'
        )
    }

    It 'defaults routine execution to GPT-5.6 Luna with medium reasoning' {
        foreach ($config in @($repoConfig, $example)) {
            $config.model | Should -Be 'gpt-5.6-luna'
            $config.reasoningEffort | Should -Be 'medium'
            $config.PSObject.Properties.Name | Should -Not -Contain 'context'
        }
        $agent | Should -Match '(?m)^model: gpt-5\.6-luna\r?$'
    }

    It 'leaves context at the host default and constrains reasoning settings' {
        $schema.required | Should -Not -Contain 'context'
        $schema.properties.PSObject.Properties.Name | Should -Not -Contain 'context'
        $schema.required | Should -Contain 'reasoningEffort'
        $schema.properties.reasoningEffort.enum | Should -Contain 'medium'
        $schema.properties.reasoningEffort.enum | Should -Contain 'high'
    }

    It 'rejects models outside the shared CLI allowlist before runtime dispatch' {
        @($schema.properties.model.enum) | Should -Be @($allowlist.CliModels)
        $invalidConfig = Get-Content -LiteralPath (
            Join-Path $pluginRoot '.autopilot.json.example'
        ) -Raw | ConvertFrom-Json
        $invalidConfig.model = 'unsupported-premium-model'
        $schemaErrors = $null
        $isValid = ($invalidConfig | ConvertTo-Json -Depth 20) |
            Test-Json -SchemaFile $schemaPath -ErrorVariable schemaErrors -ErrorAction SilentlyContinue
        $isValid | Should -BeFalse
        @($schemaErrors).Count | Should -BeGreaterThan 0
        $launcher | Should -Match '\$Config\.model -cnotin \$allowedModels'
        $launcher | Should -Match 'Invalid model.*in \.autopilot\.json'
        $modelValidation = $launcher.IndexOf('$Config.model -cnotin $allowedModels')
        $buildValidation = $launcher.IndexOf('# --- Validate build/test commands against allowlist ---')
        $runtimeDispatch = $launcher.IndexOf('# --- Determine runtime ---')
        $modelValidation | Should -BeGreaterOrEqual 0
        $modelValidation | Should -BeLessThan $buildValidation
        $modelValidation | Should -BeLessThan $runtimeDispatch
    }

    It 'passes model and effort but no context override in host mode' {
        $hostLauncher | Should -Match "\['COPILOT_MODEL'\]\s*=\s*\`$Model"
        $hostLauncher | Should -Match "ArgumentList\.Add\('--effort'\)"
        $hostLauncher | Should -Match 'ConvertTo-PowerShellQuotedToken -Token \$ReasoningEffort'
        $hostLauncher | Should -Not -Match '(?m)(?:^|\s)--context(?:\s|$)'
        $hostLauncher | Should -Not -Match '\bContextTier\b'
    }

    It 'passes model and effort but no context override in container mode' {
        $containerEntrypoint | Should -Match 'MODEL_ARGS=\(--model "\$\{COPILOT_MODEL\}"\)'
        $containerEntrypoint | Should -Match '--effort "\$\{COPILOT_REASONING_EFFORT\}"'
        $containerEntrypoint | Should -Not -Match '(?m)(?:^|\s)--context(?:\s|$)'
        $environmentWriter | Should -Not -Match '\bCOPILOT_CONTEXT\b'
    }

    It 'passes model and effort but no context override in sandbox mode' {
        $sandboxLauncher.Contains("--model '`$(`$Config.model)'") | Should -BeTrue
        $sandboxLauncher.Contains("--effort '`$(`$Config.reasoningEffort)'") | Should -BeTrue
        $sandboxLauncher | Should -Not -Match '(?m)(?:^|\s)--context(?:\s|$)'
        $sandboxLauncher | Should -Not -Match '\$Config\.context\b'
    }

    It 'contains no retired context override in active autopilot surfaces' {
        $activePaths = @(
            (Join-Path $repoRoot '.autopilot.json')
            (Join-Path $repoRoot 'plugins/autopilot')
            (Join-Path $repoRoot '.github/agents/autopilot.agent.md')
            (Join-Path $repoRoot '.github/skills/autopilot')
        )
        $files = foreach ($path in $activePaths) {
            if (Test-Path -LiteralPath $path -PathType Container) {
                Get-ChildItem -LiteralPath $path -File -Recurse -Force
            }
            else {
                Get-Item -LiteralPath $path -Force
            }
        }

        foreach ($file in $files) {
            $content = [System.IO.File]::ReadAllText($file.FullName)
            $content | Should -Not -Match '\blong_context\b' -Because $file.FullName
            $content | Should -Not -Match '\bCOPILOT_CONTEXT\b' -Because $file.FullName
            $content | Should -Not -Match '\$Config\.context\b' -Because $file.FullName
            $content | Should -Not -Match '\bContextTier\b' -Because $file.FullName
            $content | Should -Not -Match '(?m)(?:^|\s)--context(?:\s|$)' -Because $file.FullName
        }
    }
}