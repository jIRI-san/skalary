#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Archive-Epic' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $newEpic = Join-Path $repoRoot 'scripts/skalary/New-Epic.ps1'
        $archiveEpic = Join-Path $repoRoot 'scripts/skalary/Archive-Epic.ps1'
        $planState = Join-Path $repoRoot 'scripts/skalary/Get-PlanState.ps1'

        $newArchiveFixture = {
            param([switch]$Incomplete, [switch]$KeepChildActive)

            $root = Join-Path ([System.IO.Path]::GetTempPath()) (
                'epic-archive-' + [guid]::NewGuid().ToString('N')
            )
            $activePlans = Join-Path $root 'docs/implementation-plans'
            $archivedPlans = Join-Path $activePlans 'archived'
            [void](New-Item -ItemType Directory -Path $archivedPlans -Force)

            $childName = '2026-08-01-111aaa-child'
            $childDir = Join-Path $activePlans $childName
            [void](New-Item -ItemType Directory -Path $childDir -Force)
            $mark = if ($Incomplete) { ' ' } else { 'x' }
            $content = @(
                '# 111aaa: Child'
                '<!-- plan-id: 111aaa -->'
                ''
                '## Phase 1: Fixture'
                ''
                "- [$mark] 1.1 Complete child ``S``"
            ) -join "`n"
            [System.IO.File]::WriteAllText((Join-Path $childDir 'plan.md'), $content)

            $epic = & $newEpic -Title 'Archive fixture' -Slug 'archive-fixture' `
                -RepoRoot $root -Date '2026-08-01' -EpicId 'abc123'
            & $newEpic -Epic 'abc123' -RepoRoot $root -ChildPlan '111aaa' |
                Out-Null
            if (-not $KeepChildActive) {
                [System.IO.Directory]::Move(
                    $childDir,
                    (Join-Path $archivedPlans $childName)
                )
            }

            return [pscustomobject]@{
                Root = $root
                Epic = $epic
            }
        }
    }

    It 'test:ArchiveEpic archives a complete epic beside archived plans and remains resolvable' {
        $fixture = & $newArchiveFixture
        try {
            [System.IO.File]::ReadAllText($fixture.Epic.EpicFile) |
                Should -Not -Match 'child _\(archived\)_'

            $result = & $archiveEpic abc123 -RepoRoot $fixture.Root
            $result.Status | Should -BeExactly 'archived'
            $result.Path | Should -BeExactly (
                Join-Path $fixture.Root (
                    'docs/implementation-plans/archived/epics/' +
                    '2026-08-01-abc123-archive-fixture'
                )
            )
            Test-Path -LiteralPath $fixture.Epic.Path | Should -BeFalse
            Test-Path -LiteralPath $result.EpicFile | Should -BeTrue
            [System.IO.File]::ReadAllText($result.EpicFile) |
                Should -Match 'child _\(archived\)_'

            $state = & $planState abc123 -RepoRoot $fixture.Root -Json |
                ConvertFrom-Json
            $state.IsArchived | Should -BeTrue
            $state.Rollup.IsComplete | Should -BeTrue

            $repeat = & $archiveEpic abc123 -RepoRoot $fixture.Root
            $repeat.Status | Should -BeExactly 'already-archived'
            { & $newEpic -Epic abc123 -RepoRoot $fixture.Root } |
                Should -Throw '*archived and cannot be modified*'
        }
        finally {
            Remove-Item -LiteralPath $fixture.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:ArchiveEpic WhatIf skips the generated-table refresh and does not report an archive' {
        $fixture = & $newArchiveFixture
        try {
            $before = [System.IO.File]::ReadAllText($fixture.Epic.EpicFile)
            $result = & $archiveEpic abc123 -RepoRoot $fixture.Root -WhatIf

            $result.Status | Should -BeExactly 'what-if'
            $result.Path | Should -BeExactly $fixture.Epic.Path
            $result.EpicFile | Should -BeExactly $fixture.Epic.EpicFile
            Test-Path -LiteralPath $fixture.Epic.Path | Should -BeTrue
            [System.IO.File]::ReadAllText($fixture.Epic.EpicFile) | Should -BeExactly $before
            Test-Path -LiteralPath (Join-Path $fixture.Root `
                    'docs/implementation-plans/archived/epics/2026-08-01-abc123-archive-fixture') |
                Should -BeFalse
        }
        finally {
            Remove-Item -LiteralPath $fixture.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:ArchiveEpic refuses incomplete epics and complete epics with active child folders' {
        foreach ($case in @(
                @{ Incomplete = $true; KeepActive = $true; Match = '*is incomplete*' },
                @{ Incomplete = $false; KeepActive = $true; Match = '*every child plan is archived*' }
            )) {
            $fixture = & $newArchiveFixture -Incomplete:$case.Incomplete `
                -KeepChildActive:$case.KeepActive
            try {
                { & $archiveEpic abc123 -RepoRoot $fixture.Root } |
                    Should -Throw $case.Match
                Test-Path -LiteralPath $fixture.Epic.EpicFile | Should -BeTrue
            }
            finally {
                Remove-Item -LiteralPath $fixture.Root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'test:ArchiveEpic refuses an existing archive destination without moving the active epic' {
        $fixture = & $newArchiveFixture
        try {
            $destination = Join-Path $fixture.Root (
                'docs/implementation-plans/archived/epics/' +
                '2026-08-01-abc123-archive-fixture'
            )
            [void](New-Item -ItemType Directory -Path $destination -Force)

            { & $archiveEpic abc123 -RepoRoot $fixture.Root } |
                Should -Throw '*destination already exists*'
            Test-Path -LiteralPath $fixture.Epic.EpicFile | Should -BeTrue
        }
        finally {
            Remove-Item -LiteralPath $fixture.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:ArchiveEpic.LinkedEpicFile refuses a linked epic.md without refreshing or moving it' {
        $fixture = & $newArchiveFixture
        $external = $fixture.Root + '-external'
        $link = $fixture.Epic.EpicFile
        try {
            [void](New-Item -ItemType Directory -Path $external)
            $target = Join-Path $external 'epic.md'
            [System.IO.File]::Copy($link, $target)
            $before = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($target))
            Remove-Item -LiteralPath $link -Force
            [void](New-Item -ItemType SymbolicLink -Path $link -Target $target -ErrorAction Stop)
            (Get-Item -LiteralPath $link -Force).Attributes -band
                [System.IO.FileAttributes]::ReparsePoint | Should -Not -Be 0

            $destination = Join-Path $fixture.Root (
                'docs/implementation-plans/archived/epics/' +
                '2026-08-01-abc123-archive-fixture'
            )
            { & $archiveEpic abc123 -RepoRoot $fixture.Root } |
                Should -Throw "*link or reparse point '$link'*"

            [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($target)) |
                Should -BeExactly $before
            [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($link)) |
                Should -BeExactly $before
            Test-Path -LiteralPath $fixture.Epic.Path | Should -BeTrue
            (Get-Item -LiteralPath $link -Force).Attributes -band
                [System.IO.FileAttributes]::ReparsePoint | Should -Not -Be 0
            Test-Path -LiteralPath $destination | Should -BeFalse
        }
        finally {
            if (Test-Path -LiteralPath $link) { Remove-Item -LiteralPath $link -Force }
            if (Test-Path -LiteralPath $external) {
                Remove-Item -LiteralPath $external -Recurse -Force
            }
            Remove-Item -LiteralPath $fixture.Root -Recurse -Force
        }
    }
}
