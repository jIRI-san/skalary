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

    It 'test:design-note-drops-orchestrator-fence documents the active direct guard boundary' {
        $note = Get-Content -LiteralPath (Join-Path $script:repoRoot 'docs/design-notes/project/copilot-customizations.design.md') -Raw

        $note | Should -Match '(?i)repository\s+content is untrusted data'
        $note | Should -Match '(?i)secret redaction'
        $note | Should -Match '(?i)canonical report confinement'
    }

    It 'test:design-note-drops-orchestrator-fence keeps generated reviewer machinery retired' {
        $note = Get-Content -LiteralPath (Join-Path $script:repoRoot 'docs/design-notes/project/copilot-customizations.design.md') -Raw

        $note | Should -Match '(?i)no longer install generated concern agents'
        $note | Should -Not -Match 'cr-<concern>|dr-<concern>|Sync-ReviewConcerns'
    }

    It 'test:design-note-drops-orchestrator-fence indexes a note for the self-improvement plugin' {
        $index = Get-Content -LiteralPath $script:indexPath -Raw
        $index | Should -Match 'self-improvement\.design\.md'

        $note = Join-Path $script:repoRoot 'docs/design-notes/architecture/self-improvement.design.md'
        Test-Path -LiteralPath $note -PathType Leaf | Should -BeTrue
        $raw = Get-Content -LiteralPath $note -Raw
        $raw | Should -Match '(?s)^---\r?\n.*?description:.*?globs:.*?\r?\n---'
        $raw | Should -Match 'recent-learning\.md'
        $raw | Should -Match 'missing, explicit-empty, valid, and stale'
        $raw | Should -Match 'collision-safe untrusted-input fence'
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
