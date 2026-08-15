#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'design-notes index integrity' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:indexPath = Join-Path $script:repoRoot 'docs/design-notes/.design-notes.md'
        $script:copilotInstructions = Join-Path $script:repoRoot '.github/copilot-instructions.md'
        $script:archNotesDoc = Join-Path $script:repoRoot 'docs/design-notes/architecture/architecture-notes.design.md'
        $script:allowlist = Import-PowerShellDataFile -LiteralPath (Join-Path $script:repoRoot 'tools/model-allowlist.psd1')
    }

    It 'DesignNotes-IndexRowsPresent: architecture notes remain indexed and both indexes auto-load' {
        Test-Path -LiteralPath $script:archNotesDoc -PathType Leaf | Should -BeTrue

        # The note is discoverable from the root index (a note absent from the table is never loaded).
        $index = Get-Content -LiteralPath $script:indexPath -Raw
        $index | Should -Match 'architecture-notes\.design\.md'

        # The two-index divergence is wired: copilot-instructions.md loads BOTH the design-note and
        # the architecture-note index.
        $ci = Get-Content -LiteralPath $script:copilotInstructions -Raw
        $ci | Should -Match 'docs/design-notes/\.design-notes\.md'
        $ci | Should -Match 'docs/architecture-notes/\.architecture-notes\.md'

        $raw = Get-Content -LiteralPath $script:archNotesDoc -Raw
        $raw | Should -Match '(?s)^---\r?\n.*?description:.*?globs:.*?\r?\n---'
    }

    It 'test:design-note-drops-orchestrator-fence stops describing a guardrail nothing implements' {
        # /cr no longer extracts or batches content, so there is no orchestrator boundary left to
        # wrap reviewed bytes in UNTRUSTED_INPUT markers. A note that still described one would
        # send a reader looking for a control that was relocated into the concern agents.
        $note = Get-Content -LiteralPath (Join-Path $script:repoRoot 'docs/design-notes/project/copilot-customizations.design.md') -Raw

        $note | Should -Not -Match '(?i)all reviewed content .* is wrapped in'
        $note | Should -Not -Match '<<<UNTRUSTED_INPUT_START>>>'
        # The relocation is stated, not merely the deletion.
        $note | Should -Match '(?i)guardrails live in the reviewers'
        $note | Should -Match '(?i)data-only directive'
        # That the reviewers actually carry the relocated directive is asserted by
        # ConcernAgents.Tests.ps1 over all 14 agents; duplicating a weaker version here would
        # look like coverage while adding none.
    }

    It 'test:design-note-drops-orchestrator-fence keeps the per-model reviewer roster out of the note' {
        $note = Get-Content -LiteralPath (Join-Path $script:repoRoot 'docs/design-notes/project/copilot-customizations.design.md') -Raw

        # The concern taxonomy replaced the model taxonomy; a stale "Model assignments" table would
        # point at agent files that no longer exist.
        $note | Should -Not -Match '(?m)^\| `\*-opus`'
        $note | Should -Match '(?i)concern roster'
        # RISK-2: the Pro-plan caveat is recorded where a reader configuring models will find it,
        # but the concrete names stay in the gated allowlist — a literal here would be a third,
        # ungated copy that goes stale the moment the roster moves.
        $note | Should -Match '(?i)Copilot \*\*Pro\*\* plan'
        $note | Should -Match 'tools/model-allowlist\.psd1'
        foreach ($model in @($allowlist.VSCodeModels + $allowlist.Fallback.VSCode)) {
            $note | Should -Not -Match ([regex]::Escape($model)) -Because 'roster names belong to the allowlist, not to prose'
        }
    }

    It 'test:design-note-drops-orchestrator-fence indexes a note for the self-improvement plugin' {
        $index = Get-Content -LiteralPath $script:indexPath -Raw
        $index | Should -Match 'self-improvement\.design\.md'

        $note = Join-Path $script:repoRoot 'docs/design-notes/architecture/self-improvement.design.md'
        Test-Path -LiteralPath $note -PathType Leaf | Should -BeTrue
        $raw = Get-Content -LiteralPath $note -Raw
        $raw | Should -Match '(?s)^---\r?\n.*?description:.*?globs:.*?\r?\n---'
        $raw | Should -Match 'UNTRUSTED_INPUT'
        $raw | Should -Match 'Test-SiWriteScope\.ps1'
    }

    It 'test:design-note-drops-orchestrator-fence pins the documented skill-size cap to the script default' {
        # A cap stated in prose and a cap enforced in code are two values until something ties them.
        $note = Get-Content -LiteralPath (Join-Path $script:repoRoot 'docs/design-notes/architecture/plugin-registry.design.md') -Raw
        $documented = [regex]::Match($note, '-MaxBytes (?<bytes>\d+)')
        $documented.Success | Should -BeTrue

        $script = Get-Content -LiteralPath (Join-Path $script:repoRoot 'scripts/skalary/Test-SkillSize.ps1') -Raw
        $actual = [regex]::Match($script, '\[int\]\$MaxBytes = (?<bytes>\d+)')
        $actual.Success | Should -BeTrue

        $documented.Groups['bytes'].Value | Should -Be $actual.Groups['bytes'].Value
    }
}
