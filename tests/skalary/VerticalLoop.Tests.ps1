#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Vertical implementation requirement loop' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        Import-Module (Join-Path $script:repoRoot 'scripts/skalary/PlanState.psm1') -Force -DisableNameChecking
        $script:tempRoots = [System.Collections.Generic.List[string]]::new()
        $script:evidenceBuilder = Join-Path $script:repoRoot 'scripts/skalary/Build-EvidenceReceipt.ps1'
        $script:workflowNote = Join-Path $script:repoRoot 'scripts/skalary/Add-WorkflowNote.ps1'
        $script:phaseHarvest = Join-Path $script:repoRoot 'scripts/skalary/Invoke-PhaseHarvest.ps1'
        $script:getPlanState = Join-Path $script:repoRoot 'scripts/skalary/Get-PlanState.ps1'

        function Set-AdmissionAssets {
            param(
                [Parameter(Mandatory)][string]$PlanDir,
                [Parameter(Mandatory)][string]$Requirement
            )

            $assets = Join-Path $PlanDir 'assets'
            New-Item -ItemType Directory -Path $assets -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $assets 'intent.md') -Encoding utf8NoBOM -Value @'
# Intent

## Goal

Deliver one usable vertical increment.

## Desired outcome

The increment works end to end.

## Success signals

- The requirement evidence is inspectable.

## Non-goals

- A parallel plan parser.

## Definition of done

- Admission is read-only and deterministic.
'@
            Set-Content -LiteralPath (Join-Path $assets 'design.md') -Encoding utf8NoBOM -Value @'
# Design

## Components and boundaries

- Existing plan state owns parsing.

## Program flow

```mermaid
flowchart TD
    A[Read state] --> B[Admission result]
```
'@
            Set-Content -LiteralPath (Join-Path $assets 'requirements.md') -Encoding utf8NoBOM -Value @"
# Requirements

| ID | Requirement | Acceptance Criteria | Phases/Steps |
|----|-------------|---------------------|--------------|
| $Requirement | Deliver the increment | ``test:fixture`` | 1.1 |
"@
            Set-Content -LiteralPath (Join-Path $assets 'risks.md') -Encoding utf8NoBOM -Value @'
# Risks

| ID | Risk | Likelihood | Impact | Mitigation | Steps |
|----|------|------------|--------|------------|-------|
| RISK-1 | Mutation before admission | Low | High | Read state first | 1.1 |
'@
            Set-Content -LiteralPath (Join-Path $assets 'decisions.md') -Encoding utf8NoBOM -Value @'
# Decisions

- Reuse PlanState.
'@
            Set-Content -LiteralPath (Join-Path $assets 'references.md') -Encoding utf8NoBOM -Value @'
# References

