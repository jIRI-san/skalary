#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'SimpleWorkflow.OperatorGuide' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:guideRoot = Join-Path $script:repoRoot 'docs\operator-guide'
        $script:files = @('README.md', 'planning.md', 'implementation.md', 'reviews.md')
        $script:content = @{}
        foreach ($name in $script:files) {
            $path = Join-Path $script:guideRoot $name
            $script:content[$name] = Get-Content -LiteralPath $path -Raw
        }
        $script:all = ($script:content.Values -join "`n")
    }

    It 'publishes exactly the four linked human guides outside auto-loaded indexes' {
        foreach ($name in $script:files) {
            Join-Path $script:guideRoot $name | Should -Exist
        }
        $published = @(Get-ChildItem -LiteralPath $script:guideRoot -File -Filter '*.md').Name
        $published.Count | Should -Be 4
        foreach ($name in $script:files) {
            $published | Should -Contain $name
        }
        $script:content['README.md'] | Should -Match '\[Planning\]\(planning\.md\)'
        $script:content['README.md'] | Should -Match '\[Implementation\]\(implementation\.md\)'
        $script:content['README.md'] | Should -Match '\[Reviews\]\(reviews\.md\)'
        $rootReadme = Get-Content -LiteralPath (Join-Path $script:repoRoot 'README.md') -Raw
        $rootReadme | Should -Match '\[operator guide\]\(docs/operator-guide/README\.md\)'
        foreach ($index in @('docs/design-notes/.design-notes.md',
                'docs/architecture-notes/.architecture-notes.md')) {
            Get-Content -LiteralPath (Join-Path $script:repoRoot $index) -Raw |
                Should -Not -Match '\|\s*\[.*operator-guide'
        }
    }

    It 'has the required sections, source links, tables, and Mermaid flows' {
        foreach ($section in @('Purpose and audience', 'Start here', 'Artifact catalog',
                'Gates and stops', 'Global limits and budgets', 'Documentation boundary')) {
            $script:content['README.md'] | Should -Match ("##\s+" + [regex]::Escape($section))
        }
        foreach ($section in @('End-to-end flow', 'Context loading', 'Confirmation stages',
                'Decision-ready questions', 'Absolute and fuzzy language', 'Native roles and budgets',
                'Plan files and markers', 'DR selection, Git baseline, and handoff')) {
            $script:content['planning.md'] | Should -Match ("##\s+" + [regex]::Escape($section))
        }
        foreach ($section in @('Mode and runtime selection', 'Admission and criteria baseline',
                'Execution flow', 'Native work, progress, and recovery',
                'Validation, evidence, and phase close', 'Finalization',
                'Outcomes and exit codes')) {
            $script:content['implementation.md'] |
                Should -Match ("##\s+" + [regex]::Escape($section))
        }
        foreach ($section in @('Entry points and cadence', 'Model alias and budget matrix',
                'Inputs and local standards', 'Concrete threat-path rubric', 'Retained guards',
                'Report contract', 'Correction and exhaustion')) {
            $script:content['reviews.md'] | Should -Match ("##\s+" + [regex]::Escape($section))
        }
        ([regex]::Matches($script:all, '```mermaid')).Count | Should -BeGreaterOrEqual 5
        ([regex]::Matches($script:all, '\|---')).Count | Should -BeGreaterOrEqual 12
        $script:all | Should -Match '\.\./\.\./plugins/'
        $script:all | Should -Match '\.\./\.\./scripts/skalary/'
    }

    It 'keeps every local Markdown link resolvable' {
        foreach ($name in $script:files) {
            $documentPath = Join-Path $script:guideRoot $name
            foreach ($match in [regex]::Matches($script:content[$name], '\[[^\]]+\]\(([^)#]+)(?:#[^)]+)?\)')) {
                $target = [System.Uri]::UnescapeDataString($match.Groups[1].Value)
                if ($target -match '^[a-z]+:') { continue }
                $resolved = [System.IO.Path]::GetFullPath(
                    [System.IO.Path]::Combine((Split-Path -Parent $documentPath), $target)
                )
                Test-Path -LiteralPath $resolved | Should -BeTrue -Because (
                    "$name links to existing local target '$target'"
                )
            }
        }
    }

    It 'catalogs every active artifact category with ownership and authority semantics' {
        $readme = $script:content['README.md']
        foreach ($heading in @('Artifact', 'Owner', 'Location', 'Lifecycle and mutability',
                'Source of truth', 'Consumer')) {
            $readme | Should -Match ([regex]::Escape($heading))
        }
        foreach ($category in @('Epic index', 'Plan index and progress', 'Intent', 'Domain model',
                'Approved design', 'Requirements', 'Risks', 'Decisions', 'References',
                'Architecture contracts', 'AI design notes', 'Local review standards',
                'Phase/final review report', 'Current evidence', 'Recent-learning handoff',
                'Autonomous configuration', 'Baseline and progress history')) {
            $readme | Should -Match ([regex]::Escape($category))
        }
    }

    It 'documents all gates, outcomes, runtime modes, and direct evidence types' {
        foreach ($gate in @('Language gate', 'Final planning confirmation',
                'Plan validation/admission', 'Git criteria baseline', 'Runtime preflight',
                'Focused validation', 'Direct evidence', 'Non-terminal review',
                'Design-note compaction', 'Terminal review', 'Learning handoff',
                'Completion/archive')) {
            $script:content['README.md'] | Should -Match ([regex]::Escape($gate))
        }
        foreach ($mode in @('Interactive (approve each step)', 'Autopilot (autoapprove)',
                'Host autopilot', 'Container autopilot', 'Sandbox autopilot',
                'next-phase', 'whole-plan', 'scope: step | phase | plan',
                'AUTOPILOT_CONTAINER', 'AUTOPILOT_DISABLE_HOST')) {
            $script:content['implementation.md'] | Should -Match ([regex]::Escape($mode))
        }
        foreach ($outcome in @('completed', 'refused', 'blocked', 'stuck', 'interrupted',
                'Operator action', 'Offline rebundle')) {
            $script:content['implementation.md'] | Should -Match ([regex]::Escape($outcome))
        }
        foreach ($code in @('`0`', '`42`', '`43`')) {
            $script:content['implementation.md'] | Should -Match ([regex]::Escape($code))
        }
        foreach ($marker in @('`test:`', '`file:`', '`review:`')) {
            $script:content['implementation.md'] | Should -Match ([regex]::Escape($marker))
        }
    }

    It 'test:AiCreditBudget.OperatorGuidance states the global budgets and exact model matrix' {
        foreach ($value in @('180,000 operating', '20,000 reserve', '0 for direct work',
                '3 maximum', 'At most 3', '400-word target', '800-word hard cap',
                'explicit opt-in', '2 no-progress checks',
                '1 redirect', 'at most 1 replacement', 'At most 10 cited items',
                '16 KiB UTF-8')) {
            $script:all | Should -Match ([regex]::Escape($value))
        }
        $reviews = $script:content['reviews.md']
        foreach ($model in @(
                'primary-model-low', 'primary-model-mid', 'primary-model-high',
                'secondary-model-low', 'secondary-model-mid', 'secondary-model-high'
            )) {
            $reviews | Should -Match ([regex]::Escape($model))
        }
        $script:content['README.md'] | Should -Match 'models-and-pricing'
        $script:content['README.md'] | Should -Match 'optimize-ai-usage'
        $script:content['README.md'] | Should -Match 'workflow-flows'
        $script:all | Should -Not -Match 'GPT-5\.4|Claude Sonnet 4\.6'
    }

    It 'documents report shape, verdicts, threat links, guards, and closed rerun behavior' {
        $reviews = $script:content['reviews.md']
        foreach ($heading in @('## Source', '## Scope', '## Completed tasks', '## Findings',
                '## Verdict')) {
            $reviews | Should -Match ([regex]::Escape($heading))
        }
        foreach ($verdict in @('clean', 'findings', 'incomplete')) {
            $reviews | Should -Match ("\b" + $verdict + "\b")
        }
        foreach ($link in @('Attacker or untrusted input', 'Reachable capability',
                'Affected asset', 'Plausible impact')) {
            $reviews | Should -Match ([regex]::Escape($link))
        }
        foreach ($guard in @('prompt-injection', 'secret refusal/redaction', 'read-only',
                'destructive actions', 'canonical confinement', 'externally consumed formats')) {
            $reviews | Should -Match ([regex]::Escape($guard))
        }
        $reviews | Should -Match 'Never rerun unchanged scope'
        $reviews | Should -Match 'Budget exhaustion'
    }

    It 'makes the compaction exclusion explicit in guides and design notes' {
        $script:content['README.md'] | Should -Match 'design-note compaction does not apply here'
        $script:content['implementation.md'] | Should -Match 'Guide-only changes do not trigger it'
        foreach ($note in @('docs/design-notes/architecture/plan-workflow.design.md',
                'docs/design-notes/project/copilot-customizations.design.md')) {
            $text = Get-Content -LiteralPath (Join-Path $script:repoRoot $note) -Raw
            $text | Should -Match 'docs/operator-guide/README\.md'
            $text | Should -Match 'not auto-loaded|absent from both\s+auto-loaded indexes'
            $text | Should -Match 'excluded from design-note compaction|never triggers or participates'
        }
    }

    It 'does not claim obsolete workflow machinery is active authority' {
        foreach ($pattern in @(
                '(?i)review-run.{0,40}(?:source of truth|authoritative|required)',
                '(?i)Fleet.{0,40}(?:active|scheduler authority|required)',
                '(?i)(?:evidence|review) receipt.{0,40}(?:source of truth|authoritative|required)',
                '(?i)generated concern registry.{0,40}(?:active|authoritative|required)'
            )) {
            $script:all | Should -Not -Match $pattern
        }
        $script:all | Should -Match 'Retired workflow contracts remain only as non-indexed history'
        $script:all | Should -Match 'direct report and active in-memory result are the complete'
    }
}
