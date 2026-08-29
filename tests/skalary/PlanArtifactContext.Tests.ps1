#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Get-PlanArtifactContext' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $resolver = Join-Path $repoRoot 'scripts/skalary/Get-PlanArtifactContext.ps1'

        $newTempRoot = {
            $root = Join-Path ([System.IO.Path]::GetTempPath()) ('plan-artifact-context-' + [System.Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path (Join-Path $root 'docs/implementation-plans/archived') -Force | Out-Null
            return $root
        }

        $newAssetsPlan = {
            param(
                [Parameter(Mandatory)][string]$Root,
                [Parameter(Mandatory)][string]$Id,
                [Parameter(Mandatory)][string]$Slug
            )

            $planDir = Join-Path $Root "docs/implementation-plans/2026-01-02-$Id-$Slug"
            $assetsDir = Join-Path $planDir 'assets'
            New-Item -ItemType Directory -Path $assetsDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $planDir 'plan.md') -Encoding utf8NoBOM -Value @(
                "# ${Id}: Assets fixture"
                "<!-- plan-id: $Id -->"
                ''
                '## Phase 1: Fixture'
                ''
                '- [ ] 1.1 Fixture step `S`'
            )
            Set-Content -LiteralPath (Join-Path $assetsDir 'requirements.md') -Encoding utf8NoBOM -Value '# Requirements'
            Set-Content -LiteralPath (Join-Path $assetsDir 'intent.md') -Encoding utf8NoBOM -NoNewline -Value 'asset-intent'
            Set-Content -LiteralPath (Join-Path $assetsDir 'design.md') -Encoding utf8NoBOM -NoNewline -Value 'asset-design'
            Set-Content -LiteralPath (Join-Path $assetsDir 'decisions.md') -Encoding utf8NoBOM -Value @(
                '# Decisions'
                ''
                '- Asset decision.'
            )
            return $planDir
        }

        $newLegacyPlan = {
            param(
                [Parameter(Mandatory)][string]$Root,
                [Parameter(Mandatory)][string]$Id,
                [Parameter(Mandatory)][string]$Slug
            )

            $planDir = Join-Path $Root "docs/implementation-plans/archived/$Id-$Slug"
            New-Item -ItemType Directory -Path $planDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $planDir 'plan.md') -Encoding utf8NoBOM -Value @(
                "# ${Id}: Legacy fixture"
                "<!-- plan-id: $Id -->"
                ''
                '## Decisions'
                ''
                '- Legacy decision.'
                ''
                '## Phase 1: Fixture'
                ''
                '- [ ] 1.1 Fixture step `S`'
            )
            Set-Content -LiteralPath (Join-Path $planDir 'intent.md') -Encoding utf8NoBOM -NoNewline -Value 'legacy-intent'
            return $planDir
        }
    }

    It 'test:PlanArtifactContext.Resolution resolves selected active and archived plans deterministically across layouts' {
        $root = & $newTempRoot
        try {
            $assetsPlan = & $newAssetsPlan -Root $root -Id 'a1b2c3' -Slug 'assets'
            $null = & $newLegacyPlan -Root $root -Id '001' -Slug 'legacy'
            $reviewsDir = Join-Path $assetsPlan 'assets/reviews'
            New-Item -ItemType Directory -Path $reviewsDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $reviewsDir 'notes.md') -Encoding utf8NoBOM -Value 'not a finalized review'
            $badReviewId = '00000000-0000-0000-0000-000000000000'
            Set-Content -LiteralPath (Join-Path $reviewsDir "$badReviewId.review.md") -Encoding utf8NoBOM -Value '# Refused review'
            New-Item -ItemType Directory -Path (Join-Path $reviewsDir "$badReviewId.receipt.json") | Out-Null
            $reviewId = '12345678-1234-1234-1234-123456789abc'
            Set-Content -LiteralPath (Join-Path $reviewsDir "$reviewId.review.md") -Encoding utf8NoBOM -Value '# Final review'
            Set-Content -LiteralPath (Join-Path $reviewsDir "$reviewId.receipt.json") -Encoding utf8NoBOM -Value '{}'

            $arguments = @{
                RepoRoot     = $root
                PlanId       = @('a1b2c3', '001', 'a1b2c3')
                ArtifactKind = @('Intent', 'Decisions', 'Intent')
                Relationship = 'dependency'
            }
            $first = @(& $resolver @arguments)
            $second = @(& $resolver @arguments)

            ($second | ConvertTo-Json -Depth 5 -Compress) | Should -BeExactly ($first | ConvertTo-Json -Depth 5 -Compress)
            @($first | ForEach-Object { "$($_.planId)|$($_.artifactKind)" }) |
                Should -Be @('001|Decisions', '001|Intent', 'a1b2c3|Decisions', 'a1b2c3|Intent')
            @($first.status) | Should -Be @('accepted', 'accepted', 'accepted', 'accepted')

            $legacyDecision = $first[0]
            $legacyDecision.layout | Should -Be 'legacy'
            $legacyDecision.isArchived | Should -BeTrue
            $legacyDecision.path | Should -Be 'docs/implementation-plans/archived/001-legacy/plan.md'
            $legacyDecision.content | Should -Match 'Legacy decision\.'

            $assetDecision = $first[2]
            $assetDecision.layout | Should -Be 'assets'
            $assetDecision.isArchived | Should -BeFalse
            $assetDecision.path | Should -Be 'docs/implementation-plans/2026-01-02-a1b2c3-assets/assets/decisions.md'
            $assetDecision.content | Should -Match 'Asset decision\.'

            @($first.relationship | Select-Object -Unique) | Should -Be @('dependency')
            @($first.isUntrusted | Select-Object -Unique) | Should -Be @($true)
            @($first.authority | Select-Object -Unique) | Should -Be @('historical-context-only')

            $reviews = @(& $resolver -RepoRoot $root -PlanId a1b2c3 -ArtifactKind Reviews -Relationship dependency)
            $reviews.Count | Should -Be 2
            @($reviews.status) | Should -Be @('refused', 'accepted')
            $acceptedReview = $reviews | Where-Object status -eq 'accepted'
            $acceptedReview.path | Should -Be "docs/implementation-plans/2026-01-02-a1b2c3-assets/assets/reviews/$reviewId.review.md"
            $acceptedReview.content | Should -Match 'Final review'

            $mixedOverflow = @(& $resolver -RepoRoot $root -PlanId a1b2c3 -ArtifactKind Intent, Reviews -Relationship dependency -MaxCandidates 2)
            $mixedOverflow.Count | Should -BeLessOrEqual 2
            @($mixedOverflow | Where-Object { $_.status -eq 'accepted' -or $_.content }).Count | Should -Be 0

            [System.IO.File]::WriteAllBytes((Join-Path $reviewsDir "$reviewId.receipt.json"), [byte[]]::new(0))
            $emptyReceipt = @(& $resolver -RepoRoot $root -PlanId a1b2c3 -ArtifactKind Reviews -Relationship dependency)
            @($emptyReceipt | Where-Object status -eq 'accepted').Count | Should -Be 0
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:PlanArtifactContext.BoundsAndConfinement fails closed at file and aggregate boundaries' {
        $root = & $newTempRoot
        try {
            $planDir = & $newAssetsPlan -Root $root -Id 'a1b2c3' -Slug 'bounds'
            $assetsDir = Join-Path $planDir 'assets'
            $intentPath = Join-Path $assetsDir 'intent.md'
            $designPath = Join-Path $assetsDir 'design.md'
            Set-Content -LiteralPath $intentPath -Encoding utf8NoBOM -NoNewline -Value '1234'
            Set-Content -LiteralPath $designPath -Encoding utf8NoBOM -NoNewline -Value '5678'

            $exactFile = @(& $resolver -RepoRoot $root -PlanId a1b2c3 -ArtifactKind Intent -Relationship reuse -MaxArtifactBytes 4 -MaxTotalBytes 4)
            $exactFile.status | Should -Be 'accepted'
            $exactFile.byteCount | Should -Be 4
            $exactFile.content | Should -BeExactly '1234'

            $overFile = @(& $resolver -RepoRoot $root -PlanId a1b2c3 -ArtifactKind Intent -Relationship reuse -MaxArtifactBytes 3)
            $overFile.status | Should -Be 'oversized'
            $overFile.content | Should -BeNullOrEmpty

            $exactTotal = @(& $resolver -RepoRoot $root -PlanId a1b2c3 -ArtifactKind Intent, Design -Relationship reuse -MaxArtifactBytes 4 -MaxTotalBytes 8)
            @($exactTotal.status) | Should -Be @('accepted', 'accepted')

            $overTotal = @(& $resolver -RepoRoot $root -PlanId a1b2c3 -ArtifactKind Intent, Design -Relationship reuse -MaxArtifactBytes 4 -MaxTotalBytes 7)
            @($overTotal.status) | Should -Be @('oversized', 'oversized')
            @($overTotal | Where-Object { $_.content }).Count | Should -Be 0

            $overCandidates = @(& $resolver -RepoRoot $root -PlanId a1b2c3 -ArtifactKind Intent, Design -Relationship reuse -MaxCandidates 1)
            $overCandidates.Count | Should -Be 1
            $overCandidates.status | Should -Be 'refused'
            @($overCandidates | Where-Object { $_.content }).Count | Should -Be 0

            $missing = @(& $resolver -RepoRoot $root -PlanId a1b2c3 -ArtifactKind Evidence -Relationship reuse)
            $missing.status | Should -Be 'missing'
            $missing.content | Should -BeNullOrEmpty

            $unsupported = @(& $resolver -RepoRoot $root -PlanId a1b2c3 -ArtifactKind '../Intent' -Relationship reuse)
            $unsupported.status | Should -Be 'refused'
            $unsupported.content | Should -BeNullOrEmpty

            $badId = @(& $resolver -RepoRoot $root -PlanId bad-id -ArtifactKind Intent -Relationship reuse)
            $badId.status | Should -Be 'refused'
            $badId.content | Should -BeNullOrEmpty

            $malformedDir = Join-Path $root 'docs/implementation-plans/2026-01-02-ddeeff-malformed'
            New-Item -ItemType Directory -Path $malformedDir -Force | Out-Null
            $malformed = @(& $resolver -RepoRoot $root -PlanId ddeeff -ArtifactKind Intent -Relationship reuse)
            $malformed.status | Should -Be 'refused'
            $malformed.content | Should -BeNullOrEmpty

            Remove-Item -LiteralPath $intentPath -Force
            New-Item -ItemType Directory -Path $intentPath | Out-Null
            $notFile = @(& $resolver -RepoRoot $root -PlanId a1b2c3 -ArtifactKind Intent -Relationship reuse)
            $notFile.status | Should -Be 'refused'
            $notFile.content | Should -BeNullOrEmpty

            Remove-Item -LiteralPath $intentPath -Recurse -Force
            [System.IO.File]::WriteAllBytes($intentPath, [byte[]]@(0xC3, 0x28))
            $invalidUtf8 = @(& $resolver -RepoRoot $root -PlanId a1b2c3 -ArtifactKind Intent -Relationship reuse)
            $invalidUtf8.status | Should -Be 'refused'
            $invalidUtf8.content | Should -BeNullOrEmpty

            Remove-Item -LiteralPath $intentPath -Force
            [System.IO.File]::WriteAllBytes($intentPath, [byte[]]::new(0))
            $empty = @(& $resolver -RepoRoot $root -PlanId a1b2c3 -ArtifactKind Intent -Relationship reuse)
            $empty.status | Should -Be 'refused'
            $empty.content | Should -BeNullOrEmpty

            Remove-Item -LiteralPath $intentPath -Force
            $outsidePath = Join-Path $root 'outside.md'
            Set-Content -LiteralPath $outsidePath -Encoding utf8NoBOM -NoNewline -Value 'outside'
            New-Item -ItemType SymbolicLink -Path $intentPath -Target $outsidePath | Out-Null
            $linked = @(& $resolver -RepoRoot $root -PlanId a1b2c3 -ArtifactKind Intent -Relationship reuse)
            $linked.status | Should -Be 'refused'
            $linked.content | Should -BeNullOrEmpty

            Remove-Item -LiteralPath $intentPath -Force
            New-Item -ItemType HardLink -Path $intentPath -Target $outsidePath | Out-Null
            $hardLinked = @(& $resolver -RepoRoot $root -PlanId a1b2c3 -ArtifactKind Intent -Relationship reuse)
            $hardLinked.status | Should -Be 'refused'
            $hardLinked.content | Should -BeNullOrEmpty
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:PlanArtifactContext.Provenance records complete deterministic metadata only for consumed artifacts' {
        $planningGuides = @(
            'plugins/create-implementation-plan/skills/cip/assets/interview-guide.md'
            'plugins/create-implementation-plan/skills/cep/assets/decomposition-guide.md'
        )
        foreach ($relativePath in $planningGuides) {
            $text = Get-Content -LiteralPath (Join-Path $repoRoot $relativePath) -Raw
            $text | Should -Match 'references\.md'
            $text | Should -Match '\| Plan ID \| Artifact kind \| Path \| Relationship \|'
            $text | Should -Match 'planId'
            $text | Should -Match 'artifactKind'
            $text | Should -Match 'relationship'
            $text | Should -Match 'accepted'
            $text | Should -Match 'missing'
            $text | Should -Match 'refused'
            $text | Should -Match 'oversized'
            $text | Should -Match 'sorted by plan ID, artifact kind, path, then\s+relationship'
        }

        $cipGuide = Get-Content -LiteralPath (Join-Path $repoRoot $planningGuides[0]) -Raw
        $cepGuide = Get-Content -LiteralPath (Join-Path $repoRoot $planningGuides[1]) -Raw
        $cipGuide | Should -Match 'Write rows only for `accepted` results'
        $cepGuide | Should -Match 'without recording provenance'

        foreach ($relativePath in @(
                'plugins/code-review/skills/cr/assets/scope-guide.md'
                'plugins/design-review/skills/dr/assets/plan-scope-guide.md'
            )) {
            $text = Get-Content -LiteralPath (Join-Path $repoRoot $relativePath) -Raw
            $text | Should -Match 'historical-context\[planId=<id>;artifactKind=<kind>;path=<path>;relationship=<relationship>\]'
            $text | Should -Match 'Sort accepted metadata by `planId`, `artifactKind`, `path`, then `relationship`'
            $text | Should -Match 'never truncate metadata or consume unrecorded content'
        }
    }

    It 'test:PlanArtifactContext.Consumers uses one bounded resolver path without changing review-run v1 authority' {
        $canonicalResolver = Join-Path $repoRoot 'scripts/skalary/Get-PlanArtifactContext.ps1'
        $expectedHash = (Get-FileHash -LiteralPath $canonicalResolver -Algorithm SHA256).Hash
        $resolverCopies = @(
            'plugins/create-implementation-plan/skills/cip/scripts/Get-PlanArtifactContext.ps1'
            'plugins/create-implementation-plan/skills/cep/scripts/Get-PlanArtifactContext.ps1'
            'plugins/code-review/skills/cr/scripts/Get-PlanArtifactContext.ps1'
            'plugins/design-review/skills/dr/scripts/Get-PlanArtifactContext.ps1'
            '.github/skills/cip/scripts/Get-PlanArtifactContext.ps1'
            '.github/skills/cep/scripts/Get-PlanArtifactContext.ps1'
            '.github/skills/cr/scripts/Get-PlanArtifactContext.ps1'
            '.github/skills/dr/scripts/Get-PlanArtifactContext.ps1'
        )
        foreach ($relativePath in $resolverCopies) {
            Test-Path -LiteralPath (Join-Path $repoRoot $relativePath) -PathType Leaf | Should -BeTrue
            (Get-FileHash -LiteralPath (Join-Path $repoRoot $relativePath) -Algorithm SHA256).Hash |
                Should -BeExactly $expectedHash
        }

        $consumerContracts = @(
            [pscustomobject]@{
                Path = 'plugins/create-implementation-plan/skills/cip/assets/interview-guide.md'
                InstalledResolver = '.github/skills/cip/scripts/Get-PlanArtifactContext.ps1'
            }
            [pscustomobject]@{
                Path = 'plugins/create-implementation-plan/skills/cep/assets/decomposition-guide.md'
                InstalledResolver = '.github/skills/cep/scripts/Get-PlanArtifactContext.ps1'
            }
            [pscustomobject]@{
                Path = 'plugins/code-review/skills/cr/assets/scope-guide.md'
                InstalledResolver = '.github/skills/cr/scripts/Get-PlanArtifactContext.ps1'
            }
            [pscustomobject]@{
                Path = 'plugins/design-review/skills/dr/assets/plan-scope-guide.md'
                InstalledResolver = '.github/skills/dr/scripts/Get-PlanArtifactContext.ps1'
            }
        )
        foreach ($contract in $consumerContracts) {
            $text = Get-Content -LiteralPath (Join-Path $repoRoot $contract.Path) -Raw
            $text | Should -Match ([regex]::Escape($contract.InstalledResolver))
            $text | Should -Match 'accepted'
            $text | Should -Match 'untrusted'
            $text | Should -Match 'architecture\s+contracts'
            $text | Should -Match 'remain\s+authoritative|cannot\s+override'
        }

        foreach ($schemaName in @('review-plan.schema.json', 'review-run.schema.json')) {
            $schema = Get-Content -LiteralPath (Join-Path $repoRoot "schemas/review/$schemaName") -Raw
            $schema | Should -Not -Match '(?i)historicalContext|artifactContext|contextRole'
        }
        foreach ($reviewGuide in @(
                'plugins/code-review/skills/cr/assets/scope-guide.md'
                'plugins/design-review/skills/dr/assets/plan-scope-guide.md'
            )) {
            $text = Get-Content -LiteralPath (Join-Path $repoRoot $reviewGuide) -Raw
            $text | Should -Match 'existing 1024-character scope limit'
            $text | Should -Match 'do not add a context role, field, schema,\s+receipt, lifecycle'
            $text | Should -Match 'scopeAuthority'
        }
    }
}