- Existing parser.
'@
        }

        function New-AdmissionFixture {
            param([string]$TargetSlug = 'target')

            $root = Join-Path ([System.IO.Path]::GetTempPath()) ('vertical-loop-' + [guid]::NewGuid().ToString('N'))
            $plansRoot = Join-Path $root 'docs/implementation-plans'
            $dependencyDir = Join-Path $plansRoot '2026-08-01-abc111-dependency'
            $targetDir = Join-Path $plansRoot "2026-08-02-def222-$TargetSlug"
            New-Item -ItemType Directory -Path $dependencyDir, $targetDir -Force | Out-Null

            Set-Content -LiteralPath (Join-Path $dependencyDir 'plan.md') -Encoding utf8NoBOM -Value @'
# abc111: Dependency
<!-- plan-id: abc111 -->

## Phase 1: Complete dependency

- [x] 1.1 Deliver dependency (REQ-1) `S`
'@
            Set-AdmissionAssets -PlanDir $dependencyDir -Requirement 'REQ-1'

            Set-Content -LiteralPath (Join-Path $targetDir 'plan.md') -Encoding utf8NoBOM -Value @'
# def222: Target
<!-- plan-id: def222 -->
<!-- depends-on: abc111 -->
<!-- planning-confirmed: pending -->

## Phase 1: Vertical increment

- [ ] 1.1 Deliver increment (REQ-1, RISK-1) `S`
'@
            Set-AdmissionAssets -PlanDir $targetDir -Requirement 'REQ-1'
            $digest = Get-PlanningContextDigest -PlanDir $targetDir
            $targetPlan = Join-Path $targetDir 'plan.md'
            (Get-Content -LiteralPath $targetPlan -Raw).Replace(
                '<!-- planning-confirmed: pending -->',
                "<!-- planning-confirmed: sha256:$digest -->"
            ) | Set-Content -LiteralPath $targetPlan -Encoding utf8NoBOM -NoNewline

            $script:tempRoots.Add($root)
            return [pscustomobject]@{
                Root = $root
                DependencyDir = $dependencyDir
                TargetDir = $targetDir
                TargetPlan = $targetPlan
            }
        }

        function Get-FixtureSnapshot {
            param([Parameter(Mandatory)][string]$Root)

            return @(Get-ChildItem -LiteralPath $Root -Recurse -File | Sort-Object FullName | ForEach-Object {
                    $relative = [System.IO.Path]::GetRelativePath($Root, $_.FullName).Replace('\', '/')
                    "$relative=$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)"
                }) -join "`n"
        }

        function Get-FixtureAdmission {
            param(
                [Parameter(Mandatory)][string]$Root,
                [Parameter(Mandatory)][string]$Reference
            )

            $json = & $script:getPlanState $Reference -RepoRoot $Root `
                -HasUncommittedChanges:$false -Json
            return $json | ConvertFrom-Json -Depth 10 | Select-Object -ExpandProperty Admission
        }

        function Invoke-FixtureHarvest {
            param(
                [Parameter(Mandatory)][string]$PlanDir,
                [Parameter(Mandatory)][string]$Root,
                [int]$Phase = 1
            )

            $output = & pwsh -NoProfile -File $script:phaseHarvest -PlanDir $PlanDir `
                -RepoRoot $Root -Phase $Phase -Src autopilot 2>&1
            return [pscustomobject]@{
                ExitCode = $LASTEXITCODE
                Output = (($output -join "`n") -replace "`e\[[0-9;?]*[ -/]*[@-~]", '')
            }
        }

        function Get-ContainerPhaseState {
            param(
                [Parameter(Mandatory)][string]$PlanPath,
                [Parameter(Mandatory)][int]$Phase,
                [Parameter(Mandatory)][string]$RepoRoot
            )

            $entrypoint = Join-Path $script:repoRoot 'plugins/autopilot/scripts/container-entrypoint.sh'
            & bash -c 'source "$1"; phase_needs_execution "$2" "$3" "$4" "$5"' `
                phase-probe $entrypoint $PlanPath $Phase $RepoRoot $script:phaseHarvest
            return $LASTEXITCODE
        }

        function Get-ContainerDispatchAction {
            param(
                [Parameter(Mandatory)][string]$Mode,
                [Parameter(Mandatory)][int]$ExitCode,
                [Parameter(Mandatory)][int]$CloseState
            )

            $entrypoint = Join-Path $script:repoRoot 'plugins/autopilot/scripts/container-entrypoint.sh'
            return (& bash -c 'source "$1"; phase_dispatch_action "$2" "$3" "$4"' `
                    phase-dispatch $entrypoint $Mode $ExitCode $CloseState).Trim()
        }

        function Invoke-ContainerRecoveryStage {
            param([Parameter(Mandatory)][string]$RepoPath)

            $entrypoint = Join-Path $script:repoRoot 'plugins/autopilot/scripts/container-entrypoint.sh'
            & bash -c 'source "$1"; stage_recoverable_work "$2"' `
                recovery-stage $entrypoint $RepoPath
            return $LASTEXITCODE
        }
    }

    AfterAll {
        foreach ($root in $script:tempRoots) {
            if (Test-Path -LiteralPath $root -PathType Container) {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }
        Remove-Module PlanState -Force -ErrorAction SilentlyContinue
    }

    It 'test:VerticalLoop.PhaseAdmission keeps ready, blocked, missing, ambiguous, and stale-input admission read-only' {
        $skill = Get-Content -LiteralPath (
            Join-Path $script:repoRoot 'plugins/continue-implementation/skills/ci/SKILL.md'
        ) -Raw
        $admissionStart = $skill.IndexOf('### Phase admission (read-only hard gate)', [System.StringComparison]::Ordinal)
        $mutationStart = $skill.IndexOf('## Step 3: Determine execution mode and branch/worktree', [System.StringComparison]::Ordinal)
        $admissionStart | Should -BeGreaterThan -1
        $mutationStart | Should -BeGreaterThan $admissionStart
        $admissionText = $skill.Substring($admissionStart, $mutationStart - $admissionStart)
        foreach ($token in @(
                'Get-PhaseAdmission',
                'Admission.ApplicableRequirements',
                'Admission.Reason',
                'ready',
                'blocked',
                'missing',
                'ambiguous',
                'stale-input'
            )) {
            $admissionText | Should -Match ([regex]::Escape($token))
        }
        $skill | Should -Match 'Get-PlanState\.ps1 <plan-or-epic-reference> -RepoRoot \. -Json'
        $admissionText | Should -Match 'Only `ready` permits'
        @([regex]::Matches($skill, 'Get-PlanState\.ps1 <plan-or-epic-reference>')).Count |
            Should -Be 1

        $ready = New-AdmissionFixture
        $before = Get-FixtureSnapshot -Root $ready.Root
        $admission = Get-FixtureAdmission -Root $ready.Root -Reference 'def222'
        $admission.Status | Should -Be 'ready'
        $admission.CanProceed | Should -BeTrue
        $admission.ApplicableRequirements | Should -Be @('REQ-1')
        (Get-FixtureSnapshot -Root $ready.Root) | Should -BeExactly $before

        $blocked = New-AdmissionFixture
        $dependencyPlan = Join-Path $blocked.DependencyDir 'plan.md'
        (Get-Content -LiteralPath $dependencyPlan -Raw).Replace(
            '- [x] 1.1 Deliver dependency',
            '- [ ] 1.1 Deliver dependency'
        ) | Set-Content -LiteralPath $dependencyPlan -Encoding utf8NoBOM -NoNewline
        (Get-Content -LiteralPath $blocked.TargetPlan -Raw).Replace(
            '(REQ-1, RISK-1) `S`',
            '(REQ-1, RISK-1) [after: 9.9] `S`'
        ) | Set-Content -LiteralPath $blocked.TargetPlan -Encoding utf8NoBOM -NoNewline
        $before = Get-FixtureSnapshot -Root $blocked.Root
        $admission = Get-FixtureAdmission -Root $blocked.Root -Reference 'def222'
        $admission.Status | Should -Be 'blocked'
        $admission.UnmetDependencies | Should -Be @('abc111')
        (Get-FixtureSnapshot -Root $blocked.Root) | Should -BeExactly $before

        $missing = New-AdmissionFixture
        Remove-Item -LiteralPath (Join-Path $missing.TargetDir 'assets/intent.md') -Force
        $before = Get-FixtureSnapshot -Root $missing.Root
        $missingAdmission = Get-FixtureAdmission -Root $missing.Root -Reference 'def222'
        $missingAdmission.Status | Should -Be 'missing'
        $missingAdmission.Reason | Should -Match 'Planning context asset not found'
        (Get-FixtureSnapshot -Root $missing.Root) | Should -BeExactly $before

        $ambiguous = New-AdmissionFixture
        $secondDir = Join-Path $ambiguous.Root 'docs/implementation-plans/2026-08-03-abc112-dependency-copy'
        Copy-Item -LiteralPath $ambiguous.DependencyDir -Destination $secondDir -Recurse
        $secondPlan = Join-Path $secondDir 'plan.md'
        (Get-Content -LiteralPath $secondPlan -Raw).Replace(
            '<!-- plan-id: abc111 -->',
            '<!-- plan-id: abc112 -->'
        ) | Set-Content -LiteralPath $secondPlan -Encoding utf8NoBOM -NoNewline
        (Get-Content -LiteralPath $ambiguous.TargetPlan -Raw).Replace(
            '<!-- depends-on: abc111 -->',
            '<!-- depends-on: depend -->'
        ) | Set-Content -LiteralPath $ambiguous.TargetPlan -Encoding utf8NoBOM -NoNewline
        $before = Get-FixtureSnapshot -Root $ambiguous.Root
        $ambiguousAdmission = Get-FixtureAdmission -Root $ambiguous.Root -Reference 'def222'
        $ambiguousAdmission.Status | Should -Be 'ambiguous'
        $ambiguousAdmission.Reason | Should -Match 'Ambiguous plan reference'
        (Get-FixtureSnapshot -Root $ambiguous.Root) | Should -BeExactly $before

        $stale = New-AdmissionFixture
        Add-Content -LiteralPath (Join-Path $stale.TargetDir 'assets/intent.md') -Value "`nChanged after confirmation."
        $before = Get-FixtureSnapshot -Root $stale.Root
        $staleAdmission = Get-FixtureAdmission -Root $stale.Root -Reference 'def222'
        $staleAdmission.Status | Should -Be 'stale-input'
        $staleAdmission.Reason | Should -Match 'changed after confirmation'
        (Get-FixtureSnapshot -Root $stale.Root) | Should -BeExactly $before

        $noRequirements = New-AdmissionFixture
        (Get-Content -LiteralPath $noRequirements.TargetPlan -Raw).Replace(
            '(REQ-1, RISK-1)',
            '(RISK-1)'
        ) | Set-Content -LiteralPath $noRequirements.TargetPlan -Encoding utf8NoBOM -NoNewline
        (Get-FixtureAdmission -Root $noRequirements.Root -Reference 'def222').Status | Should -Be 'missing'

        $unknownRequirement = New-AdmissionFixture
        (Get-Content -LiteralPath $unknownRequirement.TargetPlan -Raw).Replace(
            '(REQ-1, RISK-1)',
            '(REQ-9, RISK-1)'
        ) | Set-Content -LiteralPath $unknownRequirement.TargetPlan -Encoding utf8NoBOM -NoNewline
        $unknown = Get-FixtureAdmission -Root $unknownRequirement.Root -Reference 'def222'
        $unknown.Status | Should -Be 'missing'
        $unknown.UnknownRequirements | Should -Be @('REQ-9')
        $unknown.Reason | Should -Match 'unknown requirements: REQ-9'

        $legacy = New-AdmissionFixture
        (Get-Content -LiteralPath $legacy.TargetPlan -Raw) -replace
            '(?m)^<!-- planning-confirmed: .+ -->\r?\n', '' |
            Set-Content -LiteralPath $legacy.TargetPlan -Encoding utf8NoBOM -NoNewline
        (Get-Content -LiteralPath (Join-Path $legacy.TargetDir 'assets/intent.md') -Raw).Replace(
            'Deliver one usable vertical increment.',
            'TBD'
        ) | Set-Content -LiteralPath (Join-Path $legacy.TargetDir 'assets/intent.md') `
            -Encoding utf8NoBOM -NoNewline
        $legacyAdmission = Get-FixtureAdmission -Root $legacy.Root -Reference 'def222'
        $legacyAdmission.Status | Should -Be 'missing'
        $legacyAdmission.Reason | Should -Match "Intent section 'Goal'.+TBD"

        $earlierPhase = New-AdmissionFixture
        $header = (Get-Content -LiteralPath $earlierPhase.TargetPlan -Raw).Split('## Phase 1')[0]
        @"
$($header.TrimEnd())
## Phase 2: Misordered candidate

- [ ] 2.1 Later increment (REQ-1) ``S``

## Phase 1: Earlier incomplete

- [ ] 1.1 Earlier increment (REQ-1) ``S``
"@ | Set-Content -LiteralPath $earlierPhase.TargetPlan -Encoding utf8NoBOM
        $earlier = Get-FixtureAdmission -Root $earlierPhase.Root -Reference 'def222'
        $earlier.Status | Should -Be 'blocked'
        $earlier.Reason | Should -Match 'Earlier phase step'

        $notRepository = New-AdmissionFixture
        {
            & $script:getPlanState def222 -RepoRoot $notRepository.Root -Json
        } | Should -Throw '*Unable to inspect the repository worktree*'

        if (-not $IsWindows) {
            $linked = New-AdmissionFixture
            $externalIntent = Join-Path $linked.Root 'external-intent.md'
            Move-Item -LiteralPath (Join-Path $linked.TargetDir 'assets/intent.md') `
                -Destination $externalIntent
            New-Item -ItemType SymbolicLink -Path (Join-Path $linked.TargetDir 'assets/intent.md') `
                -Target $externalIntent | Out-Null
            $confined = Get-FixtureAdmission -Root $linked.Root -Reference 'def222'
            $confined.Status | Should -Be 'missing'
            $confined.Reason | Should -Match 'escapes'
        }
    }

    It 'test:VerticalLoop.EvidenceCrosscheck preserves truthful phase outcomes and blocks every unresolved result' {
        $commit = 'a' * 40
        foreach ($status in @('passed', 'failed', 'skipped', 'stale', 'unrun', 'degraded')) {
            $receipt = & $script:evidenceBuilder -Result @([pscustomobject]@{
                    Req = 'REQ-1'
                    Marker = "test:fixture.$status"
                    Status = $status
                }) -Commit $commit -Phase 1

            $receipt.Text | Should -Match '^Phase 1 Crosscheck:'
            $receipt.Outcomes[0].Status | Should -Be $status
            if ($status -eq 'passed') {
                $receipt.AllPassed | Should -BeTrue
                $receipt.Lines[0] | Should -Match '^✓ REQ-1 '
            }
            else {
                $receipt.AllPassed | Should -BeFalse
                $receipt.Lines[0] | Should -Match '^✗ REQ-1 '
            }
            $receipt.Lines[0] | Should -Match "$status .+ $commit$"
        }

        $waivedFixture = New-AdmissionFixture
        [ordered]@{
            schema = 'skalary/evidence-waivers@1'
            waivers = @(
                [ordered]@{
                    plan = 'def222'
                    requirement = 'REQ-1'
                    marker = 'test:fixture'
                    outcome = 'skipped'
                    reason = 'Not applicable to this environment'
                }
            )
        } | ConvertTo-Json -Depth 8 |
            Set-Content -LiteralPath (Join-Path $waivedFixture.TargetDir 'assets/evidence-waivers.json') -Encoding utf8NoBOM

        $waived = & $script:evidenceBuilder -Result @([pscustomobject]@{
                Req = 'REQ-1'
                Marker = 'test:fixture'
                Status = 'skipped'
            }) -Commit $commit -Phase 1 -PlanDir $waivedFixture.TargetDir -RepoRoot $waivedFixture.Root
        $waived.AllPassed | Should -BeTrue
        $waived.Outcomes[0].Status | Should -Be 'waived'
        $waived.Lines[0] | Should -Match '^⊘ REQ-1 .+ waived: from skipped: '
    }

    It 'test:VerticalLoop.OperatorCheckpoint covers continue, revise, stop, and resume with intent and evidence context' {
        $guide = Get-Content -LiteralPath (
            Join-Path $script:repoRoot 'plugins/continue-implementation/skills/ci/assets/crosscheck-guide.md'
        ) -Raw
        foreach ($token in @(
                '### Operator checkpoint',
                'usable increment',
                'intent fit',
                'requirement/evidence outcome matrix',
                'contract',
                'end-user experience',
                'security',
                'irreversible structure',
                'Add-WorkflowNote.ps1 -Kind Capture',
                '**Continue**',
                '**Revise**',
                '**Stop**',
                '**Resume**'
            )) {
            $guide | Should -Match ([regex]::Escape($token))
        }
        $guide | Should -Match '(?s)Continue.+only when.+AllPassed.+no high-impact uncertainty'
        $guide | Should -Match '(?s)failed.+skipped.+stale.+unrun.+degraded.+offer Revise and Stop only'
        $checkpoint = $guide.IndexOf('8. Run the operator checkpoint below.', [System.StringComparison]::Ordinal)
        $continue = $guide.IndexOf('Only after recording **Continue**', [System.StringComparison]::Ordinal)
        $harvest = $guide.IndexOf('Invoke-PhaseHarvest.ps1', $continue, [System.StringComparison]::Ordinal)
        $checkpoint | Should -BeGreaterThan -1
        $continue | Should -BeGreaterThan $checkpoint
        $harvest | Should -BeGreaterThan $continue
        $guide.Substring($checkpoint, $continue - $checkpoint) |
            Should -Not -Match 'Invoke-PhaseHarvest\.ps1'
        $guide | Should -Match 'Stop ends the phase flow without invoking harvest'

        foreach ($status in @('failed', 'skipped', 'stale', 'unrun', 'degraded')) {
            $options = Get-PhaseCheckpointOptions -EvidenceStatus $status
            $options.CanContinue | Should -BeFalse
            $options.Options | Should -Be @('Revise', 'Stop')
        }
        foreach ($uncertainty in @('contract', 'end-user experience', 'security', 'irreversible structure')) {
            $options = Get-PhaseCheckpointOptions -EvidenceStatus passed -HasHighImpactUncertainty
            $options.CanContinue | Should -BeFalse -Because "$uncertainty uncertainty blocks continuation"
            $options.Options | Should -Be @('Revise', 'Stop')
        }
        $green = Get-PhaseCheckpointOptions -EvidenceStatus passed, waived
        $green.CanContinue | Should -BeTrue
        $green.Options | Should -Be @('Continue', 'Revise', 'Stop')

        foreach ($disposition in @('Continue', 'Revise', 'Stop', 'Resume')) {
            $fixture = New-AdmissionFixture
            $message = "usable increment=vertical path; intent=deliver end to end; evidence=REQ-1 passed; disposition=$disposition"
            & $script:workflowNote -Kind Capture -PlanDir $fixture.TargetDir -RepoRoot $fixture.Root `
                -Phase 1 -Step 1.1 -Src note -Concern testing-evidence -Requirement REQ-1 `
                -ReviewType none -Message $message | Out-Null

            $capture = Get-Content -LiteralPath (Join-Path $fixture.TargetDir 'assets/logs/capture.md') -Raw
            $capture | Should -Match 'usable increment=vertical path'
            $capture | Should -Match 'intent=deliver end to end'
            $capture | Should -Match 'evidence=REQ-1 passed'
            $capture | Should -Match "disposition=$disposition"
        }
    }

    It 'test:VerticalLoop.WorkflowNoteCapture keeps decisions, uncertainty, and checkpoint outcomes in the closed writer kinds' {
        $fixture = New-AdmissionFixture
        $capturePath = Join-Path $fixture.TargetDir 'assets/logs/capture.md'
        $learningPath = Join-Path $fixture.TargetDir 'assets/logs/learnings.md'
        $crLogPath = Join-Path $fixture.TargetDir 'assets/logs/cr-log.md'

        $decision = & $script:workflowNote -Kind Capture -PlanDir $fixture.TargetDir `
            -RepoRoot $fixture.Root -Phase 1 -Step 1.1 -Src note `
            -Concern architecture-patterns -Requirement REQ-1 -ReviewType none `
            -Message 'decision=reuse the existing workflow-note writer'
        $uncertainty = & $script:workflowNote -Kind Capture -PlanDir $fixture.TargetDir `
            -RepoRoot $fixture.Root -Phase 1 -Step 1.1 -Src note `
            -Concern maintainability-consistency -Requirement REQ-1 -ReviewType none `
            -Message 'uncertainty=wording may be refined later; impact=lower'
        $outcome = & $script:workflowNote -Kind Capture -PlanDir $fixture.TargetDir `
            -RepoRoot $fixture.Root -Phase 1 -Step 1.1 -Src note `
            -Concern testing-evidence -Requirement REQ-1 -ReviewType none `
            -Message 'checkpoint outcome=continue; evidence=REQ-1 passed'
        $learning = & $script:workflowNote -Kind Learnings -PlanDir $fixture.TargetDir `
            -RepoRoot $fixture.Root -Phase 1 -Step 1.1 -Trigger reusable-pattern `
            -Concern architecture-patterns -Requirement REQ-1 -ReviewType none `
            -Message 'Reusable phase capture stays on the existing writer.'
        $review = & $script:workflowNote -Kind CrLog -PlanDir $fixture.TargetDir `
            -RepoRoot $fixture.Root -Phase 1 -Step 1.1 -Src code-review -Sev Low `
            -Concern testing-evidence -Requirement REQ-1 -ReviewType cr `
            -Message 'Capture contract reviewed.'

        foreach ($result in @($decision, $uncertainty, $outcome)) {
            $result.Status | Should -Be 'complete'
            $result.File | Should -BeExactly $capturePath
        }
        $learning.File | Should -BeExactly $learningPath
        $review.File | Should -BeExactly $crLogPath

        $capture = Get-Content -LiteralPath $capturePath -Raw
        $capture | Should -Match 'decision=reuse the existing workflow-note writer'
        $capture | Should -Match 'uncertainty=wording may be refined later; impact=lower'
        $capture | Should -Match 'checkpoint outcome=continue; evidence=REQ-1 passed'
        @([regex]::Matches($capture, '\[source-record:[0-9a-f]{64}\]')).Count | Should -Be 3

        (Get-Content -LiteralPath $learningPath -Raw) | Should -Match '\[trigger:reusable-pattern\]'
        (Get-Content -LiteralPath $crLogPath -Raw) | Should -Match '\[src:code-review\].+\[review:cr\]'
        {
            & $script:workflowNote -Kind Checkpoint -PlanDir $fixture.TargetDir `
                -RepoRoot $fixture.Root -Phase 1
        } | Should -Throw '*Checkpoint*'
        Test-Path -LiteralPath (Join-Path $fixture.TargetDir 'assets/logs/checkpoint.md') |
            Should -BeFalse

        $guide = Get-Content -LiteralPath (
            Join-Path $script:repoRoot 'plugins/continue-implementation/skills/ci/assets/crosscheck-guide.md'
        ) -Raw
        $guide | Should -Match 'Capturing uncertainty never resolves it or changes its impact class'
        $guide | Should -Match 'Do not add a checkpoint kind, checkpoint file, parser, or parallel'
    }

    It 'test:VerticalLoop.AutopilotNextPhase stops after one checked phase and resumes from checklist progress' {
        $fixture = New-AdmissionFixture
        $planPath = $fixture.TargetPlan
        Set-Content -LiteralPath $planPath -Encoding utf8NoBOM -Value @'
# def222: Next phase fixture
<!-- plan-id: def222 -->

## Phase 1: Complete

- [x] 1.1 Complete work (REQ-1) `S`

## Phase 2: Current

- [~] 2.1 Interrupted work (REQ-1) [after: 1.1] `S`

## Phase 3: Later

- [ ] 3.1 Later work (REQ-1) [after: 2.1] `S`
'@

        foreach ($kind in @('CrLog', 'Learnings', 'Capture')) {
            & $script:workflowNote -Kind $kind -PlanDir $fixture.TargetDir `
                -RepoRoot $fixture.Root -Phase 1 | Out-Null
        }
        (Invoke-FixtureHarvest -PlanDir $fixture.TargetDir -Root $fixture.Root -Phase 1).ExitCode |
            Should -Be 0

        # Only a canonically validated receipt closes checked phase 1.
        Get-ContainerPhaseState -PlanPath $planPath -Phase 1 -RepoRoot $fixture.Root |
            Should -Be 1
        Get-ContainerPhaseState -PlanPath $planPath -Phase 2 -RepoRoot $fixture.Root |
            Should -Be 0

        # An interrupted phase remains the first runnable phase on relaunch.
        $firstRunnable = @(1..3 | Where-Object {
                (Get-ContainerPhaseState -PlanPath $planPath -Phase $_ `
                    -RepoRoot $fixture.Root) -eq 0
            })[0]
        $firstRunnable | Should -Be 2

        # Checklist completion alone cannot skip its pending phase-close checks.
        (Get-Content -LiteralPath $planPath -Raw).Replace(
            '- [~] 2.1 Interrupted work',
            '- [x] 2.1 Interrupted work'
        ) | Set-Content -LiteralPath $planPath -Encoding utf8NoBOM -NoNewline
        $closePending = @(1..3 | Where-Object {
                (Get-ContainerPhaseState -PlanPath $planPath -Phase $_ `
                    -RepoRoot $fixture.Root) -eq 0
            })[0]
        $closePending | Should -Be 2

        foreach ($kind in @('CrLog', 'Learnings', 'Capture')) {
            & $script:workflowNote -Kind $kind -PlanDir $fixture.TargetDir `
                -RepoRoot $fixture.Root -Phase 2 | Out-Null
        }
        (Invoke-FixtureHarvest -PlanDir $fixture.TargetDir -Root $fixture.Root -Phase 2).ExitCode |
            Should -Be 0

        # Once close is durable, relaunch advances without repeating checked phases.
        $resumedRunnable = @(1..3 | Where-Object {
                (Get-ContainerPhaseState -PlanPath $planPath -Phase $_ `
                    -RepoRoot $fixture.Root) -eq 0
            })[0]
        $resumedRunnable | Should -Be 3

        $receiptPath = Join-Path $fixture.TargetDir 'assets/harvest-receipts/phase-002.json'
        $validReceipt = [System.IO.File]::ReadAllBytes($receiptPath)
        Set-Content -LiteralPath $receiptPath -Encoding utf8NoBOM -Value '{}'
        Get-ContainerPhaseState -PlanPath $planPath -Phase 2 -RepoRoot $fixture.Root |
            Should -Be 2
        [System.IO.File]::WriteAllBytes($receiptPath, $validReceipt)

        # A self-consistent envelope still fails when the mandatory source set is forged.
        $forgedReceipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json -Depth 12
        $forgedReceipt.payload.sources[0].Kind = 'LearningOverflow'
        $payloadJson = $forgedReceipt.payload | ConvertTo-Json -Depth 12 -Compress
        $digestInput = [System.Text.Encoding]::UTF8.GetBytes(
            "phase-harvest-receipt/v2$([char]0)$payloadJson"
        )
        $forgedReceipt.receiptId = [Convert]::ToHexString(
            [System.Security.Cryptography.SHA256]::HashData($digestInput)
        ).ToLowerInvariant()
        $forgedReceipt | ConvertTo-Json -Depth 12 -Compress |
            Set-Content -LiteralPath $receiptPath -Encoding utf8NoBOM
        Get-ContainerPhaseState -PlanPath $planPath -Phase 2 -RepoRoot $fixture.Root |
            Should -Be 2
        [System.IO.File]::WriteAllBytes($receiptPath, $validReceipt)

        Get-ContainerDispatchAction -Mode next-phase -ExitCode 0 -CloseState 1 |
            Should -Be 'phase-complete-stop'
        Get-ContainerDispatchAction -Mode whole-plan -ExitCode 0 -CloseState 1 |
            Should -Be 'phase-complete-continue'
        Get-ContainerDispatchAction -Mode next-phase -ExitCode 42 -CloseState -1 |
            Should -Be 'human-stop'
        Get-ContainerDispatchAction -Mode next-phase -ExitCode 7 -CloseState -1 |
            Should -Be 'phase-failed'
        Get-ContainerDispatchAction -Mode next-phase -ExitCode 0 -CloseState 0 |
            Should -Be 'close-pending'
        Get-ContainerDispatchAction -Mode next-phase -ExitCode 0 -CloseState 2 |
            Should -Be 'invalid-receipt'

        $recoveryRoot = Join-Path $fixture.Root 'recovery-repo'
        New-Item -ItemType Directory -Path $recoveryRoot -Force | Out-Null
        & git -C $recoveryRoot init --quiet
        & git -C $recoveryRoot config user.name fixture
        & git -C $recoveryRoot config user.email fixture@example.invalid
        Set-Content -LiteralPath (Join-Path $recoveryRoot '.gitignore') `
            -Encoding utf8NoBOM -Value "ignored.tmp"
        Set-Content -LiteralPath (Join-Path $recoveryRoot 'tracked.txt') `
            -Encoding utf8NoBOM -Value 'before'
        & git -C $recoveryRoot add -- .gitignore tracked.txt
        & git -C $recoveryRoot commit --quiet -m fixture
        Set-Content -LiteralPath (Join-Path $recoveryRoot 'tracked.txt') `
            -Encoding utf8NoBOM -Value 'after'
        Set-Content -LiteralPath (Join-Path $recoveryRoot 'new.txt') `
            -Encoding utf8NoBOM -Value 'new'
        Set-Content -LiteralPath (Join-Path $recoveryRoot 'ignored.tmp') `
            -Encoding utf8NoBOM -Value 'ignored'

        (Invoke-ContainerRecoveryStage -RepoPath $recoveryRoot) | Should -Be 0
        $staged = @(& git -C $recoveryRoot diff --cached --name-only)
        $staged | Should -Contain 'tracked.txt'
        $staged | Should -Contain 'new.txt'
        $staged | Should -Not -Contain 'ignored.tmp'
    }

    It 'test:VerticalLoop.ConsumerInstall preserves the admitted phase loop in installed CI and autopilot payloads' {
        Import-Module (Join-Path $script:repoRoot 'tests/ConsumerInstallFixture.psm1') `
            -Force -DisableNameChecking
        $consumer = New-ConsumerInstallFixture -SourceRepoRoot $script:repoRoot
        try {
            $contracts = @(
                [pscustomobject]@{
                    Plugin = 'continue-implementation'
                    Dest = 'skills/ci/SKILL.md'
                    Tokens = @(
                        'Admission.ApplicableRequirements',
                        '**Execution extent.**',
                        'scope never infers `whole-plan`',
                        '`next-phase` stops after the first admitted phase',
                        '`whole-plan` applies the same admission and close contract'
                    )
                },
                [pscustomobject]@{
                    Plugin = 'continue-implementation'
                    Dest = 'skills/ci/assets/crosscheck-guide.md'
                    Tokens = @(
                        'Get-PhaseCheckpointOptions',
                        'Only after recording **Continue**'
                    )
                },
                [pscustomobject]@{
                    Plugin = 'autopilot'
                    Dest = 'skills/autopilot/SKILL.md'
                    Tokens = @(
                        'Accept the runtime and launcher mode selected by `/ci`',
                        'Do not derive launcher mode from plan text',
                        '`next-phase` still delegates admission',
                        '`whole-plan` uses the same admitted-phase and phase-close loop'
                    )
                },
                [pscustomobject]@{
                    Plugin = 'autopilot'
                    Dest = 'skills/autopilot/scripts/container-entrypoint.sh'
                    Tokens = @(
                        'phase_dispatch_action',
                        'phase-complete-stop',
                        'phase-complete-continue',
                        '-ValidateReceipt'
                    )
                }
            )

            foreach ($contract in $contracts) {
                $catalogFile = @(
                    $consumer.Catalog.Files |
                        Where-Object {
                            [string]$_.Plugin -eq $contract.Plugin -and
                            [string]$_.Dest -eq $contract.Dest
                        }
                )
                $catalogFile.Count | Should -Be 1

                $installedPath = Join-Path (Join-Path $consumer.Root '.github') (
                    $contract.Dest -replace '/', [System.IO.Path]::DirectorySeparatorChar
                )
                Test-Path -LiteralPath $installedPath -PathType Leaf | Should -BeTrue
                (Get-FileHash -LiteralPath $installedPath -Algorithm SHA256).Hash.ToLowerInvariant() |
                    Should -BeExactly ([string]$catalogFile[0].Sha256)

                $installed = [System.IO.File]::ReadAllText($installedPath)
                foreach ($token in $contract.Tokens) {
                    $installed | Should -Match ([regex]::Escape($token))
                }

                $registryPlugin = @(
                    $consumer.Registry.plugins |
                        Where-Object { [string]$_.name -eq $contract.Plugin }
                )
                $registryPlugin.Count | Should -Be 1
                $registryFile = @(
                    $registryPlugin[0].files |
                        Where-Object { [string]$_.dest -eq $contract.Dest }
                )
                $registryFile.Count | Should -Be 1
                [string]$registryFile[0].sha256 |
                    Should -BeExactly ([string]$catalogFile[0].Sha256)
            }

            foreach ($pluginName in @('continue-implementation', 'autopilot')) {
                $catalogPlugin = @(
                    $consumer.Catalog.Plugins |
                        Where-Object { [string]$_.Name -eq $pluginName }
                )[0]
                $registryPlugin = @(
                    $consumer.Registry.plugins |
                        Where-Object { [string]$_.name -eq $pluginName }
                )[0]
                [string]$registryPlugin.version |
                    Should -BeExactly ([string]$catalogPlugin.Version)
            }
        }
        finally {
            Remove-ConsumerInstallFixture -Fixture $consumer
        }
    }

    It 'allows phase-one harvest after legacy phase-zero planning capture' {
        $fixture = New-AdmissionFixture
        $logs = Join-Path $fixture.TargetDir 'assets/logs'
        New-Item -ItemType Directory -Path $logs -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $logs 'capture.md') -Encoding utf8NoBOM -Value @'
