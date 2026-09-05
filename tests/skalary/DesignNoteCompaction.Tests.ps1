#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'SimpleWorkflow.DesignNoteCompaction' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:helper = Join-Path $script:repoRoot 'scripts/skalary/Get-DesignNoteCompactionContext.ps1'
        $script:protocolPath = Join-Path $script:repoRoot 'plugins/autopilot/skills/autopilot/assets/design-note-compaction.md'
        $script:protocol = Get-Content -LiteralPath $script:protocolPath -Raw
        $script:scratch = [System.Collections.Generic.List[string]]::new()

        function New-CompactionFixture {
            $root = Join-Path $script:repoRoot ('tests\.design-compaction-' + [guid]::NewGuid().ToString('N'))
            $script:scratch.Add($root)
            $notes = Join-Path $root 'docs\design-notes'
            New-Item -ItemType Directory -Path $notes -Force | Out-Null
            $rows = 1..7 | ForEach-Object {
                "| [note-$_.design.md](note-$_.design.md) | ``src/area$_/**`` | concept-$_ |"
            }
            Set-Content -LiteralPath (Join-Path $notes '.design-notes.md') -Encoding utf8NoBOM -Value @"
# Design Notes

| File | Scope | Key Patterns |
|---|---|---|
$($rows -join "`n")
"@
            1..7 | ForEach-Object {
                Set-Content -LiteralPath (Join-Path $notes "note-$_.design.md") `
                    -Encoding utf8NoBOM -Value "# Note $_"
            }
            return $root
        }
    }

    AfterEach {
        foreach ($path in @($script:scratch)) {
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
        }
        $script:scratch.Clear()
    }

    It 'triggers for design notes and not operator-guide or other documentation alone' {
        $root = New-CompactionFixture
        (& $script:helper -RepoRoot $root -ChangedPath 'docs/design-notes/note-1.design.md').ShouldRun |
            Should -BeTrue
        (& $script:helper -RepoRoot $root -ChangedPath 'docs/operator-guide/reviews.md').ShouldRun |
            Should -BeFalse
        (& $script:helper -RepoRoot $root -ChangedPath 'docs/README.md').ShouldRun |
            Should -BeFalse
        $script:protocol | Should -Match 'once per `/ci` or autopilot finalization invocation'
        $script:protocol | Should -Match 'Do not run it per step'
    }

    It 'uses Git from the baseline and includes untracked design notes' {
        $root = New-CompactionFixture
        & git -C $root init -q
        & git -C $root config user.email fixture@example.test
        & git -C $root config user.name Fixture
        & git -C $root add .
        & git -C $root commit -qm baseline
        $base = (& git -C $root rev-parse HEAD).Trim()

        Set-Content -LiteralPath (Join-Path $root 'docs\design-notes\new.design.md') `
            -Encoding utf8NoBOM -Value '# New'
        $result = & $script:helper -RepoRoot $root -BaseRef $base
        $result.ShouldRun | Should -BeTrue
        $result.TouchedNotes | Should -Contain 'docs/design-notes/new.design.md'
    }

    It 'inventories active notes through the index without a corpus cache' {
        $root = New-CompactionFixture
        $result = & $script:helper -RepoRoot $root -ChangedPath 'docs/design-notes/note-1.design.md'
        @($result.ActiveNotes).Count | Should -Be 7
        $result.ActiveNotes[0].Scope | Should -Be '`src/area1/**`'
        $script:protocol | Should -Match 'Read `docs/design-notes/\.design-notes\.md`, not the whole note tree'
        $script:protocol | Should -Match 'index `Scope`'
        $script:protocol | Should -Match 'directly linked notes'
        $script:protocol | Should -Match 'sharing named concepts'
        $script:protocol | Should -Match 'explicitly chosen by the operator'
    }

    It 'splits selected active candidates into sequential batches of at most five' {
        $root = New-CompactionFixture
        $candidates = 1..7 | ForEach-Object { "docs/design-notes/note-$_.design.md" }
        $result = & $script:helper -RepoRoot $root `
            -ChangedPath 'docs/design-notes/note-1.design.md' -CandidatePath $candidates
        @($result.CandidateBatches).Count | Should -Be 2
        @($result.CandidateBatches[0].Notes).Count | Should -Be 5
        @($result.CandidateBatches[1].Notes).Count | Should -Be 2
        $script:protocol | Should -Match '(?s)concise\s+accumulated summary'
        $script:protocol | Should -Match '(?s)Never\s+hold all candidate full texts together'
    }

    It 'requires every semantic preservation category and uncertainty safety' {
        foreach ($category in @('decision', 'architectural contract', 'constraint', 'exception',
                'minimal representative example')) {
            $script:protocol | Should -Match $category
        }
        $script:protocol | Should -Match '(?s)If ownership or uniqueness\s+is uncertain, retain'
    }

    It 'requires approval details and a headless operator-action stop for cross-note changes' {
        foreach ($detail in @('exact candidate paths', 'resulting owner', 'unique item preserved',
                'complete relevant Git diff', 'benefits', 'pros and cons', 'effort:', 'complexity:')) {
            $script:protocol | Should -Match $detail
        }
        $script:protocol | Should -Match 'exactly `Apply` and `Cancel`'
        $script:protocol | Should -Match 'never self-approve'
        $script:protocol | Should -Match 'exit `42`'
    }

    It 'updates note metadata and the active index when ownership changes' {
        $script:protocol | Should -Match 'frontmatter and globs accurate'
        $script:protocol | Should -Match 'update the active index row and all affected links'
    }

    It 'keeps cancellation and failure diffs visible without promising rollback' {
        $script:protocol | Should -Match '(?s)leaves ordinary working-tree\s+changes visible'
        $script:protocol | Should -Match 'never claim transactional rollback'
        $script:protocol | Should -Match '(?s)Show the final.*diff before terminal review'
    }

    It 'is one shared installed asset used by CI and autopilot' {
        $ci = Get-Content -LiteralPath (
            Join-Path $script:repoRoot 'plugins/continue-implementation/skills/ci/SKILL.md'
        ) -Raw
        $autopilot = Get-Content -LiteralPath (
            Join-Path $script:repoRoot 'plugins/autopilot/skills/autopilot/SKILL.md'
        ) -Raw
        $ci | Should -Match '\.github/skills/autopilot/assets/design-note-compaction\.md'
        $autopilot | Should -Match '\./assets/design-note-compaction\.md'
    }
}
