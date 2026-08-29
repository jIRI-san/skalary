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

        function Get-AdmissionProjection {
            param(
                [Parameter(Mandatory)][string]$Root,
                [Parameter(Mandatory)][string]$Reference
            )

            $inventory = @(Get-PlanInventory -RepoRoot $Root)
            $plan = Resolve-Plan -Reference $Reference -RepoRoot $Root -Inventory $inventory
            $planFile = Join-Path $plan.Path 'plan.md'
            $metadata = Get-PlanMetadata -Path $planFile -RepoRoot $Root
            $markers = Get-PlanHeaderMarkers -Path $planFile
            $next = Get-NextStep -Metadata $metadata
            $planning = Get-PlanningContextState -PlanDir $plan.Path

            $unmetDependencies = [System.Collections.Generic.List[string]]::new()
            foreach ($token in @($markers.DependsOn)) {
                $dependency = Resolve-Plan -Reference $token -RepoRoot $Root -Inventory $inventory
                $dependencyMetadata = Get-PlanMetadata -Path (Join-Path $dependency.Path 'plan.md') -RepoRoot $Root
                $dependencyProgress = Get-PlanProgress -Metadata $dependencyMetadata
                if (-not ($dependency.IsArchived -or $dependencyProgress.IsComplete)) {
                    $unmetDependencies.Add($dependency.Id)
                }
            }

            $phase = if ($next.Step) { [string]$next.Step.Phase } else { '' }
            $applicableRequirements = @(
                if ($phase -and $metadata.PhaseSteps.ContainsKey($phase)) {
                    $metadata.PhaseSteps[$phase] |
                        ForEach-Object { $_.Refs } |
                        Where-Object { $_ -match '^REQ-\d+$' } |
                        Sort-Object -Unique
                }
            )
            $unknownRequirements = @(
                $applicableRequirements | Where-Object { -not $metadata.Requirements.ContainsKey($_) }
            )

            return [pscustomobject]@{
                Plan = $plan
                Next = $next
                Planning = $planning
                UnmetDependencies = $unmetDependencies.ToArray()
                ApplicableRequirements = $applicableRequirements
                UnknownRequirements = $unknownRequirements
            }
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
                'Get-PlanInventory',
                'Resolve-Plan',
                'Get-PlanProgress',
                'Get-PlanState.ps1 -Json',
                'Get-PlanMetadata',
                'Get-NextStep',
                'PlanningContext.CanProceed',
                'Metadata.PhaseSteps',
                'ready',
                'blocked',
                'missing',
                'ambiguous',
                'stale-input'
            )) {
            $admissionText | Should -Match ([regex]::Escape($token))
        }
        $admissionText | Should -Match 'Only `ready` permits'

        $ready = New-AdmissionFixture
        $before = Get-FixtureSnapshot -Root $ready.Root
        $projection = Get-AdmissionProjection -Root $ready.Root -Reference 'def222'
        $projection.Planning.Status | Should -Be 'confirmed'
        $projection.Planning.CanProceed | Should -BeTrue
        $projection.Next.BlockedByAfter | Should -BeFalse
        @($projection.UnmetDependencies).Count | Should -Be 0
        $projection.ApplicableRequirements | Should -Be @('REQ-1')
        @($projection.UnknownRequirements).Count | Should -Be 0
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
        $projection = Get-AdmissionProjection -Root $blocked.Root -Reference 'def222'
        $projection.UnmetDependencies | Should -Be @('abc111')
        $projection.Next.BlockedByAfter | Should -BeTrue
        $projection.Next.UnmetAfter | Should -Be @('9.9')
        (Get-FixtureSnapshot -Root $blocked.Root) | Should -BeExactly $before

        $missing = New-AdmissionFixture
        Remove-Item -LiteralPath (Join-Path $missing.TargetDir 'assets/intent.md') -Force
        $before = Get-FixtureSnapshot -Root $missing.Root
        (Get-AdmissionProjection -Root $missing.Root -Reference 'def222').Planning.Status | Should -Be 'missing'
        (Get-FixtureSnapshot -Root $missing.Root) | Should -BeExactly $before

        $ambiguous = New-AdmissionFixture -TargetSlug 'shared-alpha'
        $secondDir = Join-Path $ambiguous.Root 'docs/implementation-plans/2026-08-03-def223-shared-beta'
        Copy-Item -LiteralPath $ambiguous.TargetDir -Destination $secondDir -Recurse
        $secondPlan = Join-Path $secondDir 'plan.md'
        (Get-Content -LiteralPath $secondPlan -Raw).Replace(
            '<!-- plan-id: def222 -->',
            '<!-- plan-id: def223 -->'
        ) | Set-Content -LiteralPath $secondPlan -Encoding utf8NoBOM -NoNewline
        $before = Get-FixtureSnapshot -Root $ambiguous.Root
        { Get-AdmissionProjection -Root $ambiguous.Root -Reference 'shared' } |
            Should -Throw '*Ambiguous plan reference*'
        (Get-FixtureSnapshot -Root $ambiguous.Root) | Should -BeExactly $before

        $stale = New-AdmissionFixture
        Add-Content -LiteralPath (Join-Path $stale.TargetDir 'assets/intent.md') -Value "`nChanged after confirmation."
        $before = Get-FixtureSnapshot -Root $stale.Root
        (Get-AdmissionProjection -Root $stale.Root -Reference 'def222').Planning.Status | Should -Be 'stale'
        (Get-FixtureSnapshot -Root $stale.Root) | Should -BeExactly $before
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
}
