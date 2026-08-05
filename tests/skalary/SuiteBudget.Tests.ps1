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
                $head = (Get-Content -LiteralPath $plan.FullName -TotalCount 20) -join "`n"
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

        function Get-CurrentPlatformKey {
            if ($IsWindows) { return 'Windows' }
            if ($IsMacOS) { return 'MacOS' }
            return 'Linux'
        }

        function Get-PlatformEntries {
            $script:budget | Should -Not -BeNullOrEmpty -Because 'tools/suite-budget.psd1 must exist and parse'
            $script:budget.Keys |
                Should -Contain 'Platforms' -Because 'REQ-2 binds the ceiling per platform; without the entries every ceiling assertion below would pass over an empty set'

            $platforms = $script:budget.Platforms
            $entries = [ordered]@{}
            foreach ($key in @($platforms.Keys | Sort-Object)) { $entries[$key] = $platforms[$key] }
            @($entries.Keys).Count |
                Should -BeGreaterThan 0 -Because 'an empty platform set would make the ceiling assertions vacuous'
            return $entries
        }
    }

    It 'test:SuiteBudget.CeilingIsPerPlatform gives every platform its own ceiling and leaves none to a shared default' {
        Test-Path -LiteralPath $script:budgetPath -PathType Leaf |
            Should -BeTrue -Because 'tools/suite-budget.psd1 is the bound ceiling REQ-2 requires'

        $script:budget.Keys |
            Should -Contain 'Platforms' -Because 'REQ-2 binds the ceiling per platform, not once for the repo'

        foreach ($blind in @('HardCeilingSeconds', 'TargetSeconds', 'CeilingRaises')) {
            $script:budget.Keys |
                Should -Not -Contain $blind -Because "a repo-wide '$blind' lets a caller enforce a ceiling without knowing which platform it measured"
        }

        $entries = Get-PlatformEntries
        @($entries.Keys).Count |
            Should -BeGreaterThan 1 -Because 'a single entry is a shared ceiling wearing a platform name'

        foreach ($platform in @('Linux', 'Windows')) {
            $entries.Keys |
                Should -Contain $platform -Because "CI runs the suite on $platform, so $platform needs a ceiling of its own"
        }

        foreach ($platform in $entries.Keys) {
            $entry = $entries[$platform]
            foreach ($key in @('HardCeilingSeconds', 'TargetSeconds', 'CeilingRaises')) {
                $entry.Keys |
                    Should -Contain $key -Because "platform '$platform' must carry its own $key"
            }
        }

        $current = Get-CurrentPlatformKey
        $entries.Keys |
            Should -Contain $current -Because "the runner enforces the entry for the platform it runs on; add a '$current' entry rather than letting it run unbudgeted"
    }

    It 'test:SuiteBudget.AbsoluteCapIs900 caps the ceiling at 900s and keeps the target under it' {
        Test-Path -LiteralPath $script:budgetPath -PathType Leaf |
            Should -BeTrue -Because 'tools/suite-budget.psd1 is the bound ceiling REQ-2 requires'

        [int]$script:budget.AbsoluteCapSeconds | Should -Be 900

        $entries = Get-PlatformEntries
        foreach ($platform in $entries.Keys) {
            $entry = $entries[$platform]
            [int]$entry.HardCeilingSeconds |
                Should -BeGreaterThan 0 -Because "platform '$platform' needs a real ceiling"
            [int]$entry.HardCeilingSeconds |
                Should -BeLessOrEqual ([int]$script:budget.AbsoluteCapSeconds) -Because "no ceiling may exceed the absolute cap ('$platform')"
            [int]$entry.TargetSeconds |
                Should -BeGreaterThan 0 -Because "platform '$platform' needs a real target"
            [int]$entry.TargetSeconds |
                Should -BeLessOrEqual ([int]$entry.HardCeilingSeconds) -Because "the target sits under the ceiling ('$platform')"
        }
    }

    It 'test:SuiteBudget.CeilingCannotBeRaisedWithoutJustification rejects a raise with no recorded justification' {
        [int]$script:budget.BoundCeilingSeconds |
            Should -Be 600 -Because 'the ceiling bound in phase 1 is the immutable reference every platform ceiling is checked against'
        [int]$script:budget.MaxCeilingRaises | Should -Be 1

        $entries = Get-PlatformEntries
        $decisions = $null

        # Totalled and asserted before the per-platform checks: a per-platform failure below must not
        # short-circuit the "once across the whole plan" rule.
        $totalRaises = 0
        foreach ($platform in $entries.Keys) { $totalRaises += @($entries[$platform].CeilingRaises).Count }
        $totalRaises |
            Should -BeLessOrEqual ([int]$script:budget.MaxCeilingRaises) -Because 'the escape hatch may be used once across the whole plan, not once per platform'

        foreach ($platform in $entries.Keys) {
            $entry = $entries[$platform]
            $raises = @($entry.CeilingRaises)

            if ([int]$entry.HardCeilingSeconds -le [int]$script:budget.BoundCeilingSeconds) {
                $raises.Count |
                    Should -Be 0 -Because "a ceiling at or under the bound value was never raised ('$platform')"
                continue
            }

            $raises.Count |
                Should -Be 1 -Because "a raised ceiling must record the raise that produced it ('$platform')"

            $raise = $raises[0]
            [int]$raise.Seconds |
                Should -Be ([int]$entry.HardCeilingSeconds) -Because "the recorded raise must be the ceiling in force ('$platform')"
            [int]$raise.Seconds | Should -BeLessOrEqual ([int]$script:budget.AbsoluteCapSeconds)
            [string]$raise.Step | Should -Not -BeNullOrEmpty
            [string]$raise.Justification | Should -Not -BeNullOrEmpty

            if ($null -eq $decisions) {
                $planId = [string]$script:budget.JustificationPlanId
                $planId | Should -Not -BeNullOrEmpty
                $decisions = Get-PlanDecisionsText -PlanId $planId
                $decisions | Should -Not -BeNullOrEmpty -Because "plan '$planId' must carry the decisions record the justification lives in"
            }
            $decisions |
                Should -Match ([regex]::Escape([string]$raise.Justification)) -Because "the justification must be written into the plan decisions, not only into the budget file ('$platform')"
        }
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
