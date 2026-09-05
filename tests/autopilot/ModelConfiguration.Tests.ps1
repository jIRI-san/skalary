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

        function Invoke-InvalidModelLaunch {
            param([AllowEmptyString()][string]$Model)

            $fixtureRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $planRoot = Join-Path $fixtureRoot 'docs/implementation-plans/test-plan'
            $installedSchemaRoot = Join-Path $fixtureRoot '.github/skills/autopilot/schemas'
            New-Item -ItemType Directory -Path $planRoot, $installedSchemaRoot -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $planRoot 'plan.md') -Value '# test plan' -Encoding utf8NoBOM
            Copy-Item -LiteralPath $script:schemaPath -Destination (
                Join-Path $installedSchemaRoot 'autopilot.schema.json'
            )
            [ordered]@{
                runtime = 'host'
                copilotAuth = 'oauth'
                gitProvider = 'github'
                gitAuth = 'oauth'
                model = $Model
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

    It 'test:AiCreditBudget.AutopilotDefaults uses Luna medium and validates supported overrides' {
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

    It 'fails blank and unsupported models before runtime or authentication actions' {
        foreach ($model in @('', 'unsupported-premium-model')) {
            $result = Invoke-InvalidModelLaunch -Model $model
            $result.ExitCode | Should -Be 1
            $result.Output | Should -Match 'Invalid model'
            $result.Output | Should -Not -Match 'Runtime:|Fetching credentials|Validating authentication'
        }
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

    It 'test:AiCreditBudget.LongContextRetired contains no retired context override in active autopilot surfaces' {
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