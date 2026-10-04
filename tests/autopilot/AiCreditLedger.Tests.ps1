#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Autopilot AI-credit ledger' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:pluginRoot = Join-Path $script:repoRoot 'plugins/autopilot'
        $script:recorder = Join-Path $script:repoRoot '.github\skills\autopilot\scripts\Record-AiCreditUsage.ps1'

        function New-UsageFixture {
            param(
                [Parameter(Mandatory)][string]$Path,
                [Parameter(Mandatory)][string]$StartedAt,
                [Parameter(Mandatory)][int64]$TotalNanoAiu,
                [Parameter(Mandatory)][string]$Model
            )

            [ordered]@{
                totalNanoAiu = $TotalNanoAiu
                tokenDetails = [ordered]@{
                    input = @{ tokenCount = 10 }
                    cache_read = @{ tokenCount = 20 }
                    cache_write = @{ tokenCount = 30 }
                    output = @{ tokenCount = 40 }
                }
                sessionStartTime = $StartedAt
                modelMetrics = [ordered]@{
                    $Model = [ordered]@{ totalNanoAiu = $TotalNanoAiu }
                }
            } | ConvertTo-Json -Depth 10 |
                Set-Content -LiteralPath $Path -Encoding utf8NoBOM
        }
    }

    BeforeEach {
        $script:planFolder = Join-Path $TestDrive (
            "705e6c-2026-09-05-abcdef-$([guid]::NewGuid().ToString('N'))"
        )
        New-Item -ItemType Directory -Path (Join-Path $planFolder 'assets') -Force | Out-Null
        @'
# abcdef: Fixture
<!-- plan-id: abcdef -->
<!-- epic: 705e6c -->
'@ | Set-Content -LiteralPath (Join-Path $planFolder 'plan.md') -Encoding utf8NoBOM
    }

    It 'stores exact target usage and replaces a repeated import' {
        $firstUsage = Join-Path $TestDrive 'first.json'
        New-UsageFixture -Path $firstUsage `
            -StartedAt '2026-09-05T17:28:57.320Z' `
            -TotalNanoAiu 483860000 `
            -Model 'gpt-5.6-luna'

        & $recorder -PlanFolder $planFolder -UsagePath $firstUsage `
            -Target phase-1 -Runtime container -ModelAlias primary-model-low -ContextTier default | Out-Null
        & $recorder -PlanFolder $planFolder -UsagePath $firstUsage `
            -Target phase-1 -Runtime container -ModelAlias primary-model-low -ContextTier default | Out-Null

        $secondUsage = Join-Path $TestDrive 'second.json'
        New-UsageFixture -Path $secondUsage `
            -StartedAt '2026-09-05T18:00:00.000Z' `
            -TotalNanoAiu 1000000000 `
            -Model 'gpt-5.6-terra'
        & $recorder -PlanFolder $planFolder -UsagePath $secondUsage `
            -Target finalization -Runtime container -ModelAlias primary-model-mid -ContextTier default | Out-Null

        $ledger = Get-Content -LiteralPath (Join-Path $planFolder 'assets/ai-credits.json') -Raw |
            ConvertFrom-Json -Depth 20
        $ledger.schema | Should -BeExactly 'skalary-ai-credits/v1'
        $ledger.planId | Should -BeExactly 'abcdef'
        $ledger.epicId | Should -BeExactly '705e6c'
        @($ledger.executions).Count | Should -Be 2
        $ledger.totalNanoAiu | Should -Be 1483860000
        $ledger.totalAiCredits | Should -Be 1.48386
        $ledger.executions[0].modelAlias | Should -BeExactly 'primary-model-low'
        $ledger.executions[0].startedAt.ToUniversalTime().ToString('o') |
            Should -BeExactly '2026-09-05T17:28:57.3200000Z'
        $ledger.executions[0].models[0].model | Should -BeExactly 'gpt-5.6-luna'
        $ledger.executions[0].tokens.cacheWrite | Should -Be 30
    }

    It 'records finalization usage in the archive without recreating the active folder' {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $activeFolder = Join-Path $root 'docs\implementation-plans\standalone-2026-01-01-abcdef-usage'
        New-Item -ItemType Directory -Path $activeFolder -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $activeFolder 'plan.md') -Encoding utf8NoBOM `
            -Value "# abcdef: Usage`n<!-- plan-id: abcdef -->`n`n## Phase 1: Usage`n`n- [x] 1.1 Done ``S``"
        $archive = & (Join-Path $repoRoot 'scripts\skalary\Archive-Plan.ps1') `
            -Plan abcdef -RepoRoot $root
        $usagePath = Join-Path $TestDrive 'archived-usage.json'
        New-UsageFixture -Path $usagePath -StartedAt '2026-09-05T18:00:00.000Z' `
            -TotalNanoAiu 1000000000 -Model 'fixture-model'
        & $recorder -PlanFolder $activeFolder -UsagePath $usagePath `
            -Target finalization -Runtime host -ContextTier default | Out-Null
        Test-Path -LiteralPath $activeFolder | Should -BeFalse
        $ledger = Get-Content -LiteralPath (Join-Path $archive.Path 'assets\ai-credits.json') -Raw |
            ConvertFrom-Json -Depth 20
        $ledger.planId | Should -BeExactly 'abcdef'
        $ledger.totalNanoAiu | Should -Be 1000000000
    }

    It 'fails instead of recording incomplete usage output' {
        $usagePath = Join-Path $TestDrive 'invalid.json'
        '{"totalNanoAiu":100}' |
            Set-Content -LiteralPath $usagePath -Encoding utf8NoBOM

        {
            & $recorder -PlanFolder $planFolder -UsagePath $usagePath `
                -Target phase-1 -Runtime host -ContextTier default
        } | Should -Throw "*missing 'tokenDetails'*"
    }

    It 'serializes concurrent ledger updates without losing an execution' {
        $usagePaths = @(
            (Join-Path $TestDrive 'concurrent-a.json'),
            (Join-Path $TestDrive 'concurrent-b.json')
        )
        New-UsageFixture -Path $usagePaths[0] `
            -StartedAt '2026-09-05T19:00:00.000Z' `
            -TotalNanoAiu 250000000 `
            -Model 'gpt-5.6-luna'
        New-UsageFixture -Path $usagePaths[1] `
            -StartedAt '2026-09-05T19:00:01.000Z' `
            -TotalNanoAiu 750000000 `
            -Model 'gpt-5.6-terra'

        $processes = @()
        foreach ($index in 0..1) {
            $start = [System.Diagnostics.ProcessStartInfo]::new()
            $start.FileName = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source
            $start.UseShellExecute = $false
            foreach ($argument in @(
                    '-NoProfile', '-File', $recorder,
                    '-PlanFolder', $planFolder,
                    '-UsagePath', $usagePaths[$index],
                    '-Target', "phase-$($index + 1)",
                    '-Runtime', 'host',
                    '-ModelAlias', 'primary-model-low',
                    '-ContextTier', 'default'
                )) {
                [void]$start.ArgumentList.Add($argument)
            }
            $process = [System.Diagnostics.Process]::new()
            $process.StartInfo = $start
            [void]$process.Start()
            $processes += $process
        }
        foreach ($process in $processes) {
            $process.WaitForExit()
            $process.ExitCode | Should -Be 0
            $process.Dispose()
        }

        $ledger = Get-Content -LiteralPath (Join-Path $planFolder 'assets/ai-credits.json') -Raw |
            ConvertFrom-Json -Depth 20
        @($ledger.executions).Count | Should -Be 2
        $ledger.totalNanoAiu | Should -Be 1000000000
    }

    It 'wires exact local usage capture through every runtime' {
        $hostLauncher = Get-Content -LiteralPath (
            Join-Path $pluginRoot 'scripts/launch-host.ps1'
        ) -Raw
        $containerLauncher = Get-Content -LiteralPath (
            Join-Path $pluginRoot 'scripts/launch-container.ps1'
        ) -Raw
        $containerEntrypoint = Get-Content -LiteralPath (
            Join-Path $pluginRoot 'scripts/container-entrypoint.sh'
        ) -Raw
        $sandboxLauncher = Get-Content -LiteralPath (
            Join-Path $pluginRoot 'scripts/launch-sandbox.ps1'
        ) -Raw
        $manifest = Get-Content -LiteralPath (Join-Path $pluginRoot 'plugin.json') -Raw |
            ConvertFrom-Json

        $hostLauncher | Should -Match '(?s)--usage-output-file.*Record-AiCreditUsage\.ps1'
        $hostLauncher | Should -Match 'GetTempPath'
        $containerEntrypoint | Should -Match '--usage-output-file='
        $containerEntrypoint | Should -Match 'USAGE_OUTPUT_DIR="/tmp/autopilot-usage"'
        $containerLauncher | Should -Match 'Record-AiCreditUsage\.ps1'
        $containerLauncher | Should -Match 'GetTempPath'
        $containerLauncher | Should -Not -Match 'TranscriptsDir -Filter ''session-usage-'
        $sandboxLauncher | Should -Match '(?s)--usage-output-file=.*Record-AiCreditUsage\.ps1'
        $sandboxLauncher | Should -Match 'Join-Path `\$SessionPath "session-usage-phase-'
        @($manifest.files.src) | Should -Contain 'scripts/Record-AiCreditUsage.ps1'
        (Get-FileHash -LiteralPath $recorder).Hash | Should -Be (
            Get-FileHash -LiteralPath (Join-Path $pluginRoot 'scripts\Record-AiCreditUsage.ps1')
        ).Hash
    }

    It 'keeps accounting failures from replacing nonzero runtime exits' {
        foreach ($path in @(
                'scripts/launch-host.ps1',
                'scripts/launch-container.ps1',
                'scripts/launch-sandbox.ps1'
            )) {
            $launcher = Get-Content -LiteralPath (Join-Path $pluginRoot $path) -Raw
            $launcher | Should -Match 'AI-credit recording failed after'
            $launcher | Should -Match '(?s)if \(\$(?:copilotExitCode|exitCode) -eq 0\).*?throw'
        }
    }
}
