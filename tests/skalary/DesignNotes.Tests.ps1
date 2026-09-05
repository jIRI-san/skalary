#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'design-notes index integrity' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:indexPath = Join-Path $script:repoRoot 'docs/design-notes/.design-notes.md'
        $script:archIndexPath = Join-Path $script:repoRoot 'docs/architecture-notes/.architecture-notes.md'
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
        $note | Should -Match '(?i)canonical report\s+confinement'
    }

    It 'test:design-note-drops-orchestrator-fence documents direct risk-selected review' {
        $note = Get-Content -LiteralPath (Join-Path $script:repoRoot 'docs/design-notes/project/copilot-customizations.design.md') -Raw

        $note | Should -Match '(?i)skills select concerns directly from concrete scope\s*risk'
        $note | Should -Not -Match 'cr-<concern>|dr-<concern>|Sync-ReviewConcerns'
    }

    It 'lists every active design note and only resolvable architecture sources' {
        $designRoot = Split-Path -Parent $script:indexPath
        $designIndex = Get-Content -LiteralPath $script:indexPath -Raw
        $listedDesign = @(
            [regex]::Matches($designIndex, '\[[^\]]+\]\((?<path>[^)]+\.design\.md)\)') |
                ForEach-Object { $_.Groups['path'].Value }
        )
        $actualDesign = @(
            Get-ChildItem -LiteralPath $designRoot -Recurse -File -Filter '*.design.md' |
                ForEach-Object {
                    [System.IO.Path]::GetRelativePath($designRoot, $_.FullName).Replace('\', '/')
                }
        )
        @($listedDesign | Sort-Object) | Should -Be @($actualDesign | Sort-Object)

        $archRoot = Split-Path -Parent $script:archIndexPath
        $archIndex = Get-Content -LiteralPath $script:archIndexPath -Raw
        $archIndex | Should -Not -Match 'ARCH-Review-Run-V1|arch-review-run-v1'
        foreach ($match in [regex]::Matches($archIndex, '\[[^\]]+\]\((?<path>[^)]+\.md)\)')) {
            $match.Groups['path'].Value | Should -Not -Match '^archives/'
            Join-Path $archRoot $match.Groups['path'].Value | Should -Exist
        }
        Join-Path $archRoot 'archives/arch-review-run-v1.md' | Should -Exist
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
        $raw | Should -Match 'collision-safe\s+untrusted-input fence'
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
