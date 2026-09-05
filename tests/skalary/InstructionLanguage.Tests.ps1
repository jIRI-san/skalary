#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Decision-ready questions and active policy language' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        function Read-RepoText {
            param([Parameter(Mandatory)][string]$Path)
            Get-Content -LiteralPath (Join-Path $script:repoRoot $Path) -Raw
        }
        function Read-PolicyFixture {
            param([Parameter(Mandatory)][string]$Name)
            Get-Content -LiteralPath (
                Join-Path $script:repoRoot "tests/skalary/fixtures/review-policy/$Name.json"
            ) -Raw | ConvertFrom-Json
        }
    }

    It 'test:SimpleWorkflow.InstructionLanguage makes CIP resolve seeded absolute and fuzzy examples before drafting' {
        $skill = Read-RepoText 'plugins/create-implementation-plan/skills/cip/SKILL.md'
        $protocol = Read-RepoText 'plugins/create-implementation-plan/skills/cip/assets/decision-protocol.md'
        $fixture = Read-PolicyFixture 'language-audit'

        $skill | Should -Match 'Before drafting'
        $skill | Should -Match 'Do not draft an unconfirmed absolute or an\s*unobservable fuzzy requirement'
        foreach ($term in @('always', 'never', 'must', 'shall', 'required', 'only',
                'cannot', 'do not', 'refuse', 'prohibit')) {
            $protocol | Should -Match "\b$term"
        }
        $protocol | Should -Match 'Condition:.*Behavior:.*Exception:'
        $protocol | Should -Match 'confirm or revise it before drafting'
        foreach ($term in @('detailed', 'thorough', 'robust', 'appropriate', 'comprehensive',
                'fast', 'secure')) {
            $protocol | Should -Match "\b$term\b"
        }
        $protocol | Should -Match 'criterion, threshold,\s*or example'
        foreach ($case in $fixture.absoluteCases) {
            $protocol | Should -Match ([regex]::Escape(
                    ([regex]::Match([string]$case.input, '(?i)always deploy').Value)
                ))
            if ($case.expected -ceq 'confirm') {
                $protocol | Should -Match 'confirm or revise it before drafting'
            }
        }
        foreach ($case in $fixture.fuzzyCases) {
            $protocol | Should -Match ([regex]::Escape(
                    ([regex]::Match([string]$case.input, '(?i)robust retries').Value)
                ))
            if ($case.expected -ceq 'observable clarification') {
                $protocol | Should -Match 'criterion, threshold,\s*or example'
            }
        }

        foreach ($guard in $fixture.retainedGuards) {
            Read-RepoText $guard.path | Should -Match $guard.pattern
        }
        $excludedKinds = @($fixture.excludedExamples | ForEach-Object kind)
        $excludedKinds | Should -Be @('archived', 'code', 'schema', 'example')
        foreach ($pattern in @('code keywords', 'schema fields', 'examples being analyzed')) {
            $protocol | Should -Match $pattern
        }
        $audit = Read-RepoText (
            'docs/implementation-plans/705e6c-2026-09-03-367e9a-simple-review-to-plan-workflow/' +
            'assets/language-audit.md'
        )
        $audit | Should -Match 'Archived implementation plans/history'
        $audit | Should -Match 'External schema/tool keywords, code identifiers'
        $audit | Should -Match 'examples being analyzed'
    }

    It 'test:SimpleWorkflow.DecisionReadyQuestions gives both hosts equivalent rich choices' {
        $protocol = Read-RepoText 'plugins/create-implementation-plan/skills/cip/assets/decision-protocol.md'
        $fixture = Read-PolicyFixture 'decision-question'
        foreach ($expected in @($fixture.orderedLabels)) {
            $pattern = if ($expected -eq 'pros/cons') { 'pros and\s*cons' } else {
                [regex]::Escape([string]$expected)
            }
            $protocol | Should -Match $pattern
        }
        $protocol | Should -Match 'Mermaid diagram only'
        $protocol | Should -Match 'relationships or sequencing affect the decision'
        $protocol | Should -Match 'one focused question at a time'
        $protocol | Should -Match 'trivial'
        $fixture.relationshipCase | Should -Match 'before or after'
        $fixture.independentCase | Should -Not -Match 'before or after'
        [regex]::Matches([string]$fixture.freeFormQuestion, '\?').Count | Should -Be 1

        foreach ($path in @(
                '.github/copilot-instructions.md',
                'plugins/code-review/skills/cr/SKILL.md',
                'plugins/design-review/skills/dr/SKILL.md',
                'plugins/continue-implementation/skills/ci/SKILL.md',
                'plugins/autopilot/agents/autopilot.agent.md'
            )) {
            $text = Read-RepoText $path
            foreach ($expected in @($fixture.orderedLabels)) {
                $pattern = if ($expected -eq 'pros/cons') {
                    'pros(?:/|\s+and\s+)cons'
                }
                else {
                    [regex]::Escape([string]$expected)
                }
                $text | Should -Match $pattern -Because "$path must carry the same decision context"
            }
            foreach ($expected in @($fixture.hosts)) {
                $pattern = if ($expected -eq 'Copilot CLI') { 'Copilot\s+CLI' } else {
                    [regex]::Escape([string]$expected)
                }
                $text | Should -Match $pattern -Because "$path must carry both host renderings"
            }
            $text | Should -Match 'Mermaid'
            $text | Should -Match 'only\s+when\s+relationships or sequencing'
            $text | Should -Match 'one\s+focused question'
        }
    }

    It 'shares the planning protocol through both installed skill destinations' {
        $manifest = Read-RepoText 'plugins/create-implementation-plan/plugin.json' | ConvertFrom-Json
        $protocolMappings = @($manifest.files | Where-Object {
                $_.src -eq 'skills/cip/assets/decision-protocol.md'
            })
        $protocolMappings.dest | Should -Contain 'skills/cip/assets/decision-protocol.md'
        $protocolMappings.dest | Should -Contain 'skills/cep/assets/decision-protocol.md'
    }

    It 'preserves secret destructive and path-confinement invariants' {
        (Read-RepoText 'plugins/create-implementation-plan/skills/cip/SKILL.md') |
            Should -Match 'secret\s*screening'
        (Read-RepoText 'plugins/autopilot/agents/autopilot.agent.md') |
            Should -Match 'destructive-action'

        $confinement = Read-RepoText 'docs/architecture-notes/arch-install-confinement.md'
        $confinement | Should -Match 'mutate files \*\*only\*\* inside'
        $confinement | Should -Match 'traversal \(`\.\.`\), rooted, and\s*absolute dests are rejected'
        (Read-RepoText 'plugins/code-review/skills/cr/SKILL.md') |
            Should -Match 'canonical plan'
    }

    It 'records a bounded human audit without adding a runtime policy gate' {
        $audit = Read-RepoText 'docs/implementation-plans/705e6c-2026-09-03-367e9a-simple-review-to-plan-workflow/assets/language-audit.md'
        $audit | Should -Match 'Status: closed in Step 5\.1'
        $audit | Should -Match '\*\*75\*\*'
        $audit | Should -Match '\*\*764\*\*'
        $audit | Should -Match 'Unresolved policy absolutes:\s+\*\*0\*\*'
        $audit | Should -Match 'Unresolved fuzzy requirements:\s*\r?\n\*\*0\*\*'
        $audit | Should -Match 'Every one of the 764 lexical occurrences was reviewed'
        $audit | Should -Match 'Confirmed unconditional invariants retained'
        $audit | Should -Match 'Conditional rules rewritten'
        $audit | Should -Match 'Clarified fuzzy requirements'
        $audit | Should -Match 'Intentionally excluded occurrences'
        $audit | Should -Match 'No prose-policy compiler, linter service, schema, or runtime gate was added'
    }
}