## Capture
Phase: 0

- [0.1] [src:note] planning: operator confirmed intent
'@
        foreach ($kind in @('CrLog', 'Learnings', 'Capture')) {
            & $script:workflowNote -Kind $kind -PlanDir $fixture.TargetDir -RepoRoot $fixture.Root -Phase 1 |
                Out-Null
        }
        & $script:workflowNote -Kind Capture -PlanDir $fixture.TargetDir -RepoRoot $fixture.Root `
            -Phase 1 -Step 1.1 -Src note -Concern architecture-patterns -Requirement REQ-1 `
            -ReviewType none -Message 'usable increment retained after planning capture' | Out-Null

        $result = Invoke-FixtureHarvest -PlanDir $fixture.TargetDir -Root $fixture.Root
        $result.ExitCode | Should -Be 0
        $receiptPath = Join-Path $fixture.TargetDir 'assets/harvest-receipts/phase-001.json'
        $receiptText = Get-Content -LiteralPath $receiptPath -Raw
        $receipt = $receiptText |
            ConvertFrom-Json -Depth 12
        $receipt.schema | Should -Be 'phase-harvest-receipt/v2'
        @($receipt.payload.candidates).Count | Should -Be 1
        $receiptText | Should -Not -Match ([regex]::Escape($fixture.Root))
        $receipt.payload.repo | Should -Match '^path-sha256:[0-9a-f]{64}$'
        $receipt.payload.repo | Should -Not -Match ([regex]::Escape($fixture.Root))

        $invalid = New-AdmissionFixture
        $invalidLogs = Join-Path $invalid.TargetDir 'assets/logs'
        New-Item -ItemType Directory -Path $invalidLogs -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $invalidLogs 'cr-log.md') -Encoding utf8NoBOM -Value @'
## CR Capture
Phase: 0

No entries for this phase.
'@
        foreach ($kind in @('Learnings', 'Capture')) {
            & $script:workflowNote -Kind $kind -PlanDir $invalid.TargetDir -RepoRoot $invalid.Root `
                -Phase 1 | Out-Null
        }
        $refused = Invoke-FixtureHarvest -PlanDir $invalid.TargetDir -Root $invalid.Root
        $refused.ExitCode | Should -Be 3
        $refused.Output | Should -Match 'Phase 0 is valid only for planning Capture'
    }
}
