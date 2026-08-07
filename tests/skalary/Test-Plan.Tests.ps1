#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Test-Plan validator' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $scriptPath = Join-Path $repoRoot 'scripts/skalary/Test-Plan.ps1'
        $fixturesRoot = Join-Path $PSScriptRoot 'fixtures'

        # One child pwsh per case bought nothing these assertions use: they read an exit
        # code and merged output, both of which a fresh runspace reproduces without paying
        # process startup sixteen times.
        Import-Module (Join-Path $PSScriptRoot '..' 'SuiteScriptHost.psm1') -Force -DisableNameChecking

        $invokeTestPlan = {
            param(
                [Parameter(Mandatory)]
                [string]$PlanPath,

                [ValidateSet('Draft', 'PhaseCrosscheck', 'PlanCrosscheck')]
                [string]$Stage = 'Draft'
            )

            return Invoke-SuiteScript -ScriptPath $scriptPath -Parameters @{
                PlanPath = $PlanPath
                RepoRoot = $repoRoot
                Stage = $Stage
            }
        }.GetNewClosure()
    }

    It 'passes a valid fixture' {
        $result = & $invokeTestPlan -PlanPath (Join-Path $fixturesRoot 'plan-valid.md')
        $result.ExitCode | Should -Be 0
    }

    It 'fails orphan requirement references' {
        $result = & $invokeTestPlan -PlanPath (Join-Path $fixturesRoot 'plan-orphan-req.md')
        $result.ExitCode | Should -Not -Be 0
        $result.Output | Should -Match 'unknown requirement'
    }

    It 'fails when evidence marker is missing on opted-in plan' {
        $result = & $invokeTestPlan -PlanPath (Join-Path $fixturesRoot 'plan-missing-evidence.md')
        $result.ExitCode | Should -Not -Be 0
        $result.Output | Should -Match 'no typed evidence marker'
    }

    It 'fails invalid file evidence assertion vocabulary' {
        $result = & $invokeTestPlan -PlanPath (Join-Path $fixturesRoot 'plan-bad-evidence.md')
        $result.ExitCode | Should -Not -Be 0
        $result.Output | Should -Match 'Invalid file evidence assertion'
    }

    It 'fails unknown dependency targets' {
        $result = & $invokeTestPlan -PlanPath (Join-Path $fixturesRoot 'plan-bad-deps.md')
        $result.ExitCode | Should -Not -Be 0
        $result.Output | Should -Match 'depends on unknown step'
    }

    It 'warns when phase budget exceeds advisory cap' {
        $result = & $invokeTestPlan -PlanPath (Join-Path $fixturesRoot 'plan-budget-overflow.md')
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'phase-budget points'
    }

    It 'test:phase-budget-defaults-to-6 uses a cap of 6 when the marker is absent' {
        $result = & $invokeTestPlan -PlanPath (Join-Path $fixturesRoot 'plan-budget-overflow.md')
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'uses 8 phase-budget points \(advisory cap is 6\)'
    }

    It 'test:phase-budget-defaults-to-6 warns and falls back on an out-of-range marker' {
        $result = & $invokeTestPlan -PlanPath (Join-Path $fixturesRoot 'plan-budget-marker-invalid.md')
        # Plan text is untrusted: an unparseable cap must warn and default, never crash the validator.
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'Invalid <!-- phase-budget-points: 99999999999999 --> marker'
        $result.Output | Should -Match 'uses 8 phase-budget points \(advisory cap is 6\)'
    }

    It 'test:phase-budget-marker-honored reads the declared phase-budget-points cap' {
        $result = & $invokeTestPlan -PlanPath (Join-Path $fixturesRoot 'plan-budget-marker.md')
        $result.ExitCode | Should -Be 0
        # Phase 1 is 8 points and the plan declares a cap of 8, so the override must silence it.
        $result.Output | Should -Not -Match 'Phase 1: Within the declared budget uses'
        # Phase 2 is 9 points, so it still warns — and against the declared cap, not the default.
        $result.Output | Should -Match 'Phase 2: Over the declared budget uses 9 phase-budget points \(advisory cap is 8\)'
        $result.Output | Should -Not -Match 'advisory cap is 6'
    }

    It 'warns when plan is oversize' {
        $tempPlan = Join-Path ([System.IO.Path]::GetTempPath()) ("plan-oversize-" + [System.Guid]::NewGuid().ToString('N') + '.md')
        $oversizeContent = @(
            '# 908: Oversize fixture'
            '<!-- evidence: required -->'
            ''
            '## Requirements'
            ''
            '| ID | Requirement | Acceptance Criteria | Phases/Steps |'
            '|----|-------------|---------------------|--------------|'
            '| REQ-1 | Oversize warning emits | `test:Test-Plan.Size.Warns` | 1.1 |'
            ''
            '## Risks'
            ''
            '| ID | Risk | Likelihood | Impact | Mitigation | Steps |'
            '|----|------|------------|--------|------------|-------|'
            '| RISK-1 | Sample risk | Low | Low | Sample mitigation | 1.1 |'
            ''
            '## Phase 1: Oversize'
            ''
            '- [ ] 1.1 Step (REQ-1, RISK-1) `S`'
        )
        $oversizeContent += (1..420 | ForEach-Object { "padding line $_" })
        Set-Content -LiteralPath $tempPlan -Value ($oversizeContent -join "`n") -Encoding utf8
        try {
            $result = & $invokeTestPlan -PlanPath $tempPlan
            $result.ExitCode | Should -Be 0
            $result.Output | Should -Match 'Plan size warning'
        }
        finally {
            if (Test-Path -LiteralPath $tempPlan -PathType Leaf) {
                Remove-Item -LiteralPath $tempPlan -Force
            }
        }
    }

    It 'skips fenced block IDs and markers' {
        $result = & $invokeTestPlan -PlanPath (Join-Path $fixturesRoot 'plan-fenced-ids.md')
        $result.ExitCode | Should -Be 0
    }

    It 'rejects path escapes for file markers' {
        $result = & $invokeTestPlan -PlanPath (Join-Path $fixturesRoot 'plan-path-escape.md')
        $result.ExitCode | Should -Not -Be 0
        $result.Output | Should -Match 'outside repository root|must be relative'
    }

    It 'treats legacy plans as warn-only for strict evidence checks' {
        $plan003 = Join-Path $repoRoot 'docs/implementation-plans/archived/003-autopilot-skill-extraction/plan.md'
        $plan004 = Join-Path $repoRoot 'docs/implementation-plans/archived/004-process-pr-comments/plan.md'
        (& $invokeTestPlan -PlanPath $plan003).ExitCode | Should -Be 0
        (& $invokeTestPlan -PlanPath $plan004).ExitCode | Should -Be 0
    }
}

