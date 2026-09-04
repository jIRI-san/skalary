#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'review-report test and eval discovery' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        Import-Module (Join-Path $script:repoRoot 'scripts/skalary/PlanState.psm1') -Force -DisableNameChecking
        $script:plan = Resolve-Plan -Reference 'c21cdc' -RepoRoot $script:repoRoot
        $script:planMetadata = Get-PlanMetadata -Path (Join-Path $script:plan.Path 'plan.md') -RepoRoot $script:repoRoot
        $script:expectedEvalIds = @{
            CR = @(
                'eval:ReviewReport.CR.WriterScope'
                'eval:ReviewReport.CR.FreezeBeforeDispatch'
                'eval:ReviewReport.CR.IndependentDispatch'
                'eval:ReviewReport.CR.CompleteDispatch'
                'eval:ReviewReport.CR.NonzeroTaskPlan'
                'eval:ReviewReport.CR.RendererOwnedMarkdown'
                'eval:ReviewReport.CR.FixedPolicyAndRoot'
                'eval:ReviewReport.CR.DegradedArtifactPreservation'
                'eval:ReviewReport.CR.BoundedRetry'
            )
            DR = @(
                'eval:ReviewReport.DR.WriterScope'
                'eval:ReviewReport.DR.FreezeBeforeDispatch'
                'eval:ReviewReport.DR.IndependentDispatch'
                'eval:ReviewReport.DR.CompleteDispatch'
                'eval:ReviewReport.DR.NonzeroTaskPlan'
                'eval:ReviewReport.DR.RendererOwnedMarkdown'
                'eval:ReviewReport.DR.FixedPolicyAndRoot'
                'eval:ReviewReport.DR.DegradedArtifactPreservation'
                'eval:ReviewReport.DR.BoundedRetry'
            )
            Fleet = @(
                'eval:FleetDispatch.CIP.ConsumerContract'
                'eval:FleetDispatch.CI.ConsumerContract'
                'eval:FleetDispatch.Autopilot.ConsumerContract'
                'eval:FleetDispatch.CR.ConsumerContract'
                'eval:FleetDispatch.DR.ConsumerContract'
            )
        }

        function Script:Get-DeclaredCaseIds {
            param(
                [Parameter(Mandatory)][string]$Path,
                [Parameter(Mandatory)][string]$Prefix
            )

            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $Path, [ref]$tokens, [ref]$errors
            )
            @($errors).Count | Should -Be 0 -Because "$Path must be discoverable by Pester"

            return @(
                $ast.FindAll({
                        param($node)
                        $node -is [System.Management.Automation.Language.CommandAst] -and
                        $node.GetCommandName() -eq 'It'
                    }, $true) |
                    ForEach-Object {
                        if ($_.CommandElements.Count -lt 2 -or
                            (Test-CaseDisabled -Case $_)) {
                            return
                        }
                        $nameNode = $_.CommandElements[1]
                        if ($nameNode -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) {
                            return
                        }
                        $name = [string]$nameNode.Value
                        if ($name.StartsWith($Prefix, [System.StringComparison]::Ordinal)) {
                            if (@($_.CommandElements | Where-Object {
                                        $_ -is [System.Management.Automation.Language.CommandParameterAst] -and
                                        $_.ParameterName -in @('ForEach', 'TestCases')
                                    }).Count -gt 0) {
                                throw "Stable structural case '$name' must be one independently executable case, not parameterized."
                            }
                            $name.Split(' ', 2, [System.StringSplitOptions]::RemoveEmptyEntries)[0]
                        }
                    }
            )
        }

        function Script:Test-CaseDisabled {
            param([Parameter(Mandatory)][System.Management.Automation.Language.CommandAst]$Case)

            $current = $Case
            while ($null -ne $current) {
                if ($current -is [System.Management.Automation.Language.CommandAst] -and
                    $current.GetCommandName() -in @('It', 'Describe', 'Context')) {
                    if (@($current.CommandElements | Where-Object {
                                $_ -is [System.Management.Automation.Language.CommandParameterAst] -and
                                $_.ParameterName -in @('Skip', 'Pending')
                            }).Count -gt 0) {
                        return $true
                    }
                }
                $current = $current.Parent
            }
            return $false
        }

        function Script:Get-ReviewTestInventory {
            $tests = [System.Collections.Generic.List[object]]::new()
            foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $script:repoRoot 'tests') `
                        -Recurse -File -Filter '*.Tests.ps1')) {
                $tokens = $null
                $errors = $null
                $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                    $file.FullName, [ref]$tokens, [ref]$errors)
                @($errors).Count | Should -Be 0 -Because "$($file.FullName) must parse"
                foreach ($case in $ast.FindAll({
                            param($node)
                            $node -is [System.Management.Automation.Language.CommandAst] -and
                            $node.GetCommandName() -eq 'It'
                        }, $true)) {
                    if ($case.CommandElements.Count -lt 2 -or
                        $case.CommandElements[1] -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) {
                        continue
                    }
                    $tests.Add([pscustomobject]@{
                            file = [System.IO.Path]::GetRelativePath($script:repoRoot, $file.FullName)
                            test = [string]$case.CommandElements[1].Value
                        })
                }
            }
            return [pscustomobject]@{ tests = $tests.ToArray() }
        }

        function Script:Test-FileHasActiveEvidenceId {
            param(
                [Parameter(Mandatory)][string]$Path,
                [Parameter(Mandatory)][string]$EvidenceId
            )

            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $Path, [ref]$tokens, [ref]$errors
            )
            if (@($errors).Count -gt 0) { return $false }
            foreach ($case in $ast.FindAll({
                        param($node)
                        $node -is [System.Management.Automation.Language.CommandAst] -and
                        $node.GetCommandName() -eq 'It'
                    }, $true)) {
                if (Test-CaseDisabled -Case $case) { continue }
                if ($case.CommandElements.Count -lt 2 -or
                    $case.CommandElements[1] -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) {
                    continue
                }
                $ids = @([regex]::Matches(
                        [string]$case.CommandElements[1].Value,
                        'test:(?:ReviewReport\.[A-Za-z0-9]+|Epic\.ReviewRunConsumerEdgesAndState)(?=$|\s)'
                    ) | ForEach-Object { [string]$_.Value })
                if ($ids -contains $EvidenceId) { return $true }
            }
            return $false
        }
    }

    It 'test:ReviewReport.StructuralEvalDiscovery discovers the exact separately asserted CR and DR review-run cases' {
        $paths = @{
            CR = Join-Path $script:repoRoot 'plugins/code-review/evals/cr.Tests.ps1'
            DR = Join-Path $script:repoRoot 'plugins/design-review/evals/dr.Tests.ps1'
        }

        foreach ($review in @('CR', 'DR')) {
            $actual = @(Get-DeclaredCaseIds -Path $paths[$review] -Prefix "eval:ReviewReport.$review.")
            $actual | Should -Be $script:expectedEvalIds[$review]
            @($actual | Sort-Object -Unique).Count | Should -Be $actual.Count
        }

        $required = Get-Content -LiteralPath (Join-Path $script:repoRoot 'tools/structural-eval-required.json') -Raw |
            ConvertFrom-Json
        [string]$required.schema | Should -Be 'skalary/structural-eval-required@1'
        @($required.caseIds) |
            Should -Be @($script:expectedEvalIds.CR + $script:expectedEvalIds.Fleet + $script:expectedEvalIds.DR)
        $inventory = Get-ReviewTestInventory
        @($inventory.tests | Where-Object { [string]$_.test -match 'test:ReviewReport\.StructuralEvalEnforcement(?=$|\s)' }).Count |
            Should -Be 1 -Because 'the runtime gate must be executed against missing, skipped, and duplicate required outcomes'
    }

    It 'test:ReviewReport.TestAndEvalDiscovery discovers every required ordinary marker and the exact structural eval sets' {
        $required = @(
            foreach ($requirement in $script:planMetadata.Requirements.Values) {
                foreach ($marker in (Get-TypedEvidenceMarkers -AcceptanceCriteria ([string]$requirement.AcceptanceCriteria))) {
                    [string]$marker
                }
            }
        ) | Where-Object {
            $_ -match '^test:(?:ReviewReport\.[A-Za-z0-9]+|Epic\.ReviewRunConsumerEdgesAndState)$'
        # The local-first baseline retired the workflow-only dedicated gate.
        } | Where-Object {
            $_ -ne 'test:ReviewReport.ConsumerInstallDedicatedGate'
        } | Sort-Object -Unique
        $required = @($required)
        $inventory = Get-ReviewTestInventory

        $required.Count | Should -BeGreaterThan 0
        foreach ($id in $required) {
            $owners = @($inventory.tests | Where-Object {
                    @([regex]::Matches(
                            [string]$_.test,
                            'test:(?:ReviewReport\.[A-Za-z0-9]+|Epic\.ReviewRunConsumerEdgesAndState)(?=$|\s)'
                        ) | ForEach-Object { [string]$_.Value }) -contains $id
                })
            $owners.Count | Should -BeGreaterOrEqual 1 -Because "$id must have a discovered ordinary-test owner"
            @($owners | Where-Object {
                    Test-FileHasActiveEvidenceId -Path (Join-Path $script:repoRoot ([string]$_.file)) -EvidenceId $id
                }).Count | Should -BeGreaterOrEqual 1 -Because "$id must have a non-skipped ordinary-test owner"
        }

        foreach ($review in @('CR', 'DR')) {
            $path = Join-Path $script:repoRoot "plugins/$(
                if ($review -eq 'CR') { 'code-review/evals/cr.Tests.ps1' } else { 'design-review/evals/dr.Tests.ps1' }
            )"
            @(Get-DeclaredCaseIds -Path $path -Prefix "eval:ReviewReport.$review.") |
                Should -Be $script:expectedEvalIds[$review]
        }
    }

    It 'test:ReviewReport.NoNewRuntimeDependency keeps the review engine package-free and unvendored' {
        $package = Get-Content -LiteralPath (Join-Path $script:repoRoot 'package.json') -Raw | ConvertFrom-Json
        foreach ($property in @('dependencies', 'devDependencies', 'optionalDependencies', 'peerDependencies')) {
            @($package.PSObject.Properties.Name) | Should -Not -Contain $property
        }

        foreach ($lockName in @('package-lock.json', 'npm-shrinkwrap.json', 'pnpm-lock.yaml', 'yarn.lock')) {
            Test-Path -LiteralPath (Join-Path $script:repoRoot $lockName) |
                Should -BeFalse -Because 'review reporting uses native PowerShell and JSON Schema only'
        }

        foreach ($plugin in @('code-review', 'design-review')) {
            $pluginRoot = Join-Path $script:repoRoot "plugins/$plugin"
            $manifest = Get-Content -LiteralPath (Join-Path $pluginRoot 'plugin.json') -Raw | ConvertFrom-Json
            @($manifest.dependencies).Count | Should -Be 0
            @(Get-ChildItem -LiteralPath $pluginRoot -Recurse -File | Where-Object {
                    $_.Name -in @('package.json', 'package-lock.json', 'npm-shrinkwrap.json', 'pnpm-lock.yaml', 'yarn.lock')
                }).Count | Should -Be 0
            @(Get-ChildItem -LiteralPath $pluginRoot -Recurse -Directory | Where-Object {
                    $_.Name -in @('vendor', 'node_modules')
                }).Count | Should -Be 0
        }
    }
}
