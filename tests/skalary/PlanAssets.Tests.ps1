#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Plan assets layout' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $modulePath = Join-Path $repoRoot 'scripts/skalary/PlanState.psm1'
        Import-Module $modulePath -Force -DisableNameChecking

        $templatePath = Join-Path $repoRoot 'plugins/create-implementation-plan/skills/cip/assets/plan-template.md'
        $dogfoodTemplatePath = Join-Path $repoRoot '.github/skills/cip/assets/plan-template.md'
        $newPlanScript = Join-Path $repoRoot 'scripts/skalary/New-Plan.ps1'
        $testPlanScript = Join-Path $repoRoot 'scripts/skalary/Test-Plan.ps1'
        $workflowNoteScript = Join-Path $repoRoot 'scripts/skalary/Add-WorkflowNote.ps1'
        $receiptScript = Join-Path $repoRoot 'scripts/skalary/Build-EvidenceReceipt.ps1'
        $plansRoot = Join-Path $repoRoot 'docs/implementation-plans'

        $newTempDir = {
            $path = Join-Path ([System.IO.Path]::GetTempPath()) ('plan-assets-' + [System.Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $path -Force | Out-Null
            return $path
        }

        $requirementsTable = @(
            '| ID | Requirement | Acceptance Criteria | Phases/Steps |'
            '|----|-------------|---------------------|--------------|'
            '| REQ-1 | First requirement | `test:fixture-one` | 1.1 |'
            '| REQ-2 | Second requirement | `test:fixture-two` | 1.2 |'
        )
        $risksTable = @(
            '| ID | Risk | Likelihood | Impact | Mitigation | Steps |'
            '|----|------|------------|--------|------------|-------|'
            '| RISK-1 | Some risk | Low | Low | Mitigated by 1.1 | 1.1 |'
        )
        $decisionBullets = @(
            '- Resolve sections inside Get-PlanMetadata, not at the Test-Plan boundary.'
            '- Fail loud when an asset is present but empty.'
        )
        $phaseBlock = @(
            '## Phase 1: Fixture'
            '<!-- worktree: (recorded by /ci when worktree is created) -->'
            ''
            '- [ ] 1.1 First step (REQ-1, RISK-1) `S`'
            '- [ ] 1.2 Second step (REQ-2) [after: 1.1] `M`'
        )
        $headerBlock = {
            param([string]$PlanId)
            return @(
                "# ${PlanId}: Dual layout fixture"
                "<!-- plan-id: $PlanId -->"
                '<!-- evidence: required -->'
                '<!-- phase-budget-points: 6 -->'
                ''
            )
        }

        $newLegacyPlan = {
            param([string]$Dir, [string]$PlanId = 'abc123')
            New-Item -ItemType Directory -Path $Dir -Force | Out-Null
            $content = @()
            $content += (& $headerBlock $PlanId)
            $content += @('## Decisions', '')
            $content += $decisionBullets
            $content += @('', '## Requirements', '')
            $content += $requirementsTable
            $content += @('', '## Risks', '')
            $content += $risksTable
            $content += ''
            $content += $phaseBlock
            Set-Content -LiteralPath (Join-Path $Dir 'plan.md') -Value ($content -join "`n") -Encoding utf8NoBOM
            return (Join-Path $Dir 'plan.md')
        }.GetNewClosure()

        $newAssetsPlan = {
            param(
                [string]$Dir,
                [switch]$KeepLegacyTables,
                [string[]]$RequirementsOverride,
                [string]$PlanId = 'abc123'
            )
            New-Item -ItemType Directory -Path $Dir -Force | Out-Null
            $assetsDir = Join-Path $Dir 'assets'
            New-Item -ItemType Directory -Path $assetsDir -Force | Out-Null

            $reqLines = if ($RequirementsOverride) { $RequirementsOverride } else { @('# Requirements', '') + $requirementsTable }
            Set-Content -LiteralPath (Join-Path $assetsDir 'requirements.md') -Value ($reqLines -join "`n") -Encoding utf8NoBOM
            Set-Content -LiteralPath (Join-Path $assetsDir 'risks.md') -Value ((@('# Risks', '') + $risksTable) -join "`n") -Encoding utf8NoBOM
            Set-Content -LiteralPath (Join-Path $assetsDir 'decisions.md') -Value ((@('# Decisions', '') + $decisionBullets) -join "`n") -Encoding utf8NoBOM

            $content = @()
            $content += (& $headerBlock $PlanId)
            $content += @(
                '## Assets'
                ''
                '- Requirements — [assets/requirements.md](assets/requirements.md)'
                '- Risks — [assets/risks.md](assets/risks.md)'
                '- Decisions — [assets/decisions.md](assets/decisions.md)'
                ''
            )
            if ($KeepLegacyTables) {
                $content += @('## Decisions', '')
                $content += $decisionBullets
                $content += @('', '## Requirements', '')
                $content += $requirementsTable
                $content += @('', '## Risks', '')
                $content += $risksTable
                $content += ''
            }
            $content += $phaseBlock
            Set-Content -LiteralPath (Join-Path $Dir 'plan.md') -Value ($content -join "`n") -Encoding utf8NoBOM
            return (Join-Path $Dir 'plan.md')
        }.GetNewClosure()

        $compareMetadata = {
            param($Metadata)
            $reqs = @($Metadata.Requirements.Values | Sort-Object Number | ForEach-Object { "$($_.Id)|$($_.Number)|$($_.AcceptanceCriteria)" })
            $risks = @($Metadata.Risks.Keys | Sort-Object | ForEach-Object { "$_|$($Metadata.Risks[$_])" })
            $steps = @($Metadata.Steps | ForEach-Object {
                    "$($_.Id)|$($_.Status)|$($_.Role)|$($_.Size)|$($_.After -join ',')|$($_.Refs -join ',')|$($_.Phase)"
                })
            return [pscustomobject]@{
                Requirements = $reqs
                Risks        = $risks
                Steps        = $steps
                Decisions    = @($Metadata.Decisions)
            }
        }
    }

    AfterAll {
        Remove-Module PlanState -Force -ErrorAction SilentlyContinue
    }

    Context 'template and scaffolding' {
        It 'test:plan-assets-template-shape keeps plan.md to markers, an asset index, and steps' {
            $template = Get-Content -LiteralPath $templatePath -Raw

            foreach ($asset in @('assets/intent.md', 'assets/domain.md', 'assets/design.md', 'assets/requirements.md', 'assets/risks.md', 'assets/decisions.md', 'assets/references.md')) {
                $template | Should -Match ([regex]::Escape($asset))
            }
            $template | Should -Match ([regex]::Escape('assets/reviews/<uuid>.review.md'))
            $template | Should -Match ([regex]::Escape('<uuid>.receipt.json'))

            $template | Should -Match '<!-- plan-id:'
            $template | Should -Match '(?m)^## Phase 1:'
            $template | Should -Match '(?m)^- \[ \] 1\.1 '

            # The tables moved out of plan.md entirely — no section headings and no rows left behind.
            $template | Should -Not -Match '(?m)^## Requirements\s*$'
            $template | Should -Not -Match '(?m)^## Risks\s*$'
            $template | Should -Not -Match '(?m)^\|\s*REQ-\d+\s*\|'
            $template | Should -Not -Match '(?m)^\|\s*RISK-\d+\s*\|'
        }

        It 'test:plan-assets-template-shape ships the same template to the dogfood install' {
            (Get-Content -LiteralPath $dogfoodTemplatePath -Raw) | Should -Be (Get-Content -LiteralPath $templatePath -Raw)
        }

        It 'test:new-plan-scaffolds-assets writes assets/ with non-empty placeholders alongside plan.md' {
            $tempRoot = & $newTempDir
            try {
                $result = & pwsh -NoProfile -File $newPlanScript -Title 'Scaffold fixture' -Slug 'scaffold-fixture' -RepoRoot $tempRoot -PlanId 'abcdef' -Date '2026-01-02' -TemplatePath $templatePath
                $LASTEXITCODE | Should -Be 0

                $planDir = Join-Path $tempRoot 'docs/implementation-plans/standalone-2026-01-02-abcdef-scaffold-fixture'
                Test-Path -LiteralPath (Join-Path $planDir 'plan.md') | Should -BeTrue

                $assetsDir = Join-Path $planDir 'assets'
                Test-Path -LiteralPath $assetsDir -PathType Container | Should -BeTrue
                foreach ($name in @('intent.md', 'domain.md', 'design.md', 'requirements.md', 'risks.md', 'decisions.md', 'references.md')) {
                    $assetPath = Join-Path $assetsDir $name
                    Test-Path -LiteralPath $assetPath -PathType Leaf | Should -BeTrue
                    # Placeholder, never zero content — "present-but-empty" must stay distinguishable from "authored".
                    (Get-Content -LiteralPath $assetPath -Raw).Trim() | Should -Not -BeNullOrEmpty
                }
                Test-Path -LiteralPath (Join-Path $assetsDir 'reviews') |
                    Should -BeFalse -Because 'ReviewRuns is conditional output, not an empty scaffold'

                $metadata = Get-PlanMetadata -Path (Join-Path $planDir 'plan.md') -RepoRoot $tempRoot
                $metadata.Layout | Should -Be 'assets'
                $metadata.SectionSources['Requirements'] | Should -Be 'asset'
                $metadata.SectionSources['Risks'] | Should -Be 'asset'
                $metadata.Requirements.ContainsKey('REQ-1') | Should -BeTrue
                $metadata.Risks.ContainsKey('RISK-1') | Should -BeTrue
                $null = $result
            }
            finally {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:new-plan-scaffolds-assets never overwrites authored assets, even under -Force' {
            $tempRoot = & $newTempDir
            try {
                & pwsh -NoProfile -File $newPlanScript -Title 'Force fixture' -Slug 'force-fixture' -RepoRoot $tempRoot -PlanId 'abcdef' -Date '2026-01-02' -TemplatePath $templatePath | Out-Null
                $LASTEXITCODE | Should -Be 0

                $planDir = Join-Path $tempRoot 'docs/implementation-plans/standalone-2026-01-02-abcdef-force-fixture'
                $authored = Join-Path $planDir 'assets/requirements.md'
                $authoredText = "# Requirements`n`n| ID | Requirement | Acceptance Criteria | Phases/Steps |`n|----|----|----|----|`n| REQ-1 | Authored by the operator | ``test:authored`` | 1.1 |`n"
                Set-Content -LiteralPath $authored -Value $authoredText -Encoding utf8NoBOM

                & pwsh -NoProfile -File $newPlanScript -Title 'Force fixture' -Slug 'force-fixture' -RepoRoot $tempRoot -PlanId 'abcdef' -Date '2026-01-02' -TemplatePath $templatePath -Force | Out-Null
                $LASTEXITCODE | Should -Be 0

                # -Force means "overwrite plan.md"; re-scaffolding over authored content would destroy the plan.
                (Get-Content -LiteralPath $authored -Raw) | Should -Match 'Authored by the operator'
            }
            finally {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'layout detection' {
        It 'test:planstate-legacy-layout-unchanged keeps a legacy plan legacy when assets/ holds no section file' {
            $tempRoot = & $newTempDir
            try {
                $dir = Join-Path $tempRoot 'docs/implementation-plans/001-legacy'
                $null = & $newLegacyPlan $dir '001'
                & pwsh -NoProfile -File $workflowNoteScript -Kind Capture -PlanDir $dir -RepoRoot $tempRoot -Phase 1 | Out-Null
                Test-Path -LiteralPath (Join-Path $dir 'capture.md') | Should -BeTrue

                # A bare assets/ subfolder must not flip the layout and orphan the logs already at the root.
                New-Item -ItemType Directory -Path (Join-Path $dir 'assets/decisions') -Force | Out-Null
                Get-PlanLayout -PlanDir $dir | Should -Be 'legacy'
                Resolve-PlanAssetPath -PlanDir $dir -Kind Capture | Should -Be ([System.IO.Path]::GetFullPath((Join-Path $dir 'capture.md')))

                & pwsh -NoProfile -File $workflowNoteScript -Kind Capture -PlanDir $dir -RepoRoot $tempRoot -Phase 2 | Out-Null
                Test-Path -LiteralPath (Join-Path $dir 'assets/logs/capture.md') | Should -BeFalse
            }
            finally {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:no-split-brain-after-migration fails loud when one log exists at both locations' {
            $tempRoot = & $newTempDir
            try {
                $dir = Join-Path $tempRoot 'both-locations'
                $null = & $newAssetsPlan $dir
                New-Item -ItemType Directory -Path (Join-Path $dir 'assets/logs') -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $dir 'assets/logs/capture.md') -Value '## Capture' -Encoding utf8NoBOM
                Set-Content -LiteralPath (Join-Path $dir 'capture.md') -Value '## Capture' -Encoding utf8NoBOM

                { Resolve-PlanAssetPath -PlanDir $dir -Kind Capture } | Should -Throw -ExpectedMessage '*both*'
            }
            finally {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Resolve-PlanSection' {
        It 'test:planstate-dual-layout-parity yields identical metadata for a legacy plan and its assets twin' {
            $tempRoot = & $newTempDir
            try {
                $legacyPlan = & $newLegacyPlan (Join-Path $tempRoot 'legacy')
                $assetsPlan = & $newAssetsPlan (Join-Path $tempRoot 'assets-twin')

                $legacyMeta = Get-PlanMetadata -Path $legacyPlan -RepoRoot $tempRoot
                $assetsMeta = Get-PlanMetadata -Path $assetsPlan -RepoRoot $tempRoot

                $legacyMeta.SectionSources['Requirements'] | Should -Be 'legacy'
                $assetsMeta.SectionSources['Requirements'] | Should -Be 'asset'

                $legacyView = & $compareMetadata $legacyMeta
                $assetsView = & $compareMetadata $assetsMeta

                $assetsView.Requirements | Should -Be $legacyView.Requirements
                $assetsView.Risks | Should -Be $legacyView.Risks
                $assetsView.Steps | Should -Be $legacyView.Steps
                $assetsView.Decisions | Should -Be $legacyView.Decisions
            }
            finally {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:planstate-resolver-both-present lets the asset win and errors on divergence' {
            $tempRoot = & $newTempDir
            try {
                $bothPlan = & $newAssetsPlan (Join-Path $tempRoot 'both') -KeepLegacyTables
                $metadata = Get-PlanMetadata -Path $bothPlan -RepoRoot $tempRoot
                $metadata.SectionSources['Requirements'] | Should -Be 'asset'
                $metadata.Requirements.Count | Should -Be 2

                $divergentDir = Join-Path $tempRoot 'divergent'
                $divergentPlan = & $newAssetsPlan $divergentDir -KeepLegacyTables
                $assetFile = Join-Path $divergentDir 'assets/requirements.md'
                $divergent = @(
                    '# Requirements'
                    ''
                    '| ID | Requirement | Acceptance Criteria | Phases/Steps |'
                    '|----|-------------|---------------------|--------------|'
                    '| REQ-1 | First requirement | `test:fixture-one` | 1.1 |'
                    '| REQ-2 | Second requirement CHANGED | `test:fixture-two` | 1.2 |'
                )
                Set-Content -LiteralPath $assetFile -Value ($divergent -join "`n") -Encoding utf8NoBOM

                { Get-PlanMetadata -Path $divergentPlan -RepoRoot $tempRoot } | Should -Throw -ExpectedMessage '*diverges*'
            }
            finally {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:planstate-divergence-ignores-cosmetic-drift compares records, not raw text' {
            $tempRoot = & $newTempDir
            try {
                $dir = Join-Path $tempRoot 'cosmetic'
                $planPath = & $newAssetsPlan $dir -KeepLegacyTables
                # Same records: reordered rows, different column padding, extra prose and blank lines.
                $cosmetic = @(
                    '# Requirements'
                    ''
                    'Extra prose that exists only in the asset file.'
                    ''
                    '| ID | Requirement | Acceptance Criteria | Phases/Steps |'
                    '| --- | --- | --- | --- |'
                    '|REQ-2|   Second    requirement   |`test:fixture-two`|1.2|'
                    '|    REQ-1 | First requirement | `test:fixture-one` |   1.1   |'
                    ''
                )
                Set-Content -LiteralPath (Join-Path $dir 'assets/requirements.md') -Value ($cosmetic -join "`n") -Encoding utf8NoBOM

                $metadata = Get-PlanMetadata -Path $planPath -RepoRoot $tempRoot
                $metadata.SectionSources['Requirements'] | Should -Be 'asset'
                @($metadata.Requirements.Keys | Sort-Object) | Should -Be @('REQ-1', 'REQ-2')
            }
            finally {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:planstate-asset-fences-stripped ignores rows inside fenced code blocks' {
            $tempRoot = & $newTempDir
            try {
                $dir = Join-Path $tempRoot 'fenced'
                $fenced = @(
                    '# Requirements'
                    ''
                    '```markdown'
                    '| REQ-9 | Example row that is documentation, not a requirement | `test:nope` | 9.9 |'
                    '```'
                    ''
                    '| ID | Requirement | Acceptance Criteria | Phases/Steps |'
                    '|----|-------------|---------------------|--------------|'
                    '| REQ-1 | First requirement | `test:fixture-one` | 1.1 |'
                    '| REQ-2 | Second requirement | `test:fixture-two` | 1.2 |'
                )
                $planPath = & $newAssetsPlan $dir -RequirementsOverride $fenced

                $metadata = Get-PlanMetadata -Path $planPath -RepoRoot $tempRoot
                $metadata.Requirements.ContainsKey('REQ-9') | Should -BeFalse
                @($metadata.Requirements.Keys | Sort-Object) | Should -Be @('REQ-1', 'REQ-2')
            }
            finally {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:planstate-resolver-empty-fails-loud refuses a present-but-empty asset' {
            $tempRoot = & $newTempDir
            try {
                $dir = Join-Path $tempRoot 'empty'
                $planPath = & $newAssetsPlan $dir
                Set-Content -LiteralPath (Join-Path $dir 'assets/requirements.md') -Value "   `n`n" -Encoding utf8NoBOM

                { Get-PlanMetadata -Path $planPath -RepoRoot $tempRoot } | Should -Throw -ExpectedMessage '*present but empty*'
            }
            finally {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:planstate-resolver-malformed-fails-loud refuses an asset with no records' {
            $tempRoot = & $newTempDir
            try {
                $dir = Join-Path $tempRoot 'malformed'
                $planPath = & $newAssetsPlan $dir -RequirementsOverride @('# Requirements', '', 'Prose only. The table never got written.')

                { Get-PlanMetadata -Path $planPath -RepoRoot $tempRoot } | Should -Throw -ExpectedMessage '*malformed*'
            }
            finally {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:planstate-resolver-malformed-fails-loud refuses rows the requirement parser would discard' {
            $tempRoot = & $newTempDir
            try {
                $dir = Join-Path $tempRoot 'short-columns'
                # Three columns: Get-PlanMetadata's requirement parser discards these rows, so treating them
                # as well-formed here would resolve the section to zero requirements without failing.
                $shortTable = @(
                    '# Requirements'
                    ''
                    '| ID | Requirement | Acceptance Criteria |'
                    '|----|-------------|---------------------|'
                    '| REQ-1 | First requirement | `test:fixture-one` |'
                )
                $planPath = & $newAssetsPlan $dir -RequirementsOverride $shortTable

                { Get-PlanMetadata -Path $planPath -RepoRoot $tempRoot } | Should -Throw -ExpectedMessage '*malformed*'
            }
            finally {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:planstate-legacy-layout-unchanged keeps every legacy plan resolving from plan.md' {
            $planFiles = @(Get-ChildItem -LiteralPath $plansRoot -Recurse -File -Filter 'plan.md')
            $asserted = 0

            foreach ($planFile in $planFiles) {
                $planDir = Split-Path -Parent $planFile.FullName
                if ((Get-PlanLayout -PlanDir $planDir) -eq 'assets') { continue }

                $metadata = Get-PlanMetadata -Path $planFile.FullName -RepoRoot $repoRoot
                $metadata.Layout | Should -Be 'legacy' -Because $planFile.FullName
                $metadata.SectionSources['Requirements'] | Should -Be 'legacy' -Because $planFile.FullName
                $metadata.Requirements.Count | Should -BeGreaterThan 0 -Because $planFile.FullName
                $asserted++
            }

            # Never pass vacuously: the legacy path is permanent, so at least one plan must exercise it.
            $asserted | Should -BeGreaterThan 0
        }
    }

    Context 'consumer parity' {
        It 'test:getplanstate-dual-layout-parity reports the same state for both layouts' {
            $tempRoot = & $newTempDir
            try {
                $plansDir = Join-Path $tempRoot 'docs/implementation-plans'
                New-Item -ItemType Directory -Path $plansDir -Force | Out-Null
                $legacyDir = Join-Path $plansDir '2026-01-02-aaa111-legacy-twin'
                $assetsDir = Join-Path $plansDir '2026-01-02-bbb222-assets-twin'
                $null = & $newLegacyPlan $legacyDir 'aaa111'
                $null = & $newAssetsPlan $assetsDir -PlanId 'bbb222'

                $getPlanState = Join-Path $repoRoot 'scripts/skalary/Get-PlanState.ps1'
                $legacyJson = (& pwsh -NoProfile -File $getPlanState -Reference 'aaa111' -RepoRoot $tempRoot -HasUncommittedChanges:$false -Json) -join "`n"
                $assetsJson = (& pwsh -NoProfile -File $getPlanState -Reference 'bbb222' -RepoRoot $tempRoot -HasUncommittedChanges:$false -Json) -join "`n"

                $legacyJson | Should -Not -BeNullOrEmpty
                $assetsJson | Should -Not -BeNullOrEmpty
                $legacyState = $legacyJson | ConvertFrom-Json
                $assetsState = $assetsJson | ConvertFrom-Json
                $legacyState.Progress.Total | Should -Be 2
                $assetsState.NextStep.Id | Should -Be '1.1'

                ($assetsState.Progress | ConvertTo-Json -Depth 5) | Should -Be ($legacyState.Progress | ConvertTo-Json -Depth 5)
                ($assetsState.NextStep | ConvertTo-Json -Depth 5) | Should -Be ($legacyState.NextStep | ConvertTo-Json -Depth 5)
                ($assetsState.Markers | ConvertTo-Json -Depth 5) | Should -Be ($legacyState.Markers | ConvertTo-Json -Depth 5)
            }
            finally {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:ci-loads-assets-on-demand documents on-demand asset loading in the ci skill' {
            $skill = Get-Content -LiteralPath (Join-Path $repoRoot 'plugins/continue-implementation/skills/ci/SKILL.md') -Raw
            $skill | Should -Match 'on demand'
            $skill | Should -Match 'never wholesale'
            $skill | Should -Match 'assets/intent\.md'
            $skill | Should -Match 'assets/requirements\.md'
            $skill | Should -Match 'assets/logs/'
            $skill | Should -Match 'Resolve-PlanAssetPath'

            $dogfood = Get-Content -LiteralPath (Join-Path $repoRoot '.github/skills/ci/SKILL.md') -Raw
            $dogfood | Should -Be $skill
        }
    }

    Context 'layout-aware writers' {
        It 'test:planstate-capture-roots confines overflow and receipt roots to an inventoried plan' {
            $tempRoot = & $newTempDir
            try {
                $assetsPlanDir = Join-Path $tempRoot 'docs/implementation-plans/2026-01-01-abc123-assets-plan'
                $null = & $newAssetsPlan $assetsPlanDir
                $legacyPlanDir = Join-Path $tempRoot 'docs/implementation-plans/001-legacy-plan'
                $null = & $newLegacyPlan $legacyPlanDir '001'
                $inventory = @(Get-PlanInventory -RepoRoot $tempRoot)

                Resolve-PlanAssetPath -PlanDir $assetsPlanDir -Kind LearningOverflowRoot `
                    -RepoRoot $tempRoot -Inventory $inventory |
                    Should -Be ([System.IO.Path]::GetFullPath((Join-Path $assetsPlanDir 'assets/logs/learning-overflow')))
                Resolve-PlanAssetPath -PlanDir $assetsPlanDir -Kind HarvestReceiptRoot `
                    -RepoRoot $tempRoot -Inventory $inventory |
                    Should -Be ([System.IO.Path]::GetFullPath((Join-Path $assetsPlanDir 'assets/harvest-receipts')))
                Resolve-PlanAssetPath -PlanDir $legacyPlanDir -Kind LearningOverflowRoot `
                    -RepoRoot $tempRoot -Inventory $inventory |
                    Should -Be ([System.IO.Path]::GetFullPath((Join-Path $legacyPlanDir 'learning-overflow')))
                Resolve-PlanAssetPath -PlanDir $legacyPlanDir -Kind HarvestReceiptRoot `
                    -RepoRoot $tempRoot -Inventory $inventory |
                    Should -Be ([System.IO.Path]::GetFullPath((Join-Path $legacyPlanDir 'harvest-receipts')))

                $outside = Join-Path $tempRoot 'outside'
                [void](New-Item -ItemType Directory -Path $outside -Force)
                {
                    Resolve-PlanAssetPath -PlanDir $outside -Kind LearningOverflowRoot `
                        -RepoRoot $tempRoot -Inventory $inventory
                } | Should -Throw '*escapes repository plan root*'

                $untracked = Join-Path $tempRoot 'docs/implementation-plans/untracked'
                [void](New-Item -ItemType Directory -Path $untracked -Force)
                {
                    Resolve-PlanAssetPath -PlanDir $untracked -Kind HarvestReceiptRoot `
                        -RepoRoot $tempRoot -Inventory $inventory
                } | Should -Throw '*not a unique member*'
            }
            finally {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:planstate-capture-roots refuses a case-distinct non-inventory plan directory' {
            $tempRoot = & $newTempDir
            try {
                $inventoriedPlanDir = Join-Path $tempRoot 'docs/implementation-plans/2026-01-01-abc123-CasePlan'
                $null = & $newAssetsPlan $inventoriedPlanDir
                $inventory = @(Get-PlanInventory -RepoRoot $tempRoot)
                $caseDistinctDir = Join-Path $tempRoot 'docs/implementation-plans/2026-01-01-abc123-caseplan'
                if (Test-Path -LiteralPath $caseDistinctDir) {
                    Set-ItResult -Skipped -Because 'the test filesystem is case-insensitive'
                    return
                }
                [void](New-Item -ItemType Directory -Path $caseDistinctDir -Force)

                {
                    Resolve-PlanAssetPath -PlanDir $caseDistinctDir -Kind LearningOverflowRoot `
                        -RepoRoot $tempRoot -Inventory $inventory
                } | Should -Throw '*not a unique member*'
            }
            finally {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:planstate-capture-roots refuses a logical alias to an inventoried plan' {
            $tempRoot = & $newTempDir
            try {
                $actualPlanDir = Join-Path $tempRoot 'docs/implementation-plans/2026-01-01-abc123-actual-plan'
                $null = & $newAssetsPlan $actualPlanDir
                $inventory = @(Get-PlanInventory -RepoRoot $tempRoot)
                $aliasPlanDir = Join-Path $tempRoot 'docs/implementation-plans/2026-01-01-def456-plan-alias'
                try {
                    [void](New-Item -ItemType SymbolicLink -Path $aliasPlanDir -Target $actualPlanDir -ErrorAction Stop)
                }
                catch [System.Exception] {
                    Set-ItResult -Skipped -Because "this host cannot create a symbolic link unprivileged: $($_.Exception.Message)"
                    return
                }

                {
                    Resolve-PlanAssetPath -PlanDir $aliasPlanDir -Kind LearningOverflowRoot `
                        -RepoRoot $tempRoot -Inventory $inventory
                } | Should -Throw '*not a unique member*'
            }
            finally {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:planstate-capture-roots preserves a symlink-mounted repository path' {
            $tempParent = & $newTempDir
            try {
                $actualRoot = Join-Path $tempParent 'actual-repo'
                $actualPlanDir = Join-Path $actualRoot 'docs/implementation-plans/2026-01-01-abc123-mounted-plan'
                $null = & $newAssetsPlan $actualPlanDir
                $mountedRoot = Join-Path $tempParent 'mounted-repo'
                try {
                    [void](New-Item -ItemType SymbolicLink -Path $mountedRoot -Target $actualRoot -ErrorAction Stop)
                }
                catch [System.Exception] {
                    Set-ItResult -Skipped -Because "this host cannot create a symbolic link unprivileged: $($_.Exception.Message)"
                    return
                }

                $mountedPlanDir = Join-Path $mountedRoot 'docs/implementation-plans/2026-01-01-abc123-mounted-plan'
                $inventory = @(Get-PlanInventory -RepoRoot $mountedRoot)
                $resolved = Resolve-PlanAssetPath -PlanDir $mountedPlanDir -Kind LearningOverflowRoot `
                    -RepoRoot $mountedRoot -Inventory $inventory
                $expected = [System.IO.Path]::GetFullPath(
                    (Join-Path $mountedPlanDir 'assets/logs/learning-overflow')
                )

                $resolved | Should -Be $expected
                [System.IO.Path]::GetRelativePath($mountedRoot, $resolved) |
                    Should -Not -Match '^\.\.(?:[\\/]|$)'
            }
            finally {
                Remove-Item -LiteralPath $tempParent -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:planstate-capture-roots refuses a symlinked overflow escape' {
            $tempRoot = & $newTempDir
            try {
                $assetsPlanDir = Join-Path $tempRoot 'docs/implementation-plans/2026-01-01-abc123-assets-plan'
                $null = & $newAssetsPlan $assetsPlanDir
                $outside = Join-Path $tempRoot 'outside-overflow'
                [void](New-Item -ItemType Directory -Path $outside -Force)
                try {
                    [void](New-Item -ItemType SymbolicLink `
                            -Path (Join-Path $assetsPlanDir 'assets/logs') -Target $outside -ErrorAction Stop)
                }
                catch [System.Exception] {
                    Set-ItResult -Skipped -Because "this host cannot create a symbolic link unprivileged: $($_.Exception.Message)"
                    return
                }

                $inventory = @(Get-PlanInventory -RepoRoot $tempRoot)
                {
                    Resolve-PlanAssetPath -PlanDir $assetsPlanDir -Kind LearningOverflowRoot `
                        -RepoRoot $tempRoot -Inventory $inventory
                } | Should -Throw '*escapes inventoried plan folder*'
            }
            finally {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:workflownote-dual-layout writes logs under assets/logs when the layout is in use' {
            $tempRoot = & $newTempDir
            try {
                $assetsPlanDir = Join-Path $tempRoot 'docs/implementation-plans/2026-01-01-abc123-assets-plan'
                $null = & $newAssetsPlan $assetsPlanDir
                $legacyPlanDir = Join-Path $tempRoot 'docs/implementation-plans/001-legacy-plan'
                $null = & $newLegacyPlan $legacyPlanDir '001'

                foreach ($kind in @('CrLog', 'Learnings', 'Capture')) {
                    & pwsh -NoProfile -File $workflowNoteScript -Kind $kind -PlanDir $assetsPlanDir -RepoRoot $tempRoot -Phase 1 | Out-Null
                    $LASTEXITCODE | Should -Be 0
                    & pwsh -NoProfile -File $workflowNoteScript -Kind $kind -PlanDir $legacyPlanDir -RepoRoot $tempRoot -Phase 1 | Out-Null
                    $LASTEXITCODE | Should -Be 0
                }

                foreach ($name in @('cr-log.md', 'learnings.md', 'capture.md')) {
                    Test-Path -LiteralPath (Join-Path $assetsPlanDir "assets/logs/$name") -PathType Leaf | Should -BeTrue
                    Test-Path -LiteralPath (Join-Path $assetsPlanDir $name) | Should -BeFalse
                    Test-Path -LiteralPath (Join-Path $legacyPlanDir $name) -PathType Leaf | Should -BeTrue
                    Test-Path -LiteralPath (Join-Path $legacyPlanDir "assets/logs/$name") | Should -BeFalse
                }

                # Appending resolves to the same file the initializer created — no split-brain.
                & pwsh -NoProfile -File $workflowNoteScript -Kind Capture -PlanDir $assetsPlanDir -RepoRoot $tempRoot `
                    -Phase 1 -Step '1.1' -Concern architecture-patterns -Requirement REQ-1 `
                    -ReviewType none -Message 'layout resolved' | Out-Null
                (Get-Content -LiteralPath (Join-Path $assetsPlanDir 'assets/logs/capture.md') -Raw) | Should -Match 'layout resolved'
            }
            finally {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:evidence-receipt-dual-layout resolves the receipt path for both layouts' {
            $tempRoot = & $newTempDir
            try {
                $assetsPlanDir = Join-Path $tempRoot 'assets-plan'
                $null = & $newAssetsPlan $assetsPlanDir
                $legacyPlanDir = Join-Path $tempRoot 'legacy-plan'
                $null = & $newLegacyPlan $legacyPlanDir

                $results = @([pscustomobject]@{ Req = 'REQ-1'; Marker = 'test:fixture-one'; Success = $true })

                $assetsReceipt = & $receiptScript -Result $results -Commit 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' -Phase 1 -PlanDir $assetsPlanDir
                $legacyReceipt = & $receiptScript -Result $results -Commit 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' -Phase 1 -PlanDir $legacyPlanDir

                $assetsReceipt.ReceiptPath | Should -Be ([System.IO.Path]::GetFullPath((Join-Path $assetsPlanDir 'assets/evidence.md')))
                $legacyReceipt.ReceiptPath | Should -Be ([System.IO.Path]::GetFullPath((Join-Path $legacyPlanDir 'evidence.md')))

                # The formatter stays pure: it resolves the path but never writes it.
                Test-Path -LiteralPath $assetsReceipt.ReceiptPath | Should -BeFalse
                $assetsReceipt.Text | Should -Be $legacyReceipt.Text
                Get-Command Get-PlanLayout -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
                Get-Command Resolve-PlanAssetPath -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
            }
            finally {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'migration invariants' {
        It 'test:migration-is-atomic leaves no plan half-migrated' {
            $asserted = 0
            foreach ($planFile in @(Get-ChildItem -LiteralPath $plansRoot -Recurse -File -Filter 'plan.md')) {
                $asserted++
                $planDir = Split-Path -Parent $planFile.FullName
                $planText = (Get-Content -LiteralPath $planFile.FullName -Raw) -replace "`r`n", "`n"

                foreach ($section in @('Requirements', 'Risks')) {
                    $assetPath = Resolve-PlanAssetPath -PlanDir $planDir -Kind $section
                    $prefix = if ($section -eq 'Requirements') { 'REQ' } else { 'RISK' }
                    $hasLegacyRows = $planText -match "(?m)^\s*\|\s*$prefix-\d+\s*\|"
                    $hasAsset = Test-Path -LiteralPath $assetPath -PathType Leaf

                    # A window where the table is gone but the asset is not yet written would be mis-parsed
                    # by the very next Get-PlanMetadata call, so it must never be committed.
                    ($hasLegacyRows -or $hasAsset) | Should -BeTrue -Because "$($planFile.FullName) has neither a legacy $section table nor $assetPath"
                }
            }

            $asserted | Should -BeGreaterThan 0
        }

        It 'test:migrated-plan-validates keeps assets-layout plans passing the Draft validator' {
            $asserted = 0
            foreach ($planFile in @(Get-ChildItem -LiteralPath $plansRoot -Recurse -File -Filter 'plan.md')) {
                $planDir = Split-Path -Parent $planFile.FullName
                if ((Get-PlanLayout -PlanDir $planDir) -ne 'assets') { continue }

                $output = @(& pwsh -NoProfile -File $testPlanScript -PlanPath $planFile.FullName -RepoRoot $repoRoot -Stage Draft 2>&1)
                $LASTEXITCODE | Should -Be 0 -Because (($output | ForEach-Object { "$_" }) -join "`n")
                $asserted++
            }

            $asserted | Should -BeGreaterThan 0
        }

        It 'test:no-split-brain-after-migration keeps logs and receipts out of the plan root once migrated' {
            $asserted = 0
            foreach ($planFile in @(Get-ChildItem -LiteralPath $plansRoot -Recurse -File -Filter 'plan.md')) {
                $planDir = Split-Path -Parent $planFile.FullName
                if ((Get-PlanLayout -PlanDir $planDir) -ne 'assets') { continue }
                $asserted++

                foreach ($kind in @('Evidence', 'EvolutionLog', 'DecisionRecords', 'CrLog', 'Learnings', 'Capture', 'LearningOverflowRoot', 'HarvestReceiptRoot', 'Intent', 'References')) {
                    $resolved = Resolve-PlanAssetPath -PlanDir $planDir -Kind $kind
                    $resolved | Should -Match ([regex]::Escape([System.IO.Path]::Combine('assets', ''))) -Because "$kind must resolve under assets/ for $planDir"
                }

                foreach ($stray in @('evidence.md', 'cr-log.md', 'learnings.md', 'capture.md', 'learning-overflow', 'harvest-receipts', 'evolution-log.md', 'intent.md', 'references.md', 'requirements.md', 'risks.md', 'decisions.md', 'decisions')) {
                    Test-Path -LiteralPath (Join-Path $planDir $stray) | Should -BeFalse -Because "$stray must not linger at the root of migrated plan $planDir"
                }
            }

            $asserted | Should -BeGreaterThan 0
        }
    }
}
