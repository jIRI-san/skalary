#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'App CI worker boundaries and integration' {
    BeforeAll {
        $script:repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
        $script:resultScript = Join-Path $script:repo 'scripts\skalary\Test-AppCiWorkerResult.ps1'
        $script:rootSkill = Get-Content (Join-Path $script:repo 'plugins\continue-implementation\skills\ci\SKILL.md') -Raw
        $script:guide = Get-Content (Join-Path $script:repo 'plugins\continue-implementation\skills\ci\assets\app-coordinator.md') -Raw
        $script:launch = Get-Content (Join-Path $script:repo 'plugins\autopilot\scripts\launch.ps1') -Raw
        function Invoke-FixtureGit([string]$Root, [string[]]$Argument) {
            $output = @(& git -C $Root @Argument 2>&1)
            if ($LASTEXITCODE -ne 0) { throw "Fixture git failed: $($output -join ' ')" }
            return ($output -join "`n").Trim()
        }

        function Commit-Worker {
            Invoke-FixtureGit $script:worker @('add', '.') | Out-Null
            Invoke-FixtureGit $script:worker @('commit', '-qm', 'worker') | Out-Null
        }
        function Complete-Step([string]$Id) {
            $text = Get-Content $script:workerPlan -Raw
            $text = $text.Replace("- [ ] $Id ", "- [x] $Id ")
            Set-Content $script:workerPlan $text -NoNewline
        }
        function Result([int]$Phase = 1) {
            & $script:resultScript -IntegrationRoot $script:integration -WorkerRoot $script:worker `
                -PlanReference abc123 -ExpectedStartCommit $script:start -Phase $Phase
        }
    }
    BeforeEach {
        $script:scratch = Join-Path $script:repo ('tests\.app-ci-' + [guid]::NewGuid().ToString('N'))
        $script:integration = Join-Path $script:scratch 'integration'
        $script:worker = Join-Path $script:scratch 'worker'
        $script:folder = 'standalone-2026-01-01-abc123-fixture'
        $planDir = Join-Path $script:integration "docs\implementation-plans\$script:folder"
        $assets = Join-Path $planDir 'assets'
        New-Item -ItemType Directory $assets -Force | Out-Null
        Set-Content (Join-Path $planDir 'plan.md') @'
# abc123: Fixture
<!-- plan-id: abc123 -->
<!-- cip-stage: drafted -->
<!-- planning-confirmed: pending -->

## Assets

- Intent - [assets/intent.md](assets/intent.md)
- Requirements - [assets/requirements.md](assets/requirements.md)
- Risks - [assets/risks.md](assets/risks.md)
- Decisions - [assets/decisions.md](assets/decisions.md)

## Phase 1: First

- [ ] 1.1 First AI `S`
- [ ] 1.2 Human @human `S`
- [ ] 1.3 Dependent [after: 1.2] `S`

## Phase 2: Second

- [ ] 2.1 Later AI `S`
'@
        Set-Content (Join-Path $assets 'intent.md') @'
# Intent

## Goal

Preserve fixture.

## Desired outcome

Scoped committed progress.

## Success signals

Exact-head verified acceptance.

## Non-goals

No unrelated work.

## Definition of done

Current evidence and committed scope.
'@
        Set-Content (Join-Path $assets 'design.md') @'
# Design

## Components and boundaries

Existing Git and plan helpers.

## Program flow

```mermaid
flowchart TD
  A[Confirmed source] --> B[Scoped worker]
```
'@
        Set-Content (Join-Path $assets 'requirements.md') "# Requirements`n`n| ID | Requirement | Acceptance Criteria | Phases/Steps |`n|---|---|---|---|`n| REQ-1 | Fixture | file:plan.md#exists | 1.1 |"
        Set-Content (Join-Path $assets 'risks.md') "# Risks`n`n| ID | Risk | Likelihood | Impact | Mitigation | Steps |`n|---|---|---|---|---|---|`n| RISK-1 | Drift | Low | Low | Preserve | 1.1 |"
        Set-Content (Join-Path $assets 'decisions.md') "# Decisions`n`n- Preserve fixture."
        Set-Content (Join-Path $script:integration '.gitattributes') '* text=auto eol=lf'
        Invoke-FixtureGit $script:integration @('init', '-q', '--initial-branch=main') | Out-Null
        Invoke-FixtureGit $script:integration @('config', 'user.name', 'Fixture') | Out-Null
        Invoke-FixtureGit $script:integration @('config', 'user.email', 'fixture@example.invalid') | Out-Null
        & (Join-Path $script:repo '.github\skills\cip\scripts\Set-PlanStage.ps1') `
            -PlanFile (Join-Path $planDir 'plan.md') -Stage drafted -ConfirmPlanningContext | Out-Null
        Invoke-FixtureGit $script:integration @('add', '.') | Out-Null
        Invoke-FixtureGit $script:integration @('commit', '-qm', 'confirmed') | Out-Null
        $script:start = Invoke-FixtureGit $script:integration @('rev-parse', 'HEAD')
        Invoke-FixtureGit $script:integration @('worktree', 'add', '-q', '-b', 'worker', $script:worker, $script:start) | Out-Null
        $script:workerPlan = Join-Path $script:worker "docs\implementation-plans\$script:folder\plan.md"
    }
    AfterEach {
        if (Test-Path $script:scratch) {
            Remove-Item -LiteralPath $script:scratch -Recurse -Force
        }
    }

    It 'test:AppCi.WorkerKickoff binds exact full-session identity and all settings' {
        $guide | Should -Match 'workspace_type: "worktree"'
        $guide | Should -Match 'base_branch.*explicitly'
        $guide | Should -Match 'kickoff.model: "gpt-6.1-sol"'
        $guide | Should -Match 'reasoning_effort: "high"'
        $guide | Should -Match 'context_tier: "default"'
        $guide | Should -Match 'mode: "interactive"'
        $guide | Should -Match 'Never silently substitute'
        $guide | Should -Match 'No phase/child PR, recursive coordinator or whole-plan loop'
    }
    It 'test:AppCi.VSCodePreservation retains explicit routing without app dependencies' {
        $rootSkill | Should -Match 'retained non-app route'
        $rootSkill | Should -Match 'Invoke-EpicAutopilot.ps1'
        $rootSkill | Should -Match 'Native VS Code phase\s+coordination is deferred'
        $guide | Should -Match 'Retained VS Code epic wrapper/provider proof remains unchanged'
        $launch | Should -Match "'whole-plan', 'next-phase', 'app-phase', 'app-finalization'"
        $launch | Should -Match 'if \(\$appWorker\)'
    }
    It 'test:AppCi.SerialIntegration verifies partial committed scope without falsely closing it' {
        Complete-Step 1.1
        Commit-Worker
        $result = Result
        $result.Status | Should -Be 'partial'
        $result.CompletedSteps | Should -Be @('1.1')
        $result.RequiresCurrentEvidenceAndScopeReview | Should -BeTrue
        Invoke-FixtureGit $script:integration @('merge', '--ff-only', $result.WorkerCommit) | Out-Null
        Invoke-FixtureGit $script:integration @('rev-parse', 'HEAD') | Should -Be $result.WorkerCommit
    }
    It 'refuses dirty committed-result acceptance' {
        Complete-Step 1.1
        { Result } | Should -Throw '*clean committed*'
    }
    It 'refuses source movement and prevents duplicate acceptance after integration' {
        Complete-Step 1.1
        Commit-Worker
        $result = Result
        Invoke-FixtureGit $script:integration @('merge', '--ff-only', $result.WorkerCommit) | Out-Null
        { Result } | Should -Throw '*HEAD moved*'
    }
    It 'refuses divergence' {
        Invoke-FixtureGit $script:worker @('checkout', '--orphan', 'divergent') | Out-Null
        Invoke-FixtureGit $script:worker @('commit', '-qm', 'unrelated') | Out-Null
        { Result } | Should -Throw '*Git check failed*'
    }
    It 'refuses criteria drift' {
        Complete-Step 1.1
        Set-Content (Join-Path (Split-Path $script:workerPlan) 'assets\intent.md') '# Changed intent'
        Commit-Worker
        { Result } | Should -Throw '*differs*baseline*'
    }
    It 'refuses unauthorized human completion' {
        Complete-Step 1.1
        Complete-Step 1.2
        Commit-Worker
        { Result } | Should -Throw '*unauthorized checklist*'
    }
    It 'refuses dependent AI work before human approval' {
        Complete-Step 1.3
        Commit-Worker
        { Result } | Should -Throw '*prerequisite*'
    }
    It 'refuses later-phase work without earlier closure' {
        Complete-Step 2.1
        Commit-Worker
        { Result 2 } | Should -Throw '*earlier phases*'
    }
    It 'refuses checklist body and prerequisite rewrites' {
        $text = (Get-Content $script:workerPlan -Raw).Replace('[after: 1.2]', '[after: 1.1]')
        Set-Content $script:workerPlan $text -NoNewline
        Commit-Worker
        { Result } | Should -Throw '*immutable checklist*'
    }
    It 'refuses same-worktree execution' {
        { & $resultScript -IntegrationRoot $integration -WorkerRoot $integration `
            -PlanReference abc123 -ExpectedStartCommit $start -Phase 1 } |
            Should -Throw '*distinct worktree*'
    }
    It 'test:AppCi.HumanBlockerReadiness admits only an independent AI sibling in the first unfinished phase' {
        $plan = Join-Path $script:integration "docs\implementation-plans\$script:folder\plan.md"
        $text = (Get-Content $plan -Raw).Replace('- [ ] 1.1 ', '- [x] 1.1 ')
        $text = $text.Replace('## Phase 2:', "- [ ] 1.4 Independent AI ``S```n`n## Phase 2:")
        Set-Content $plan $text -NoNewline
        Invoke-FixtureGit $script:integration @('add', '.') | Out-Null
        Invoke-FixtureGit $script:integration @('commit', '-qm', 'prior approved progress') | Out-Null
        $stateScript = Join-Path $script:repo 'scripts\skalary\Get-PhaseExecutionState.ps1'
        & $stateScript -PlanPath $plan -Phase 1 -RepoRoot $script:integration -AllowIndependentAi |
            Should -Be 'execution-required'
        & $stateScript -PlanPath $plan -Phase 2 -RepoRoot $script:integration -AllowIndependentAi |
            Should -BeNullOrEmpty
        $LASTEXITCODE | Should -Be 2
    }
    It 'test:AppCi.HumanExhaustion preserves human and dependent work as operator action' {
        $plan = Join-Path $script:integration "docs\implementation-plans\$script:folder\plan.md"
        $text = (Get-Content $plan -Raw).Replace('- [ ] 1.1 ', '- [x] 1.1 ')
        Set-Content $plan $text -NoNewline
        Invoke-FixtureGit $script:integration @('add', '.') | Out-Null
        Invoke-FixtureGit $script:integration @('commit', '-qm', 'prior approved progress') | Out-Null
        & (Join-Path $script:repo 'scripts\skalary\Get-PhaseExecutionState.ps1') `
            -PlanPath $plan -Phase 1 -RepoRoot $script:integration -AllowIndependentAi |
            Should -Be 'operator-action'
        (Get-Content $plan -Raw) | Should -Match '\[ \] 1.2 Human'
        (Get-Content $plan -Raw) | Should -Match '\[ \] 2.1 Later'
    }
    It 'test:AppCi.CloseRefusal rejects an idle/no-progress result and premature finalization' {
        { Result } | Should -Throw '*no newly completed*'
        { & $resultScript -IntegrationRoot $integration -WorkerRoot $worker `
            -PlanReference abc123 -ExpectedStartCommit $start -Finalization } |
            Should -Throw '*all closed steps*'
    }
}
