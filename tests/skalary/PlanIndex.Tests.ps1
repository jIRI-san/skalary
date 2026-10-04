#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Get-PlanIndex' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $indexScript = Join-Path $repoRoot 'scripts/skalary/Get-PlanIndex.ps1'

        $newTempRoot = {
            $path = Join-Path ([System.IO.Path]::GetTempPath()) ('plan-index-' + [System.Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path (Join-Path $path 'docs/implementation-plans/archived') -Force | Out-Null
            return $path
        }

        # A legacy plan keeps requirements/risks/decisions inside plan.md; the assets plan moves them into
        # assets/. Both shapes have to reach the index, so the fixtures deliberately differ in layout.
        $newLegacyPlan = {
            param([string]$Dir, [string]$PlanId, [string]$Title, [string]$Marker)
            New-Item -ItemType Directory -Path $Dir -Force | Out-Null
            $content = @(
                "# ${PlanId}: $Title"
                "<!-- plan-id: $PlanId -->"
                ''
                '## Decisions'
                ''
                "- Legacy decision about $Marker."
                ''
                '## Requirements'
                ''
                '| ID | Requirement | Acceptance Criteria | Phases/Steps |'
                '|----|-------------|---------------------|--------------|'
                "| REQ-1 | Legacy requirement about $Marker | ``test:$Marker-one`` | 1.1 |"
                "| REQ-2 | Second legacy requirement | ``test:$Marker-two`` | 1.2 |"
                ''
                '## Risks'
                ''
                '| ID | Risk | Likelihood | Impact | Mitigation | Steps |'
                '|----|------|------------|--------|------------|-------|'
                "| RISK-1 | Legacy risk about $Marker | Low | High | Mitigated by 1.1 | 1.1 |"
                ''
                '## Phase 1: Fixture'
                ''
                '- [ ] 1.1 First step (REQ-1, RISK-1) `S`'
                '- [ ] 1.2 Second step (REQ-2) `S`'
            )
            Set-Content -LiteralPath (Join-Path $Dir 'plan.md') -Value ($content -join "`n") -Encoding utf8NoBOM
        }

        $newAssetsPlan = {
            param([string]$Dir, [string]$PlanId, [string]$Title, [string]$Marker)
            $assetsDir = Join-Path $Dir 'assets'
            New-Item -ItemType Directory -Path $assetsDir -Force | Out-Null

            Set-Content -LiteralPath (Join-Path $assetsDir 'requirements.md') -Encoding utf8NoBOM -Value (@(
                '# Requirements'
                ''
                '| ID | Requirement | Acceptance Criteria | Phases/Steps |'
                '|----|-------------|---------------------|--------------|'
                "| REQ-1 | Asset requirement about $Marker | ``test:$Marker-one`` | 1.1 |"
            ) -join "`n")
            Set-Content -LiteralPath (Join-Path $assetsDir 'risks.md') -Encoding utf8NoBOM -Value (@(
                '# Risks'
                ''
                '| ID | Risk | Likelihood | Impact | Mitigation | Steps |'
                '|----|------|------------|--------|------------|-------|'
                "| RISK-1 | Asset risk about $Marker | Low | High | Mitigated by 1.1 | 1.1 |"
            ) -join "`n")
            Set-Content -LiteralPath (Join-Path $assetsDir 'decisions.md') -Encoding utf8NoBOM -Value (@(
                '# Decisions'
                ''
                "- Asset decision about $Marker."
            ) -join "`n")

            Set-Content -LiteralPath (Join-Path $Dir 'plan.md') -Encoding utf8NoBOM -Value (@(
                "# ${PlanId}: $Title"
                "<!-- plan-id: $PlanId -->"
                ''
                '## Assets'
                ''
                '- Requirements — [assets/requirements.md](assets/requirements.md)'
                ''
                '## Phase 1: Fixture'
                ''
                '- [ ] 1.1 First step (REQ-1, RISK-1) `S`'
            ) -join "`n")
        }

        # Active plan uses the assets layout, archived plan uses the legacy layout, so a single index run
        # has to cross both the active/archived and the assets/legacy boundary at once.
        $newCorpus = {
            $root = & $newTempRoot
            $plansRoot = Join-Path $root 'docs/implementation-plans'
            & $newAssetsPlan (Join-Path $plansRoot '2026-07-31-ff00aa-active-fixture') 'ff00aa' 'Active fixture plan' 'alpha'
            & $newLegacyPlan (Join-Path $plansRoot 'archived/003-archived-fixture') '003' 'Archived fixture plan' 'bravo'
            return $root
        }.GetNewClosure()
    }

    Context 'corpus coverage' {
        It 'test:planindex-covers-archived indexes archived and active plans across both layouts' {
            $root = & $newCorpus
            try {
                $index = & $indexScript -RepoRoot $root -Format Json | ConvertFrom-Json

                @($index.plans | ForEach-Object { $_.id }) | Should -Contain '003'
                @($index.plans | ForEach-Object { $_.id }) | Should -Contain 'ff00aa'

                $archived = $index.plans | Where-Object { $_.id -eq '003' }
                $archived.isArchived | Should -BeTrue
                $archived.layout | Should -Be 'legacy'
                @($archived.requirements | ForEach-Object { $_.id }) | Should -Be @('REQ-1', 'REQ-2')
                $archived.requirements[0].text | Should -Be 'Legacy requirement about bravo'
                @($archived.risks | ForEach-Object { $_.text }) | Should -Be @('Legacy risk about bravo')
                @($archived.decisions) | Should -Be @('Legacy decision about bravo.')

                $active = $index.plans | Where-Object { $_.id -eq 'ff00aa' }
                $active.isArchived | Should -BeFalse
                $active.layout | Should -Be 'assets'
                $active.requirements[0].text | Should -Be 'Asset requirement about alpha'
                @($active.risks | ForEach-Object { $_.text }) | Should -Be @('Asset risk about alpha')
                @($active.decisions) | Should -Be @('Asset decision about alpha.')

                $index.totals.plans | Should -Be 2
                $index.totals.archived | Should -Be 1
                $index.totals.active | Should -Be 1

                $markdown = & $indexScript -RepoRoot $root -Format Markdown
                $markdown | Should -Match 'Legacy requirement about bravo'
                $markdown | Should -Match 'Legacy risk about bravo'
                $markdown | Should -Match 'Legacy decision about bravo'
                $markdown | Should -Match 'Asset requirement about alpha'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'reports an unparseable plan instead of losing the rest of the corpus' {
            $root = & $newCorpus
            try {
                $brokenDir = Join-Path $root 'docs/implementation-plans/2026-07-31-ee11bb-broken-fixture'
                & $newAssetsPlan $brokenDir 'ee11bb' 'Broken fixture plan' 'charlie'
                Set-Content -LiteralPath (Join-Path $brokenDir 'assets/requirements.md') -Value '# Requirements' -Encoding utf8NoBOM

                $index = & $indexScript -RepoRoot $root -Format Json | ConvertFrom-Json
                @($index.plans | ForEach-Object { $_.id }) | Should -Not -Contain 'ee11bb'
                @($index.plans).Count | Should -Be 2
                @($index.errors).Count | Should -Be 1
                $index.errors[0] | Should -Match 'ee11bb'
                # Repo-relative, so the report is identical on any machine.
                $index.errors[0] | Should -Not -Match ([regex]::Escape($root))
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'fails loud when the plan corpus root is missing' {
            $root = & $newTempRoot
            try {
                Remove-Item -LiteralPath (Join-Path $root 'docs') -Recurse -Force
                # An empty index reads as "no prior art to reconcile" and unblocks the /cip prior-art gate,
                # so a mis-rooted run has to fail instead of succeeding with zero records.
                { & $indexScript -RepoRoot $root -Format Json } | Should -Throw -ExpectedMessage '*No plan corpus*'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'narrows the index to matching records when filtered' {
            $root = & $newCorpus
            try {
                $filtered = & $indexScript -RepoRoot $root -Format Json -Filter 'Legacy requirement about' | ConvertFrom-Json
                @($filtered.plans).Count | Should -Be 1
                $filtered.plans[0].id | Should -Be '003'
                @($filtered.plans[0].requirements | ForEach-Object { $_.id }) | Should -Be @('REQ-1')
                @($filtered.plans[0].risks).Count | Should -Be 0
                @($filtered.plans[0].decisions).Count | Should -Be 0
                $filtered.filter | Should -Be 'Legacy requirement about'

                $byMarker = & $indexScript -RepoRoot $root -Format Json -Filter 'alpha' | ConvertFrom-Json
                @($byMarker.plans | ForEach-Object { $_.id }) | Should -Be @('ff00aa')
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:intentalignment-history-intent-snippets indexes active and archived plan and epic intent with bounded provenance' {
            $root = & $newCorpus
            try {
                $activePlanIntent = Join-Path $root 'docs/implementation-plans/2026-07-31-ff00aa-active-fixture/assets/intent.md'
                Set-Content -LiteralPath $activePlanIntent -Encoding utf8NoBOM -Value (@(
                    '# Intent'
                    ''
                    '## Goal'
                    'Retain migration intent marker for the active plan.'
                    ''
                    '## Desired outcome'
                    'Migration intent marker second statement.'
                    ''
                    '## Success signals'
                    'Migration intent marker third statement.'
                    ''
                    '## Non-goals'
                    'Migration intent marker fourth statement.'
                    ''
                    '## Definition of done'
                    'Unrelated outcome.'
                ) -join "`n")

                $archivedIntent = Join-Path $root 'docs/implementation-plans/archived/003-archived-fixture/intent.md'
                Set-Content -LiteralPath $archivedIntent -Encoding utf8NoBOM -Value (@(
                    '# Intent'
                    ''
                    '## Goal'
                    'Archived migration intent marker.'
                ) -join "`n")
                & $newAssetsPlan (Join-Path $root 'docs/implementation-plans/2026-08-03-ee11bb-missing-intent') `
                    'ee11bb' 'Migration intent marker without an intent asset' 'charlie'
                $secretPlan = Join-Path $root 'docs/implementation-plans/2026-08-04-ee22ff-secret-intent'
                & $newAssetsPlan $secretPlan 'ee22ff' 'Unrelated secret fixture' 'delta'
                Set-Content -LiteralPath (Join-Path $secretPlan 'assets/intent.md') -Encoding utf8NoBOM `
                    -Value "# Intent`n`n## Goal`nMigration intent marker ghp_$('a' * 36)"

                $epicsRoot = Join-Path $root 'docs/implementation-plans/epics'
                $archivedEpicsRoot = Join-Path $root 'docs/implementation-plans/archived/epics'
                $activeEpic = Join-Path $epicsRoot '2026-08-01-aa11bb-active-epic'
                $archivedEpic = Join-Path $archivedEpicsRoot '2026-08-02-bb22cc-archived-epic'
                New-Item -ItemType Directory -Path $activeEpic, $archivedEpic -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $activeEpic 'epic.md') -Encoding utf8NoBOM -Value (@(
                    '# aa11bb: Active epic'
                    '<!-- epic-id: aa11bb -->'
                    ''
                    '## Goal'
                    'Active epic migration intent marker.'
                    ''
                    '## Child plans'
                    'Migration intent marker here must not be treated as epic intent.'
                    ''
                    '## Decomposition notes'
                    'Active decomposition migration intent marker.'
                ) -join "`n")
                Set-Content -LiteralPath (Join-Path $archivedEpic 'epic.md') -Encoding utf8NoBOM -Value (@(
                    '# bb22cc: Archived epic'
                    '<!-- epic-id: bb22cc -->'
                    ''
                    '## Goal'
                    'Archived epic migration intent marker.'
                    ''
                    '## Decomposition notes'
                    'Unrelated.'
                ) -join "`n")

                $index = & $indexScript -RepoRoot $root -Format Json -Filter 'migration intent marker' |
                    ConvertFrom-Json
                $candidates = @($index.intentCandidates)
                $candidates.Count | Should -Be 6
                $activePlan = $candidates | Where-Object { $_.kind -eq 'plan' -and $_.id -eq 'ff00aa' }
                $activePlan.path | Should -Be 'docs/implementation-plans/2026-07-31-ff00aa-active-fixture/assets/intent.md'
                $activePlan.isArchived | Should -BeFalse
                $activePlan.matchedSection | Should -Be 'Goal, Desired outcome, Success signals'
                @($activePlan.snippets).Count | Should -Be 3
                foreach ($snippet in $activePlan.snippets) { $snippet.Length | Should -BeLessOrEqual 240 }

                $archivedPlan = $candidates | Where-Object { $_.kind -eq 'plan' -and $_.id -eq '003' }
                $archivedPlan.isArchived | Should -BeTrue
                $archivedPlan.path | Should -Be 'docs/implementation-plans/archived/003-archived-fixture/intent.md'
                $missing = $candidates | Where-Object { $_.kind -eq 'plan' -and $_.id -eq 'ee11bb' }
                $missing.missingContextReason | Should -Be 'Intent artifact does not exist.'
                @($missing.snippets).Count | Should -Be 0
                $secret = $candidates | Where-Object { $_.kind -eq 'plan' -and $_.id -eq 'ee22ff' }
                $secret.missingContextReason | Should -Be 'Matching intent text was omitted by secret screening.'
                @($secret.snippets).Count | Should -Be 0
                ($index | ConvertTo-Json -Depth 10) | Should -Not -Match 'ghp_'

                $epicCandidates = @($candidates | Where-Object kind -eq 'epic')
                @($epicCandidates | ForEach-Object id) | Should -Be @('aa11bb', 'bb22cc')
                $epicCandidates[0].matchedSection | Should -Be 'Goal, Decomposition notes'
                $epicCandidates[0].isArchived | Should -BeFalse
                $epicCandidates[1].isArchived | Should -BeTrue
                ($epicCandidates | ForEach-Object snippets | Out-String) |
                    Should -Not -Match 'Child plans'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'determinism' {
        It 'test:planindex-deterministic emits byte-identical, order-stable output on repeated runs' {
            $root = & $newCorpus
            try {
                # Created last but ordered first: ordering must come from the record ids, never from
                # filesystem enumeration order.
                & $newLegacyPlan (Join-Path $root 'docs/implementation-plans/001-late-fixture') '001' 'Late fixture plan' 'delta'

                foreach ($format in @('Markdown', 'Json')) {
                    $first = & $indexScript -RepoRoot $root -Format $format
                    $second = & $indexScript -RepoRoot $root -Format $format
                    $second | Should -BeExactly $first
                }

                $markdown = & $indexScript -RepoRoot $root -Format Markdown
                $order = @([regex]::Matches($markdown, '(?m)^##\s+(?<id>\S+)\s') | ForEach-Object { $_.Groups['id'].Value })
                $order | Should -Be @('001', '003', 'ff00aa')

                # Any timestamp or host-specific path would make two runs on different days or machines
                # diverge, which is the whole contract this index sells to /cip.
                $markdown | Should -Not -Match '\d{4}-\d{2}-\d{2}T'
                $markdown | Should -Not -Match ([regex]::Escape($root))

                $json = & $indexScript -RepoRoot $root -Format Json
                $json | Should -Not -Match ([regex]::Escape($root))
                { $json | ConvertFrom-Json } | Should -Not -Throw
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
