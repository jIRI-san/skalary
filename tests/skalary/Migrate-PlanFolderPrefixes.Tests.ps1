#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Migrate-PlanFolderPrefixes' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:migrationScriptPath = Join-Path $repoRoot 'scripts/skalary/Migrate-PlanFolderPrefixes.ps1'

        function New-MigrationRepo {
            $root = Join-Path ([System.IO.Path]::GetTempPath()) (
                'plan-folder-prefix-migration-' + [guid]::NewGuid().ToString('N')
            )
            New-Item -ItemType Directory -Path (Join-Path $root 'docs/implementation-plans') -Force | Out-Null
            return $root
        }

        function New-TestPlan {
            param(
                [Parameter(Mandatory)]
                [string]$Repo,

                [Parameter(Mandatory)]
                [string]$Folder,

                [Parameter(Mandatory)]
                [string]$PlanId,

                [string]$EpicId
            )

            $planDir = Join-Path $Repo "docs/implementation-plans/$Folder"
            New-Item -ItemType Directory -Path $planDir -Force | Out-Null
            $lines = @("# ${PlanId}: Test plan", "<!-- plan-id: $PlanId -->")
            if ($EpicId) {
                $lines += "<!-- epic: $EpicId -->"
            }
            $lines += '', '## Phase 1: Work', ''
            Set-Content -LiteralPath (Join-Path $planDir 'plan.md') -Value $lines -Encoding utf8NoBOM
            return $planDir
        }

        function New-TestEpic {
            param(
                [Parameter(Mandatory)]
                [string]$Repo,

                [Parameter(Mandatory)]
                [string]$EpicId
            )

            $epicDir = Join-Path $Repo "docs/implementation-plans/epics/2026-01-01-$EpicId-parent"
            New-Item -ItemType Directory -Path $epicDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $epicDir 'epic.md') `
                -Value @("# ${EpicId}: Parent", "<!-- epic-id: $EpicId -->") `
                -Encoding utf8NoBOM
        }
    }

    It 'test:PlanFolderPrefix.MigrationWhatIf inventories deterministically without moving folders' {
        $repo = New-MigrationRepo
        try {
            New-TestEpic -Repo $repo -EpicId 'abcdef'
            $active = New-TestPlan -Repo $repo -Folder '2026-01-02-a1b2c3-active' `
                -PlanId 'a1b2c3' -EpicId 'abcdef'
            $archived = New-TestPlan -Repo $repo -Folder 'archived/2025-12-30-d4e5f6-old' `
                -PlanId 'd4e5f6'
            New-TestPlan -Repo $repo -Folder '001-legacy' -PlanId '001' | Out-Null
            New-TestPlan -Repo $repo -Folder 'standalone-2026-01-03-112233-prefixed' `
                -PlanId '112233' | Out-Null

            $mappingPath = Join-Path $repo 'migration.json'
            $before = @(Get-ChildItem -LiteralPath (Join-Path $repo 'docs/implementation-plans') -Recurse |
                    ForEach-Object { $_.FullName.Substring($repo.Length) })
            $result = & $script:migrationScriptPath -RepoRoot $repo -MappingPath $mappingPath
            $firstBytes = [System.IO.File]::ReadAllBytes($mappingPath)

            $result.Mode | Should -Be 'Inventory'
            $result.MappingWritten | Should -BeTrue
            $result.Count | Should -Be 2
            $mapping = Get-Content -LiteralPath $mappingPath -Raw | ConvertFrom-Json
            $mapping.schema | Should -Be 'skalary/plan-folder-prefix-migration@1'
            $mapping.mode | Should -Be 'inventory'
            @($mapping.entries.source) | Should -Be @(
                'docs/implementation-plans/2026-01-02-a1b2c3-active'
                'docs/implementation-plans/archived/2025-12-30-d4e5f6-old'
            )
            @($mapping.entries.target) | Should -Be @(
                'docs/implementation-plans/abcdef-2026-01-02-a1b2c3-active'
                'docs/implementation-plans/archived/standalone-2025-12-30-d4e5f6-old'
            )
            @($mapping.entries.status) | Should -Be @('pending', 'pending')

            & $script:migrationScriptPath -RepoRoot $repo -MappingPath $mappingPath | Out-Null
            [System.IO.File]::ReadAllBytes($mappingPath) | Should -Be $firstBytes
            $after = @(Get-ChildItem -LiteralPath (Join-Path $repo 'docs/implementation-plans') -Recurse |
                    ForEach-Object { $_.FullName.Substring($repo.Length) })
            $after | Should -Be $before
            Test-Path -LiteralPath $active -PathType Container | Should -BeTrue
            Test-Path -LiteralPath $archived -PathType Container | Should -BeTrue

            $whatIfPath = Join-Path $repo 'what-if.json'
            $whatIfResult = & $script:migrationScriptPath -RepoRoot $repo -MappingPath $whatIfPath -WhatIf
            $whatIfResult.MappingWritten | Should -BeFalse
            Test-Path -LiteralPath $whatIfPath | Should -BeFalse
        }
        finally {
            Remove-Item -LiteralPath $repo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:PlanFolderPrefix.MigrationPreflight rejects the full mapping before any write' {
        $repos = [System.Collections.Generic.List[string]]::new()
        try {
            $mismatchRepo = New-MigrationRepo
            $repos.Add($mismatchRepo)
            New-TestPlan -Repo $mismatchRepo -Folder '2026-01-02-a1b2c3-mismatch' `
                -PlanId 'ffffff' | Out-Null
            $mismatchMapping = Join-Path $mismatchRepo 'migration.json'
            { & $script:migrationScriptPath -RepoRoot $mismatchRepo -MappingPath $mismatchMapping } |
                Should -Throw '*mismatched identity*'
            Test-Path -LiteralPath $mismatchMapping | Should -BeFalse

            $collisionRepo = New-MigrationRepo
            $repos.Add($collisionRepo)
            New-TestEpic -Repo $collisionRepo -EpicId 'abcdef'
            New-TestPlan -Repo $collisionRepo -Folder '2026-01-02-a1b2c3-collision' `
                -PlanId 'a1b2c3' -EpicId 'abcdef' | Out-Null
            New-TestPlan -Repo $collisionRepo -Folder 'abcdef-2026-01-02-a1b2c3-collision' `
                -PlanId '112233' | Out-Null
            $collisionMapping = Join-Path $collisionRepo 'migration.json'
            { & $script:migrationScriptPath -RepoRoot $collisionRepo -MappingPath $collisionMapping } |
                Should -Throw '*collides with migration target*'
            Test-Path -LiteralPath $collisionMapping | Should -BeFalse

            $epicRepo = New-MigrationRepo
            $repos.Add($epicRepo)
            New-TestPlan -Repo $epicRepo -Folder '2026-01-02-a1b2c3-orphan' `
                -PlanId 'a1b2c3' -EpicId 'abcdef' | Out-Null
            $epicMapping = Join-Path $epicRepo 'migration.json'
            { & $script:migrationScriptPath -RepoRoot $epicRepo -MappingPath $epicMapping } |
                Should -Throw "*references unresolved epic 'abcdef'*"
            Test-Path -LiteralPath $epicMapping | Should -BeFalse

            $progressRepo = New-MigrationRepo
            $repos.Add($progressRepo)
            New-TestPlan -Repo $progressRepo -Folder '2026-01-02-a1b2c3-progress' `
                -PlanId 'a1b2c3' | Out-Null
            $progressMapping = Join-Path $progressRepo 'migration.json'
            $progress = [ordered]@{
                schema = 'skalary/plan-folder-prefix-migration@1'
                mode = 'apply'
                entries = @([ordered]@{ status = 'complete' })
            } | ConvertTo-Json -Depth 4
            Set-Content -LiteralPath $progressMapping -Value $progress -Encoding utf8NoBOM
            $progressBytes = [System.IO.File]::ReadAllBytes($progressMapping)
            { & $script:migrationScriptPath -RepoRoot $progressRepo -MappingPath $progressMapping } |
                Should -Throw '*refusing to overwrite resumable state*'
            [System.IO.File]::ReadAllBytes($progressMapping) | Should -Be $progressBytes

            if (-not $IsWindows) {
                $symlinkRepo = New-MigrationRepo
                $repos.Add($symlinkRepo)
                $planDir = Join-Path $symlinkRepo 'docs/implementation-plans/2026-01-02-a1b2c3-linked'
                New-Item -ItemType Directory -Path $planDir -Force | Out-Null
                $externalFile = Join-Path $symlinkRepo 'external-plan.md'
                Set-Content -LiteralPath $externalFile `
                    -Value @('# a1b2c3: Linked', '<!-- plan-id: a1b2c3 -->') `
                    -Encoding utf8NoBOM
                [void][System.IO.File]::CreateSymbolicLink((Join-Path $planDir 'plan.md'), $externalFile)
                $symlinkMapping = Join-Path $symlinkRepo 'migration.json'
                { & $script:migrationScriptPath -RepoRoot $symlinkRepo -MappingPath $symlinkMapping } |
                    Should -Throw '*escapes its inventoried plan folder*'
                Test-Path -LiteralPath $symlinkMapping | Should -BeFalse

                $danglingRepo = New-MigrationRepo
                $repos.Add($danglingRepo)
                New-TestPlan -Repo $danglingRepo -Folder '2026-01-02-a1b2c3-dangling' `
                    -PlanId 'a1b2c3' | Out-Null
                $danglingTarget = Join-Path $danglingRepo (
                    'docs/implementation-plans/standalone-2026-01-02-a1b2c3-dangling'
                )
                [void][System.IO.Directory]::CreateSymbolicLink(
                    $danglingTarget,
                    (Join-Path $danglingRepo 'missing-target')
                )
                $danglingMapping = Join-Path $danglingRepo 'migration.json'
                { & $script:migrationScriptPath -RepoRoot $danglingRepo -MappingPath $danglingMapping } |
                    Should -Throw '*collides with migration target*'
                Test-Path -LiteralPath $danglingMapping | Should -BeFalse

                $rootLinkRepo = Join-Path ([System.IO.Path]::GetTempPath()) (
                    'plan-folder-prefix-root-link-' + [guid]::NewGuid().ToString('N')
                )
                $externalPlans = Join-Path ([System.IO.Path]::GetTempPath()) (
                    'plan-folder-prefix-external-' + [guid]::NewGuid().ToString('N')
                )
                $repos.Add($rootLinkRepo)
                $repos.Add($externalPlans)
                New-Item -ItemType Directory -Path (Join-Path $rootLinkRepo 'docs') -Force | Out-Null
                New-Item -ItemType Directory -Path $externalPlans -Force | Out-Null
                [void][System.IO.Directory]::CreateSymbolicLink(
                    (Join-Path $rootLinkRepo 'docs/implementation-plans'),
                    $externalPlans
                )
                { & $script:migrationScriptPath -RepoRoot $rootLinkRepo -MappingPath migration.json } |
                    Should -Throw '*escapes repository root*'
                Test-Path -LiteralPath (Join-Path $rootLinkRepo 'migration.json') | Should -BeFalse
            }
        }
        finally {
            foreach ($repo in $repos) {
                Remove-Item -LiteralPath $repo -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'test:PlanFolderPrefix.MigrationResume applies and resumes the reviewed mapping idempotently' {
        $repo = New-MigrationRepo
        try {
            New-TestEpic -Repo $repo -EpicId 'abcdef'
            $firstSource = New-TestPlan -Repo $repo -Folder '2026-01-02-a1b2c3-first' `
                -PlanId 'a1b2c3' -EpicId 'abcdef'
            $secondSource = New-TestPlan -Repo $repo -Folder '2026-01-03-d4e5f6-second' `
                -PlanId 'd4e5f6'
            $mappingPath = Join-Path $repo 'migration.json'
            & $script:migrationScriptPath -RepoRoot $repo -MappingPath $mappingPath | Out-Null
            $mapping = Get-Content -LiteralPath $mappingPath -Raw | ConvertFrom-Json
            $firstTarget = Join-Path $repo $mapping.entries[0].target
            $secondTarget = Join-Path $repo $mapping.entries[1].target

            Move-Item -LiteralPath $firstSource -Destination $firstTarget
            $mapping.mode = 'apply'
            Set-Content -LiteralPath $mappingPath `
                -Value ($mapping | ConvertTo-Json -Depth 8) -Encoding utf8NoBOM
            $interruptedBytes = [System.IO.File]::ReadAllBytes($mappingPath)
            { & $script:migrationScriptPath -RepoRoot $repo -MappingPath $mappingPath } |
                Should -Throw '*refusing to overwrite resumable state*'
            [System.IO.File]::ReadAllBytes($mappingPath) | Should -Be $interruptedBytes

            $previewBytes = [System.IO.File]::ReadAllBytes($mappingPath)
            $preview = & $script:migrationScriptPath -RepoRoot $repo `
                -MappingPath $mappingPath -Apply -WhatIf
            $preview.MappingWritten | Should -BeFalse
            $preview.Moved | Should -Be 0
            Test-Path -LiteralPath $secondSource -PathType Container | Should -BeTrue
            [System.IO.File]::ReadAllBytes($mappingPath) | Should -Be $previewBytes

            $result = & $script:migrationScriptPath -RepoRoot $repo `
                -MappingPath $mappingPath -Apply
            $result.Mode | Should -Be 'Apply'
            $result.Moved | Should -Be 1
            $result.Recovered | Should -Be 1
            $result.Completed | Should -Be 2
            Test-Path -LiteralPath $firstSource | Should -BeFalse
            Test-Path -LiteralPath $secondSource | Should -BeFalse
            Test-Path -LiteralPath $firstTarget -PathType Container | Should -BeTrue
            Test-Path -LiteralPath $secondTarget -PathType Container | Should -BeTrue

            $completed = Get-Content -LiteralPath $mappingPath -Raw | ConvertFrom-Json
            $completed.mode | Should -Be 'apply'
            @($completed.entries.status) | Should -Be @('complete', 'complete')
            $completedBytes = [System.IO.File]::ReadAllBytes($mappingPath)

            $again = & $script:migrationScriptPath -RepoRoot $repo `
                -MappingPath $mappingPath -Apply
            $again.Moved | Should -Be 0
            $again.Recovered | Should -Be 0
            $again.Completed | Should -Be 2
            $again.MappingWritten | Should -BeFalse
            [System.IO.File]::ReadAllBytes($mappingPath) | Should -Be $completedBytes
        }
        finally {
            Remove-Item -LiteralPath $repo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects a tampered apply mapping before moving any folder' {
        $repo = New-MigrationRepo
        try {
            $firstSource = New-TestPlan -Repo $repo -Folder '2026-01-02-a1b2c3-first' `
                -PlanId 'a1b2c3'
            $secondSource = New-TestPlan -Repo $repo -Folder '2026-01-03-d4e5f6-second' `
                -PlanId 'd4e5f6'
            $mappingPath = Join-Path $repo 'migration.json'
            & $script:migrationScriptPath -RepoRoot $repo -MappingPath $mappingPath | Out-Null
            $mapping = Get-Content -LiteralPath $mappingPath -Raw | ConvertFrom-Json
            $firstTarget = Join-Path $repo $mapping.entries[0].target
            $mapping.entries[1].target = 'docs/implementation-plans/standalone-2026-01-03-ffffff-second'
            Set-Content -LiteralPath $mappingPath `
                -Value ($mapping | ConvertTo-Json -Depth 8) -Encoding utf8NoBOM

            { & $script:migrationScriptPath -RepoRoot $repo -MappingPath $mappingPath -Apply } |
                Should -Throw '*source, target, and canonical plan identity do not match*'
            Test-Path -LiteralPath $firstSource -PathType Container | Should -BeTrue
            Test-Path -LiteralPath $secondSource -PathType Container | Should -BeTrue
            Test-Path -LiteralPath $firstTarget | Should -BeFalse
        }
        finally {
            Remove-Item -LiteralPath $repo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects incomplete or self-moving mappings before moving any folder' {
        $repos = [System.Collections.Generic.List[string]]::new()
        try {
            $incompleteRepo = New-MigrationRepo
            $repos.Add($incompleteRepo)
            $firstSource = New-TestPlan -Repo $incompleteRepo `
                -Folder '2026-01-02-a1b2c3-first' -PlanId 'a1b2c3'
            $secondSource = New-TestPlan -Repo $incompleteRepo `
                -Folder '2026-01-03-d4e5f6-second' -PlanId 'd4e5f6'
            $thirdSource = New-TestPlan -Repo $incompleteRepo `
                -Folder '2026-01-04-778899-third' -PlanId '778899'
            $mappingPath = Join-Path $incompleteRepo 'migration.json'
            & $script:migrationScriptPath -RepoRoot $incompleteRepo `
                -MappingPath $mappingPath | Out-Null
            $mapping = Get-Content -LiteralPath $mappingPath -Raw | ConvertFrom-Json
            $firstTarget = Join-Path $incompleteRepo $mapping.entries[0].target
            $mapping.entries = @($mapping.entries[0], $mapping.entries[1])
            Set-Content -LiteralPath $mappingPath `
                -Value ($mapping | ConvertTo-Json -Depth 8) -Encoding utf8NoBOM

            { & $script:migrationScriptPath -RepoRoot $incompleteRepo `
                    -MappingPath $mappingPath -Apply } |
                Should -Throw '*does not cover eligible unprefixed plan folder*'
            Test-Path -LiteralPath $firstSource -PathType Container | Should -BeTrue
            Test-Path -LiteralPath $secondSource -PathType Container | Should -BeTrue
            Test-Path -LiteralPath $thirdSource -PathType Container | Should -BeTrue
            Test-Path -LiteralPath $firstTarget | Should -BeFalse

            $nestedRepo = New-MigrationRepo
            $repos.Add($nestedRepo)
            $nestedSource = New-TestPlan -Repo $nestedRepo `
                -Folder '2026-01-02-112233-nested' -PlanId '112233'
            $nestedMappingPath = Join-Path $nestedSource 'migration.json'
            & $script:migrationScriptPath -RepoRoot $nestedRepo `
                -MappingPath $nestedMappingPath | Out-Null

            { & $script:migrationScriptPath -RepoRoot $nestedRepo `
                    -MappingPath $nestedMappingPath -Apply } |
                Should -Throw '*contains the migration mapping beneath a folder*'
            Test-Path -LiteralPath $nestedSource -PathType Container | Should -BeTrue

            if (-not $IsWindows) {
                $linkedRepo = New-MigrationRepo
                $repos.Add($linkedRepo)
                $linkedSource = New-TestPlan -Repo $linkedRepo `
                    -Folder '2026-01-02-445566-linked' -PlanId '445566'
                $mappingLink = Join-Path $linkedRepo 'mapping-link'
                [void][System.IO.Directory]::CreateSymbolicLink($mappingLink, $linkedSource)
                $linkedMappingPath = Join-Path $mappingLink 'migration.json'
                & $script:migrationScriptPath -RepoRoot $linkedRepo `
                    -MappingPath $linkedMappingPath | Out-Null

                { & $script:migrationScriptPath -RepoRoot $linkedRepo `
                        -MappingPath $linkedMappingPath -Apply } |
                    Should -Throw '*contains the migration mapping beneath a folder*'
                Test-Path -LiteralPath $linkedSource -PathType Container | Should -BeTrue
            }
        }
        finally {
            foreach ($repo in $repos) {
                Remove-Item -LiteralPath $repo -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
