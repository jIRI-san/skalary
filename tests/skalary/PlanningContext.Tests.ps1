#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Confirmed planning context' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $setStage = Join-Path $repoRoot 'scripts/skalary/Set-PlanStage.ps1'
        $getState = Join-Path $repoRoot 'scripts/skalary/Get-PlanState.ps1'
        $newPlan = Join-Path $repoRoot 'scripts/skalary/New-Plan.ps1'
        $planTemplate = Join-Path $repoRoot 'plugins/create-implementation-plan/skills/cip/assets/plan-template.md'
        $designTemplate = Join-Path $repoRoot 'plugins/create-implementation-plan/skills/cip/assets/design-template.md'

        function New-PlanningRepo {
            $root = Join-Path ([System.IO.Path]::GetTempPath()) ('planning-context-' + [guid]::NewGuid().ToString('N'))
            $planDir = Join-Path $root 'docs/implementation-plans/standalone-2026-08-28-abcdef-sample'
            $assetsDir = Join-Path $planDir 'assets'
            New-Item -ItemType Directory -Path $assetsDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $planDir 'plan.md') -Encoding utf8NoBOM -Value @'
# abcdef: Sample
<!-- plan-id: abcdef -->
<!-- cip-stage: scaffolded -->
<!-- planning-confirmed: pending -->

## Phase 1: MVP

- [ ] 1.1 Deliver the usable path (REQ-1) `S`
'@
            Set-Content -LiteralPath (Join-Path $assetsDir 'intent.md') -Encoding utf8NoBOM -Value @'
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
            Set-Content -LiteralPath (Join-Path $assetsDir 'design.md') -Encoding utf8NoBOM -Value @'
# Approved Design

## Components and boundaries

- The planner owns confirmation.

## Program flow

```mermaid
flowchart TD
    A[Interview] --> B[Draft]
```

## Optional call stacks

The Mermaid flow is sufficient.
'@
            Set-Content -LiteralPath (Join-Path $assetsDir 'requirements.md') -Encoding utf8NoBOM -Value @'
# Requirements

| ID | Requirement | Acceptance Criteria | Phases/Steps |
|----|-------------|---------------------|--------------|
| REQ-1 | Deliver a path | `test:sample` | 1.1 |
'@
            Set-Content -LiteralPath (Join-Path $assetsDir 'risks.md') -Encoding utf8NoBOM -Value @'
# Risks

