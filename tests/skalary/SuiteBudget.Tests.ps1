#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'suite budget' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:budgetPath = Join-Path $script:repoRoot 'tools/suite-budget.psd1'
        $script:budget = $null
        if (Test-Path -LiteralPath $script:budgetPath -PathType Leaf) {
            $script:budget = Import-PowerShellDataFile -LiteralPath $script:budgetPath
        }

        function Get-PlanDecisionsText {
            param([string]$PlanId)

            $planRoot = Join-Path $script:repoRoot 'docs/implementation-plans'
            if (-not (Test-Path -LiteralPath $planRoot -PathType Container)) { return $null }

            foreach ($plan in (Get-ChildItem -LiteralPath $planRoot -Recurse -File -Filter 'plan.md')) {
                $head = Get-Content -LiteralPath $plan.FullName -TotalCount 20 -Raw
                if ($head -match "plan-id:\s*$([regex]::Escape($PlanId))\b") {
                    $decisions = Join-Path $plan.DirectoryName 'assets/decisions.md'
                    if (-not (Test-Path -LiteralPath $decisions -PathType Leaf)) {
                        $decisions = Join-Path $plan.DirectoryName 'decisions.md'
                    }
                    if (Test-Path -LiteralPath $decisions -PathType Leaf) {
                        return (Get-Content -LiteralPath $decisions -Raw)
                    }
                }
            }
            return $null
        }
    }

    It 'test:SuiteBudget.AbsoluteCapIs900 caps the ceiling at 900s and keeps the target under it' {
        Test-Path -LiteralPath $script:budgetPath -PathType Leaf |
            Should -BeTrue -Because 'tools/suite-budget.psd1 is the bound ceiling REQ-2 requires'

        [int]$script:budget.AbsoluteCapSeconds | Should -Be 900
        [int]$script:budget.HardCeilingSeconds | Should -BeGreaterThan 0
        [int]$script:budget.HardCeilingSeconds |
            Should -BeLessOrEqual ([int]$script:budget.AbsoluteCapSeconds) -Because 'no ceiling may exceed the absolute cap'
        [int]$script:budget.TargetSeconds | Should -BeGreaterThan 0
        [int]$script:budget.TargetSeconds |
            Should -BeLessOrEqual ([int]$script:budget.HardCeilingSeconds) -Because 'the target sits under the ceiling'
    }

    It 'test:SuiteBudget.CeilingCannotBeRaisedWithoutJustification rejects a raise with no recorded justification' {
        [int]$script:budget.BoundCeilingSeconds |
            Should -Be 600 -Because 'the ceiling bound in phase 1 is the immutable reference the hard ceiling is checked against'
        [int]$script:budget.MaxCeilingRaises | Should -Be 1

        $raises = @($script:budget.CeilingRaises)

        if ([int]$script:budget.HardCeilingSeconds -le [int]$script:budget.BoundCeilingSeconds) {
            $raises.Count | Should -Be 0 -Because 'a ceiling at or under the bound value was never raised'
            return
        }

        $raises.Count |
            Should -BeLessOrEqual ([int]$script:budget.MaxCeilingRaises) -Because 'the escape hatch may be used once'
        $raises.Count | Should -Be 1 -Because 'a raised ceiling must record the raise that produced it'

        $raise = $raises[0]
        [int]$raise.Seconds |
            Should -Be ([int]$script:budget.HardCeilingSeconds) -Because 'the recorded raise must be the ceiling in force'
        [int]$raise.Seconds | Should -BeLessOrEqual ([int]$script:budget.AbsoluteCapSeconds)
        [string]$raise.Step | Should -Not -BeNullOrEmpty
        [string]$raise.Justification | Should -Not -BeNullOrEmpty

        $planId = [string]$script:budget.JustificationPlanId
        $planId | Should -Not -BeNullOrEmpty
        $decisions = Get-PlanDecisionsText -PlanId $planId
        $decisions | Should -Not -BeNullOrEmpty -Because "plan '$planId' must carry the decisions record the justification lives in"
        $decisions |
            Should -Match ([regex]::Escape([string]$raise.Justification)) -Because 'the justification must be written into the plan decisions, not only into the budget file'
    }

    It 'test:SuiteBudget.MeasuresFullNpmTest budgets the whole npm test command, not the Pester leg alone' {
        [string]$script:budget.MeasuredCommand | Should -Be 'npm test'

        $packageJson = Get-Content -LiteralPath (Join-Path $script:repoRoot 'package.json') -Raw | ConvertFrom-Json
        $testScript = [string]$packageJson.scripts.test
        $testScript | Should -Not -BeNullOrEmpty

        $legs = @($script:budget.MeasuredLegs)
        $legs.Count | Should -BeGreaterThan 1
        foreach ($leg in $legs) {
            $testScript |
                Should -Match ([regex]::Escape([string]$leg)) -Because "the budgeted command must cover the '$leg' leg"
        }
    }
}
