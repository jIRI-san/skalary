#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Active direct workflow consumers' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:adapter = Join-Path $script:repoRoot 'scripts/skalary/Get-DirectPlanArtifactConsumerContext.ps1'
        $script:installedAdapter = Join-Path $script:repoRoot (
            '.github/skills/cr/scripts/Get-DirectPlanArtifactConsumerContext.ps1'
        )
        $script:siReader = Join-Path $script:repoRoot '.github/skills/si/scripts/Get-SiHarvest.ps1'
        $script:learningWriter = Join-Path $script:repoRoot 'scripts/skalary/Write-RecentLearning.ps1'
        $script:active = @(
            'plugins/code-review/skills/cr/SKILL.md'
            'plugins/design-review/skills/dr/SKILL.md'
            'plugins/create-implementation-plan/skills/cep/SKILL.md'
            'plugins/create-implementation-plan/skills/cip/SKILL.md'
            'plugins/continue-implementation/skills/ci/SKILL.md'
            'plugins/autopilot/skills/autopilot/SKILL.md'
            'plugins/autopilot/agents/autopilot.agent.md'
        )
        $script:scratch = [System.Collections.Generic.List[string]]::new()

        function New-DirectConsumerFixture {
            param([switch]$Learning)
            $root = Join-Path $script:repoRoot ('tests\.direct-consumer-' + [guid]::NewGuid().ToString('N'))
            $script:scratch.Add($root)
            $plan = Join-Path $root 'docs\implementation-plans\standalone-2026-01-01-abc123-direct-history'
            $assets = Join-Path $plan 'assets'
            $reviews = Join-Path $assets 'reviews'
            New-Item -ItemType Directory -Path $reviews -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $plan 'plan.md') -Encoding utf8NoBOM -Value @'
# abc123: Direct history
<!-- plan-id: abc123 -->

## Phase 1: Fixture

