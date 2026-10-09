#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'direct plan intent contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:cipSkill = Join-Path $script:repoRoot 'plugins/create-implementation-plan/skills/cip/SKILL.md'
        $script:cepSkill = Join-Path $script:repoRoot 'plugins/create-implementation-plan/skills/cep/SKILL.md'
        $script:decisionProtocol = Join-Path $script:repoRoot 'plugins/create-implementation-plan/skills/cip/assets/decision-protocol.md'
        $script:ciSkill = Join-Path $script:repoRoot 'plugins/continue-implementation/skills/ci/SKILL.md'
        $script:newPlan = Join-Path $script:repoRoot 'scripts/skalary/New-Plan.ps1'
        $script:newEpic = Join-Path $script:repoRoot 'scripts/skalary/New-Epic.ps1'
        $script:intentSections = @(
            'Goal', 'Desired outcome', 'Success signals', 'Non-goals', 'Definition of done'
        )
    }

    It 'test:cip-intent-gate keeps intent confirmation in the active planning skill' {
        $content = Get-Content -LiteralPath $script:cipSkill -Raw
        $content | Should -Match 'Confirm current intent first'
        $content | Should -Match 'After the selected edits, confirm the current intent, requirements, risks, and decisions together'
        $content | Should -Match 'planning-confirmed marker'
    }

    It 'test:ci-reads-intent protects intent through the Git criteria baseline' {
        $content = Get-Content -LiteralPath $script:ciSkill -Raw
        $content | Should -Match 'Before any checklist, branch,\s*worktree, log, or source mutation'
        $content | Should -Match 'Test-PlanCriteriaBaseline'
        $content | Should -Match 'intent,\s*requirements, risks, or decisions'
    }

    It 'test:intentalignment-planning-question-bounds captures meaning without another review gate' {
        $protocol = Get-Content -LiteralPath $script:decisionProtocol -Raw
        $protocol | Should -Match 'two plausible interpretations materially change'
        $protocol | Should -Match 'selected operator wording separately from the agent.s summary'
        $protocol | Should -Match 'bounded choice'
        $protocol | Should -Match 'owner and the condition that resolves it or stops implementation'
        $protocol | Should -Match 'no more than three snippets of 240 characters per artifact'
        $protocol | Should -Match 'history informs but does not veto'
        $protocol | Should -Match 'single highest-leverage'
        $protocol | Should -Match 'Do not turn every useful planning input into a checklist or a menu'

        $cip = Get-Content -LiteralPath $script:cipSkill -Raw
        $cep = Get-Content -LiteralPath $script:cepSkill -Raw
        $cip | Should -Match 'Catch consequential interpretation ambiguity before drafting'
        $cip | Should -Match 'lightweight RFC'
        $cep | Should -Match 'existing `epic.md` Goal and Decomposition notes'
        $cep | Should -Match 'relevant inherited wording and provenance'

        $epic = Get-Content -LiteralPath $script:newEpic -Raw
        $epic | Should -Match 'Selected operator wording: TBD'
        $epic | Should -Match '## Decomposition notes'
    }

    It 'test:intentalignment-handoff detects draft drift and preserves progress at runtime' {
        $preReview = Get-Content -LiteralPath (
            Join-Path $script:repoRoot 'plugins/create-implementation-plan/skills/cip/assets/pre-confirmation-review.md'
        ) -Raw
        $preReview | Should -Match 'selected operator wording and confirmed interpretations'
        $preReview | Should -Match 'unsupported additions, omissions, scope shifts'
        $preReview | Should -Match 'intent-alignment questions distinct from technical findings'
        $preReview | Should -Match 'intentional openness are not drift'
        $preReview | Should -Match 'existing reviewer call'
        $preReview | Should -Match 'Dispatch exactly these two calls'

        $dr = Get-Content -LiteralPath (
            Join-Path $script:repoRoot 'plugins/design-review/skills/dr/SKILL.md'
        ) -Raw
        $dr | Should -Match 'selected operator wording and confirmed\s+interpretations'
        $dr | Should -Match 'separately from technical findings'
        $dr | Should -Match 'not drift'

        foreach ($path in @(
                (Join-Path $script:repoRoot 'plugins/continue-implementation/skills/ci/SKILL.md')
                (Join-Path $script:repoRoot 'plugins/autopilot/agents/autopilot.agent.md')
                (Join-Path $script:repoRoot 'plugins/autopilot/skills/autopilot/SKILL.md')
            )) {
            $content = Get-Content -LiteralPath $path -Raw
            $content | Should -Match 'material intent'
            $content | Should -Match 'preserve (?:checklist and worktree )?progress'
            $content | Should -Match '42'
            $content | Should -Match 'affected criterion'
            $content | Should -Match 'reconfirmation|confirmation baseline'
            $content | Should -Match 'Test-PlanCriteriaBaseline|baseline passes'
            $content | Should -Match 'redraft unrelated'
        }
    }

    It 'presents operator questions as Markdown briefs outside input-tool fields' {
        foreach ($path in @(
                $script:decisionProtocol,
                $script:ciSkill,
                (Join-Path $script:repoRoot '.github/copilot-instructions.md')
            )) {
            $content = Get-Content -LiteralPath $path -Raw
            $content | Should -Match 'every operator question as rendered Markdown in the conversation'
            $content | Should -Match 'question in its own paragraph'
            $content | Should -Match 'bold\s+option labels|options with bold labels'
            $content | Should -Match 'blank lines'
            $content | Should -Match 'before invoking\s+the input tool'
            $content | Should -Match 'only the short question and option labels'
            $content | Should -Match 'vscode_askQuestions'
            $content | Should -Match 'ask_user'
            $content | Should -Match 'Without a picker'
        }

        $protocol = Get-Content -LiteralPath $script:decisionProtocol -Raw
        $protocol | Should -Match '(?m)^### Retry behavior\r?$'
        $protocol | Should -Match '(?m)^1\. \*\*Retry twice \(Recommended\)\*\*\r?$'
        $protocol | Should -Match '(?m)^2\. \*\*Keep one attempt\*\*\r?$'
        $protocol | Should -Match 'Do not rely on Markdown\s+rendering inside tool fields'
        $protocol | Should -Match 'yes/no choice is trivial'

        $cip = Get-Content -LiteralPath $script:cipSkill -Raw
        $cip | Should -Match 'for every operator question, including review selections and final confirmation'
        $preReview = Get-Content -LiteralPath (
            Join-Path $script:repoRoot 'plugins/create-implementation-plan/skills/cip/assets/pre-confirmation-review.md'
        ) -Raw
        $preReview | Should -Match 'rendered\s+Markdown question format'
        $preReview | Should -Match 'input tool receives only the short question and\s+option labels'
    }

    It 'test:new-plan-scaffolds-intent writes all confirmed intent sections' {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $script:newPlan,
            [ref]$null,
            [ref]$null
        )
        $function = $ast.Find({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq 'Get-PlanAssetScaffold'
            }, $true)
        $function | Should -Not -BeNullOrEmpty
        $scaffold = & ([scriptblock]::Create(
                $function.Extent.Text + "`nGet-PlanAssetScaffold"
            ))
        $headings = @(
            [regex]::Matches(
                (($scaffold['intent.md'] -replace "`r`n", "`n")),
                '(?m)^##\s+(.+?)\s*$'
            ) | ForEach-Object { $_.Groups[1].Value }
        )
        $headings | Should -Be $script:intentSections
        $scaffold['intent.md'] | Should -Match 'Selected operator wording and confirmed interpretation'
        $scaffold['intent.md'] | Should -Match 'Deferred choice, owner, and resolve-or-stop condition'
        $scaffold['design.md'] | Should -Match 'Lightweight RFC'
    }

    It 'ships the active intent contract unchanged to dogfood' {
        $pairs = @(
            @{ Source = 'plugins/create-implementation-plan/skills/cip/SKILL.md'; Installed = '.github/skills/cip/SKILL.md' }
            @{ Source = 'plugins/create-implementation-plan/skills/cip/assets/decision-protocol.md'; Installed = '.github/skills/cip/assets/decision-protocol.md' }
            @{ Source = 'plugins/create-implementation-plan/skills/cip/assets/decision-protocol.md'; Installed = '.github/skills/cep/assets/decision-protocol.md' }
            @{ Source = 'plugins/create-implementation-plan/skills/cip/assets/pre-confirmation-review.md'; Installed = '.github/skills/cip/assets/pre-confirmation-review.md' }
            @{ Source = 'plugins/create-implementation-plan/skills/cep/SKILL.md'; Installed = '.github/skills/cep/SKILL.md' }
            @{ Source = 'plugins/design-review/skills/dr/SKILL.md'; Installed = '.github/skills/dr/SKILL.md' }
            @{ Source = 'plugins/continue-implementation/skills/ci/SKILL.md'; Installed = '.github/skills/ci/SKILL.md' }
            @{ Source = 'plugins/autopilot/skills/autopilot/SKILL.md'; Installed = '.github/skills/autopilot/SKILL.md' }
            @{ Source = 'plugins/autopilot/agents/autopilot.agent.md'; Installed = '.github/agents/autopilot.agent.md' }
        )
        foreach ($pair in $pairs) {
            $source = Join-Path $script:repoRoot $pair.Source
            $installed = Join-Path $script:repoRoot $pair.Installed
            (Get-FileHash -LiteralPath $installed -Algorithm SHA256).Hash |
                Should -BeExactly (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
        }
    }
}
