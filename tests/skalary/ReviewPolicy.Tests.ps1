#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Proportional review policy fixtures' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        function Read-RepoText {
            param([Parameter(Mandatory)][string]$Path)
            Get-Content -LiteralPath (Join-Path $script:repoRoot $Path) -Raw
        }
        function Read-PolicyFixture {
            param([Parameter(Mandatory)][string]$Name)
            Get-Content -LiteralPath (
                Join-Path $script:repoRoot "tests/skalary/fixtures/review-policy/$Name.json"
            ) -Raw | ConvertFrom-Json
        }
        function ConvertTo-FlexiblePattern {
            param([Parameter(Mandatory)][string]$Text)
            return ([regex]::Escape($Text) -replace '\\ ', '\s+')
        }
        $script:skills = @(
            Read-RepoText 'plugins/code-review/skills/cr/SKILL.md'
            Read-RepoText 'plugins/design-review/skills/dr/SKILL.md'
        )
    }

    It 'test:SimpleReview.ProportionalSecurity requires a complete threat and keeps hardening advisory' {
        $fixture = Read-PolicyFixture 'concrete-threat'
        foreach ($skill in $script:skills) {
            foreach ($field in $fixture.requiredFields) {
                $skill | Should -Match (ConvertTo-FlexiblePattern $field.label)
            }
            $skill | Should -Match 'Missing any link'
            $skill | Should -Match 'optional hardening'
            $skill | Should -Match 'Only complete four-part paths enter report Findings'
        }
    }

    It 'presents simple and safer options without blocking on machinery alone' {
        $fixture = Read-PolicyFixture 'concrete-threat'
        foreach ($skill in $script:skills) {
            foreach ($label in $fixture.simpleVersusSaferLabels) {
                $skill | Should -Match (ConvertTo-FlexiblePattern $label)
            }
            $skill | Should -Match 'Do not block only because more defense in depth exists'
        }
    }

    It 'omits absent-boundary demands and permits findings when the boundary is introduced' {
        $fixture = Read-PolicyFixture 'absent-boundary'
        foreach ($skill in $script:skills) {
            foreach ($demand in $fixture.demands) {
                $skill | Should -Match (ConvertTo-FlexiblePattern $demand)
            }
            $skill | Should -Match 'unless the change introduces that boundary'
        }
        foreach ($field in @(
                'AttackerOrInput', 'ReachableCapability', 'AffectedAsset', 'PlausibleImpact'
            )) {
            [string]$fixture.introducedBoundary.$field | Should -Not -BeNullOrEmpty
        }
    }

    It 'retains mandatory prompt, publication, mutation, path, format, and verdict guards' {
        $fixture = Read-PolicyFixture 'retained-guard'
        foreach ($skill in $script:skills) {
            foreach ($pattern in $fixture.skillPatterns) {
                $skill | Should -Match (ConvertTo-FlexiblePattern $pattern)
            }
        }
    }
}
