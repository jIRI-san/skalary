#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Completed plan archival' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $archiveScript = Join-Path $repoRoot 'scripts\skalary\Archive-Plan.ps1'
        Import-Module (Join-Path $repoRoot 'scripts\skalary\PlanState.psm1') -Force -DisableNameChecking

        function New-ArchiveFixture {
            param(
                [string]$Steps = '- [x] 1.1 Completed step `S`',
                [switch]$Child
            )
            $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $folder = if ($Child) { 'def456-2026-01-01-abc123-archive-fixture' }
                else { 'standalone-2026-01-01-abc123-archive-fixture' }
            $planDir = Join-Path $root "docs\implementation-plans\$folder"
            New-Item -ItemType Directory -Path (Join-Path $planDir 'assets\reviews') -Force | Out-Null
            $membership = if ($Child) { "<!-- epic: def456 -->`n" } else { '' }
            Set-Content -LiteralPath (Join-Path $planDir 'plan.md') -Encoding utf8NoBOM `
                -Value "# abc123: Archive fixture`n<!-- plan-id: abc123 -->`n$membership`n## Phase 1: Fixture`n`n$Steps"
            foreach ($name in @('intent', 'decisions')) {
                Set-Content -LiteralPath (Join-Path $planDir "assets\$name.md") -Encoding utf8NoBOM `
                    -Value "# $name`n`n- Preserve $name unchanged."
            }
            Set-Content -LiteralPath (Join-Path $planDir 'assets\requirements.md') -Encoding utf8NoBOM `
                -Value "# Requirements`n`n| ID | Requirement | Acceptance Criteria | Phases/Steps |`n|---|---|---|---|`n| REQ-1 | Preserve bytes | file:assets/evidence.bin#exists | 1.1 |"
            Set-Content -LiteralPath (Join-Path $planDir 'assets\risks.md') -Encoding utf8NoBOM `
                -Value "# Risks`n`n| ID | Risk | Likelihood | Impact | Mitigation | Steps |`n|---|---|---|---|---|---|`n| RISK-1 | Lost history | Low | Low | Preserve directory | 1.1 |"
            Set-Content -LiteralPath (Join-Path $planDir 'assets\reviews\final.md') -Encoding utf8NoBOM `
                -Value "# Advisory review`n`nPreserve review history."
            [System.IO.File]::WriteAllBytes(
                (Join-Path $planDir 'assets\evidence.bin'), [byte[]]@(0, 255, 13, 10))
            [pscustomobject]@{
                Root = $root
                PlanDir = $planDir
                ArchiveRoot = Join-Path $root 'docs\implementation-plans\archived'
                Destination = Join-Path $root "docs\implementation-plans\archived\$folder"
            }
        }
    }

    It 'moves every byte and remains resolvable through <Helper>' -ForEach @(
        @{ Helper = 'scripts\skalary\Archive-Plan.ps1' }
        @{ Helper = '.github\skills\ci\scripts\Archive-Plan.ps1' }
        @{ Helper = '.github\skills\autopilot\scripts\Archive-Plan.ps1' }
    ) {
        $fixture = New-ArchiveFixture
        $before = @{}
        foreach ($file in Get-ChildItem -LiteralPath $fixture.PlanDir -File -Recurse -Force) {
            $relative = [System.IO.Path]::GetRelativePath($fixture.PlanDir, $file.FullName)
            $before[$relative] = (Get-FileHash -LiteralPath $file.FullName).Hash
        }
        $result = & (Join-Path $repoRoot $Helper) -Plan abc123 -RepoRoot $fixture.Root
        $result.Status | Should -BeExactly 'archived'
        $result.PlanId | Should -BeExactly 'abc123'
        Test-Path -LiteralPath $fixture.PlanDir | Should -BeFalse
        foreach ($relative in $before.Keys) {
            (Get-FileHash -LiteralPath (Join-Path $result.Path $relative)).Hash | Should -Be $before[$relative]
        }
        @(Get-ChildItem -LiteralPath $result.Path -File -Recurse -Force).Count | Should -Be $before.Count
        $resolved = Resolve-Plan -Reference abc123 -RepoRoot $fixture.Root
        $resolved.IsArchived | Should -BeTrue
        (Get-PlanProgress -Path $result.PlanFile -RepoRoot $fixture.Root).IsComplete | Should -BeTrue
        (& $archiveScript -Plan abc123 -RepoRoot $fixture.Root).Status | Should -BeExactly 'already-archived'
    }

    It 'preserves epic-child membership without moving the epic index' {
        $fixture = New-ArchiveFixture -Child
        $epicDir = Join-Path $fixture.Root 'docs\implementation-plans\epics\2026-01-01-def456-fixture'
        New-Item -ItemType Directory -Path $epicDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $epicDir 'epic.md') -Value '<!-- epic-id: def456 -->'
        & $archiveScript -Plan abc123 -RepoRoot $fixture.Root | Out-Null
        $resolved = Resolve-Plan -Reference abc123 -RepoRoot $fixture.Root
        $resolved.EpicId | Should -BeExactly 'def456'
        $resolved.IsArchived | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $epicDir 'epic.md') | Should -BeTrue
    }

    It 'refuses <Reason> without making an archive directory' -ForEach @(
        @{ Reason = 'pending work'; Steps = '- [ ] 1.1 Pending `S`' }
        @{ Reason = 'in-progress work'; Steps = '- [~] 1.1 In progress `S`' }
        @{ Reason = 'a partially complete plan'; Steps = "- [x] 1.1 Done ``S```n- [ ] 1.2 Pending ``S``" }
        @{ Reason = 'an empty checklist'; Steps = '' }
    ) {
        $fixture = New-ArchiveFixture -Steps $Steps
        { & $archiveScript -Plan abc123 -RepoRoot $fixture.Root } | Should -Throw '*incomplete*'
        Test-Path -LiteralPath $fixture.PlanDir | Should -BeTrue
        Test-Path -LiteralPath $fixture.ArchiveRoot | Should -BeFalse
    }

    It 'previews without creating directories or changing plan bytes' {
        $fixture = New-ArchiveFixture
        $hash = (Get-FileHash -LiteralPath (Join-Path $fixture.PlanDir 'plan.md')).Hash
        (& $archiveScript -Plan abc123 -RepoRoot $fixture.Root -WhatIf).Status | Should -BeExactly 'what-if'
        Test-Path -LiteralPath $fixture.ArchiveRoot | Should -BeFalse
        (Get-FileHash -LiteralPath (Join-Path $fixture.PlanDir 'plan.md')).Hash | Should -Be $hash
    }

    It 'refuses destination collisions without overwriting existing content' {
        $fixture = New-ArchiveFixture
        New-Item -ItemType Directory -Path $fixture.Destination -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $fixture.Destination 'keep.txt') -Value 'existing'
        { & $archiveScript -Plan abc123 -RepoRoot $fixture.Root } | Should -Throw '*destination already exists*'
        Get-Content -LiteralPath (Join-Path $fixture.Destination 'keep.txt') | Should -BeExactly 'existing'
        Test-Path -LiteralPath $fixture.PlanDir | Should -BeTrue
    }

    It 'refuses ambiguous references instead of selecting an active copy' {
        $fixture = New-ArchiveFixture
        New-Item -ItemType Directory -Path $fixture.Destination -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $fixture.PlanDir 'plan.md') -Destination $fixture.Destination
        { & $archiveScript -Plan abc123 -RepoRoot $fixture.Root } | Should -Throw '*Ambiguous plan reference*'
        Test-Path -LiteralPath $fixture.PlanDir | Should -BeTrue
    }

    It 'refuses linked source assets and archive roots' {
        foreach ($location in @('asset', 'archive')) {
            $fixture = New-ArchiveFixture
            $target = Join-Path $fixture.Root 'link-target'
            New-Item -ItemType Directory -Path $target | Out-Null
            $link = if ($location -eq 'asset') { Join-Path $fixture.PlanDir 'assets\linked' }
                else { $fixture.ArchiveRoot }
            $linkType = if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }
            New-Item -ItemType $linkType -Path $link -Target $target | Out-Null
            $expected = if ($location -eq 'asset') { '*link or reparse point*' } else { '*regular directory*' }
            { & $archiveScript -Plan abc123 -RepoRoot $fixture.Root } | Should -Throw $expected
            Test-Path -LiteralPath $fixture.PlanDir | Should -BeTrue
        }
    }

    It 'wires archival after learning and excludes phase and non-clean finalization' {
        foreach ($path in @(
            'plugins\continue-implementation\skills\ci\SKILL.md'
            'plugins\autopilot\skills\autopilot\SKILL.md'
            'plugins\autopilot\agents\autopilot.agent.md'
        )) {
            $text = Get-Content -LiteralPath (Join-Path $repoRoot $path) -Raw
            $text | Should -Match 'committed learning handoff'
            $text | Should -Match 'Archive-Plan\.ps1'
            $text | Should -Match 'already-archived'
            $text | Should -Match '(?i)phase.*(?:never archive|never reaches)|Never archive from a phase'
            $text | Should -Match 'failed|incomplete'
        }
    }
}
