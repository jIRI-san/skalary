#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Plan c21cdc REQ-9, RISK-10. Two sibling plans are supposed to consume this plan's v1 contract
# rather than invent a second one: `8a0644` produces frozen task plans through it and `ca8ba8` adds
# corroboration policy on top of it. That is only true if the dependency exists in the graph the
# workflow actually resolves, so both edges are read through `PlanState` rather than grepped, and
# the state rule they exist to produce — a dependent is blocked exactly while its dependency is
# incomplete — is proven on a synthetic plan tree as well as on the real one.
#
# The synthetic half matters because the real half is time-dependent: once `c21cdc` completes and is
# archived, the live plans stop being blocked. An assertion that they are blocked *today* would have
# to be deleted then; the equivalence asserted here holds before and after.
Describe 'review-run consumer edges' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        Import-Module (Join-Path $script:repoRoot 'scripts/skalary/PlanState.psm1') -Force -DisableNameChecking
        $script:newEpic = Join-Path $script:repoRoot 'scripts/skalary/New-Epic.ps1'

        $script:consumers = @(
            [pscustomobject]@{
                Id = 'ca8ba8'
                Path = 'docs/implementation-plans/2026-08-08-ca8ba8-review-corroboration-truth/plan.md'
                Owns = 'later similarity and corroboration policy'
            }
            [pscustomobject]@{
                Id = '8a0644'
                Path = 'docs/implementation-plans/2026-08-08-8a0644-dispatch-plan-up-front/plan.md'
                Owns = 'future fleet task planning'
            }
        )

        $script:newSyntheticRoot = {
            $path = Join-Path ([System.IO.Path]::GetTempPath()) ('review-consumer-' + [System.Guid]::NewGuid().ToString('N'))
            [void](New-Item -ItemType Directory -Path (Join-Path $path 'docs/implementation-plans/archived') -Force)
            return $path
        }

        $script:newSyntheticPlan = {
            param([string]$Root, [string]$PlanId, [string]$Slug, [int]$Done = 0, [int]$Steps = 2, [switch]$Archived)

            $parent = if ($Archived) { 'docs/implementation-plans/archived' } else { 'docs/implementation-plans' }
            $dir = Join-Path $Root "$parent/2026-08-02-$PlanId-$Slug"
            [void](New-Item -ItemType Directory -Path $dir -Force)
            $stepLines = for ($i = 1; $i -le $Steps; $i++) {
                $mark = if ($i -le $Done) { 'x' } else { ' ' }
                "- [$mark] 1.$i Step $i (REQ-1) ``S``"
            }
            $content = @(
                "# ${PlanId}: $Slug"
                "<!-- plan-id: $PlanId -->"
                ''
                '## Requirements'
                ''
                '| ID | Requirement | Acceptance Criteria | Phases/Steps |'
                '|----|-------------|---------------------|--------------|'
                '| REQ-1 | Synthetic requirement | `test:synthetic-one` | 1.1 |'
                ''
                '## Phase 1: Fixture'
                ''
            ) + $stepLines
            Set-Content -LiteralPath (Join-Path $dir 'plan.md') -Value (($content -join "`n") + "`n") -Encoding utf8NoBOM
            return $dir
        }
    }

    It 'test:Epic.ReviewRunConsumerEdgesAndState carries c21cdc in both consumer dependency markers' {
        $inventory = @(Get-PlanInventory -RepoRoot $script:repoRoot)
        $self = Resolve-Plan -Reference 'c21cdc' -RepoRoot $script:repoRoot -Inventory $inventory
        $self.Id | Should -Be 'c21cdc' -Because 'the dependency has to resolve to exactly one plan or every edge below is ambiguous'

        foreach ($consumer in $script:consumers) {
            $planFile = Join-Path $script:repoRoot $consumer.Path
            Test-Path -LiteralPath $planFile -PathType Leaf |
                Should -BeTrue -Because "REQ-9 names $($consumer.Id) as the owner of $($consumer.Owns)"

            $markers = Get-PlanHeaderMarkers -Path $planFile
            @($markers.DependsOn) |
                Should -Contain 'c21cdc' -Because "$($consumer.Id) must consume v1 rather than redefine it"

            # Read from the header view, so a plan that merely mentions the id in its body does not
            # count as declaring the edge.
            $header = (Split-PlanHeader -Content (Get-Content -LiteralPath $planFile -Raw)).Header
            $header | Should -Match '<!--\s*depends-on:[^>]*c21cdc'
        }
    }

    It 'test:Epic.ReviewRunConsumerEdgesAndState resolves both edges through the epic rollup and keeps blocked equivalent to an incomplete dependency' {
        $inventory = @(Get-PlanInventory -RepoRoot $script:repoRoot)

        foreach ($consumer in $script:consumers) {
            $entry = @($inventory | Where-Object { $_.Id -eq $consumer.Id })
            $entry.Count | Should -Be 1
            [string]$entry[0].EpicId | Should -Not -BeNullOrEmpty -Because 'the rollup resolves edges per epic'

            $rollup = Get-EpicRollup -EpicId ([string]$entry[0].EpicId) -RepoRoot $script:repoRoot -Inventory $inventory
            $child = @($rollup.Children | Where-Object { $_.Id -eq $consumer.Id })
            $child.Count | Should -Be 1

            @($child[0].DependsOn) | Should -Contain 'c21cdc'
            @($child[0].UnknownDependsOn).Count |
                Should -Be 0 -Because "an unresolvable token would block $($consumer.Id) for the wrong reason"

            # The equivalence, computed from the dependencies rather than restated: a child is
            # blocked exactly while it is incomplete and at least one dependency is incomplete.
            $incomplete = [System.Collections.Generic.List[string]]::new()
            foreach ($token in @($child[0].DependsOn)) {
                $dependency = Resolve-Plan -Reference $token -RepoRoot $script:repoRoot -Inventory $inventory
                $progress = Get-PlanProgress -Metadata (Get-PlanMetadata -Path (Join-Path $dependency.Path 'plan.md') -RepoRoot $script:repoRoot)
                if (-not ($progress.IsComplete -or $dependency.IsArchived)) { $incomplete.Add($dependency.Id) }
            }

            $expectedBlocked = (-not $child[0].IsComplete) -and ($incomplete.Count -gt 0)
            $child[0].IsBlocked |
                Should -Be $expectedBlocked -Because "$($consumer.Id) must be blocked exactly while a dependency is incomplete"

            @($child[0].UnmetDependsOn | Sort-Object) |
                Should -Be @($incomplete | Sort-Object) -Because 'the rollup must report exactly the dependencies that are still incomplete'
        }
    }

    It 'test:Epic.ReviewRunConsumerEdgesAndState proves the same state rule on a synthetic incomplete, complete and archived dependency' {
        $root = & $script:newSyntheticRoot
        try {
            & $script:newSyntheticPlan -Root $root -PlanId 'c21cdc' -Slug 'contract' -Done 0 -Steps 2 | Out-Null
            & $script:newSyntheticPlan -Root $root -PlanId '8a0644' -Slug 'producer' -Done 0 -Steps 2 | Out-Null
            & $script:newSyntheticPlan -Root $root -PlanId 'ca8ba8' -Slug 'consumer' -Done 0 -Steps 2 | Out-Null

            & $script:newEpic -Title 'Review runs' -Slug 'review-runs' -RepoRoot $root -EpicId 'aa11bb' -ChildPlan 'c21cdc' | Out-Null
            & $script:newEpic -Epic 'aa11bb' -RepoRoot $root -ChildPlan '8a0644' -DependsOn 'c21cdc' | Out-Null
            & $script:newEpic -Epic 'aa11bb' -RepoRoot $root -ChildPlan 'ca8ba8' -DependsOn 'c21cdc' | Out-Null

            $blocked = Get-EpicRollup -EpicId 'aa11bb' -RepoRoot $root
            $blocked.ChildCount | Should -Be 3
            foreach ($id in @('8a0644', 'ca8ba8')) {
                $child = @($blocked.Children | Where-Object { $_.Id -eq $id })[0]
                $child.IsBlocked | Should -BeTrue -Because "$id depends on an incomplete c21cdc"
                @($child.UnmetDependsOn) | Should -Be @('c21cdc')
            }
            $blocked.NextChild.Id | Should -Be 'c21cdc' -Because 'the dependency is the only child that can start'

            # Complete the dependency: both consumers unblock, and nothing else changes.
            & $script:newSyntheticPlan -Root $root -PlanId 'c21cdc' -Slug 'contract' -Done 2 -Steps 2 | Out-Null
            $unblocked = Get-EpicRollup -EpicId 'aa11bb' -RepoRoot $root
            foreach ($id in @('8a0644', 'ca8ba8')) {
                $child = @($unblocked.Children | Where-Object { $_.Id -eq $id })[0]
                $child.IsBlocked | Should -BeFalse -Because "$id must start once v1 exists"
                @($child.UnmetDependsOn).Count | Should -Be 0
            }

            # Archival is the terminal state of the workflow, so an archived dependency must not
            # leave a dependent blocked forever — which is the state the real graph ends in.
            Remove-Item -LiteralPath (Join-Path $root 'docs/implementation-plans/2026-08-02-c21cdc-contract') -Recurse -Force
            & $script:newSyntheticPlan -Root $root -PlanId 'c21cdc' -Slug 'contract' -Done 0 -Steps 2 -Archived | Out-Null
            $archived = Get-EpicRollup -EpicId 'aa11bb' -RepoRoot $root
            foreach ($id in @('8a0644', 'ca8ba8')) {
                $child = @($archived.Children | Where-Object { $_.Id -eq $id })[0]
                $child.IsBlocked | Should -BeFalse -Because "$id must not stay blocked behind an archived dependency"
            }
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
