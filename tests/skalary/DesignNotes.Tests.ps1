#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'design-notes index integrity' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:indexPath = Join-Path $script:repoRoot 'docs/design-notes/.design-notes.md'
        $script:copilotInstructions = Join-Path $script:repoRoot '.github/copilot-instructions.md'
        $script:archNotesDoc = Join-Path $script:repoRoot 'docs/design-notes/architecture/architecture-notes.design.md'
        $script:archTestsDoc = Join-Path $script:repoRoot 'docs/design-notes/architecture/architecture-tests.design.md'
    }

    It 'DesignNotes-IndexRowsPresent: the two architecture-guardrails design notes exist and are indexed, and both indexes auto-load' {
        # The new design notes exist.
        Test-Path -LiteralPath $script:archNotesDoc -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $script:archTestsDoc -PathType Leaf | Should -BeTrue

        # Each is discoverable from the root index (a note absent from the table is never loaded).
        $index = Get-Content -LiteralPath $script:indexPath -Raw
        $index | Should -Match 'architecture-notes\.design\.md'
        $index | Should -Match 'architecture-tests\.design\.md'

        # The two-index divergence is wired: copilot-instructions.md loads BOTH the design-note and
        # the architecture-note index.
        $ci = Get-Content -LiteralPath $script:copilotInstructions -Raw
        $ci | Should -Match 'docs/design-notes/\.design-notes\.md'
        $ci | Should -Match 'docs/architecture-notes/\.architecture-notes\.md'

        # Both new notes carry the required frontmatter (description + globs) so they load correctly.
        foreach ($doc in @($script:archNotesDoc, $script:archTestsDoc)) {
            $raw = Get-Content -LiteralPath $doc -Raw
            $raw | Should -Match '(?s)^---\r?\n.*?description:.*?globs:.*?\r?\n---'
        }
    }
}
