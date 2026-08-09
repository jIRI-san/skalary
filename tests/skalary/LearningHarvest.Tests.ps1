#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Installed learning harvest workflow' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:ciScript = Join-Path $script:repoRoot 'plugins/continue-implementation/skills/ci/scripts/Invoke-PhaseHarvest.ps1'
        $script:autopilotScript = Join-Path $script:repoRoot 'plugins/autopilot/skills/autopilot/scripts/Invoke-PhaseHarvest.ps1'

        function Script:New-HarvestFixture {
            param(
                [switch]$MalformedCapture,
                [switch]$MissingCrLog
            )

            $root = Join-Path ([System.IO.Path]::GetTempPath()) ('learning-harvest-' + [guid]::NewGuid().ToString('N'))
            $planDir = Join-Path $root 'docs/implementation-plans/2026-08-09-a1b2c3-harvest-fixture'
            $logs = Join-Path $planDir 'assets/logs'
            [void](New-Item -ItemType Directory -Path $logs -Force)
            [System.IO.File]::WriteAllText(
                (Join-Path $planDir 'plan.md'),
                @(
                    '# a1b2c3: Harvest fixture'
                    '<!-- plan-id: a1b2c3 -->'
                    ''
                    '## Phase 1: Fixture'
                    '- [x] 1.1 Fixture step (REQ-1, RISK-1) `S`'
                    ''
                ) -join "`n",
                [System.Text.UTF8Encoding]::new($false)
            )
            [System.IO.File]::WriteAllText(
                (Join-Path $planDir 'assets/requirements.md'),
                @(
                    '# Requirements'
                    ''
                    '| ID | Requirement | Acceptance Criteria | Phases/Steps |'
                    '|----|-------------|---------------------|--------------|'
                    '| REQ-1 | Fixture | `test:fixture` | 1.1 |'
                    ''
                ) -join "`n",
                [System.Text.UTF8Encoding]::new($false)
            )
            [System.IO.File]::WriteAllText(
                (Join-Path $logs 'capture.md'),
                $(if ($MalformedCapture) {
                        "## Capture`nPhase: 1`n"
                    }
                    else {
                        "## Capture`nPhase: 1`n`nNo entries for this phase.`n"
                    }),
                [System.Text.UTF8Encoding]::new($false)
            )
            [System.IO.File]::WriteAllText(
                (Join-Path $logs 'learnings.md'),
                "## Learnings Capture`nPhase: 1`n`nNo entries for this phase.`n",
                [System.Text.UTF8Encoding]::new($false)
            )
            if (-not $MissingCrLog) {
                [System.IO.File]::WriteAllText(
                    (Join-Path $logs 'cr-log.md'),
                    "## CR Capture`nPhase: 1`n`nNo entries for this phase.`n",
                    [System.Text.UTF8Encoding]::new($false)
                )
            }
            return [pscustomobject]@{ Root = $root; PlanDir = $planDir }
        }

        function Script:Invoke-InstalledHarvest {
            param(
                [Parameter(Mandatory)][string]$ScriptPath,
                [Parameter(Mandatory)]$Fixture,
                [Parameter(Mandatory)][ValidateSet('ci', 'autopilot')][string]$Source
            )

            $output = & pwsh -NoProfile -File $ScriptPath -PlanDir $Fixture.PlanDir `
                -Phase 1 -Src $Source -RepoRoot $Fixture.Root 2>&1
            return [pscustomobject]@{
                ExitCode = $LASTEXITCODE
                Output = ($output | Out-String)
            }
        }
    }

    It 'test:LearningHarvest.InstalledInvocationAndAutopilotAllowlist invokes both installed copies and surfaces malformed or missing sections as degraded' {
        $ciGuide = [System.IO.File]::ReadAllText(
            (Join-Path $script:repoRoot 'plugins/continue-implementation/skills/ci/assets/crosscheck-guide.md')
        )
        $agent = [System.IO.File]::ReadAllText(
            (Join-Path $script:repoRoot 'plugins/autopilot/agents/autopilot.agent.md')
        )
        $ciGuide | Should -Match '\.github/skills/ci/scripts/Invoke-PhaseHarvest\.ps1'
        $ciGuide | Should -Match '\-Phase <N> \-Src ci'
        $agent | Should -Match '\.github/skills/autopilot/scripts/Invoke-PhaseHarvest\.ps1'
        $agent | Should -Match '\-Phase <N> \-Src autopilot'
        $agent | Should -Match 'Workflow carve-out.+Invoke-PhaseHarvest\.ps1'
        $agent | Should -Match 'stage the returned receipt path'
        $ciGuide | Should -Match 'stage the returned receipt path'
        $agent | Should -Match 'stop phase completion'
        $ciGuide | Should -Match 'stop phase completion'
        $agent | Should -Match 'stop before branch selection or archival'
        $ciGuide | Should -Match 'stop before branch selection or archival'
        $agent | Should -Not -Match 'Test-Path docs/review-ledger/security\.md'
        $ciGuide | Should -Not -Match 'Test-Path docs/review-ledger/security\.md'

        $ciFixture = New-HarvestFixture -MalformedCapture
        $autopilotFixture = New-HarvestFixture -MissingCrLog
        try {
            $ci = Invoke-InstalledHarvest -ScriptPath $script:ciScript -Fixture $ciFixture -Source ci
            $ci.ExitCode | Should -Be 3
            $ci.Output | Should -Match 'Status'
            $ci.Output | Should -Match 'degraded'
            $ci.Output | Should -Match 'placeholder'

            $autopilot = Invoke-InstalledHarvest -ScriptPath $script:autopilotScript `
                -Fixture $autopilotFixture -Source autopilot
            $autopilot.ExitCode | Should -Be 3
            $autopilot.Output | Should -Match 'Status'
            $autopilot.Output | Should -Match 'degraded'
            $autopilot.Output | Should -Match 'Missing required workflow log'
        }
        finally {
            Remove-Item -LiteralPath $ciFixture.Root -Recurse -Force
            Remove-Item -LiteralPath $autopilotFixture.Root -Recurse -Force
        }
    }

    It 'declares both scripts, modules, and receipt scaffolds in standalone plugin manifests' {
        foreach ($plugin in @('continue-implementation', 'autopilot')) {
            $manifest = Get-Content -LiteralPath (Join-Path $script:repoRoot "plugins/$plugin/plugin.json") `
                -Raw | ConvertFrom-Json
            $destinations = @($manifest.files.dest)
            $skill = if ($plugin -eq 'autopilot') { 'autopilot' } else { 'ci' }
            $destinations | Should -Contain "skills/$skill/scripts/Invoke-PhaseHarvest.ps1"
            $destinations | Should -Contain "skills/$skill/scripts/LedgerStore.psm1"
            @($manifest.scaffolds.path) | Should -Contain 'docs/implementation-plans/<plan>/assets/harvest-receipts/**'
            @($manifest.scaffolds.path) | Should -Contain 'docs/implementation-plans/<plan>/harvest-receipts/**'
        }
    }
}