Describe 'PlanState Get-PlanMetadata' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $modulePath = Join-Path $repoRoot 'scripts/skalary/PlanState.psm1'
        Import-Module $modulePath -Force -DisableNameChecking
        $fixturesRoot = Join-Path $PSScriptRoot 'fixtures'
        $validPlan = Join-Path $fixturesRoot 'plan-valid.md'
    }

    AfterAll {
        Remove-Module PlanState -Force -ErrorAction SilentlyContinue
    }

    It 'test:planstate-parser-parity parses identically under a non-default RepoRoot' {
        $default = Get-PlanMetadata -Path $validPlan -RepoRoot $repoRoot

        $altRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("planstate-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $altRoot -Force | Out-Null
        try {
            $alt = Get-PlanMetadata -Path $validPlan -RepoRoot $altRoot

            $alt.Steps.Count | Should -Be $default.Steps.Count
            $alt.Requirements.Keys.Count | Should -Be $default.Requirements.Keys.Count
            $alt.Risks.Keys.Count | Should -Be $default.Risks.Keys.Count
            ($alt.Steps | ForEach-Object { $_.Id }) -join ',' | Should -Be (($default.Steps | ForEach-Object { $_.Id }) -join ',')
        }
        finally {
            Remove-Item -LiteralPath $altRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:planstate-parser-parity honors the explicit RepoRoot in returned metadata' {
        $altRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("planstate-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $altRoot -Force | Out-Null
        try {
            $meta = Get-PlanMetadata -Path $validPlan -RepoRoot $altRoot
            $meta.RepoRoot | Should -Be ([System.IO.Path]::GetFullPath($altRoot))
        }
        finally {
            Remove-Item -LiteralPath $altRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'requires the RepoRoot parameter' {
        $repoRootParam = (Get-Command Get-PlanMetadata).Parameters['RepoRoot']
        $mandatory = $repoRootParam.Attributes |
            Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
            ForEach-Object { $_.Mandatory }
        $mandatory | Should -Contain $true
    }
}
