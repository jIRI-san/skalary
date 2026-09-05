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
    }

    It 'test:SimpleWorkflow.InstructionLanguage makes CIP resolve seeded absolute and fuzzy examples before drafting' {
        $skill = Read-RepoText 'plugins/create-implementation-plan/skills/cip/SKILL.md'
        $protocol = Read-RepoText 'plugins/create-implementation-plan/skills/cip/assets/decision-protocol.md'

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
        $protocol | Should -Match 'always deploy'
        $protocol | Should -Match 'robust retries'
    }

    It 'test:SimpleWorkflow.DecisionReadyQuestions gives both hosts equivalent rich choices' {
        $protocol = Read-RepoText 'plugins/create-implementation-plan/skills/cip/assets/decision-protocol.md'
        foreach ($expected in @(
                'current context', 'concrete example', 'benefits', 'pros and\s*cons',
                'recommendation/default', 'effort: <1-10>', 'complexity: <1-10>',
                'Mermaid diagram only', 'vscode_askQuestions', 'numbered list',
                'one focused question at a time', 'trivial'
            )) {
            $protocol | Should -Match $expected
        }

        foreach ($path in @(
                '.github/copilot-instructions.md',
                'plugins/code-review/skills/cr/SKILL.md',
                'plugins/design-review/skills/dr/SKILL.md',
                'plugins/continue-implementation/skills/ci/SKILL.md',
                'plugins/autopilot/agents/autopilot.agent.md'
            )) {
            $text = Read-RepoText $path
            foreach ($expected in @(
                    'context', 'concrete example', 'benefits', 'pros(?:/|\s+and\s+)cons',
                    'recommendation/default', 'effort', 'complexity', 'Mermaid',
                    'vscode_askQuestions', 'Copilot\s+CLI', 'one\s+focused question'
                )) {
                $text | Should -Match $expected -Because "$path must carry the same decision context"
            }
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
        $audit | Should -Match '\*\*76\*\*'
        $audit | Should -Match 'Confirmed unconditional invariants retained'
        $audit | Should -Match 'Conditional rules rewritten'
        $audit | Should -Match 'Clarified fuzzy requirements'
        $audit | Should -Match 'Intentionally excluded occurrences'
        $audit | Should -Match 'No prose-policy compiler, linter service, schema, or runtime gate was added'
    }
}
