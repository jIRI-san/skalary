#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Dormant direct workflow consumers' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:adapter = Join-Path $script:repoRoot `
            'scripts/skalary/Get-DirectPlanArtifactConsumerContext.ps1'
        $script:activation = Join-Path $script:repoRoot `
            'scripts/skalary/assets/direct-workflow-activation.md'
        $script:targets = [ordered]@{
            cr = 'plugins/code-review/skills/cr/targets/direct/SKILL.md'
            dr = 'plugins/design-review/skills/dr/targets/direct/SKILL.md'
            cep = 'plugins/create-implementation-plan/skills/cep/targets/direct/SKILL.md'
            cip = 'plugins/create-implementation-plan/skills/cip/targets/direct/SKILL.md'
            ci = 'plugins/continue-implementation/skills/ci/targets/direct/SKILL.md'
            autopilotSkill = 'plugins/autopilot/skills/autopilot/targets/direct/SKILL.md'
            autopilotAgent = 'plugins/autopilot/agents/targets/direct/autopilot.agent.md'
        }
        $script:scratch = [System.Collections.Generic.List[string]]::new()

        function New-DirectConsumerFixture {
            $root = Join-Path $script:repoRoot (
                'tests\.direct-consumer-' + [guid]::NewGuid().ToString('N')
            )
            $script:scratch.Add($root)
            $plan = Join-Path $root `
                'docs\implementation-plans\standalone-2026-01-01-abc123-direct-history'
            $assets = Join-Path $plan 'assets'
            $reviews = Join-Path $assets 'reviews'
            New-Item -ItemType Directory -Path $reviews -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $plan 'plan.md') -Encoding utf8NoBOM -NoNewline -Value @'
# abc123: Direct history
<!-- plan-id: abc123 -->

## Phase 1: Fixture

