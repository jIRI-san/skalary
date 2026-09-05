#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Confirmed planning criteria' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:setStage = Join-Path $script:repoRoot 'scripts/skalary/Set-PlanStage.ps1'
        $script:getState = Join-Path $script:repoRoot 'scripts/skalary/Get-PlanState.ps1'
        $script:roots = [System.Collections.Generic.List[string]]::new()

        function New-PlanningRepo {
            $root = Join-Path $script:repoRoot ('tests\.planning-context-' + [guid]::NewGuid().ToString('N'))
            $script:roots.Add($root)
            $planDir = Join-Path $root 'docs\implementation-plans\standalone-2026-08-28-abcdef-sample'
            $assets = Join-Path $planDir 'assets'
            New-Item -ItemType Directory -Path $assets -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $planDir 'plan.md') -Encoding utf8NoBOM -Value @'
# abcdef: Sample
<!-- plan-id: abcdef -->
<!-- cip-stage: scaffolded -->
<!-- planning-confirmed: pending -->

## Phase 1: MVP

- [ ] 1.1 Deliver the usable path (REQ-1, RISK-1) `S`
'@
            Set-Content -LiteralPath (Join-Path $assets 'intent.md') -Encoding utf8NoBOM -Value @'
# Intent
## Goal
Deliver a usable path.
## Desired outcome
The path works end to end.
## Success signals
- A focused test passes.
## Non-goals
- Broader redesign.
## Definition of done
- The complete path is available.
'@
            Set-Content -LiteralPath (Join-Path $assets 'design.md') -Encoding utf8NoBOM -Value @'
# Approved Design
## Components and boundaries
- The planner owns confirmation.
## Program flow
```mermaid
flowchart TD
    A[Interview] --> B[Draft]
```
'@
            Set-Content -LiteralPath (Join-Path $assets 'requirements.md') -Encoding utf8NoBOM -Value @'
# Requirements
| ID | Requirement | Acceptance Criteria | Phases/Steps |
|---|---|---|---|
| REQ-1 | Deliver | `test:sample` | 1.1 |
'@
            Set-Content -LiteralPath (Join-Path $assets 'risks.md') -Encoding utf8NoBOM -Value @'
# Risks
| ID | Risk | Likelihood | Impact | Mitigation | Steps |
|---|---|---|---|---|---|
| RISK-1 | Drift | Low | Medium | Confirm | 1.1 |
'@
            Set-Content -LiteralPath (Join-Path $assets 'decisions.md') -Encoding utf8NoBOM `
                -Value "# Decisions`n`n- Use one marker."
            Set-Content -LiteralPath (Join-Path $assets 'references.md') -Encoding utf8NoBOM `
                -Value "# References`n`n- Existing workflow."
            [pscustomobject]@{ Root = $root; PlanDir = $planDir; PlanFile = Join-Path $planDir 'plan.md' }
        }
    }

    AfterEach {
        foreach ($root in @($script:roots)) {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
        $script:roots.Clear()
    }

    It 'confirms and invalidates each protected criteria file independently' {
        foreach ($name in @('intent.md', 'requirements.md', 'risks.md', 'decisions.md')) {
            $fixture = New-PlanningRepo
            & $script:setStage -PlanFile $fixture.PlanFile -Stage scaffolded `
                -ConfirmPlanningContext | Out-Null
            $state = (& $script:getState -Reference abcdef -RepoRoot $fixture.Root -Json `
                    -HasUncommittedChanges:$false) | ConvertFrom-Json
            $state.PlanningContext.Status | Should -Be 'confirmed'

            Add-Content -LiteralPath (Join-Path $fixture.PlanDir "assets\$name") `
                -Value "`nChanged protected criteria."
            $state = (& $script:getState -Reference abcdef -RepoRoot $fixture.Root -Json `
                    -HasUncommittedChanges:$false) | ConvertFrom-Json
            $state.PlanningContext.Status | Should -Be 'stale' -Because "$name is protected"
            { & $script:setStage -PlanFile $fixture.PlanFile -Stage drafted } |
                Should -Throw '*stale*'
        }
    }

    It 'does not treat implementation design detail as confirmed execution criteria' {
        $fixture = New-PlanningRepo
        & $script:setStage -PlanFile $fixture.PlanFile -Stage scaffolded `
            -ConfirmPlanningContext | Out-Null
        Add-Content -LiteralPath (Join-Path $fixture.PlanDir 'assets\design.md') `
            -Value "`nAdditional design detail."
        $state = (& $script:getState -Reference abcdef -RepoRoot $fixture.Root -Json `
                -HasUncommittedChanges:$false) | ConvertFrom-Json
        $state.PlanningContext.Status | Should -Be 'confirmed'
    }
}