| ID | Risk | Likelihood | Impact | Mitigation | Steps |
|----|------|------------|--------|------------|-------|
| RISK-1 | Drift | Low | Medium | Confirm context | 1.1 |
'@
            Set-Content -LiteralPath (Join-Path $assetsDir 'decisions.md') -Encoding utf8NoBOM -Value "# Decisions`n`n- Use one marker."
            Set-Content -LiteralPath (Join-Path $assetsDir 'references.md') -Encoding utf8NoBOM -Value "# References`n`n- Existing workflow."
            return [pscustomobject]@{ Root = $root; PlanDir = $planDir; PlanFile = (Join-Path $planDir 'plan.md') }
        }
    }

    It 'test:Cip.IntentConfirmationCheckpoints defines three correction-aware operator checkpoints' {
        $guide = Get-Content -LiteralPath (Join-Path $repoRoot 'plugins/create-implementation-plan/skills/cip/assets/interview-guide.md') -Raw
        foreach ($checkpoint in @('Checkpoint 1', 'Checkpoint 2', 'Checkpoint 3')) {
            $guide | Should -Match ([regex]::Escape($checkpoint))
        }
        $guide | Should -Match '(?i)rephrase'
        $guide | Should -Match '(?i)repeat the affected'
        foreach ($section in @('Goal', 'Desired outcome', 'Success signals', 'Non-goals', 'Definition of done')) {
            $guide | Should -Match ([regex]::Escape($section))
        }
    }

    It 'test:Cip.IntentDesignConfirmationLifecycle confirms, invalidates, and resumes through current plan state' {
        $fixture = New-PlanningRepo
        try {
            { & $setStage -PlanFile $fixture.PlanFile -Stage drafted } | Should -Throw '*pending*'

            & $setStage -PlanFile $fixture.PlanFile -Stage scaffolded -ConfirmPlanningContext | Out-Null
            & $setStage -PlanFile $fixture.PlanFile -Stage drafted | Out-Null

            $state = (& $getState -Reference abcdef -RepoRoot $fixture.Root -Json -HasUncommittedChanges:$false) |
                ConvertFrom-Json
            $state.PlanningContext.Status | Should -Be 'confirmed'
            $state.PlanningContext.CanProceed | Should -BeTrue
            $state.Markers.PlanningConfirmed | Should -Match '^sha256:[0-9a-f]{64}$'

            Add-Content -LiteralPath (Join-Path $fixture.PlanDir 'assets/intent.md') -Value "`nAdditional confirmed detail."
            $state = (& $getState -Reference abcdef -RepoRoot $fixture.Root -Json -HasUncommittedChanges:$false) |
                ConvertFrom-Json
            $state.PlanningContext.Status | Should -Be 'stale'
            { & $setStage -PlanFile $fixture.PlanFile -Stage 'dr-round-1' } | Should -Throw '*stale*'

            & $setStage -PlanFile $fixture.PlanFile -Stage drafted -ConfirmPlanningContext | Out-Null
            (& $getState -Reference abcdef -RepoRoot $fixture.Root -Json -HasUncommittedChanges:$false |
                ConvertFrom-Json).PlanningContext.Status | Should -Be 'confirmed'

            Add-Content -LiteralPath (Join-Path $fixture.PlanDir 'assets/design.md') -Value "`nAdditional design detail."
            (& $getState -Reference abcdef -RepoRoot $fixture.Root -Json -HasUncommittedChanges:$false |
                ConvertFrom-Json).PlanningContext.Status | Should -Be 'stale'
        }
        finally {
            Remove-Item -LiteralPath $fixture.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'treats an empty enrolled confirmation marker as invalid' {
        $fixture = New-PlanningRepo
        try {
            (Get-Content -LiteralPath $fixture.PlanFile -Raw).Replace(
                '<!-- planning-confirmed: pending -->',
                '<!-- planning-confirmed: -->'
            ) | Set-Content -LiteralPath $fixture.PlanFile -Encoding utf8NoBOM -NoNewline

            $state = (& $getState -Reference abcdef -RepoRoot $fixture.Root -Json -HasUncommittedChanges:$false) |
                ConvertFrom-Json
            $state.PlanningContext.Status | Should -Be 'invalid'
            $state.PlanningContext.IsEnrolled | Should -BeTrue
            $state.PlanningContext.CanProceed | Should -BeFalse
            { & $setStage -PlanFile $fixture.PlanFile -Stage drafted } | Should -Throw '*invalid*'

            & $setStage -PlanFile $fixture.PlanFile -Stage scaffolded -ConfirmPlanningContext | Out-Null
            (& $getState -Reference abcdef -RepoRoot $fixture.Root -Json -HasUncommittedChanges:$false |
                ConvertFrom-Json).PlanningContext.Status | Should -Be 'confirmed'
        }
        finally {
            Remove-Item -LiteralPath $fixture.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'treats malformed confirmation declarations as invalid and repairable' {
        $fixture = New-PlanningRepo
        try {
            (Get-Content -LiteralPath $fixture.PlanFile -Raw).Replace(
                '<!-- planning-confirmed: pending -->',
                '<!-- planning-confirmed: pending'
            ) | Set-Content -LiteralPath $fixture.PlanFile -Encoding utf8NoBOM -NoNewline

            $state = (& $getState -Reference abcdef -RepoRoot $fixture.Root -Json -HasUncommittedChanges:$false) |
                ConvertFrom-Json
            $state.PlanningContext.Status | Should -Be 'invalid'
            $state.PlanningContext.CanProceed | Should -BeFalse
            { & $setStage -PlanFile $fixture.PlanFile -Stage drafted } | Should -Throw '*invalid*'

            & $setStage -PlanFile $fixture.PlanFile -Stage scaffolded -ConfirmPlanningContext | Out-Null
            (& $getState -Reference abcdef -RepoRoot $fixture.Root -Json -HasUncommittedChanges:$false |
                ConvertFrom-Json).PlanningContext.Status | Should -Be 'confirmed'

            (Get-Content -LiteralPath $fixture.PlanFile -Raw).Replace(
                '<!-- planning-confirmed:',
                '<!-- planning-confirmed'
            ) | Set-Content -LiteralPath $fixture.PlanFile -Encoding utf8NoBOM -NoNewline
            $state = (& $getState -Reference abcdef -RepoRoot $fixture.Root -Json -HasUncommittedChanges:$false) |
                ConvertFrom-Json
            $state.PlanningContext.Status | Should -Be 'invalid'
            { & $setStage -PlanFile $fixture.PlanFile -Stage drafted } | Should -Throw '*invalid*'
            & $setStage -PlanFile $fixture.PlanFile -Stage drafted -ConfirmPlanningContext | Out-Null

            (Get-Content -LiteralPath $fixture.PlanFile -Raw).Replace(
                '<!-- planning-confirmed: sha256:',
                '<!-- planning-confirmed: broken > sha256:'
            ) | Set-Content -LiteralPath $fixture.PlanFile -Encoding utf8NoBOM -NoNewline
            & $setStage -PlanFile $fixture.PlanFile -Stage drafted -ConfirmPlanningContext | Out-Null
            (& $getState -Reference abcdef -RepoRoot $fixture.Root -Json -HasUncommittedChanges:$false |
                ConvertFrom-Json).PlanningContext.Status | Should -Be 'confirmed'
        }
        finally {
            Remove-Item -LiteralPath $fixture.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'refuses to confirm a whitespace-only Mermaid program flow' {
        $fixture = New-PlanningRepo
        try {
            $designPath = Join-Path $fixture.PlanDir 'assets/design.md'
            $design = Get-Content -LiteralPath $designPath -Raw
            $design.Replace(
                "flowchart TD`r`n    A[Interview] --> B[Draft]",
                '   '
            ).Replace(
                "flowchart TD`n    A[Interview] --> B[Draft]",
                '   '
            ) | Set-Content -LiteralPath $designPath -Encoding utf8NoBOM -NoNewline

            { & $setStage -PlanFile $fixture.PlanFile -Stage scaffolded -ConfirmPlanningContext } |
                Should -Throw '*non-empty Mermaid*'
        }
        finally {
            Remove-Item -LiteralPath $fixture.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:Cip.ConciseDesignFlow scaffolds the concise Mermaid design and requires confirmation' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ('planning-scaffold-' + [guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path (Join-Path $root 'docs/implementation-plans') -Force | Out-Null
            $created = & $newPlan -Title 'Design fixture' -Slug 'design-fixture' -RepoRoot $root `
                -PlanId abcdef -Date 2026-08-28 -TemplatePath $planTemplate

            $design = (Get-Content -LiteralPath (Join-Path $created.AssetsDir 'design.md') -Raw) -replace "`r`n", "`n"
            $design | Should -Be ((Get-Content -LiteralPath $designTemplate -Raw) -replace "`r`n", "`n")
            $design | Should -Match '(?ms)^## Program flow\s*$.*```mermaid'
            $design | Should -Match '(?m)^## Optional call stacks\s*$'
            (Get-Content -LiteralPath $created.PlanFile -Raw) | Should -Match '<!-- planning-confirmed: pending -->'
            { & $setStage -PlanFile $created.PlanFile -Stage drafted } | Should -Throw '*pending*'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:Cip.VerticalPlanObjectiveInvariants keeps plans MVP-first and complete' {
        $guide = Get-Content -LiteralPath (Join-Path $repoRoot 'plugins/create-implementation-plan/skills/cip/assets/drafting-guide.md') -Raw
        $guide | Should -Match '(?i)usable end-to-end MVP'
        $guide | Should -Match '(?i)vertical increments'
        $guide | Should -Match '(?i)complete outcome'
        $guide | Should -Match '(?i)Route every requirement'
        $guide | Should -Match '(?i)Reject layer-only'
    }

    It 'test:Cip.ConfirmedContextInstalledConsumers gates ci, dr, and autopilot on shared state' {
        $consumers = @(
            'plugins/continue-implementation/skills/ci/SKILL.md'
            'plugins/design-review/skills/dr/assets/plan-scope-guide.md'
            'plugins/autopilot/agents/autopilot.agent.md'
        )
        foreach ($relative in $consumers) {
            $text = Get-Content -LiteralPath (Join-Path $repoRoot $relative) -Raw
            $text | Should -Match 'confirmed'
            $text | Should -Match 'stale'
            $text | Should -Match 'legacy'
        }
        (Get-Content -LiteralPath (Join-Path $repoRoot $consumers[1]) -Raw) |
            Should -Match 'Get-PlanningContextState'
        (Get-Content -LiteralPath (Join-Path $repoRoot $consumers[2]) -Raw) |
            Should -Match 'Get-PlanningContextState'
    }
}
