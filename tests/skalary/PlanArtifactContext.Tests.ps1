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

        $newFinalizedReview = {
            param(
                [Parameter(Mandatory)][string]$ReviewsDir,
                [Parameter(Mandatory)][string]$RunId,
                [string]$Content = '# Final review'
            )

            New-Item -ItemType Directory -Path $ReviewsDir -Force | Out-Null
            $reportName = "$RunId.review.md"
            $reportPath = Join-Path $ReviewsDir $reportName
            $receiptPath = Join-Path $ReviewsDir "$RunId.receipt.json"
            $reportBytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Content)
            [System.IO.File]::WriteAllBytes($reportPath, $reportBytes)
            $reportDigest = 'sha256:' + [System.Convert]::ToHexString(
                [System.Security.Cryptography.SHA256]::HashData($reportBytes)
            ).ToLowerInvariant()
            $receipt = [ordered]@{
                schema         = 'skalary/review-result-receipt@1'
                runId          = $RunId
                reviewType     = 'code'
                verdict        = 'approved'
                state          = 'clean'
                source         = [ordered]@{
                    mode      = 'paths'
                    pathCount = 1
                    digest    = 'sha256:' + ('1' * 64)
                }
                planDigest     = 'sha256:' + ('2' * 64)
                runDigest      = 'sha256:' + ('3' * 64)
                manifestDigest = 'sha256:' + ('4' * 64)
                legacySource   = $false
                attendance     = [ordered]@{
                    completed   = 1
                    failed      = 0
                    'timed-out' = 0
                    omitted     = 0
                    cancelled   = 0
                    pending     = 0
                }
                findings       = [ordered]@{
                    merged   = 0
                    raw      = 0
                    severity = [ordered]@{ critical = 0; high = 0; medium = 0; low = 0 }
                }
                report         = [ordered]@{
                    name   = $reportName
                    bytes  = $reportBytes.Length
                    digest = $reportDigest
                }
            }
            $receiptText = $receipt | ConvertTo-Json -Depth 10 -Compress
            [System.IO.File]::WriteAllBytes(
                $receiptPath,
                [System.Text.UTF8Encoding]::new($false).GetBytes($receiptText)
            )
            return [pscustomobject]@{
                ReportPath  = $reportPath
                ReceiptPath = $receiptPath
                Receipt     = $receipt
                PairBytes   = $reportBytes.Length + ([System.IO.FileInfo]$receiptPath).Length
            }
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
            $reviewPair = & $newFinalizedReview -ReviewsDir $reviewsDir -RunId $reviewId

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
            $acceptedReview.byteCount | Should -Be $reviewPair.PairBytes

            $mixedRelationships = @(& $resolver `
                    -RepoRoot $root `
                    -PlanId a1b2c3, '001' `
                    -ArtifactKind Intent `
                    -Relationship extends, dependency)
            @($mixedRelationships | ForEach-Object { "$($_.planId)|$($_.relationship)" }) |
                Should -Be @('001|dependency', 'a1b2c3|extends')

            $relationshipMismatch = @(& $resolver `
                    -RepoRoot $root `
                    -PlanId a1b2c3, '001' `
                    -ArtifactKind Intent `
                    -Relationship extends, dependency, sibling)
            $relationshipMismatch.status | Should -Be 'refused'
            $relationshipMismatch.content | Should -BeNullOrEmpty

            $relationshipConflict = @(& $resolver `
                    -RepoRoot $root `
                    -PlanId a1b2c3, a1b2c3 `
                    -ArtifactKind Intent `
                    -Relationship extends, conflicts)
            $relationshipConflict.status | Should -Be 'refused'
            $relationshipConflict.content | Should -BeNullOrEmpty

            $unsupportedRelationship = @(& $resolver `
                    -RepoRoot $root `
                    -PlanId a1b2c3 `
                    -ArtifactKind Intent `
                    -Relationship reuse)
            $unsupportedRelationship.status | Should -Be 'refused'
            $unsupportedRelationship.content | Should -BeNullOrEmpty

            $nativeJsonText = @(& pwsh `
                    -NoProfile `
                    -File $resolver `
                    -RepoRoot $root `
                    -PlanId a1b2c3 `
                    -ArtifactKind Intent `
                    -Relationship reuses `
                    -Format Json) -join "`n"
            $LASTEXITCODE | Should -Be 0
            $nativeJson = @($nativeJsonText | ConvertFrom-Json -Depth 10)
            $nativeJson.Count | Should -Be 1
            $nativeJson[0].status | Should -Be 'accepted'
            $nativeJson[0].content | Should -BeExactly 'asset-intent'

            $mixedOverflow = @(& $resolver -RepoRoot $root -PlanId a1b2c3 -ArtifactKind Intent, Reviews -Relationship dependency -MaxCandidates 2)
            $mixedOverflow.Count | Should -BeLessOrEqual 2
            @($mixedOverflow.status) | Should -Contain 'refused'
            @($mixedOverflow | Where-Object status -eq 'accepted').artifactKind | Should -Be @('Intent')

            [System.IO.File]::WriteAllBytes((Join-Path $reviewsDir "$reviewId.receipt.json"), [byte[]]::new(0))
            $emptyReceipt = @(& $resolver -RepoRoot $root -PlanId a1b2c3 -ArtifactKind Reviews -Relationship dependency)
            @($emptyReceipt | Where-Object status -eq 'accepted').Count | Should -Be 0
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'accepts only bounded finalized review pairs with exact receipt bindings' {
        $root = & $newTempRoot
        try {
            $planDir = & $newAssetsPlan -Root $root -Id 'a1b2c3' -Slug 'reviews'
            $reviewsDir = Join-Path $planDir 'assets/reviews'
            $reviewId = '12345678-1234-1234-1234-123456789abc'
            $pair = & $newFinalizedReview -ReviewsDir $reviewsDir -RunId $reviewId

            $exactTotal = @(& $resolver `
                    -RepoRoot $root `
                    -PlanId a1b2c3 `
                    -ArtifactKind Reviews `
                    -Relationship reuses `
                    -MaxTotalBytes $pair.PairBytes)
            $exactTotal.status | Should -Be 'accepted'
            $exactTotal.byteCount | Should -Be $pair.PairBytes

            $branchReceipt = Get-Content -LiteralPath $pair.ReceiptPath -Raw | ConvertFrom-Json -AsHashtable
            $branchReceipt['source']['mode'] = 'branch'
            $branchReceipt['source']['base'] = 'main'
            $branchReceipt['source']['head'] = 'HEAD'
            Set-Content -LiteralPath $pair.ReceiptPath -Encoding utf8NoBOM -NoNewline -Value (
                $branchReceipt | ConvertTo-Json -Depth 10 -Compress
            )
            $branchSource = @(& $resolver `
                    -RepoRoot $root `
                    -PlanId a1b2c3 `
                    -ArtifactKind Reviews `
                    -Relationship reuses)
            $branchSource.status | Should -Be 'accepted'

            foreach ($mode in @('uncommitted', 'design')) {
                $modePair = & $newFinalizedReview -ReviewsDir $reviewsDir -RunId $reviewId
                $modeReceipt = Get-Content -LiteralPath $modePair.ReceiptPath -Raw | ConvertFrom-Json -AsHashtable
                $modeReceipt['source']['mode'] = $mode
                Set-Content -LiteralPath $modePair.ReceiptPath -Encoding utf8NoBOM -NoNewline -Value (
                    $modeReceipt | ConvertTo-Json -Depth 10 -Compress
                )
                $modeResult = @(& $resolver `
                        -RepoRoot $root `
                        -PlanId a1b2c3 `
                        -ArtifactKind Reviews `
                        -Relationship reuses)
                $modeResult.status | Should -Be 'accepted'
            }

            $overTotal = @(& $resolver `
                    -RepoRoot $root `
                    -PlanId a1b2c3 `
                    -ArtifactKind Reviews `
                    -Relationship reuses `
                    -MaxTotalBytes ($pair.PairBytes - 1))
            $overTotal.status | Should -Be 'oversized'
            $overTotal.content | Should -BeNullOrEmpty

            $receiptLength = ([System.IO.FileInfo]$pair.ReceiptPath).Length
            $oversizedReceipt = @(& $resolver `
                    -RepoRoot $root `
                    -PlanId a1b2c3 `
                    -ArtifactKind Reviews `
                    -Relationship reuses `
                    -MaxArtifactBytes ($receiptLength - 1))
            $oversizedReceipt.status | Should -Be 'oversized'
            $oversizedReceipt.content | Should -BeNullOrEmpty

            foreach ($mutation in @(
                    'run-id',
                    'report-name',
                    'report-bytes',
                    'report-digest',
                    'extra-field',
                    'report-bytes-string',
                    'source-count-fraction',
                    'attendance-boolean',
                    'findings-null',
                    'severity-overflow',
                    'source-mode-invalid',
                    'source-mode-nonstring',
                    'branch-missing-head',
                    'paths-with-base',
                    'review-type-case',
                    'verdict-case',
                    'state-case'
                )) {
                $pair = & $newFinalizedReview -ReviewsDir $reviewsDir -RunId $reviewId
                $receipt = Get-Content -LiteralPath $pair.ReceiptPath -Raw | ConvertFrom-Json -AsHashtable
                switch ($mutation) {
                    'run-id' { $receipt['runId'] = '00000000-0000-0000-0000-000000000000' }
                    'report-name' { $receipt['report']['name'] = 'other.review.md' }
                    'report-bytes' { $receipt['report']['bytes']++ }
                    'report-digest' { $receipt['report']['digest'] = 'sha256:' + ('0' * 64) }
                    'extra-field' { $receipt['extra'] = $true }
                    'report-bytes-string' { $receipt['report']['bytes'] = [string]$receipt['report']['bytes'] }
                    'source-count-fraction' { $receipt['source']['pathCount'] = 1.5 }
                    'attendance-boolean' { $receipt['attendance']['completed'] = $true }
                    'findings-null' { $receipt['findings']['merged'] = $null }
                    'severity-overflow' { $receipt['findings']['severity']['low'] = 1e30 }
                    'source-mode-invalid' { $receipt['source']['mode'] = 'commit' }
                    'source-mode-nonstring' { $receipt['source']['mode'] = 1 }
                    'branch-missing-head' { $receipt['source']['mode'] = 'branch' }
                    'paths-with-base' { $receipt['source']['base'] = 'main' }
                    'review-type-case' { $receipt['reviewType'] = 'Code' }
                    'verdict-case' { $receipt['verdict'] = 'Approved' }
                    'state-case' { $receipt['state'] = 'Clean' }
                }
                Set-Content -LiteralPath $pair.ReceiptPath -Encoding utf8NoBOM -NoNewline -Value (
                    $receipt | ConvertTo-Json -Depth 10 -Compress
                )

                $result = @(& $resolver `
                        -RepoRoot $root `
                        -PlanId a1b2c3 `
                        -ArtifactKind Reviews `
                        -Relationship reuses)
                $result.status | Should -Be 'refused'
                $result.content | Should -BeNullOrEmpty
            }

            $pair = & $newFinalizedReview -ReviewsDir $reviewsDir -RunId $reviewId
            Set-Content -LiteralPath $pair.ReportPath -Encoding utf8NoBOM -NoNewline -Value '# Tampered report'
            $tamperedReport = @(& $resolver `
                    -RepoRoot $root `
                    -PlanId a1b2c3 `
                    -ArtifactKind Reviews `
                    -Relationship reuses)
            $tamperedReport.status | Should -Be 'refused'
            $tamperedReport.content | Should -BeNullOrEmpty

            Set-Content -LiteralPath $pair.ReceiptPath -Encoding utf8NoBOM -NoNewline -Value '{'
            $malformedReceipt = @(& $resolver `
                    -RepoRoot $root `
                    -PlanId a1b2c3 `
                    -ArtifactKind Reviews `
                    -Relationship reuses)
            $malformedReceipt.status | Should -Be 'refused'
            $malformedReceipt.content | Should -BeNullOrEmpty

            $overflowPlan = & $newAssetsPlan -Root $root -Id 'ddeeff' -Slug 'review-overflow'
            $overflowDir = Join-Path $overflowPlan 'assets/reviews'
            New-Item -ItemType Directory -Path $overflowDir -Force | Out-Null
            foreach ($name in @('z.md', 'a.md', 'm.md')) {
                Set-Content -LiteralPath (Join-Path $overflowDir $name) -Encoding utf8NoBOM -Value '# Not retained'
            }
            $firstOverflow = @(& $resolver `
                    -RepoRoot $root `
                    -PlanId ddeeff `
                    -ArtifactKind Reviews `
                    -Relationship reuses `
                    -MaxCandidates 2)
            $secondOverflow = @(& $resolver `
                    -RepoRoot $root `
                    -PlanId ddeeff `
                    -ArtifactKind Reviews `
                    -Relationship reuses `
                    -MaxCandidates 2)
            ($firstOverflow | ConvertTo-Json -Compress) |
                Should -BeExactly ($secondOverflow | ConvertTo-Json -Compress)
            $firstOverflow.status | Should -Be 'refused'
            $firstOverflow.path | Should -Be 'docs/implementation-plans/2026-01-02-ddeeff-review-overflow/assets/reviews'
            $firstOverflow.content | Should -BeNullOrEmpty
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

            $exactFile = @(& $resolver -RepoRoot $root -PlanId a1b2c3 -ArtifactKind Intent -Relationship reuses -MaxArtifactBytes 4 -MaxTotalBytes 4)
            $exactFile.status | Should -Be 'accepted'
            $exactFile.byteCount | Should -Be 4
            $exactFile.content | Should -BeExactly '1234'

            $overFile = @(& $resolver -RepoRoot $root -PlanId a1b2c3 -ArtifactKind Intent -Relationship reuses -MaxArtifactBytes 3)
            $overFile.status | Should -Be 'oversized'
            $overFile.content | Should -BeNullOrEmpty

            $exactTotal = @(& $resolver -RepoRoot $root -PlanId a1b2c3 -ArtifactKind Intent, Design -Relationship reuses -MaxArtifactBytes 4 -MaxTotalBytes 8)
            @($exactTotal.status) | Should -Be @('accepted', 'accepted')

            $overTotal = @(& $resolver -RepoRoot $root -PlanId a1b2c3 -ArtifactKind Intent, Design -Relationship reuses -MaxArtifactBytes 4 -MaxTotalBytes 7)
            @($overTotal.status) | Should -Be @('oversized', 'oversized')
            @($overTotal | Where-Object { $_.content }).Count | Should -Be 0

            $overCandidates = @(& $resolver -RepoRoot $root -PlanId a1b2c3 -ArtifactKind Intent, Design -Relationship reuses -MaxCandidates 1)
            $overCandidates.Count | Should -Be 1
            $overCandidates.status | Should -Be 'refused'
            @($overCandidates | Where-Object { $_.content }).Count | Should -Be 0

            $missing = @(& $resolver -RepoRoot $root -PlanId a1b2c3 -ArtifactKind Evidence -Relationship reuses)
            $missing.status | Should -Be 'missing'
            $missing.content | Should -BeNullOrEmpty

            $unsupported = @(& $resolver -RepoRoot $root -PlanId a1b2c3 -ArtifactKind '../Intent' -Relationship reuses)
            $unsupported.status | Should -Be 'refused'
            $unsupported.content | Should -BeNullOrEmpty

            $badId = @(& $resolver -RepoRoot $root -PlanId bad-id -ArtifactKind Intent -Relationship reuses)
            $badId.status | Should -Be 'refused'
            $badId.content | Should -BeNullOrEmpty

            $malformedDir = Join-Path $root 'docs/implementation-plans/2026-01-02-ddeeff-malformed'
            New-Item -ItemType Directory -Path $malformedDir -Force | Out-Null
            $malformed = @(& $resolver -RepoRoot $root -PlanId ddeeff -ArtifactKind Intent -Relationship reuses)
            $malformed.status | Should -Be 'refused'
            $malformed.content | Should -BeNullOrEmpty

            Remove-Item -LiteralPath $intentPath -Force
            New-Item -ItemType Directory -Path $intentPath | Out-Null
            $notFile = @(& $resolver -RepoRoot $root -PlanId a1b2c3 -ArtifactKind Intent -Relationship reuses)
            $notFile.status | Should -Be 'refused'
            $notFile.content | Should -BeNullOrEmpty

            Remove-Item -LiteralPath $intentPath -Recurse -Force
            [System.IO.File]::WriteAllBytes($intentPath, [byte[]]@(0xC3, 0x28))
            $invalidUtf8 = @(& $resolver -RepoRoot $root -PlanId a1b2c3 -ArtifactKind Intent -Relationship reuses)
            $invalidUtf8.status | Should -Be 'refused'
            $invalidUtf8.content | Should -BeNullOrEmpty

            Remove-Item -LiteralPath $intentPath -Force
            [System.IO.File]::WriteAllBytes($intentPath, [byte[]]::new(0))
            $empty = @(& $resolver -RepoRoot $root -PlanId a1b2c3 -ArtifactKind Intent -Relationship reuses)
            $empty.status | Should -Be 'refused'
            $empty.content | Should -BeNullOrEmpty

            Remove-Item -LiteralPath $intentPath -Force
            $outsidePath = Join-Path $root 'outside.md'
            Set-Content -LiteralPath $outsidePath -Encoding utf8NoBOM -NoNewline -Value 'outside'
            New-Item -ItemType SymbolicLink -Path $intentPath -Target $outsidePath | Out-Null
            $linked = @(& $resolver -RepoRoot $root -PlanId a1b2c3 -ArtifactKind Intent -Relationship reuses)
            $linked.status | Should -Be 'refused'
            $linked.content | Should -BeNullOrEmpty

            Remove-Item -LiteralPath $intentPath -Force
            New-Item -ItemType HardLink -Path $intentPath -Target $outsidePath | Out-Null
            $hardLinked = @(& $resolver -RepoRoot $root -PlanId a1b2c3 -ArtifactKind Intent -Relationship reuses)
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
        $cipGuide | Should -Match '^# Interview Guide \(`cip` Step 2\)'
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
            $text | Should -Match 'one bounded invocation'
            $text | Should -Match 'Align each\s+`Relationship` value with the `PlanId`'
        }

        $root = & $newTempRoot
        try {
            $null = & $newAssetsPlan -Root $root -Id 'a1b2c3' -Slug 'provenance-a'
            $null = & $newAssetsPlan -Root $root -Id 'ddeeff' -Slug 'provenance-b'
            $results = @(& $resolver `
                    -RepoRoot $root `
                    -PlanId ddeeff, a1b2c3 `
                    -ArtifactKind Intent, Evidence `
                    -Relationship sibling, extends)

            @($results.status) | Should -Be @('missing', 'accepted', 'missing', 'accepted')
            $recorded = @(
                $results |
                    Where-Object status -eq 'accepted' |
                    ForEach-Object {
                        "$($_.planId)|$($_.artifactKind)|$($_.path)|$($_.relationship)"
                    }
            )
            $recorded | Should -Be @(
                'a1b2c3|Intent|docs/implementation-plans/2026-01-02-a1b2c3-provenance-a/assets/intent.md|extends'
                'ddeeff|Intent|docs/implementation-plans/2026-01-02-ddeeff-provenance-b/assets/intent.md|sibling'
            )
            @($recorded | Where-Object { $_ -match 'Evidence' }).Count | Should -Be 0
            Test-Path -LiteralPath (Join-Path $root 'docs/implementation-plans/provenance-receipts') |
                Should -BeFalse
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
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
                Path = 'plugins/create-implementation-plan/skills/cip/SKILL.md'
                InstalledResolver = '.github/skills/cip/scripts/Get-PlanArtifactContext.ps1'
            }
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
        $resolverText = Get-Content -LiteralPath $canonicalResolver -Raw
        $relationshipBlock = [regex]::Match(
            $resolverText,
            '(?s)\$relationshipValues\s*=\s*@\((?<values>.*?)\)'
        )
        $relationshipBlock.Success | Should -BeTrue
        $closedRelationships = @(
            [regex]::Matches($relationshipBlock.Groups['values'].Value, "'(?<value>[^']+)'") |
                ForEach-Object { $_.Groups['value'].Value }
        )
        $closedRelationships | Should -Be @(
            'reuses', 'extends', 'supersedes', 'conflicts', 'dependency', 'sibling', 'operator-selected'
        )
        foreach ($contract in $consumerContracts) {
            $text = Get-Content -LiteralPath (Join-Path $repoRoot $contract.Path) -Raw
            $text | Should -Match ([regex]::Escape($contract.InstalledResolver))
            $text | Should -Match 'accepted'
            $text | Should -Match 'untrusted'
            $text | Should -Match 'architecture\s+contracts'
            $text | Should -Match 'remain\s+authoritative|cannot\s+override'
            $text | Should -Match 'one bounded invocation'
            $text | Should -Match 'align(?:ing)?\s+each\s+`Relationship`\s+value\s+with\s+the\s+`PlanId`'
            $text | Should -Match '(?i)-Format Json'
            $text | Should -Match '(?i)parse\s+the\s+returned\s+JSON\s+array'
            $text | Should -Match 'resolver''s\s+closed\s+`Relationship`'
        }

        $cipGuide = Get-Content -LiteralPath (
            Join-Path $repoRoot 'plugins/create-implementation-plan/skills/cip/assets/interview-guide.md'
        ) -Raw
        $relationshipTable = [regex]::Match(
            $cipGuide,
            '(?s)\| Relationship \| What to record \|(?<rows>.*?)\r?\n\r?\nRecord provenance'
        )
        $relationshipTable.Success | Should -BeTrue
        $documentedRelationships = @(
            [regex]::Matches(
                $relationshipTable.Groups['rows'].Value,
                '(?m)^\|\s*(?<value>[A-Za-z][A-Za-z-]*)\s*\|'
            ) |
                ForEach-Object { $_.Groups['value'].Value.ToLowerInvariant() }
        )
        $documentedRelationships | Should -Be $closedRelationships

        foreach ($skillPath in @(
                'plugins/create-implementation-plan/skills/cip/SKILL.md'
                'plugins/create-implementation-plan/skills/cep/SKILL.md'
            )) {
            $skillText = Get-Content -LiteralPath (Join-Path $repoRoot $skillPath) -Raw
            $architectureIndex = $skillText.IndexOf('docs/architecture-notes/.architecture-notes.md')
            $designIndex = $skillText.IndexOf('docs/design-notes/.design-notes.md')
            $architectureIndex | Should -BeGreaterOrEqual 0
            $designIndex | Should -BeGreaterThan $architectureIndex
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
