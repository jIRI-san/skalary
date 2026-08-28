#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'New-Plan scaffolding' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $scriptPath = Join-Path $repoRoot 'scripts/skalary/New-Plan.ps1'
        $newEpicScript = Join-Path $repoRoot 'scripts/skalary/New-Epic.ps1'
        $realTemplate = Join-Path $repoRoot 'plugins/create-implementation-plan/skills/cip/assets/plan-template.md'

        function New-TempRepo {
            $root = Join-Path ([System.IO.Path]::GetTempPath()) ("newplan-" + [guid]::NewGuid().ToString('N'))
            $plans = Join-Path $root 'docs/implementation-plans'
            New-Item -ItemType Directory -Path $plans -Force | Out-Null
            $templateDest = Join-Path $root '.github/skills/cip/assets'
            New-Item -ItemType Directory -Path $templateDest -Force | Out-Null
            Copy-Item -LiteralPath $realTemplate -Destination (Join-Path $templateDest 'plan-template.md') -Force
            Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts/skalary/PlanState.psm1') -Destination (Join-Path $root 'scripts/skalary/PlanState.psm1') -Force -ErrorAction SilentlyContinue
            return $root
        }
    }

    It 'test:PlanFolderPrefix.NewCreationAndCompatibility creates a standalone-prefixed folder with a plan-id anchor' {
        $repo = New-TempRepo
        try {
            $created = & $scriptPath -Title 'My Cool Plan' -Slug 'My Cool Plan!!' -Date '2026-07-01' -RepoRoot $repo
            $created.PlanId | Should -Match '^[0-9a-f]{6}$'
            $created.Slug | Should -Be 'my-cool-plan'
            $created.FolderPrefix | Should -Be 'standalone'
            $created.EpicId | Should -BeNullOrEmpty
            $created.FolderName | Should -Be "standalone-2026-07-01-$($created.PlanId)-my-cool-plan"
            Test-Path -LiteralPath $created.PlanFile | Should -BeTrue

            $content = Get-Content -LiteralPath $created.PlanFile -Raw
            $content | Should -Match "(?m)^#\s+$($created.PlanId):\s+My Cool Plan$"
            $content | Should -Match "<!--\s*plan-id:\s*$($created.PlanId)\s*-->"
        }
        finally {
            Remove-Item -LiteralPath $repo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:new-plan-scaffold honors an explicit -PlanId' {
        $repo = New-TempRepo
        try {
            $created = & $scriptPath -Title 'Fixed Id' -Slug 'fixed-id' -Date '2026-07-02' -PlanId 'abcd12' -RepoRoot $repo
            $created.PlanId | Should -Be 'abcd12'
            $created.FolderName | Should -Be 'standalone-2026-07-02-abcd12-fixed-id'
        }
        finally {
            Remove-Item -LiteralPath $repo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:new-plan-traversal sanitizes a traversal slug and confines the folder to the plans root' {
        $repo = New-TempRepo
        try {
            $plansRoot = [System.IO.Path]::GetFullPath((Join-Path $repo 'docs/implementation-plans'))
            $created = & $scriptPath -Title 'Evil' -Slug '../../../../etc/passwd' -Date '2026-07-03' -RepoRoot $repo

            $created.Slug | Should -Be 'etc-passwd'
            $created.FolderName | Should -Match '^standalone-2026-07-03-[0-9a-f]{6}-etc-passwd$'

            $resolved = [System.IO.Path]::GetFullPath($created.Path)
            $resolved.StartsWith($plansRoot) | Should -BeTrue

            # nothing escaped above the plans root
            Test-Path -LiteralPath (Join-Path $repo 'etc/passwd') | Should -BeFalse
        }
        finally {
            Remove-Item -LiteralPath $repo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:new-plan-traversal rejects a slug that sanitizes to empty' {
        $repo = New-TempRepo
        try {
            { & $scriptPath -Title 'Nope' -Slug '///...' -Date '2026-07-04' -RepoRoot $repo } | Should -Throw
        }
        finally {
            Remove-Item -LiteralPath $repo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'refuses to overwrite an existing plan without -Force' {
        $repo = New-TempRepo
        try {
            $first = & $scriptPath -Title 'One' -Slug 'dup' -Date '2026-07-05' -PlanId 'aaaa11' -RepoRoot $repo
            { & $scriptPath -Title 'Two' -Slug 'dup' -Date '2026-07-05' -PlanId 'aaaa11' -RepoRoot $repo } | Should -Throw
            $first.PlanId | Should -Be 'aaaa11'
        }
        finally {
            Remove-Item -LiteralPath $repo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 're-enters the same prefixed folder only when -Force is explicit' {
        $repo = New-TempRepo
        try {
            $first = & $scriptPath -Title 'One' -Slug 'same' -Date '2026-07-05' -PlanId 'aaaa11' -RepoRoot $repo
            $second = & $scriptPath -Title 'Two' -Slug 'same' -Date '2026-07-05' -PlanId 'aaaa11' -RepoRoot $repo -Force
            $second.Path | Should -Be $first.Path
            $second.FolderName | Should -Be 'standalone-2026-07-05-aaaa11-same'
        }
        finally {
            Remove-Item -LiteralPath $repo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'creates an epic-prefixed child with membership in the initial plan content' {
        $repo = New-TempRepo
        try {
            & $newEpicScript -Title 'Parent' -Slug 'parent' -Date '2026-07-05' -EpicId 'fedcba' -RepoRoot $repo | Out-Null
            $created = & $scriptPath -Title 'Child' -Slug 'child' -Date '2026-07-06' -PlanId 'aaaa11' -EpicId 'FEDCBA' -RepoRoot $repo

            $created.FolderPrefix | Should -Be 'fedcba'
            $created.EpicId | Should -Be 'fedcba'
            $created.FolderName | Should -Be 'fedcba-2026-07-06-aaaa11-child'
            $content = Get-Content -LiteralPath $created.PlanFile -Raw
            $content | Should -Match '(?m)^<!-- epic: fedcba -->$'
            Test-Path -LiteralPath (Join-Path $repo 'docs/implementation-plans/standalone-2026-07-06-aaaa11-child') |
                Should -BeFalse

            & $newEpicScript -Epic 'fedcba' -ChildPlan 'aaaa11' -RepoRoot $repo | Out-Null

            Import-Module (Join-Path $repoRoot 'scripts/skalary/PlanState.psm1') -Force -DisableNameChecking
            try {
                $entry = Resolve-Plan -Reference 'aaaa11' -RepoRoot $repo
                $entry.Id | Should -Be 'aaaa11'
                $entry.EpicId | Should -Be 'fedcba'
                $entry.FolderPrefix | Should -Be 'fedcba'
                $entry.Path | Should -Be $created.Path
                @(Get-PlanInventory -RepoRoot $repo) | Should -HaveCount 1
            }
            finally {
                Remove-Module PlanState -Force -ErrorAction SilentlyContinue
            }
        }
        finally {
            Remove-Item -LiteralPath $repo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects an epic prefix that does not identify an existing epic' {
        $repo = New-TempRepo
        try {
            { & $scriptPath -Title 'Orphan' -Slug 'orphan' -Date '2026-07-06' -PlanId 'aaaa11' -EpicId 'fedcba' -RepoRoot $repo } |
                Should -Throw '*does not identify an existing epic*'
            @(Get-PlanInventory -RepoRoot $repo) | Should -HaveCount 0
        }
        finally {
            Remove-Item -LiteralPath $repo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects an epic inventory folder whose epic.md is missing' {
        $repo = New-TempRepo
        try {
            $brokenEpic = Join-Path $repo 'docs/implementation-plans/epics/2026-07-05-fedcba-broken'
            New-Item -ItemType Directory -Path $brokenEpic -Force | Out-Null

            { & $scriptPath -Title 'Orphan' -Slug 'orphan' -Date '2026-07-06' -PlanId 'aaaa11' -EpicId 'fedcba' -RepoRoot $repo } |
                Should -Throw '*has no epic.md*'
            @(Get-PlanInventory -RepoRoot $repo) | Should -HaveCount 0
        }
        finally {
            Remove-Item -LiteralPath $repo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:new-plan-scaffold stamps the scaffolded stage through the single anchor writer' {
        $repo = New-TempRepo
        try {
            $created = & $scriptPath -Title 'Stamped' -Slug 'stamped' -Date '2026-07-06' -RepoRoot $repo
            $created.Stage | Should -Be 'scaffolded'

            $content = Get-Content -LiteralPath $created.PlanFile -Raw
            $content | Should -Match '(?m)^<!-- cip-stage: scaffolded -->$'
            ([regex]::Matches($content, 'cip-stage:')).Count | Should -Be 1

            # The stamp has to resolve as the lowest lifecycle stage, or a fresh scaffold would be
            # validated as though it had been authored.
            Import-Module (Join-Path $repoRoot 'scripts/skalary/PlanState.psm1') -Force -DisableNameChecking
            try {
                $markers = Get-PlanHeaderMarkers -Path $created.PlanFile
                Test-PlanStageAtLeast -Stage $markers.CipStage -Minimum 'drafted' | Should -BeFalse
            }
            finally {
                Remove-Module PlanState -Force -ErrorAction SilentlyContinue
            }
        }
        finally {
            Remove-Item -LiteralPath $repo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:new-plan-scaffold does not become a second writer of the stage anchor' {
        # Two writers of one anchor is how the grammar drifts; the scaffold path must delegate.
        $source = Get-Content -LiteralPath $scriptPath -Raw
        $source | Should -Not -Match '<!--\s*cip-stage'
        $source | Should -Match 'Set-PlanStage\.ps1'
    }
}
