#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'isolated direct-workflow consumer installs' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:fixtureRoot = Join-Path $script:repoRoot (
            'tests\.direct-install-' + [guid]::NewGuid().ToString('N')
        )
        $script:directPlugins = @(
            'code-review', 'design-review', 'create-implementation-plan',
            'continue-implementation', 'autopilot'
        )
        $script:forbiddenNames = @(
            'ReviewRun.psm1', 'Build-ReviewReport.ps1', 'Get-ReviewRun.ps1',
            'Remove-ReviewRun.ps1', 'FleetDispatch.psm1', 'Build-EvidenceReceipt.ps1',
            'Invoke-PhaseHarvest.ps1', 'ReviewCycleGate.ps1', 'ReviewResultReceipt.psm1',
            'LedgerStore.psm1', 'Add-LedgerEntry.ps1', 'Remove-LedgerEntry.ps1',
            'Repair-Plans.ps1', 'Get-PlanArtifactContext.ps1',
            'Get-PlanArtifactConsumerContext.ps1', 'Test-DependencyPlan006.ps1'
        )
        $script:forbiddenTokens = @(
            'ReviewRun', 'ReviewCycleGate', 'FleetDispatch', 'Build-EvidenceReceipt',
            'Invoke-PhaseHarvest', 'LedgerStore', 'ReviewResultReceipt',
            'Get-PlanArtifactContext', 'Get-PlanArtifactConsumerContext',
            'Repair-Plans', 'Sync-ReviewConcerns', 'review-concerns.json',
            'concern-ledger-map', 'harvest-receipts', 'learning-overflow'
        )
        New-Item -ItemType Directory -Path $script:fixtureRoot -Force | Out-Null
        foreach ($pluginName in $script:directPlugins) {
            $pluginRoot = Join-Path $script:repoRoot "plugins/$pluginName"
            $manifest = Get-Content -LiteralPath (Join-Path $pluginRoot 'plugin.json') -Raw |
                ConvertFrom-Json -Depth 50
            foreach ($mapping in @($manifest.files)) {
                $source = Join-Path $pluginRoot (([string]$mapping.src -replace '/', '\'))
                $destination = Join-Path $script:fixtureRoot (
                    '.github\' + ([string]$mapping.dest -replace '/', '\')
                )
                New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force |
                    Out-Null
                Copy-Item -LiteralPath $source -Destination $destination -Force
            }
        }
    }

    AfterAll {
        Remove-Item -LiteralPath $script:fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'test:SimpleWorkflow.ConsumerInstall installs the direct module closure for every runtime consumer' {
        foreach ($skill in @('cr', 'dr', 'ci', 'autopilot')) {
            $scripts = Join-Path $script:fixtureRoot ".github\skills\$skill\scripts"
            foreach ($name in @('DirectWorkflow.psm1', 'PlanState.psm1', 'SecretGuard.psm1')) {
                Join-Path $scripts $name | Should -Exist
            }
        }
        foreach ($skill in @('cr', 'dr', 'cep', 'cip')) {
            Join-Path $script:fixtureRoot (
                ".github\skills\$skill\scripts\Get-DirectPlanArtifactConsumerContext.ps1"
            ) | Should -Exist
        }
    }

    It 'loads installed direct modules without source-tree fallback' {
        foreach ($skill in @('cr', 'dr', 'ci', 'autopilot')) {
            $module = Join-Path $script:fixtureRoot (
                ".github\skills\$skill\scripts\DirectWorkflow.psm1"
            )
            Import-Module $module -Force -DisableNameChecking
            Get-Command Test-PlanCriteriaBaseline -ErrorAction Stop | Should -Not -BeNullOrEmpty
            Get-Command Invoke-DirectEvidence -ErrorAction Stop | Should -Not -BeNullOrEmpty
            Remove-Module DirectWorkflow -Force
        }
    }

    It 'installs no retired review workflow files' {
        foreach ($name in $script:forbiddenNames) {
            @(Get-ChildItem -LiteralPath (Join-Path $script:fixtureRoot '.github') -Recurse -File |
                    Where-Object Name -eq $name).Count | Should -Be 0
        }
        @(Get-ChildItem -LiteralPath (Join-Path $script:fixtureRoot '.github\agents') -File |
                Where-Object Name -Match '^(?:cr|dr)-').Count | Should -Be 0
    }

    It 'test:SimpleWorkflow.RetiredMachinery independently closes source and installed residue' {
        $sets = [ordered]@{
            source = @(
                foreach ($pluginName in $script:directPlugins) {
                    Get-ChildItem -LiteralPath (
                        Join-Path $script:repoRoot "plugins\$pluginName"
                    ) -Recurse -File
                }
            )
            installed = @(
                Get-ChildItem -LiteralPath (Join-Path $script:fixtureRoot '.github') -Recurse -File
            )
        }

        foreach ($set in $sets.GetEnumerator()) {
            $offenders = [System.Collections.Generic.List[string]]::new()
            foreach ($file in @($set.Value)) {
                $relative = [System.IO.Path]::GetRelativePath(
                    $(if ($set.Key -eq 'source') { $script:repoRoot } else { $script:fixtureRoot }),
                    $file.FullName
                ).Replace('\', '/')
                if ($file.Name -cin $script:forbiddenNames -or
                    $relative -match '/scripts/schemas/review/' -or
                    $relative.EndsWith('/assets/concern-ledger-map.md')) {
                    $offenders.Add("$relative :: forbidden path")
                }
                if ($relative -match '/(?:cr|dr)-(?:architecture|correctness|maintainability|operability|performance|security|testing)-') {
                    $offenders.Add("$relative :: generated concern agent")
                }
                $content = [System.IO.File]::ReadAllText($file.FullName)
                foreach ($token in $script:forbiddenTokens) {
                    if ($content.Contains($token, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $offenders.Add("$relative :: $token")
                    }
                }
            }
            @($offenders | Sort-Object -Unique) | Should -BeNullOrEmpty -Because (
                "$($set.Key) direct payload must contain no retired workflow reference"
            )
        }
    }

    It 'keeps retained host surfaces and externally consumed formats' {
        foreach ($relative in @(
                'agents/cr.agent.md', 'agents/dr.agent.md', 'agents/autopilot.agent.md',
                'prompts/cr.prompt.md', 'prompts/dr.prompt.md',
                'skills/cr/SKILL.md', 'skills/dr/SKILL.md', 'skills/cep/SKILL.md',
                'skills/cip/SKILL.md', 'skills/ci/SKILL.md', 'skills/autopilot/SKILL.md',
                'skills/autopilot/.autopilot.json.example',
                'skills/autopilot/.autopilot.host.json.example',
                'skills/autopilot/schemas/autopilot.schema.json',
                'skills/autopilot/schemas/autopilot.host.schema.json',
                'skills/autopilot/devcontainer/devcontainer.json'
            )) {
            Join-Path $script:fixtureRoot ".github\$relative" | Should -Exist
        }
        foreach ($relative in @(
                '.autopilot.json', 'registry.json', '.github/plugin/marketplace.json',
                'schemas/plugin/plugin.schema.json', 'schemas/registry/registry.schema.json',
                'schemas/receipt/receipt.schema.json'
            )) {
            Join-Path $script:repoRoot $relative | Should -Exist
        }
    }
}
