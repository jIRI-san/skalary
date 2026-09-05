#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'isolated direct-workflow consumer installs' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:fixtureRoot = Join-Path $script:repoRoot (
            'tests\.direct-install-' + [guid]::NewGuid().ToString('N')
        )
        New-Item -ItemType Directory -Path $script:fixtureRoot -Force | Out-Null
        foreach ($pluginName in @(
                'code-review', 'design-review', 'create-implementation-plan',
                'continue-implementation', 'autopilot'
            )) {
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

    It 'installs the direct module closure for every runtime consumer' {
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
        $forbidden = @(
            'ReviewRun.psm1', 'Build-ReviewReport.ps1', 'Get-ReviewRun.ps1',
            'Remove-ReviewRun.ps1', 'FleetDispatch.psm1', 'Build-EvidenceReceipt.ps1',
            'Invoke-PhaseHarvest.ps1', 'ReviewCycleGate.ps1', 'ReviewResultReceipt.psm1'
        )
        foreach ($name in $forbidden) {
            @(Get-ChildItem -LiteralPath (Join-Path $script:fixtureRoot '.github') -Recurse -File |
                    Where-Object Name -eq $name).Count | Should -Be 0
        }
        @(Get-ChildItem -LiteralPath (Join-Path $script:fixtureRoot '.github\agents') -File |
                Where-Object Name -Match '^(?:cr|dr)-').Count | Should -Be 0
    }
}
