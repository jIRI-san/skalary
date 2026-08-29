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
            $null = & $newAssetsPlan -Root $root -Id 'a1b2c3' -Slug 'assets'
            $null = & $newLegacyPlan -Root $root -Id '001' -Slug 'legacy'

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
            $outsidePath = Join-Path $root 'outside.md'
            Set-Content -LiteralPath $outsidePath -Encoding utf8NoBOM -NoNewline -Value 'outside'
            New-Item -ItemType SymbolicLink -Path $intentPath -Target $outsidePath | Out-Null
            $linked = @(& $resolver -RepoRoot $root -PlanId a1b2c3 -ArtifactKind Intent -Relationship reuse)
            $linked.status | Should -Be 'refused'
            $linked.content | Should -BeNullOrEmpty
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
