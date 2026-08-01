#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'human-step-detail gate' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $modulePath = Join-Path $repoRoot 'scripts/skalary/PlanState.psm1'
        Import-Module $modulePath -Force -DisableNameChecking

        $testPlanScript = Join-Path $repoRoot 'scripts/skalary/Test-Plan.ps1'
        $planStateScript = Join-Path $repoRoot 'scripts/skalary/Get-PlanState.ps1'

        $newTempPlansRoot = {
            $path = Join-Path ([System.IO.Path]::GetTempPath()) ('human-step-' + [System.Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path (Join-Path $path 'docs/implementation-plans') -Force | Out-Null
            return $path
        }

        # A minimal opted-in plan with exactly one @human step, so the only thing under test is the
        # presence/shape of that step's details block.
        $newPlan = {
            param(
                [string]$RepoRoot,
                [string]$FolderName,
                [string[]]$DetailBlock,
                [switch]$Archived
            )

            $planDir = if ($Archived) {
                Join-Path $RepoRoot "docs/implementation-plans/archived/$FolderName"
            }
            else {
                Join-Path $RepoRoot "docs/implementation-plans/$FolderName"
            }
            New-Item -ItemType Directory -Path $planDir -Force | Out-Null

            $lines = @(
                '# abc123: Human step fixture'
                '<!-- plan-id: abc123 -->'
                '<!-- evidence: required -->'
                ''
                '## Requirements'
                ''
                '| ID | Requirement | Acceptance Criteria | Phases/Steps |'
                '|----|-------------|---------------------|--------------|'
                '| REQ-1 | Only requirement | `test:fixture-one` | 1.1 |'
                ''
                '## Phase 1: Fixture'
                ''
                '- [ ] 1.1 Operator gate (REQ-1) @human `S`'
            ) + $DetailBlock

            $planFile = Join-Path $planDir 'plan.md'
            Set-Content -LiteralPath $planFile -Value ($lines -join "`n") -Encoding utf8NoBOM
            return $planFile
        }

        $fullDetail = @(
            '  <details><summary>Details</summary>'
            ''
            '  **Steps:**'
            '  1. Do the manual thing.'
            ''
            '  **Verify:** the manual thing took effect.'
            ''
            '  **Rollback:** undo the manual thing.'
            ''
            '  </details>'
        )

        $runValidator = {
            param([string]$PlanFile, [string]$RepoRoot)
            # Write-Host goes to the information stream in PowerShell 7; `*>&1` is what actually captures it.
            $output = & $testPlanScript -PlanPath $PlanFile -RepoRoot $RepoRoot -Stage Draft *>&1
            return [pscustomobject]@{
                ExitCode = $LASTEXITCODE
                Text     = ($output | Out-String)
            }
        }
    }

    Context 'validator' {
        It 'test:human-step-detail-gate-fails blocks an @human step with no details block' {
            $root = & $newTempPlansRoot
            try {
                $planFile = & $newPlan -RepoRoot $root -FolderName '2026-01-01-abc123-no-detail' -DetailBlock @()
                $result = & $runValidator -PlanFile $planFile -RepoRoot $root

                $result.ExitCode | Should -Be 1
                $result.Text | Should -Match 'ERROR: human-step-detail'
                $result.Text | Should -Match "step '1\.1'"
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:human-step-detail-gate-fails blocks a details block missing any required section' {
            foreach ($omitted in @('Steps', 'Verify', 'Rollback')) {
                $root = & $newTempPlansRoot
                try {
                    $partial = @($fullDetail | Where-Object { $_ -notmatch "\*\*${omitted}:" })
                    $planFile = & $newPlan -RepoRoot $root -FolderName "2026-01-01-abc123-no-$($omitted.ToLowerInvariant())" -DetailBlock $partial
                    $result = & $runValidator -PlanFile $planFile -RepoRoot $root

                    $result.ExitCode | Should -Be 1 -Because "omitting **$omitted** must fail the gate"
                    $result.Text | Should -Match "human-step-detail.*\*\*$omitted\*\*"
                }
                finally {
                    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }

        It 'test:human-step-detail-gate-passes accepts a details block carrying Steps, Verify, and Rollback' {
            $root = & $newTempPlansRoot
            try {
                $planFile = & $newPlan -RepoRoot $root -FolderName '2026-01-01-abc123-full-detail' -DetailBlock $fullDetail
                $result = & $runValidator -PlanFile $planFile -RepoRoot $root

                $result.ExitCode | Should -Be 0
                $result.Text | Should -Not -Match 'human-step-detail'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:human-step-detail-gate-passes leaves @ai-agent steps alone' {
            $root = & $newTempPlansRoot
            try {
                $planFile = & $newPlan -RepoRoot $root -FolderName '2026-01-01-abc123-agent-step' -DetailBlock @()
                (Get-Content -LiteralPath $planFile -Raw).Replace(' @human ', ' ') |
                    Set-Content -LiteralPath $planFile -Encoding utf8NoBOM

                $result = & $runValidator -PlanFile $planFile -RepoRoot $root
                $result.ExitCode | Should -Be 0
                $result.Text | Should -Not -Match 'human-step-detail'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:human-step-detail-gate-passes warns instead of failing for archived plans' {
            # Archived plans are historical records; a gate added afterwards must not retroactively fail them.
            $root = & $newTempPlansRoot
            try {
                $planFile = & $newPlan -RepoRoot $root -FolderName '2026-01-01-abc123-archived' -DetailBlock @() -Archived
                $result = & $runValidator -PlanFile $planFile -RepoRoot $root

                $result.ExitCode | Should -Be 0
                $result.Text | Should -Match 'WARN: human-step-detail'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'parser' {
        It 'test:human-step-detail-gate-passes captures the details block on the step it belongs to' {
            $root = & $newTempPlansRoot
            try {
                $planFile = & $newPlan -RepoRoot $root -FolderName '2026-01-01-abc123-parse' -DetailBlock $fullDetail
                $metadata = Get-PlanMetadata -Path $planFile -RepoRoot $root

                $step = @($metadata.Steps | Where-Object { $_.Id -eq '1.1' })[0]
                $step.Detail | Should -Match '\*\*Steps:\*\*'
                $step.Detail | Should -Match '\*\*Verify:\*\*'
                $step.Detail | Should -Match '\*\*Rollback:\*\*'
                $step.Detail | Should -Match '</details>'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:human-step-detail-gate-fails does not leak one step''s detail onto the next step' {
            $root = & $newTempPlansRoot
            try {
                $planFile = & $newPlan -RepoRoot $root -FolderName '2026-01-01-abc123-leak' -DetailBlock ($fullDetail + @('', '- [ ] 1.2 Second operator gate (REQ-1) @human `S`'))
                $metadata = Get-PlanMetadata -Path $planFile -RepoRoot $root

                $second = @($metadata.Steps | Where-Object { $_.Id -eq '1.2' })[0]
                $second.Detail | Should -BeNullOrEmpty

                $result = & $runValidator -PlanFile $planFile -RepoRoot $root
                $result.ExitCode | Should -Be 1
                $result.Text | Should -Match "step '1\.2'"
                $result.Text | Should -Not -Match "step '1\.1'"
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:human-step-detail-gate-passes keeps fenced operator commands in the captured detail' {
            # Handoffs routinely contain fenced commands; the parser reads fence-stripped lines, so the
            # detail text must come from the raw lines or the operator loses exactly what they must run.
            $root = & $newTempPlansRoot
            try {
                $withFence = @(
                    '  <details><summary>Details</summary>'
                    ''
                    '  **Steps:**'
                    '  1. Run:'
                    ''
                    '  ```bash'
                    '  az login --tenant contoso'
                    '  ```'
                    ''
                    '  **Verify:** the login succeeded.'
                    ''
                    '  **Rollback:** az logout.'
                    ''
                    '  </details>'
                )
                $planFile = & $newPlan -RepoRoot $root -FolderName '2026-01-01-abc123-fenced' -DetailBlock $withFence
                $metadata = Get-PlanMetadata -Path $planFile -RepoRoot $root

                $step = @($metadata.Steps | Where-Object { $_.Id -eq '1.1' })[0]
                $step.Detail | Should -Match 'az login --tenant contoso'

                (& $runValidator -PlanFile $planFile -RepoRoot $root).ExitCode | Should -Be 0
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:human-step-detail-gate-passes closes on the matching tag when details blocks nest' {
            $root = & $newTempPlansRoot
            try {
                $nested = @(
                    '  <details><summary>Details</summary>'
                    ''
                    '  **Steps:**'
                    '  1. Expand the sub-note:'
                    '     <details><summary>Sub-note</summary>'
                    '     Extra context.'
                    '     </details>'
                    ''
                    '  **Verify:** the thing happened.'
                    ''
                    '  **Rollback:** undo it.'
                    ''
                    '  </details>'
                )
                $planFile = & $newPlan -RepoRoot $root -FolderName '2026-01-01-abc123-nested' -DetailBlock $nested
                $metadata = Get-PlanMetadata -Path $planFile -RepoRoot $root

                $step = @($metadata.Steps | Where-Object { $_.Id -eq '1.1' })[0]
                $step.Detail | Should -Match '\*\*Verify:\*\*'
                $step.Detail | Should -Match '\*\*Rollback:\*\*'

                (& $runValidator -PlanFile $planFile -RepoRoot $root).ExitCode | Should -Be 0
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:human-step-detail-gate-passes reads every details block under the step, not just the first' {
            # Plans also carry Result/evidence blocks under a step; keying on the first block would
            # misread one of those as the operator handoff.
            $root = & $newTempPlansRoot
            try {
                $resultFirst = @(
                    '  <details><summary>Result (2026-01-01)</summary>'
                    '  Prior run output.'
                    '  </details>'
                    ''
                ) + $fullDetail
                $planFile = & $newPlan -RepoRoot $root -FolderName '2026-01-01-abc123-two-blocks' -DetailBlock $resultFirst
                $result = & $runValidator -PlanFile $planFile -RepoRoot $root

                $result.ExitCode | Should -Be 0
                $result.Text | Should -Not -Match 'human-step-detail'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:human-step-detail-gate-fails treats an unterminated block the same wherever it appears' {
            $root = & $newTempPlansRoot
            try {
                $unterminated = @(
                    '  <details><summary>Details</summary>'
                    ''
                    '  **Steps:**'
                    '  1. Do the thing.'
                    ''
                    '- [ ] 1.2 Second operator gate (REQ-1) @human `S`'
                    '  <details><summary>Details</summary>'
                    ''
                    '  **Steps:**'
                    '  1. Do the other thing.'
                )
                $planFile = & $newPlan -RepoRoot $root -FolderName '2026-01-01-abc123-unterminated' -DetailBlock $unterminated
                $metadata = Get-PlanMetadata -Path $planFile -RepoRoot $root

                # Both blocks are unterminated; both must be kept, and both must fail for the same reason.
                foreach ($id in @('1.1', '1.2')) {
                    $step = @($metadata.Steps | Where-Object { $_.Id -eq $id })[0]
                    $step.Detail | Should -Match '\*\*Steps:\*\*'
                }

                $result = & $runValidator -PlanFile $planFile -RepoRoot $root
                $result.ExitCode | Should -Be 1
                foreach ($id in @('1.1', '1.2')) {
                    $result.Text | Should -Match "human-step-detail: step '$([regex]::Escape($id))'.*\*\*Verify\*\*"
                }
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:human-step-detail-gate-passes accepts the sections as list items' {
            $root = & $newTempPlansRoot
            try {
                $bulleted = @(
                    '  <details><summary>Details</summary>'
                    ''
                    '  - **Steps:** do the thing.'
                    '  - **Verify:** it took effect.'
                    '  - **Rollback:** undo it.'
                    ''
                    '  </details>'
                )
                $planFile = & $newPlan -RepoRoot $root -FolderName '2026-01-01-abc123-bulleted' -DetailBlock $bulleted
                (& $runValidator -PlanFile $planFile -RepoRoot $root).ExitCode | Should -Be 0
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:human-step-detail-gate-passes classifies archived plans by path, not by the -RepoRoot argument' {
            $root = & $newTempPlansRoot
            try {
                $planFile = & $newPlan -RepoRoot $root -FolderName '2026-01-01-abc123-relative' -DetailBlock @() -Archived
                $metadata = Get-PlanMetadata -Path $planFile -RepoRoot $root
                $metadata.IsArchived | Should -BeTrue

                Push-Location $root
                try {
                    # A relative repo root must not flip the exemption off.
                    $relative = Get-PlanMetadata -Path $planFile -RepoRoot '.'
                    $relative.IsArchived | Should -BeTrue
                }
                finally {
                    Pop-Location
                }
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'handoff' {
        It 'test:ci-human-handoff-detail prints the full detail block when the next step is @human' {
            $root = & $newTempPlansRoot
            try {
                $planFile = & $newPlan -RepoRoot $root -FolderName '2026-01-01-abc123-handoff' -DetailBlock $fullDetail
                $output = (& $planStateScript -Reference 'abc123' -RepoRoot $root -HasUncommittedChanges:$false | Out-String)

                $output | Should -Match '@human'
                $output | Should -Match '(?m)^Handoff:'
                $output | Should -Match '\*\*Steps:\*\*'
                $output | Should -Match '\*\*Verify:\*\*'
                $output | Should -Match '\*\*Rollback:\*\*'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:ci-human-handoff-detail says so plainly when an @human step has no detail block' {
            $root = & $newTempPlansRoot
            try {
                $planFile = & $newPlan -RepoRoot $root -FolderName '2026-01-01-abc123-handoff-bare' -DetailBlock @()
                $output = (& $planStateScript -Reference 'abc123' -RepoRoot $root -HasUncommittedChanges:$false | Out-String)

                $output | Should -Match '(?m)^Handoff:'
                $output | Should -Match 'human-step-detail'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:ci-human-handoff-detail omits the handoff block for @ai-agent steps' {
            $root = & $newTempPlansRoot
            try {
                $planFile = & $newPlan -RepoRoot $root -FolderName '2026-01-01-abc123-handoff-agent' -DetailBlock $fullDetail
                (Get-Content -LiteralPath $planFile -Raw).Replace(' @human ', ' ') |
                    Set-Content -LiteralPath $planFile -Encoding utf8NoBOM

                $output = (& $planStateScript -Reference 'abc123' -RepoRoot $root -HasUncommittedChanges:$false | Out-String)
                $output | Should -Not -Match '(?m)^Handoff:'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'documented shape' {
        BeforeAll {
            $draftingGuidePath = Join-Path $repoRoot 'plugins/create-implementation-plan/skills/cip/assets/drafting-guide.md'
            $planTemplatePath = Join-Path $repoRoot 'plugins/create-implementation-plan/skills/cip/assets/plan-template.md'
            $ciSkillPath = Join-Path $repoRoot 'plugins/continue-implementation/skills/ci/SKILL.md'
            $executionGuidePath = Join-Path $repoRoot 'plugins/continue-implementation/skills/ci/assets/execution-guide.md'

            $readText = {
                param([string]$Path)
                (Get-Content -LiteralPath $Path -Raw) -replace "`r`n", "`n"
            }
        }

        It 'test:ci-human-handoff-detail documents the three required sections in the drafting guide' {
            $guide = & $readText $draftingGuidePath
            $guide | Should -Match 'human-step-detail'
            foreach ($section in @('Steps', 'Verify', 'Rollback')) {
                $guide | Should -Match "\*\*$section\*\*"
            }
        }

        It 'test:ci-human-handoff-detail ships a plan template whose @human examples pass the gate' {
            # The template is the shape every drafted plan copies; an example that fails the gate teaches
            # the wrong shape and ships in the installed payload.
            $templateLines = (& $readText $planTemplatePath).Split("`n")
            $examples = [System.Collections.Generic.List[string]]::new()
            $current = $null
            foreach ($line in $templateLines) {
                if ($line -match '^-\s\[.\]\s+\S+\s') {
                    if ($null -ne $current) { $examples.Add($current -join "`n") }
                    # Direct assignment: an empty List returned as an if-expression value gets enumerated
                    # away to $null by the pipeline.
                    if ($line -match '@human\b') {
                        $current = [System.Collections.Generic.List[string]]::new()
                    }
                    else {
                        $current = $null
                    }
                    continue
                }
                if ($line -match '^##\s') {
                    if ($null -ne $current) { $examples.Add($current -join "`n") }
                    $current = $null
                    continue
                }
                if ($null -ne $current) { $current.Add($line) }
            }
            if ($null -ne $current) { $examples.Add($current -join "`n") }

            $examples.Count | Should -Be 2 -Because 'the template ships one @human phase example and one @human finalization example'
            foreach ($detail in $examples) {
                $detail | Should -Match '<details'
                foreach ($section in @('Steps', 'Verify', 'Rollback')) {
                    $detail | Should -Match "(?im)^\s*(?:[-*+]\s+|\d+\.\s+)?\*\*${section}:?\*\*"
                }
            }
        }

        It 'test:ci-human-handoff-detail tells /ci to print the handoff block instead of the bare title' {
            foreach ($path in @($ciSkillPath, $executionGuidePath)) {
                $text = & $readText $path
                # Anchor on the Handoff sentence itself: a file-wide (?s) span would be satisfied by any
                # unrelated later use of "full"/"verbatim".
                $handoffLine = @(($text.Split("`n")) | Where-Object { $_ -match 'Handoff:' })
                $handoffLine.Count | Should -BeGreaterThan 0
                ($handoffLine -join "`n") | Should -Match 'verbatim'
                ($handoffLine -join "`n") | Should -Match '\*\*Steps\*\*'
                ($handoffLine -join "`n") | Should -Match 'title'
            }
        }
    }
}
