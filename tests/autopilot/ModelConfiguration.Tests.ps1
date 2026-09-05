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
        $script:modelPolicyPath = Join-Path $repoRoot 'tools/model-allowlist.psd1'
        $script:modelPolicy = Import-PowerShellDataFile -LiteralPath $modelPolicyPath

        function Invoke-InvalidModelLaunch {
            param([AllowEmptyString()][string]$Model)

            $fixtureRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $planRoot = Join-Path $fixtureRoot 'docs/implementation-plans/test-plan'
            $installedSchemaRoot = Join-Path $fixtureRoot '.github/skills/autopilot/schemas'
            $installedAssetRoot = Join-Path $fixtureRoot '.github/skills/autopilot/assets'
            New-Item -ItemType Directory -Path $planRoot, $installedSchemaRoot, $installedAssetRoot -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $planRoot 'plan.md') -Value '# test plan' -Encoding utf8NoBOM
            Copy-Item -LiteralPath $script:schemaPath -Destination (
                Join-Path $installedSchemaRoot 'autopilot.schema.json'
            )
            Copy-Item -LiteralPath $script:modelPolicyPath -Destination (
                Join-Path $installedAssetRoot 'model-aliases.psd1'
            )
            [ordered]@{
                runtime = 'host'
                copilotAuth = 'oauth'
                gitProvider = 'github'
                gitAuth = 'oauth'
                model = $Model
                context = 'default'
                reasoningEffort = 'medium'
                git = [ordered]@{ name = 'Test'; email = 'test@example.com' }
                maxIterationsPerStep = 1
                build = 'npm run build'
                test = 'npm test'
            } | ConvertTo-Json -Depth 10 |
                Set-Content -LiteralPath (Join-Path $fixtureRoot '.autopilot.json') -Encoding utf8NoBOM
            & git -C $fixtureRoot init --quiet
            if ($LASTEXITCODE -ne 0) { throw 'Unable to initialize launcher test repository.' }

            $start = [System.Diagnostics.ProcessStartInfo]::new()
            $start.FileName = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source
            $start.WorkingDirectory = $fixtureRoot
            $start.UseShellExecute = $false
            $start.RedirectStandardOutput = $true
            $start.RedirectStandardError = $true
            foreach ($argument in @(
                    '-NoProfile', '-File', (Join-Path $script:pluginRoot 'scripts/launch.ps1'),
                    '-PlanSlug', 'test-plan', '-Mode', 'next-phase'
                )) {
                [void]$start.ArgumentList.Add($argument)
            }

            $process = [System.Diagnostics.Process]::new()
            $process.StartInfo = $start
            [void]$process.Start()
            $stdout = $process.StandardOutput.ReadToEndAsync()
            $stderr = $process.StandardError.ReadToEndAsync()
            $process.WaitForExit()
            return [pscustomobject]@{
                ExitCode = $process.ExitCode
                Output = $stdout.Result + $stderr.Result
            }
        }
    }

    It 'test:AiCreditBudget.AutopilotDefaults uses the low alias, medium effort, and default context' {
        foreach ($config in @($repoConfig, $example)) {
            $config.model | Should -Be 'model-low'
            $config.context | Should -Be 'default'
            $config.reasoningEffort | Should -Be 'medium'
        }
        $agent | Should -Not -Match '(?m)^model:'
    }

    It 'keeps long context available as an explicit opt-in' {
        $schema.required | Should -Contain 'context'
        $schema.properties.context.enum | Should -Be @('default', 'long_context')
        $schema.required | Should -Contain 'reasoningEffort'
        $schema.properties.reasoningEffort.enum | Should -Contain 'medium'
        $schema.properties.reasoningEffort.enum | Should -Contain 'high'
    }

    It 'rejects model aliases outside the canonical map before runtime dispatch' {
        @($script:modelPolicy.Aliases.Keys).Count | Should -Be 6
        $schema.properties.model.pattern | Should -Be '^(?:model|alternate-model)-(?:low|mid|high)$'
        $invalidConfig = Get-Content -LiteralPath (
            Join-Path $pluginRoot '.autopilot.json.example'
        ) -Raw | ConvertFrom-Json
        $invalidConfig.model = 'unsupported-premium-model'
        $schemaErrors = $null
        $isValid = ($invalidConfig | ConvertTo-Json -Depth 20) |
            Test-Json -SchemaFile $schemaPath -ErrorVariable schemaErrors -ErrorAction SilentlyContinue
        $isValid | Should -BeFalse
        @($schemaErrors).Count | Should -BeGreaterThan 0
        $launcher | Should -Match '\$Config\.model -cnotin \$allowedAliases'
        $launcher | Should -Match 'Invalid model alias.*in \.autopilot\.json'
        $launcher | Should -Match '\$Config\.model = \$resolvedModel'
        $modelValidation = $launcher.IndexOf('$Config.model -cnotin $allowedAliases')
        $buildValidation = $launcher.IndexOf('# --- Validate build/test commands against allowlist ---')
        $runtimeDispatch = $launcher.IndexOf('# --- Determine runtime ---')
        $modelValidation | Should -BeGreaterOrEqual 0
        $modelValidation | Should -BeLessThan $buildValidation
        $modelValidation | Should -BeLessThan $runtimeDispatch
    }

    It 'fails blank and unsupported models before runtime or authentication actions' {
        foreach ($model in @('', 'unsupported-premium-model')) {
            $result = Invoke-InvalidModelLaunch -Model $model
            $result.ExitCode | Should -Be 1
            $result.Output | Should -Match 'Invalid model alias'
            $result.Output | Should -Not -Match 'Runtime:|Fetching credentials|Validating authentication'
        }
    }

    It 'passes resolved model, effort, and context in host mode' {
        $hostLauncher | Should -Match "\['COPILOT_MODEL'\]\s*=\s*\`$Model"
        $hostLauncher | Should -Match "ArgumentList\.Add\('--effort'\)"
        $hostLauncher | Should -Match 'ConvertTo-PowerShellQuotedToken -Token \$ReasoningEffort'
        $hostLauncher | Should -Match "ArgumentList\.Add\('--context'\)"
        $hostLauncher | Should -Match '\bContextTier\b'
    }

    It 'passes resolved model, effort, and context in container mode' {
        $containerEntrypoint | Should -Match 'MODEL_ARGS=\(--model "\$\{COPILOT_MODEL\}"\)'
        $containerEntrypoint | Should -Match '--effort "\$\{COPILOT_REASONING_EFFORT\}"'
        $containerEntrypoint | Should -Match '--context "\$\{COPILOT_CONTEXT\}"'
        $environmentWriter | Should -Match '\bCOPILOT_CONTEXT\b'
    }

    It 'passes resolved model, effort, and context in sandbox mode' {
        $sandboxLauncher.Contains("--model '`$(`$Config.model)'") | Should -BeTrue
        $sandboxLauncher.Contains("--effort '`$(`$Config.reasoningEffort)'") | Should -BeTrue
        $sandboxLauncher.Contains("--context '`$(`$Config.context)'") | Should -BeTrue
    }

    It 'test:AiCreditBudget.LongContextOptIn keeps every committed autopilot config on default' {
        $configPaths = @(
            (Join-Path $repoRoot '.autopilot.json'),
            (Join-Path $pluginRoot '.autopilot.json.example'),
            (Join-Path $repoRoot '.github/skills/autopilot/.autopilot.json.example')
        )
        foreach ($path in $configPaths) {
            (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json).context |
                Should -Be 'default' -Because $path
        }
    }
}