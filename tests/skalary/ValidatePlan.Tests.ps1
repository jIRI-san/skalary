#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Validate-Plan stage gate' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:scriptPath = Join-Path $script:repoRoot 'scripts/skalary/Validate-Plan.ps1'
        $script:fixturesRoot = Join-Path $PSScriptRoot 'fixtures'

        function New-StagedPlan {
            <#
            .SYNOPSIS
                Writes a plan fixture into a temp folder with the given stage anchor (or none).
            #>
            param(
                [Parameter(Mandatory)][string]$Fixture,
                [string]$Stage
            )

            $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("validateplan-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $dir -Force | Out-Null

            $body = (Get-Content -LiteralPath (Join-Path $script:fixturesRoot $Fixture) -Raw) -replace "`r`n", "`n"
            if ($Stage) {
                $lines = [System.Collections.Generic.List[string]]::new()
                $lines.AddRange([string[]]$body.Split("`n"))
                $lines.Insert(1, "<!-- cip-stage: $Stage -->")
                $body = $lines -join "`n"
            }

            $file = Join-Path $dir 'plan.md'
            Set-Content -LiteralPath $file -Value $body -Encoding utf8NoBOM
            return $file
        }

        function Invoke-ValidatePlan {
            param(
                [string]$PlanPath,
                [string]$RepoRoot = $script:repoRoot
            )

            $arguments = @('-NoProfile', '-File', $script:scriptPath, '-RepoRoot', $RepoRoot)
            if ($PlanPath) { $arguments += @('-PlanPath', $PlanPath) }

            $output = @(& pwsh @arguments 2>&1)
            return [pscustomobject]@{
                ExitCode = $LASTEXITCODE
                Output   = ($output | ForEach-Object { "$_" }) -join "`n"
            }
        }
    }

    It 'test:ValidatePlan.ScaffoldedPlanReportsSkipped skips a scaffold with a signal no check can read as a pass' {
        $plan = New-StagedPlan -Fixture 'plan-valid.md' -Stage 'scaffolded'
        try {
            $result = Invoke-ValidatePlan -PlanPath $plan

            $result.ExitCode | Should -Be 0 -Because 'a fresh scaffold must not turn the test command red'
            $result.Output | Should -Match 'PLAN-VALIDATION: SKIPPED stage=scaffolded'
            $result.Output | Should -Not -Match 'Test-Plan passed' -Because 'nothing was actually validated'
        }
        finally {
            Remove-Item -LiteralPath (Split-Path $plan) -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:ValidatePlan.ScaffoldedPlanReportsSkipped reports a skip when no plan reaches the floor' {
        # Default resolution, not an explicit path: a repo whose only plans are scaffolds must still say
        # so out loud rather than exiting 0 as though a plan had been checked.
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("validateplanroot-" + [guid]::NewGuid().ToString('N'))
        try {
            $planDir = Join-Path $root 'docs/implementation-plans/2026-08-02-aaaaaa-scaffold'
            $scriptDir = Join-Path $root 'scripts/skalary'
            New-Item -ItemType Directory -Path $planDir -Force | Out-Null
            New-Item -ItemType Directory -Path $scriptDir -Force | Out-Null
            foreach ($name in @('Validate-Plan.ps1', 'PlanState.psm1')) {
                Copy-Item -LiteralPath (Join-Path $script:repoRoot "scripts/skalary/$name") -Destination (Join-Path $scriptDir $name)
            }

            $source = New-StagedPlan -Fixture 'plan-valid.md' -Stage 'scaffolded'
            Copy-Item -LiteralPath $source -Destination (Join-Path $planDir 'plan.md')
            Remove-Item -LiteralPath (Split-Path $source) -Recurse -Force -ErrorAction SilentlyContinue

            $output = @(& pwsh -NoProfile -File (Join-Path $scriptDir 'Validate-Plan.ps1') -RepoRoot $root 2>&1)
            $exitCode = $LASTEXITCODE

            $exitCode | Should -Be 0
            (($output | ForEach-Object { "$_" }) -join "`n") | Should -Match 'PLAN-VALIDATION: SKIPPED reason=no-plan-at-or-above-floor'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:ValidatePlan.ScaffoldedPlanReportsSkipped keeps both npm test legs on one floor' {
        # npm test validates plans twice — Validate-Plan.ps1 for the working plan, scripts/validate.ps1
        # for the whole tree. A floor honoured by only one of them is cosmetic: the below-floor plan is
        # skipped by one leg and hard-failed by the other, so the drafting session stays red and the
        # floor only changes which leg reports it.
        Import-Module (Join-Path $script:repoRoot 'scripts/skalary/PlanState.psm1') -Force -DisableNameChecking
        try {
            $scaffold = New-StagedPlan -Fixture 'plan-bad-evidence.md' -Stage 'scaffolded'
            $drafted = New-StagedPlan -Fixture 'plan-bad-evidence.md' -Stage 'drafted'
            try {
                $skip = Get-PlanValidationDecision -Path $scaffold
                $skip.ShouldValidate | Should -BeFalse
                $skip.Signal | Should -Match '^PLAN-VALIDATION: SKIPPED '

                $check = Get-PlanValidationDecision -Path $drafted
                $check.ShouldValidate | Should -BeTrue
                $check.Signal | Should -Match '^PLAN-VALIDATION: VALIDATING '

                $unknown = New-StagedPlan -Fixture 'plan-valid.md' -Stage 'draftd'
                try {
                    { Get-PlanValidationDecision -Path $unknown } |
                        Should -Throw -ExpectedMessage '*Unrecognised plan stage*'
                }
                finally {
                    Remove-Item -LiteralPath (Split-Path $unknown) -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            finally {
                Remove-Item -LiteralPath (Split-Path $scaffold) -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath (Split-Path $drafted) -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        finally {
            Remove-Module PlanState -Force -ErrorAction SilentlyContinue
        }

        foreach ($entryPoint in @('scripts/skalary/Validate-Plan.ps1', 'scripts/validate.ps1')) {
            $source = Get-Content -LiteralPath (Join-Path $script:repoRoot $entryPoint) -Raw
            $source | Should -Match 'Get-PlanValidationDecision' -Because "$entryPoint must not carry its own floor"
        }
    }

    It 'test:ValidatePlan.DraftedPlanStillValidated validates a drafted plan and still fails a broken one' {
        $good = New-StagedPlan -Fixture 'plan-valid.md' -Stage 'drafted'
        $bad = New-StagedPlan -Fixture 'plan-bad-evidence.md' -Stage 'drafted'
        try {
            $passing = Invoke-ValidatePlan -PlanPath $good
            $passing.ExitCode | Should -Be 0
            $passing.Output | Should -Match 'PLAN-VALIDATION: VALIDATING stage=drafted'
            $passing.Output | Should -Match 'Test-Plan passed'

            # The half that matters: reaching the floor must mean the plan is really checked, not waved
            # through with a friendlier message.
            $failing = Invoke-ValidatePlan -PlanPath $bad
            $failing.ExitCode | Should -Not -Be 0
            $failing.Output | Should -Match 'Invalid file evidence assertion'
        }
        finally {
            Remove-Item -LiteralPath (Split-Path $good) -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath (Split-Path $bad) -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:ValidatePlan.DraftedPlanStillValidated treats a plan with no stage anchor as drafted' {
        # RISK-7: plans written by an older installed copy carry no anchor. They must keep being
        # validated, so a missing anchor is the default stage rather than an unknown one.
        $plan = New-StagedPlan -Fixture 'plan-valid.md'
        try {
            (Get-Content -LiteralPath $plan -Raw) | Should -Not -Match 'cip-stage'

            $result = Invoke-ValidatePlan -PlanPath $plan
            $result.ExitCode | Should -Be 0
            $result.Output | Should -Match 'PLAN-VALIDATION: VALIDATING stage=drafted'
            $result.Output | Should -Match 'Test-Plan passed'
        }
        finally {
            Remove-Item -LiteralPath (Split-Path $plan) -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:ValidatePlan.UnknownStageFailsLoud refuses to resolve an unrecognised stage to a skip' {
        foreach ($bad in @('draftd', 'in-review', 'dr-round')) {
            $plan = New-StagedPlan -Fixture 'plan-valid.md' -Stage $bad
            try {
                $result = Invoke-ValidatePlan -PlanPath $plan

                $result.ExitCode | Should -Not -Be 0 -Because "'$bad' must not exit 0 while checking nothing"
                $result.Output | Should -Match 'Unrecognised plan stage'
                $result.Output | Should -Match ([regex]::Escape($plan))
            }
            finally {
                Remove-Item -LiteralPath (Split-Path $plan) -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
