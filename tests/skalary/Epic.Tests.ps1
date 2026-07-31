#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'New-Epic' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $newEpic = Join-Path $repoRoot 'scripts/skalary/New-Epic.ps1'
        Import-Module (Join-Path $repoRoot 'scripts/skalary/PlanState.psm1') -Force -DisableNameChecking

        $newTempRoot = {
            $path = Join-Path ([System.IO.Path]::GetTempPath()) ('epic-' + [System.Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path (Join-Path $path 'docs/implementation-plans/archived') -Force | Out-Null
            return $path
        }

        # A child plan is an ordinary plan folder: the epic never contains it, it only stamps a marker
        # into it, so the fixture is deliberately a plain sibling plan.
        $newChildPlan = {
            param([string]$Root, [string]$PlanId, [string]$Slug, [string]$Date = '2026-08-01')
            $dir = Join-Path $Root "docs/implementation-plans/$Date-$PlanId-$Slug"
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $content = @(
                "# ${PlanId}: Child $Slug"
                "<!-- plan-id: $PlanId -->"
                '<!-- execution-mode: manual -->'
                '<!-- scope: plan -->'
                ''
                '## Requirements'
                ''
                '| ID | Requirement | Acceptance Criteria | Phases/Steps |'
                '|----|-------------|---------------------|--------------|'
                '| REQ-1 | Child requirement | `test:child-one` | 1.1 |'
                ''
                '## Phase 1: Fixture'
                ''
                '- [ ] 1.1 First step (REQ-1) `S`'
            )
            Set-Content -LiteralPath (Join-Path $dir 'plan.md') -Value ($content -join "`n") -Encoding utf8NoBOM
            return $dir
        }
    }

    Context 'test:epic-scaffold-links-children' {
        It 'test:epic-scaffold-links-children scaffolds an epic folder with an epic.md anchor' {
            $tmp = & $newTempRoot
            try {
                $result = & $newEpic -Title 'Payments rework' -Slug 'payments-rework' -RepoRoot $tmp -Date '2026-08-01' -EpicId 'aa11bb'

                $result.EpicId | Should -Be 'aa11bb'
                $result.FolderName | Should -Be '2026-08-01-aa11bb-payments-rework'
                Test-Path -LiteralPath $result.EpicFile | Should -BeTrue

                $epicText = Get-Content -LiteralPath $result.EpicFile -Raw
                $epicText | Should -Match '<!--\s*epic-id:\s*aa11bb\s*-->'
                $epicText | Should -Match '(?m)^#\s+aa11bb: Payments rework'

                # The epic sits beside plans, not inside the plan namespace: plan resolution must not see it.
                @(Get-PlanInventory -RepoRoot $tmp) | Should -HaveCount 0
                (Get-EpicInventory -RepoRoot $tmp).Id | Should -Be 'aa11bb'
            }
            finally {
                Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:epic-scaffold-links-children stamps the epic marker into every child plan' {
            $tmp = & $newTempRoot
            try {
                & $newChildPlan -Root $tmp -PlanId '111aaa' -Slug 'core' | Out-Null
                & $newChildPlan -Root $tmp -PlanId '222bbb' -Slug 'api' | Out-Null

                $result = & $newEpic -Title 'Split delivery' -Slug 'split-delivery' -RepoRoot $tmp -Date '2026-08-01' -EpicId 'cc33dd' -ChildPlan '111aaa', '222bbb'

                $result.Children | Should -Be @('111aaa', '222bbb')
                foreach ($id in @('111aaa', '222bbb')) {
                    $planFile = Join-Path $tmp "docs/implementation-plans/2026-08-01-$id-$(if ($id -eq '111aaa') { 'core' } else { 'api' })/plan.md"
                    $markers = Get-PlanHeaderMarkers -Path $planFile
                    $markers.EpicId | Should -Be 'cc33dd'
                    $markers.PlanId | Should -Be $id
                }

                # Membership is readable straight off the child plans, without consulting epic.md.
                @(Get-PlanInventory -RepoRoot $tmp | Where-Object { $_.EpicId -eq 'cc33dd' }) | Should -HaveCount 2
            }
            finally {
                Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:epic-scaffold-links-children mirrors the marker set into the epic child table' {
            $tmp = & $newTempRoot
            try {
                & $newChildPlan -Root $tmp -PlanId '111aaa' -Slug 'core' | Out-Null
                & $newChildPlan -Root $tmp -PlanId '222bbb' -Slug 'api' | Out-Null

                $result = & $newEpic -Title 'Split delivery' -Slug 'split-delivery' -RepoRoot $tmp -EpicId 'cc33dd' -ChildPlan '111aaa'
                $afterFirst = Get-Content -LiteralPath $result.EpicFile -Raw
                $afterFirst | Should -Match '\|\s*`111aaa`\s*\|'
                $afterFirst | Should -Not -Match '\|\s*`222bbb`\s*\|'
                $afterFirst | Should -Not -Match '_\(none yet\)_'

                & $newEpic -Epic 'cc33dd' -RepoRoot $tmp -ChildPlan '222bbb' | Out-Null
                $afterSecond = Get-Content -LiteralPath $result.EpicFile -Raw
                $afterSecond | Should -Match '\|\s*`111aaa`\s*\|'
                $afterSecond | Should -Match '\|\s*`222bbb`\s*\|'

                # Rebuilt from the markers on disk, so a repeat attach is a no-op rather than a duplicate row.
                $childBefore = Get-Content -LiteralPath (Join-Path $tmp 'docs/implementation-plans/2026-08-01-222bbb-api/plan.md') -Raw
                & $newEpic -Epic 'cc33dd' -RepoRoot $tmp -ChildPlan '222bbb' | Out-Null
                Get-Content -LiteralPath $result.EpicFile -Raw | Should -BeExactly $afterSecond
                Get-Content -LiteralPath (Join-Path $tmp 'docs/implementation-plans/2026-08-01-222bbb-api/plan.md') -Raw |
                    Should -BeExactly $childBefore
            }
            finally {
                Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:epic-scaffold-links-children wires depends-on between siblings and merges idempotently' {
            $tmp = & $newTempRoot
            try {
                & $newChildPlan -Root $tmp -PlanId '111aaa' -Slug 'core' | Out-Null
                & $newChildPlan -Root $tmp -PlanId '222bbb' -Slug 'api' | Out-Null
                & $newChildPlan -Root $tmp -PlanId '333ccc' -Slug 'ui' | Out-Null

                & $newEpic -Title 'Split delivery' -Slug 'split-delivery' -RepoRoot $tmp -EpicId 'cc33dd' -ChildPlan '111aaa' | Out-Null
                & $newEpic -Epic 'cc33dd' -RepoRoot $tmp -ChildPlan '222bbb' -DependsOn '111aaa' | Out-Null
                & $newEpic -Epic 'cc33dd' -RepoRoot $tmp -ChildPlan '333ccc' -DependsOn '222bbb' | Out-Null
                & $newEpic -Epic 'cc33dd' -RepoRoot $tmp -ChildPlan '333ccc' -DependsOn '222bbb' | Out-Null

                $apiMarkers = Get-PlanHeaderMarkers -Path (Join-Path $tmp 'docs/implementation-plans/2026-08-01-222bbb-api/plan.md')
                $apiMarkers.DependsOn | Should -Be @('111aaa')
                $uiMarkers = Get-PlanHeaderMarkers -Path (Join-Path $tmp 'docs/implementation-plans/2026-08-01-333ccc-ui/plan.md')
                $uiMarkers.DependsOn | Should -Be @('222bbb')

                { & $newEpic -Epic 'cc33dd' -RepoRoot $tmp -ChildPlan '333ccc' -DependsOn '333ccc' } |
                    Should -Throw '*cannot depend on itself*'
                { & $newEpic -Epic 'cc33dd' -RepoRoot $tmp -ChildPlan '111aaa', '222bbb' -DependsOn '333ccc' } |
                    Should -Throw '*exactly one -ChildPlan*'
            }
            finally {
                Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:epic-scaffold-links-children keeps a stamped child independently executable' {
            $tmp = & $newTempRoot
            try {
                $childDir = & $newChildPlan -Root $tmp -PlanId '111aaa' -Slug 'core'
                $before = Get-PlanMetadata -Path (Join-Path $childDir 'plan.md') -RepoRoot $tmp

                & $newEpic -Title 'Split delivery' -Slug 'split-delivery' -RepoRoot $tmp -EpicId 'cc33dd' -ChildPlan '111aaa' | Out-Null

                $after = Get-PlanMetadata -Path (Join-Path $childDir 'plan.md') -RepoRoot $tmp
                @($after.Steps).Count | Should -Be @($before.Steps).Count
                @($after.Requirements.Keys) | Should -Be @($before.Requirements.Keys)
                (Resolve-Plan -Reference '111aaa' -RepoRoot $tmp).Path | Should -Be $childDir
            }
            finally {
                Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:epic-scaffold-links-children refuses silent re-parenting and id collisions' {
            $tmp = & $newTempRoot
            try {
                & $newChildPlan -Root $tmp -PlanId '111aaa' -Slug 'core' | Out-Null

                & $newEpic -Title 'First epic' -Slug 'first-epic' -RepoRoot $tmp -EpicId 'cc33dd' -ChildPlan '111aaa' | Out-Null
                & $newEpic -Title 'Second epic' -Slug 'second-epic' -RepoRoot $tmp -EpicId 'ee55ff' | Out-Null

                { & $newEpic -Epic 'ee55ff' -RepoRoot $tmp -ChildPlan '111aaa' } | Should -Throw '*already belongs to epic*'

                & $newEpic -Epic 'ee55ff' -RepoRoot $tmp -ChildPlan '111aaa' -Force | Out-Null
                (Get-PlanHeaderMarkers -Path (Join-Path $tmp 'docs/implementation-plans/2026-08-01-111aaa-core/plan.md')).EpicId |
                    Should -Be 'ee55ff'

                # Re-parenting must not leave the losing epic advertising a child it no longer owns.
                $firstEpicFile = (Get-EpicInventory -RepoRoot $tmp | Where-Object { $_.Id -eq 'cc33dd' }).EpicFile
                Get-Content -LiteralPath $firstEpicFile -Raw | Should -Not -Match '\|\s*`111aaa`\s*\|'
                Get-Content -LiteralPath $firstEpicFile -Raw | Should -Match '_\(none yet\)_'
                (Get-EpicInventory -RepoRoot $tmp | Where-Object { $_.Id -eq 'ee55ff' }).EpicFile |
                    ForEach-Object { Get-Content -LiteralPath $_ -Raw } | Should -Match '\|\s*`111aaa`\s*\|'

                { & $newEpic -Title 'Clashing' -Slug 'clashing' -RepoRoot $tmp -EpicId '111aaa' } | Should -Throw '*already taken*'
            }
            finally {
                Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:epic-scaffold-links-children reads membership from the plan header, not the plan body' {
            $tmp = & $newTempRoot
            try {
                $dir = Join-Path $tmp 'docs/implementation-plans/2026-08-01-999fff-doc'
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
                # A plan that merely documents the marker in a fenced example must not be enrolled.
                Set-Content -LiteralPath (Join-Path $dir 'plan.md') -Encoding utf8NoBOM -Value (@(
                    '# 999fff: Documents the marker'
                    '<!-- plan-id: 999fff -->'
                    ''
                    '## Phase 1: Fixture'
                    ''
                    '- [ ] 1.1 Explain the marker `S`'
                    ''
                    '```markdown'
                    '<!-- epic: cc33dd -->'
                    '```'
                ) -join "`n")

                (Get-PlanInventory -RepoRoot $tmp | Where-Object { $_.Id -eq '999fff' }).EpicId | Should -BeNullOrEmpty

                $result = & $newEpic -Title 'Split delivery' -Slug 'split-delivery' -RepoRoot $tmp -EpicId 'cc33dd'
                Get-Content -LiteralPath $result.EpicFile -Raw | Should -Not -Match '\|\s*`999fff`\s*\|'
            }
            finally {
                Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:epic-scaffold-links-children keeps plan ids and epic ids in one id space' {
            $tmp = & $newTempRoot
            try {
                $newPlan = Join-Path $repoRoot 'scripts/skalary/New-Plan.ps1'
                $template = Join-Path $repoRoot 'plugins/create-implementation-plan/skills/cip/assets/plan-template.md'

                & $newEpic -Title 'Split delivery' -Slug 'split-delivery' -RepoRoot $tmp -EpicId 'cc33dd' | Out-Null

                { & $newPlan -Title 'Colliding plan' -Slug 'colliding' -RepoRoot $tmp -PlanId 'cc33dd' -TemplatePath $template } |
                    Should -Throw '*already taken*'
            }
            finally {
                Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:epic-scaffold-links-children confines the epic folder to the epics root' {
            $tmp = & $newTempRoot
            try {
                $result = & $newEpic -Title 'Escape attempt' -Slug '../../etc/passwd' -RepoRoot $tmp -EpicId 'ab12cd' -Date '2026-08-01'

                $epicsRoot = [System.IO.Path]::GetFullPath((Join-Path $tmp 'docs/implementation-plans/epics'))
                $result.Path.StartsWith($epicsRoot) | Should -BeTrue
                $result.FolderName | Should -Be '2026-08-01-ab12cd-etc-passwd'
            }
            finally {
                Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'cep skill' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $pluginRoot = Join-Path $repoRoot 'plugins/create-implementation-plan'
        $skillPath = Join-Path $pluginRoot 'skills/cep/SKILL.md'
        $guidePath = Join-Path $pluginRoot 'skills/cep/assets/decomposition-guide.md'
        $manifest = Get-Content -LiteralPath (Join-Path $pluginRoot 'plugin.json') -Raw | ConvertFrom-Json
        $skillText = Get-Content -LiteralPath $skillPath -Raw
        $guideText = Get-Content -LiteralPath $guidePath -Raw
    }

    It 'ships the skill and its decomposition asset from the create-implementation-plan plugin' {
        Test-Path -LiteralPath $skillPath | Should -BeTrue
        Test-Path -LiteralPath $guidePath | Should -BeTrue
        $skillText | Should -Match '(?m)^name:\s*cep\s*$'
        $skillText | Should -Match '(?m)^user-invocable:\s*true\s*$'

        $declared = @($manifest.files | ForEach-Object { $_.src })
        $declared | Should -Contain 'skills/cep/SKILL.md'
        $declared | Should -Contain 'skills/cep/assets/decomposition-guide.md'
        # /cep scaffolds child plans, so the template New-Plan.ps1 reads must reach an installed copy.
        @($manifest.files | ForEach-Object { $_.dest }) | Should -Contain 'skills/cep/assets/plan-template.md'
    }

    It 'declares every installed path it reads, so an installed copy is not missing an asset' {
        $declaredDest = @($manifest.files | ForEach-Object { $_.dest })
        $referenced = @()
        foreach ($text in @($skillText, $guideText)) {
            foreach ($match in [regex]::Matches($text, '\.github/skills/cep/(?<rel>[A-Za-z0-9._/-]+)')) {
                $referenced += "skills/cep/$($match.Groups['rel'].Value)"
            }
        }

        @($referenced) | Should -Not -BeNullOrEmpty
        foreach ($ref in ($referenced | Sort-Object -Unique)) {
            $declaredDest | Should -Contain $ref
            # The payload source may live under another skill's folder (e.g. the shared plan template),
            # so resolve through the manifest entry rather than assuming src equals dest.
            $entry = @($manifest.files | Where-Object { $_.dest -eq $ref })
            $entry | Should -HaveCount 1
            Test-Path -LiteralPath (Join-Path $pluginRoot $entry[0].src) | Should -BeTrue
        }
    }

    It 'stays thin by pushing decomposition detail into the asset' {
        # The orchestrator carries the flow; the question bank, gates, and anti-patterns live in the asset.
        (Get-Item -LiteralPath $skillPath).Length | Should -BeLessOrEqual 8192
        $guideText | Should -Match 'epic-intent'
        $guideText | Should -Match 'Independent-executability test'
        $skillText | Should -Match './assets/decomposition-guide.md'
        $skillText | Should -Not -Match 'Anti-pattern \|'
    }

    It 'scaffolds and wires only, delegating child plan content to /cip' {
        $skillText | Should -Match '/cip'
        $skillText | Should -Match 'New-Epic\.ps1'
        $skillText | Should -Match '-DependsOn'
        # Membership authority has to stay with the child plan marker, not the generated epic table.
        $skillText | Should -Match '<!-- epic: <id> -->'
    }
}

Describe 'New-Plan template resolution' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    }

    It 'resolves the template from the skill assets beside the script when there is no plugins tree' {
        # An installed copy only has .github/skills/<skill>/{scripts,assets}; the repo layout is absent.
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('newplan-' + [System.Guid]::NewGuid().ToString('N'))
        try {
            $scriptDir = Join-Path $tmp '.github/skills/cep/scripts'
            $assetDir = Join-Path $tmp '.github/skills/cep/assets'
            New-Item -ItemType Directory -Path $scriptDir -Force | Out-Null
            New-Item -ItemType Directory -Path $assetDir -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $tmp 'docs/implementation-plans') -Force | Out-Null
            foreach ($name in @('New-Plan.ps1', 'PlanState.psm1')) {
                Copy-Item -LiteralPath (Join-Path $repoRoot "scripts/skalary/$name") -Destination (Join-Path $scriptDir $name)
            }
            Copy-Item -LiteralPath (Join-Path $repoRoot 'plugins/create-implementation-plan/skills/cip/assets/plan-template.md') -Destination (Join-Path $assetDir 'plan-template.md')

            $result = & (Join-Path $scriptDir 'New-Plan.ps1') -Title 'Installed copy' -Slug 'installed-copy' -RepoRoot $tmp
            Test-Path -LiteralPath $result.PlanFile | Should -BeTrue
            Get-Content -LiteralPath $result.PlanFile -Raw | Should -Match "<!--\s*plan-id: $($result.PlanId)\s*-->"
        }
        finally {
            Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
