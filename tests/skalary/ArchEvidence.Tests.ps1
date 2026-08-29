#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'retired arch evidence marker' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:canonicalState = Join-Path $script:repoRoot 'scripts/skalary/PlanState.psm1'
        $script:canonicalEvidence = Join-Path $script:repoRoot 'scripts/skalary/PlanEvidence.psm1'
        $script:canonicalValidator = Join-Path $script:repoRoot 'scripts/skalary/Test-Plan.ps1'

        function Get-ManifestScriptBundle {
            param([Parameter(Mandatory)][string]$LeafName)

            $bundles = [System.Collections.Generic.List[object]]::new()
            foreach ($manifestPath in (Get-ChildItem -LiteralPath (Join-Path $script:repoRoot 'plugins') -File -Recurse -Filter 'plugin.json')) {
                $pluginRoot = Split-Path -Parent $manifestPath.FullName
                $manifest = Get-Content -LiteralPath $manifestPath.FullName -Raw | ConvertFrom-Json -Depth 100
                foreach ($entry in @($manifest.files)) {
                    if ([System.IO.Path]::GetFileName([string]$entry.src) -ne $LeafName) { continue }
                    $dest = ([string]$entry.dest).Replace('\', '/')
                    $skill = [regex]::Match($dest, '^skills/(?<name>[^/]+)/scripts/').Groups['name'].Value
                    $bundles.Add([pscustomobject]@{
                            Plugin = [string]$manifest.name
                            Skill = $skill
                            Path = Join-Path $pluginRoot ([string]$entry.src)
                        })
                }
            }
            return @($bundles | Sort-Object Skill, Plugin)
        }
        function New-MarkerPlanFixture {
            param([switch]$SeedFile)

            $root = Join-Path ([System.IO.Path]::GetTempPath()) ("marker-retirement-" + [guid]::NewGuid().ToString('N'))
            [void](New-Item -ItemType Directory -Path $root -Force)
            if ($SeedFile) {
                Set-Content -LiteralPath (Join-Path $root 'README.md') -Value 'seeded' -NoNewline
            }
            $criteria = '`test:Known` and `file:README.md#exists` and `review:cr` and `review:dr` and `arch:ARCH-Retired` and `bogus:still-red`'
            $plan = @(
                '# 900: Marker retirement fixture'
                '<!-- evidence: required -->'
                '<!-- phase-budget-points: 6 -->'
                ''
                '## Requirements'
                ''
                '| ID | Requirement | Acceptance Criteria | Phases/Steps |'
                '|----|-------------|---------------------|--------------|'
                "| REQ-1 | Retired marker fails loud | $criteria | 1.1 |"
                ''
                '## Risks'
                ''
                '| ID | Risk | Likelihood | Impact | Mitigation | Steps |'
                '|----|------|------------|--------|------------|-------|'
                '| RISK-1 | False green | Low | High | Tokenize independently | 1.1 |'
                ''
                '## Phase 1: Baseline'
                ''
                '- [ ] 1.1 Validate marker retirement (REQ-1, RISK-1) `S`'
            ) -join "`n"
            $path = Join-Path $root 'plan.md'
            Set-Content -LiteralPath $path -Value $plan -NoNewline
            return [pscustomobject]@{ Root = $root; PlanPath = $path }
        }

        function Invoke-MarkerPlan {
            param(
                [Parameter(Mandatory)]$Fixture,
                [Parameter(Mandatory)][ValidateSet('Draft', 'PhaseCrosscheck')][string]$Stage
            )

            $output = pwsh -NoProfile -File $script:canonicalValidator -PlanPath $Fixture.PlanPath -RepoRoot $Fixture.Root -Stage $Stage 2>&1
            return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join "`n") }
        }

        $script:stateBundles = @(Get-ManifestScriptBundle -LeafName 'PlanState.psm1')
        $script:evidenceBundles = @(Get-ManifestScriptBundle -LeafName 'PlanEvidence.psm1')
        $script:validatorBundles = @(Get-ManifestScriptBundle -LeafName 'Test-Plan.ps1')
        $script:fixtures = [System.Collections.Generic.List[string]]::new()
    }

    AfterAll {
        foreach ($root in $script:fixtures) {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:PlanEvidence.MarkerTokenizationAndRetiredArch synchronizes the manifest-derived parser closure' {
        @($script:stateBundles.Skill) |
            Should -Be @('autopilot', 'cep', 'ci', 'cip', 'cr', 'dr', 'pfb', 'si', 'work-hierarchy-sync')
        @($script:validatorBundles.Skill) | Should -Be @('autopilot', 'cep', 'ci', 'cip')
        @($script:evidenceBundles.Skill) | Should -Be @('autopilot', 'cep', 'ci', 'cip', 'cr', 'dr')

        $canonicalStateHash = (Get-FileHash -LiteralPath $script:canonicalState -Algorithm SHA256).Hash
        foreach ($bundle in $script:stateBundles) {
            Test-Path -LiteralPath $bundle.Path -PathType Leaf | Should -BeTrue
            (Get-FileHash -LiteralPath $bundle.Path -Algorithm SHA256).Hash | Should -Be $canonicalStateHash
        }
        $canonicalEvidenceHash = (Get-FileHash -LiteralPath $script:canonicalEvidence -Algorithm SHA256).Hash
        foreach ($bundle in $script:evidenceBundles) {
            (Get-FileHash -LiteralPath $bundle.Path -Algorithm SHA256).Hash | Should -Be $canonicalEvidenceHash
        }
        $canonicalValidatorHash = (Get-FileHash -LiteralPath $script:canonicalValidator -Algorithm SHA256).Hash
        foreach ($bundle in $script:validatorBundles) {
            (Get-FileHash -LiteralPath $bundle.Path -Algorithm SHA256).Hash | Should -Be $canonicalValidatorHash
        }
    }

    It 'test:PlanEvidence.MarkerTokenizationAndRetiredArch extracts every mixed occurrence in every parser bundle' {
        $criteria = '`test:Known` and `file:README.md#exists` and `review:cr` and `review:dr` and `arch:ARCH-Retired` and `bogus:still-red`'
        $expected = @('test:Known', 'file:README.md#exists', 'review:cr', 'review:dr', 'arch:ARCH-Retired', 'bogus:still-red')
        foreach ($bundle in $script:stateBundles) {
            Import-Module $bundle.Path -Force -DisableNameChecking
            (@(Get-TypedEvidenceMarkers -AcceptanceCriteria $criteria) | ConvertTo-Json -Compress) |
                Should -Be ($expected | ConvertTo-Json -Compress)
            (@(Get-TypedEvidenceMarkers -AcceptanceCriteria '`file:a#contains:foo bar`') | ConvertTo-Json -Compress) |
                Should -Be '["file:a#contains:foo bar"]'
            (@(Get-TypedEvidenceMarkers -AcceptanceCriteria '`review:critical` · `review:drift`') | ConvertTo-Json -Compress) |
                Should -Be (@('review:critical', 'review:drift') | ConvertTo-Json -Compress)
            (@(Get-TypedEvidenceMarkers -AcceptanceCriteria 'prose arch:ARCH-Unquoted and test:Known') | ConvertTo-Json -Compress) |
                Should -Be '["arch:ARCH-Unquoted","test:Known"]'
            Remove-Module PlanState -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:PlanEvidence.MarkerTokenizationAndRetiredArch removes the evaluator and ArchReceipt workflow closure' {
        $evidence = Get-Content -LiteralPath $script:canonicalEvidence -Raw
        $validator = Get-Content -LiteralPath $script:canonicalValidator -Raw
        $evidence | Should -Not -Match 'ArchReceipt|Invoke-PlanArchEvidence|Find-ArchCheckForContract'
        $validator | Should -Not -Match 'Invoke-PlanArchEvidence|StartsWith\(''arch:''\)'

        foreach ($pluginName in @('create-implementation-plan', 'continue-implementation')) {
            $manifest = Get-Content -LiteralPath (Join-Path $script:repoRoot "plugins/$pluginName/plugin.json") -Raw
            $manifest | Should -Not -Match 'ArchReceipt\.psm1'
        }
    }

    It 'test:PlanEvidence.MarkerTokenizationAndRetiredArch is red at Draft and PhaseCrosscheck with seeded known evidence' {
        $fixture = New-MarkerPlanFixture -SeedFile
        $script:fixtures.Add($fixture.Root)
        foreach ($stage in @('Draft', 'PhaseCrosscheck')) {
            $result = Invoke-MarkerPlan -Fixture $fixture -Stage $stage
            $result.ExitCode | Should -Not -Be 0
            $result.Output | Should -Match "unknown evidence marker 'arch:ARCH-Retired'"
            $result.Output | Should -Match "unknown evidence marker 'bogus:still-red'"
            $result.Output | Should -Not -Match 'Missing target'
            $result.Output | Should -Not -Match "unknown evidence marker '(test|file|review):"
        }
    }

    It 'test:PlanEvidence.MarkerTokenizationAndRetiredArch keeps retired and missing-file failures visible on an empty root' {
        $fixture = New-MarkerPlanFixture
        $script:fixtures.Add($fixture.Root)
        foreach ($stage in @('Draft', 'PhaseCrosscheck')) {
            $result = Invoke-MarkerPlan -Fixture $fixture -Stage $stage
            $result.ExitCode | Should -Not -Be 0
            $result.Output | Should -Match "unknown evidence marker 'arch:ARCH-Retired'"
            $result.Output | Should -Match "Missing target 'README.md'"
        }
    }
}
