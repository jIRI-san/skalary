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

        It 'reconciles a prefixed folder during attachment and forced re-parenting' {
            $tmp = & $newTempRoot
            try {
                $newPlan = Join-Path $repoRoot 'scripts/skalary/New-Plan.ps1'
                $template = Join-Path $repoRoot 'plugins/create-implementation-plan/skills/cip/assets/plan-template.md'
                & $newEpic -Title 'First epic' -Slug 'first-epic' -RepoRoot $tmp -Date '2026-08-01' -EpicId 'cc33dd' | Out-Null
                & $newEpic -Title 'Second epic' -Slug 'second-epic' -RepoRoot $tmp -Date '2026-08-01' -EpicId 'ee55ff' | Out-Null
                $created = & $newPlan -Title 'Attach later' -Slug 'attach-later' -RepoRoot $tmp -Date '2026-08-01' -PlanId '111aaa' -TemplatePath $template
                $created.FolderName | Should -Be 'standalone-2026-08-01-111aaa-attach-later'

                $attached = & $newEpic -Epic 'cc33dd' -RepoRoot $tmp -ChildPlan '111aaa'
                $attached.Stamped[0].Path | Should -Be (Join-Path $tmp 'docs/implementation-plans/cc33dd-2026-08-01-111aaa-attach-later')
                Test-Path -LiteralPath $created.Path | Should -BeFalse
                (Resolve-Plan -Reference '111aaa' -RepoRoot $tmp).EpicId | Should -Be 'cc33dd'

                $reparented = & $newEpic -Epic 'ee55ff' -RepoRoot $tmp -ChildPlan '111aaa' -Force
                $reparented.Stamped[0].Path | Should -Be (Join-Path $tmp 'docs/implementation-plans/ee55ff-2026-08-01-111aaa-attach-later')
                Test-Path -LiteralPath $attached.Stamped[0].Path | Should -BeFalse
                $resolved = Resolve-Plan -Reference '111aaa' -RepoRoot $tmp
                $resolved.EpicId | Should -Be 'ee55ff'
                $resolved.FolderPrefix | Should -Be 'ee55ff'
            }
            finally {
                Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'rejects a prefix target collision before changing membership' {
            $tmp = & $newTempRoot
            try {
                $newPlan = Join-Path $repoRoot 'scripts/skalary/New-Plan.ps1'
                $template = Join-Path $repoRoot 'plugins/create-implementation-plan/skills/cip/assets/plan-template.md'
                & $newEpic -Title 'Parent' -Slug 'parent' -RepoRoot $tmp -Date '2026-08-01' -EpicId 'cc33dd' | Out-Null
                $created = & $newPlan -Title 'Attach later' -Slug 'attach-later' -RepoRoot $tmp -Date '2026-08-01' -PlanId '111aaa' -TemplatePath $template
                $collision = Join-Path $tmp 'docs/implementation-plans/cc33dd-2026-08-01-111aaa-attach-later'
                New-Item -ItemType Directory -Path $collision -Force | Out-Null

                { & $newEpic -Epic 'cc33dd' -RepoRoot $tmp -ChildPlan '111aaa' } |
                    Should -Throw '*Ambiguous plan reference*'

                Test-Path -LiteralPath $created.Path | Should -BeTrue
                (Get-PlanHeaderMarkers -Path $created.PlanFile).EpicId | Should -BeNullOrEmpty
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
        $cipSkillPath = Join-Path $pluginRoot 'skills/cip/SKILL.md'
        $manifest = Get-Content -LiteralPath (Join-Path $pluginRoot 'plugin.json') -Raw | ConvertFrom-Json
        $skillText = Get-Content -LiteralPath $skillPath -Raw
        $guideText = Get-Content -LiteralPath $guidePath -Raw
        $cipSkillText = Get-Content -LiteralPath $cipSkillPath -Raw
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
        $guideText | Should -Match 'child-context'
        $guideText | Should -Match 'Epic discussion provenance'
        $guideText | Should -Match 'rejected alternatives'
        $guideText | Should -Match 'Independent-executability test'
        $skillText | Should -Match './assets/decomposition-guide.md'
        $skillText | Should -Not -Match 'Anti-pattern \|'
    }

    It 'preserves preliminary epic context while delegating full child drafting to /cip' {
        $skillText | Should -Match '/cip'
        $skillText | Should -Match 'New-Epic\.ps1'
        $skillText | Should -Match '-DependsOn'
        $skillText | Should -Match 'child-context'
        $skillText | Should -Match 'assets/intent\.md'
        $skillText | Should -Match 'assets/decisions\.md'
        $skillText | Should -Match 'assets/references\.md'
        $skillText | Should -Match 'Epic discussion provenance'
        $skillText | Should -Match 'must not reset them to templates'
        $skillText | Should -Match 'owns child requirements, risks, evidence, and steps'
        $skillText | Should -Match '/cep` never writes those sections'
        $cipSkillText | Should -Match 'preserve their \*\*Epic discussion provenance\*\*'
        $cipSkillText | Should -Match 'never reset them to scaffold templates'
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
            foreach ($name in @('New-Plan.ps1', 'PlanState.psm1', 'Set-PlanStage.ps1')) {
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

Describe 'Epic rollup for /ci' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $newEpic = Join-Path $repoRoot 'scripts/skalary/New-Epic.ps1'
        $planState = Join-Path $repoRoot 'scripts/skalary/Get-PlanState.ps1'
        Import-Module (Join-Path $repoRoot 'scripts/skalary/PlanState.psm1') -Force -DisableNameChecking

        $newTempRoot = {
            $path = Join-Path ([System.IO.Path]::GetTempPath()) ('epic-rollup-' + [System.Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path (Join-Path $path 'docs/implementation-plans/archived') -Force | Out-Null
            return $path
        }

        $newChildPlan = {
            param([string]$Root, [string]$PlanId, [string]$Slug, [int]$Done = 0, [int]$Steps = 2, [switch]$Archived)
            $parent = if ($Archived) { 'docs/implementation-plans/archived' } else { 'docs/implementation-plans' }
            $dir = Join-Path $Root "$parent/2026-08-01-$PlanId-$Slug"
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $stepLines = for ($i = 1; $i -le $Steps; $i++) {
                $mark = if ($i -le $Done) { 'x' } else { ' ' }
                "- [$mark] 1.$i Step $i (REQ-1) ``S``"
            }
            $content = @(
                "# ${PlanId}: Child $Slug"
                "<!-- plan-id: $PlanId -->"
                ''
                '## Requirements'
                ''
                '| ID | Requirement | Acceptance Criteria | Phases/Steps |'
                '|----|-------------|---------------------|--------------|'
                '| REQ-1 | Child requirement | `test:child-one` | 1.1 |'
                ''
                '## Phase 1: Fixture'
                ''
            ) + $stepLines
            Set-Content -LiteralPath (Join-Path $dir 'plan.md') -Value ($content -join "`n") -Encoding utf8NoBOM
            return $dir
        }
    }

    Context 'test:ci-selects-next-child-plan' {
        It 'test:ci-selects-next-child-plan skips blocked children and picks the first unblocked one' {
            $tmp = & $newTempRoot
            try {
                & $newChildPlan -Root $tmp -PlanId '111aaa' -Slug 'core' -Done 2 | Out-Null
                & $newChildPlan -Root $tmp -PlanId '222bbb' -Slug 'api' -Done 1 | Out-Null
                & $newChildPlan -Root $tmp -PlanId '333ccc' -Slug 'ui' -Done 0 | Out-Null

                & $newEpic -Title 'Rollup' -Slug 'rollup' -RepoRoot $tmp -EpicId 'ab12cd' -ChildPlan '111aaa' | Out-Null
                & $newEpic -Epic 'ab12cd' -RepoRoot $tmp -ChildPlan '222bbb' -DependsOn '111aaa' | Out-Null
                & $newEpic -Epic 'ab12cd' -RepoRoot $tmp -ChildPlan '333ccc' -DependsOn '222bbb' | Out-Null

                $rollup = Get-EpicRollup -EpicId 'ab12cd' -RepoRoot $tmp

                $rollup.ChildCount | Should -Be 3
                $rollup.CompleteCount | Should -Be 1
                $rollup.BlockedCount | Should -Be 1
                $rollup.CompletedSteps | Should -Be 3
                $rollup.TotalSteps | Should -Be 6
                $rollup.NextChild.Id | Should -Be '222bbb'
                $rollup.NextChild.NextStepId | Should -Be '1.2'
                $blockedChild = @($rollup.Children | Where-Object { $_.Id -eq '333ccc' }) | Select-Object -First 1
                $blockedChild.UnmetDependsOn | Should -Be @('222bbb')
            }
            finally {
                Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:ci-selects-next-child-plan unblocks a dependent once its dependency is complete or archived' {
            $tmp = & $newTempRoot
            try {
                & $newChildPlan -Root $tmp -PlanId '111aaa' -Slug 'core' -Done 2 -Archived | Out-Null
                & $newChildPlan -Root $tmp -PlanId '222bbb' -Slug 'api' -Done 0 | Out-Null

                & $newEpic -Title 'Rollup' -Slug 'rollup' -RepoRoot $tmp -EpicId 'ab12cd' -ChildPlan '111aaa' | Out-Null
                & $newEpic -Epic 'ab12cd' -RepoRoot $tmp -ChildPlan '222bbb' -DependsOn '111aaa' | Out-Null

                $rollup = Get-EpicRollup -EpicId 'ab12cd' -RepoRoot $tmp
                (@($rollup.Children | Where-Object { $_.Id -eq '111aaa' }) | Select-Object -First 1).IsComplete | Should -BeTrue
                $rollup.BlockedCount | Should -Be 0
                $rollup.NextChild.Id | Should -Be '222bbb'
            }
            finally {
                Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:ci-selects-next-child-plan skips an earlier blocked child for a later free one' {
            $tmp = & $newTempRoot
            try {
                & $newChildPlan -Root $tmp -PlanId '111aaa' -Slug 'core' -Done 0 | Out-Null
                & $newChildPlan -Root $tmp -PlanId '222bbb' -Slug 'api' -Done 0 | Out-Null
                & $newChildPlan -Root $tmp -PlanId '333ccc' -Slug 'ui' -Done 0 | Out-Null

                & $newEpic -Title 'Rollup' -Slug 'rollup' -RepoRoot $tmp -EpicId 'ab12cd' -ChildPlan '222bbb' | Out-Null
                # The first child in order is blocked; selection must walk past it, not stop at it.
                & $newEpic -Epic 'ab12cd' -RepoRoot $tmp -ChildPlan '111aaa' -DependsOn '333ccc' | Out-Null

                $rollup = Get-EpicRollup -EpicId 'ab12cd' -RepoRoot $tmp
                @($rollup.Children | ForEach-Object { $_.Id }) | Should -Be @('111aaa', '222bbb')
                (@($rollup.Children | Where-Object { $_.Id -eq '111aaa' }) | Select-Object -First 1).IsBlocked | Should -BeTrue
                $rollup.NextChild.Id | Should -Be '222bbb'
            }
            finally {
                Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:ci-selects-next-child-plan judges a non-member dependency by its own state' {
            $tmp = & $newTempRoot
            try {
                # A depends-on may point outside the epic; membership must not decide its completeness.
                & $newChildPlan -Root $tmp -PlanId '999fff' -Slug 'outside' -Done 2 | Out-Null
                & $newChildPlan -Root $tmp -PlanId '222bbb' -Slug 'api' -Done 0 | Out-Null

                & $newEpic -Title 'Rollup' -Slug 'rollup' -RepoRoot $tmp -EpicId 'ab12cd' -ChildPlan '222bbb' -DependsOn '999fff' | Out-Null

                $rollup = Get-EpicRollup -EpicId 'ab12cd' -RepoRoot $tmp
                $child = @($rollup.Children | Where-Object { $_.Id -eq '222bbb' }) | Select-Object -First 1
                $child.DependsOn | Should -Be @('999fff')
                $child.UnmetDependsOn | Should -BeNullOrEmpty
                $child.IsBlocked | Should -BeFalse
                $rollup.NextChild.Id | Should -Be '222bbb'
            }
            finally {
                Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:ci-selects-next-child-plan keeps a plan reference resolving to the plan' {
            $tmp = & $newTempRoot
            try {
                & $newChildPlan -Root $tmp -PlanId '222bbb' -Slug 'payments-core' -Done 0 | Out-Null
                & $newEpic -Title 'Payments rework' -Slug 'payments-rework' -RepoRoot $tmp -EpicId 'ab12cd' -Date '2026-08-01' -ChildPlan '222bbb' | Out-Null

                # A date or slug that both a plan and an epic answer to must keep resolving to the plan.
                (& $planState '2026-08-01' -RepoRoot $tmp -Json | ConvertFrom-Json).Kind | Should -Be 'plan'
                (& $planState 'payments' -RepoRoot $tmp -Json | ConvertFrom-Json).Kind | Should -Be 'plan'
                (& $planState 'payments-rework' -RepoRoot $tmp -Epic -Json | ConvertFrom-Json).Kind | Should -Be 'epic'
                (& $planState 'ab12cd' -RepoRoot $tmp -Json | ConvertFrom-Json).Kind | Should -Be 'epic'
            }
            finally {
                Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:ci-selects-next-child-plan is fail-closed on an unresolvable dependency' {
            $tmp = & $newTempRoot
            try {
                $dir = & $newChildPlan -Root $tmp -PlanId '222bbb' -Slug 'api' -Done 0
                & $newEpic -Title 'Rollup' -Slug 'rollup' -RepoRoot $tmp -EpicId 'ab12cd' -ChildPlan '222bbb' | Out-Null

                $planFile = Join-Path $dir 'plan.md'
                $raw = Get-Content -LiteralPath $planFile -Raw
                Set-Content -LiteralPath $planFile -Encoding utf8NoBOM -Value ($raw -replace '<!-- epic: ab12cd -->', "<!-- epic: ab12cd -->`n<!-- depends-on: deadbe -->")

                $rollup = Get-EpicRollup -EpicId 'ab12cd' -RepoRoot $tmp
                $child = @($rollup.Children | Where-Object { $_.Id -eq '222bbb' }) | Select-Object -First 1
                $child.UnknownDependsOn | Should -Be @('deadbe')
                $child.IsBlocked | Should -BeTrue
                $rollup.NextChild | Should -BeNullOrEmpty
            }
            finally {
                Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:ci-selects-next-child-plan reports the epic through Get-PlanState without hand-picking a child' {
            $tmp = & $newTempRoot
            try {
                & $newChildPlan -Root $tmp -PlanId '111aaa' -Slug 'core' -Done 2 | Out-Null
                & $newChildPlan -Root $tmp -PlanId '222bbb' -Slug 'api' -Done 0 | Out-Null
                & $newEpic -Title 'Rollup' -Slug 'rollup' -RepoRoot $tmp -EpicId 'ab12cd' -ChildPlan '111aaa' | Out-Null
                & $newEpic -Epic 'ab12cd' -RepoRoot $tmp -ChildPlan '222bbb' -DependsOn '111aaa' | Out-Null

                $state = & $planState 'ab12cd' -RepoRoot $tmp -Json | ConvertFrom-Json
                $state.Kind | Should -Be 'epic'
                $state.NextChild.Id | Should -Be '222bbb'
                $state.Rollup.ChildCount | Should -Be 2
                $state.Rollup.CompleteCount | Should -Be 1

                $text = & $planState 'ab12cd' -RepoRoot $tmp
                $text | Should -Match 'Next child:\s+222bbb'

                # A plan reference must keep returning plan state, and surface its epic membership.
                $childState = & $planState '222bbb' -RepoRoot $tmp -Json | ConvertFrom-Json
                $childState.Kind | Should -Be 'plan'
                $childState.Markers.EpicId | Should -Be 'ab12cd'
                $childState.NextStep.Id | Should -Be '1.1'

                # -Epic forces epic resolution, so a plan reference fails loud instead of silently
                # falling back to plan state.
                { & $planState '222bbb' -RepoRoot $tmp -Epic } | Should -Throw '*No epic matches*'
            }
            finally {
                Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:ci-selects-next-child-plan reports completion instead of inventing work' {
            $tmp = & $newTempRoot
            try {
                & $newChildPlan -Root $tmp -PlanId '111aaa' -Slug 'core' -Done 2 | Out-Null
                & $newEpic -Title 'Rollup' -Slug 'rollup' -RepoRoot $tmp -EpicId 'ab12cd' -ChildPlan '111aaa' | Out-Null

                $rollup = Get-EpicRollup -EpicId 'ab12cd' -RepoRoot $tmp
                $rollup.IsComplete | Should -BeTrue
                $rollup.NextChild | Should -BeNullOrEmpty
                (& $planState 'ab12cd' -RepoRoot $tmp) | Should -Match 'every child plan is complete'
            }
            finally {
                Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:ci-selects-next-child-plan documents epic resolution in the /ci skill' {
            $skill = Get-Content -LiteralPath (Join-Path $repoRoot 'plugins/continue-implementation/skills/ci/SKILL.md') -Raw
            $skill | Should -Match 'epic'
            $skill | Should -Match 'NextChild'
            # The orchestrator must defer selection to the script rather than choosing a child itself.
            $skill | Should -Match 'Do not pick a child yourself'
        }
    }
}