- [x] 1.1 Complete fixture `S`
'@
            Set-Content -LiteralPath (Join-Path $assets 'requirements.md') -Encoding utf8NoBOM `
                -Value "# Requirements`n`n| ID | Requirement | Acceptance Criteria | Phases/Steps |`n|---|---|---|---|`n| REQ-1 | Direct | file:README.md#exists | 1.1 |"
            Set-Content -LiteralPath (Join-Path $assets 'intent.md') -Encoding utf8NoBOM `
                -Value "# Intent`n`nCurrent operator intent."
            Set-Content -LiteralPath (Join-Path $assets 'design.md') -Encoding utf8NoBOM `
                -Value "# Design`n`nCurrent design."
            Set-Content -LiteralPath (Join-Path $reviews 'phase-1.md') -Encoding utf8NoBOM -Value @'
## Source

1111111111111111111111111111111111111111

## Scope

- src/example.ps1

## Completed tasks

- [x] combined review — complete

## Findings

None.

## Verdict

clean
'@
            Set-Content -LiteralPath (Join-Path $root 'README.md') -Encoding utf8NoBOM -Value '# Fixture'
            & git -C $root init -q
            & git -C $root config user.email fixture@example.test
            & git -C $root config user.name Fixture
            & git -C $root add .
            & git -C $root commit -qm initial
            $base = (& git -C $root rev-parse HEAD).Trim()
            if ($Learning) {
                & $script:learningWriter -RepoRoot $root -PlanReference abc123 -SourceCommit $base `
                    -Lesson 'Keep direct evidence bounded.' -Citation 'README.md' | Out-Null
                & git -C $root add .
                & git -C $root commit -qm learning
            }
            [pscustomobject]@{
                Root = $root
                Assets = $assets
                Base = $base
                Head = (& git -C $root rev-parse HEAD).Trim()
            }
        }
    }

    AfterEach {
        foreach ($path in @($script:scratch)) {
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
        }
        $script:scratch.Clear()
    }

    It 'activates every direct target and removes dormant scaffolds' {
        foreach ($relative in $script:active) {
            $content = Get-Content -LiteralPath (Join-Path $script:repoRoot $relative) -Raw
            $content | Should -Match 'DirectWorkflow|direct'
            $content | Should -Not -Match 'DORMANT TARGET|targets/direct'
        }
        @(Get-ChildItem -LiteralPath (Join-Path $script:repoRoot 'plugins') -Recurse -Directory |
                Where-Object { $_.FullName -match '[\\/]targets[\\/]direct$' }).Count | Should -Be 0
    }

    It 'installs direct closures and no retired workflow payloads' {
        foreach ($plugin in @('code-review', 'design-review', 'create-implementation-plan',
                'continue-implementation', 'autopilot')) {
            $manifest = Get-Content -LiteralPath (
                Join-Path $script:repoRoot "plugins/$plugin/plugin.json"
            ) -Raw | ConvertFrom-Json
            $destinations = @($manifest.files | ForEach-Object { [string]$_.dest })
            $destinations -join "`n" | Should -Not -Match (
                'ReviewRun|Build-ReviewReport|FleetDispatch|EvidenceReceipt|PhaseHarvest|' +
                'ReviewCycle|ReviewResultReceipt|LedgerStore|review/schemas'
            )
        }
        foreach ($skill in @('cr', 'dr', 'ci', 'autopilot')) {
            $scriptRoot = Join-Path $script:repoRoot "plugins"
            $matches = @(Get-ChildItem -LiteralPath $scriptRoot -Recurse -File -Filter DirectWorkflow.psm1 |
                    Where-Object { $_.FullName -match "[\\/]skills[\\/]$skill[\\/]scripts[\\/]" })
            $matches.Count | Should -Be 1
        }
    }

    It 'reads direct stage Markdown without receipt authority and frames it once' {
        $fixture = New-DirectConsumerFixture
        foreach ($adapterPath in @($script:adapter, $script:installedAdapter)) {
            $result = & $adapterPath -PlanId abc123 -ArtifactKind Intent, Reviews `
                -Relationship reuses -RepoRoot $fixture.Root
            @($result.accepted).Count | Should -Be 2
            $result.untrustedInput | Should -Match '^<UNTRUSTED_INPUT_'
            ([regex]::Matches($result.untrustedInput, '<UNTRUSTED_INPUT_')).Count | Should -Be 1
            $result.untrustedInput | Should -Not -Match '"receipt"'
        }
    }

    It 'keeps the historical adapter dependency closure direct and Markdown-only' {
        $forbidden = @(
            'ReviewRun', 'ReviewResultReceipt', 'PlanEvidence', 'LedgerStore',
            'Invoke-PhaseHarvest', 'Build-EvidenceReceipt', 'Get-ReviewRun'
        )
        foreach ($adapterPath in @(
                $script:adapter,
                'plugins/code-review/skills/cr/scripts/Get-DirectPlanArtifactConsumerContext.ps1',
                'plugins/design-review/skills/dr/scripts/Get-DirectPlanArtifactConsumerContext.ps1',
                'plugins/create-implementation-plan/skills/cip/scripts/Get-DirectPlanArtifactConsumerContext.ps1',
                'plugins/create-implementation-plan/skills/cep/scripts/Get-DirectPlanArtifactConsumerContext.ps1',
                $script:installedAdapter
            )) {
            $resolved = if ([System.IO.Path]::IsPathRooted($adapterPath)) {
                $adapterPath
            }
            else {
                Join-Path $script:repoRoot $adapterPath
            }
            $content = [System.IO.File]::ReadAllText($resolved)
            foreach ($token in $forbidden) {
                $content | Should -Not -Match ([regex]::Escape($token))
            }
            $imports = @(
                [regex]::Matches(
                    $content,
                    "Import-Module \(Join-Path \`$PSScriptRoot '(?<name>[^']+)'\)"
                ) | ForEach-Object { $_.Groups['name'].Value }
            )
            $imports | Should -Be @(
                'PlanState.psm1', 'SecretGuard.psm1', 'DirectWorkflow.psm1'
            )
            $content | Should -Match "supportedKinds = @\('Intent', 'Design', 'Decisions', 'Reviews', 'Learnings'\)"
            $content | Should -Match '\(\?:phase-\[1-9\]\[0-9\]\*\|final\)\\\.md'
        }
    }

    It 'distinguishes missing valid empty and stale recent learning with read-time fencing' {
        $missing = New-DirectConsumerFixture
        (& $script:siReader -RepoRoot $missing.Root -PlanReference abc123 `
                -PinnedBaseOid $missing.Head).Status | Should -Be 'missing'

        $valid = New-DirectConsumerFixture -Learning
        $validResult = & $script:siReader -RepoRoot $valid.Root -PlanReference abc123 `
            -PinnedBaseOid $valid.Head
        $validResult.Status | Should -Be 'valid'
        $validResult.Items[0].wrappedContent | Should -Match '^<UNTRUSTED_INPUT_'

        $learningPath = Join-Path $valid.Root 'docs\feedback\recent-learning.md'
        (Get-Content -LiteralPath $learningPath -Raw).Replace(
            'Source plan: `abc123 direct-history`',
            'Source plan: `ffffff other-plan`'
        ) |
            Set-Content -LiteralPath $learningPath -Encoding utf8NoBOM
        & git -C $valid.Root add .
        & git -C $valid.Root commit -qm stale
        $staleHead = (& git -C $valid.Root rev-parse HEAD).Trim()
        (& $script:siReader -RepoRoot $valid.Root -PlanReference abc123 `
                -PinnedBaseOid $staleHead).Status | Should -Be 'stale'

        $empty = New-DirectConsumerFixture
        & $script:learningWriter -RepoRoot $empty.Root -PlanReference abc123 `
            -SourceCommit $empty.Base | Out-Null
        & git -C $empty.Root add .
        & git -C $empty.Root commit -qm empty
        $emptyHead = (& git -C $empty.Root rev-parse HEAD).Trim()
        (& $script:siReader -RepoRoot $empty.Root -PlanReference abc123 `
                -PinnedBaseOid $emptyHead).Status | Should -Be 'empty'
    }

    It 'has no active retired machinery or elapsed agent kill path' {
        foreach ($relative in @(
                'schemas/review'
                'scripts/skalary/ReviewRun.psm1'
                'scripts/skalary/FleetDispatch.psm1'
                'scripts/skalary/Build-EvidenceReceipt.ps1'
                'scripts/skalary/Invoke-PhaseHarvest.ps1'
                'scripts/skalary/Repair-Plans.ps1'
                'docs/review-ledger'
                'tools/review-concerns.json'
            )) {
            Test-Path -LiteralPath (Join-Path $script:repoRoot $relative) | Should -BeFalse
        }
        $runtime = @(
            'plugins/autopilot/scripts/launch-host.ps1'
            'plugins/autopilot/scripts/launch-container.ps1'
            'plugins/autopilot/scripts/launch-sandbox.ps1'
            'plugins/autopilot/scripts/container-entrypoint.sh'
        ) | ForEach-Object { Get-Content -LiteralPath (Join-Path $script:repoRoot $_) -Raw }
        ($runtime -join "`n") | Should -Not -Match 'planTimeout|PHASE_TIMEOUT|timed out after|docker kill'
    }
}