- [x] 1.1 Complete fixture `S`
'@
            Set-Content -LiteralPath (Join-Path $assets 'requirements.md') `
                -Encoding utf8NoBOM -Value '# Requirements'
            Set-Content -LiteralPath (Join-Path $assets 'intent.md') `
                -Encoding utf8NoBOM -Value "# Intent`n`nCurrent operator intent."
            Set-Content -LiteralPath (Join-Path $assets 'design.md') `
                -Encoding utf8NoBOM -Value "# Design`n`nCurrent design."
            Set-Content -LiteralPath (Join-Path $reviews 'phase-1.md') `
                -Encoding utf8NoBOM -Value @'
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
            return [pscustomobject]@{ Root = $root; Assets = $assets }
        }
    }

    AfterEach {
        foreach ($path in @($script:scratch)) {
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
        }
        $script:scratch.Clear()
    }

    It 'provides a complete explicitly dormant target for every consumer' {
        foreach ($entry in $script:targets.GetEnumerator()) {
            $path = Join-Path $script:repoRoot $entry.Value
            $path | Should -Exist
            (Get-Content -LiteralPath $path -Raw) |
                Should -Match 'DORMANT TARGET' -Because "$($entry.Key) must not activate early"
        }

        $expectations = @{
            cr = @('no fixed concern matrix', 'Write-DirectReviewReport', 'read-only', 'five maximum')
            dr = @('no fixed concern matrix', 'Write-DirectReviewReport', 'read-only', 'five maximum')
            cep = @('decision-ready', 'condition/behavior/exception', 'combined design/requirements', 'Judge')
            cip = @('fuzzy requirements', 'current intent, requirements, risks, and decisions', 'Judge', 'five maximum')
            ci = @('Test-PlanCriteriaBaseline', 'Invoke-DirectEvidence', 'terminal phase skips post-phase review', 'direct learning handoff')
            autopilotSkill = @('Test-PlanCriteriaBaseline', 'duration alone never cancels', 'deterministic build, test, command', 'direct learning handoff')
            autopilotAgent = @('Invoke-DirectEvidence', 'one whole-plan direct CR', 'at most 10 items', 'Never cancel because elapsed agent time')
        }
        foreach ($entry in $expectations.GetEnumerator()) {
            $content = Get-Content -LiteralPath (
                Join-Path $script:repoRoot $script:targets[$entry.Key]
            ) -Raw
            foreach ($token in $entry.Value) {
                $content | Should -Match ([regex]::Escape($token))
            }
        }
    }

    It 'keeps every active entry point and manifest on the legacy path' {
        $active = @(
            'plugins/code-review/skills/cr/SKILL.md'
            'plugins/design-review/skills/dr/SKILL.md'
            'plugins/create-implementation-plan/skills/cep/SKILL.md'
            'plugins/create-implementation-plan/skills/cip/SKILL.md'
            'plugins/continue-implementation/skills/ci/SKILL.md'
            'plugins/autopilot/skills/autopilot/SKILL.md'
            'plugins/autopilot/agents/autopilot.agent.md'
            'plugins/code-review/plugin.json'
            'plugins/design-review/plugin.json'
            'plugins/create-implementation-plan/plugin.json'
            'plugins/continue-implementation/plugin.json'
            'plugins/autopilot/plugin.json'
        )
        foreach ($relative in $active) {
            $content = Get-Content -LiteralPath (Join-Path $script:repoRoot $relative) -Raw
            $content | Should -Not -Match 'Get-DirectPlanArtifactConsumerContext'
            $content | Should -Not -Match 'DirectWorkflow'
            $content | Should -Not -Match 'targets/direct'
        }

        Get-ChildItem -LiteralPath (Join-Path $script:repoRoot '.github') -Recurse -File -Force |
            ForEach-Object {
                (Get-Content -LiteralPath $_.FullName -Raw) |
                    Should -Not -Match 'Get-DirectPlanArtifactConsumerContext|DirectWorkflow|targets/direct'
            }
    }

    It 'records the canonical closure and exact delayed activation sequence' {
        $content = Get-Content -LiteralPath $script:activation -Raw
        foreach ($token in @(
                'DirectWorkflow.psm1`, `PlanState.psm1`, `SecretGuard.psm1'
                'Get-DirectPlanArtifactConsumerContext.ps1'
                'Sync-PluginScripts.ps1'
                'Build-Registry.ps1'
                'Sync-Dogfood.ps1'
                'Step 2.2'
                'compatibility flag'
            )) {
            $content | Should -Match ([regex]::Escape($token))
        }
    }

    It 'reads direct stage Markdown without a receipt and frames it once as untrusted data' {
        $fixture = New-DirectConsumerFixture
        $result = & $script:adapter -PlanId abc123 -ArtifactKind Intent, Reviews `
            -Relationship reuses -RepoRoot $fixture.Root

        @($result.accepted).Count | Should -Be 2
        @($result.accepted | ForEach-Object artifactKind) | Should -Be @('Intent', 'Reviews')
        @($result.accepted | ForEach-Object path) |
            Should -Contain 'docs/implementation-plans/standalone-2026-01-01-abc123-direct-history/assets/reviews/phase-1.md'
        $result.untrustedInput | Should -Match '^<UNTRUSTED_INPUT_'
        ([regex]::Matches($result.untrustedInput, '<UNTRUSTED_INPUT_')).Count | Should -Be 1
        $result.untrustedInput | Should -Match '"content":"## Source'
        $result.untrustedInput | Should -Not -Match 'receipt'
    }

    It 'refuses secrets and over-budget historical selection' {
        $fixture = New-DirectConsumerFixture
        Set-Content -LiteralPath (Join-Path $fixture.Assets 'design.md') `
            -Encoding utf8NoBOM -Value (
                '# Design' + "`n`n" + 'ghp_a1B2c3D4e5F6g7H8i9J0k1L2m3N4o5P6q7R8'
            )

        $result = & $script:adapter -PlanId abc123 -ArtifactKind Design `
            -Relationship reuses -RepoRoot $fixture.Root
        @($result.accepted).Count | Should -Be 0
        @($result.diagnostics).Count | Should -Be 1
        $result.diagnostics[0].reason | Should -Match 'credential'
        $result.untrustedInput | Should -BeNullOrEmpty

        {
            & $script:adapter -PlanId abc123 -ArtifactKind Intent, Design `
                -Relationship reuses -RepoRoot $fixture.Root -MaxCandidates 1
        } | Should -Throw '*supporting-artifact limit*'
    }
}
