#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Epic coherency review contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:guidePath = Join-Path $script:repoRoot (
            'plugins/create-implementation-plan/skills/cep/assets/decomposition-guide.md'
        )
        $script:guide = [System.IO.File]::ReadAllText($script:guidePath)
        $handoffIndex = $script:guide.IndexOf(
            '## Epic-review extension handoff (inactive)',
            [System.StringComparison]::Ordinal
        )
        $handoffIndex | Should -BeGreaterOrEqual 0
        $script:handoff = $script:guide.Substring($handoffIndex)
    }

    It 'test:EpicCoherency.FixedScope freezes the complete accepted-cut scope' {
        $labels = @(
            'goal-success-coverage'
            'definition-of-done-coverage'
            'verticality'
            'child-independence-overlap'
            'shared-ownership'
            'necessary-direct-acyclic-dependencies'
            'usable-mvp-to-final-route'
            'prior-art-reuse'
        )
        foreach ($label in $labels) {
            ([regex]::Matches($script:handoff, [regex]::Escape("| ``$label`` |"))).Count |
                Should -Be 1
        }

        $script:handoff | Should -Match 'sole accepted-cut design source'
        $script:handoff | Should -Match '\{\s*path:\s*<canonical epic\.md>,\s*status:\s*modified\s*\}'
        $script:handoff | Should -Match 'designSource.*kind:\s*plan'
        $script:handoff | Should -Match 'exact snapshot bytes'
        $script:handoff | Should -Match 'byte-identical envelope for every frozen'
    }

    It 'test:EpicCoherency.IntentAndOwnership checks intent, duplication, ownership, and edges' {
        $script:handoff | Should -Match 'confirmed Goal, desired outcome, success'
        $script:handoff | Should -Match 'every proposed mechanism in canonical child then'
        $script:handoff | Should -Match 'exactly one owning child'
        $script:handoff | Should -Match 'names all\s+consuming children/plans'
        $script:handoff | Should -Match 'Compare delivered semantic capability, not mechanism names'
        $script:handoff | Should -Match 'after consolidation to one owner with every consumer'
        $script:handoff | Should -Match 'dependent cannot implement or validate its delivered slice'
        $script:handoff | Should -Match 'Reject transitive, convenience, sequencing,\s+platform-first, and infrastructure-only edges'
        $script:handoff | Should -Match 'Prefer deletion, reuse of accepted prior art, or the narrowest repair'
    }

    It 'test:EpicCoherency.ProportionalityGuardrail rejects unjustified platform machinery' {
        foreach ($class in @('required shared contract', 'speculative platform', 'local fix')) {
            ([regex]::Matches(
                    $script:handoff,
                    ('(?m)^\d+\.\s+\*\*`' + [regex]::Escape($class) + '`\*\*')
                )).Count | Should -Be 1
        }

        $script:handoff | Should -Match 'same concrete invariant\s+across at least two named children/plans'
        $script:handoff | Should -Match 'Classification is fail-closed'
        $script:handoff | Should -Match 'local/minor finding manufactures a new\s+schema, protocol, store, state machine, compatibility layer, provider, or dependency'
        $script:handoff | Should -Match 'without independent `required shared contract` proof'
    }

    It 'test:EpicCoherency.ExistingReviewPath retains existing DR and review-run authority' {
        foreach ($concern in @(
                'security'
                'correctness-reliability'
                'architecture-patterns'
                'performance'
                'testing-evidence'
                'maintainability-consistency'
                'operability-observability'
            )) {
            $script:handoff | Should -Match ([regex]::Escape($concern))
            Test-Path -LiteralPath (
                Join-Path $script:repoRoot "plugins/design-review/agents/dr-$concern.agent.md"
            ) -PathType Leaf | Should -BeTrue
        }

        $freezeIndex = $script:handoff.IndexOf('`Freeze`', [System.StringComparison]::Ordinal)
        $fleetIndex = $script:handoff.IndexOf(
            'creating Fleet descriptors',
            [System.StringComparison]::Ordinal
        )
        $publishIndex = $script:handoff.IndexOf('`Publish`', [System.StringComparison]::Ordinal)
        $freezeIndex | Should -BeGreaterOrEqual 0
        $fleetIndex | Should -BeGreaterThan $freezeIndex
        $publishIndex | Should -BeGreaterThan $fleetIndex
        $script:handoff | Should -Match 'do not create an epic concern, topical agent, task type'
        $script:handoff | Should -Match 'Fleet attendance is invocation-local and non-authoritative'
        $script:handoff | Should -Match 'Review-run `Freeze`,\s+`Publish`, persistence, and rendering remain authoritative'
    }
}
