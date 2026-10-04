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
        $script:planningProtocol = Read-RepoText `
            'plugins/create-implementation-plan/skills/cip/assets/decision-protocol.md'
        $script:ciSkill = Read-RepoText 'plugins/continue-implementation/skills/ci/SKILL.md'
        $script:autopilotSkill = Read-RepoText 'plugins/autopilot/skills/autopilot/SKILL.md'
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

    It 'test:ReviewQuality.Evidence requires concrete paths and disconfirmation before publishing candidates' {
        foreach ($skill in $script:skills) {
            $skill | Should -Match 'trigger|precondition'
            $skill | Should -Match 'evidence'
            $skill | Should -Match 'disconfirm'
            $skill | Should -Match 'guard'
            $skill | Should -Match 'static trace'
            $skill | Should -Match 'before any earlier findings, analysis, or verdict'
            $skill | Should -Match 'independent evidence trace'
            $skill | Should -Match 'technical defects, plan-intent alignment questions, and optional advice distinct'
        }
        $script:skills[1] | Should -Match 'selected operator\s+statement'
        $script:skills[1] | Should -Match 'exact draft section'
    }

    It 'test:ReviewQuality.LocalFit prefers current local contracts without excusing demonstrated failures' {
        foreach ($text in @($script:skills) + @(
                $script:planningProtocol, $script:ciSkill, $script:autopilotSkill
            )) {
            $text | Should -Match 'contracts, helpers, tests, configuration'
            $text | Should -Match 'legacy'
            $text | Should -Match 'precedent'
        }
        $script:planningProtocol | Should -Match 'Confirmed local choice beats generic preference'
        $script:skills[0] | Should -Match 'confirmed choices beat generic preference'
        $script:skills[1] | Should -Match 'confirmed choices beat generic preference'
        $script:ciSkill | Should -Match 'confirmed local choices beat generic'
    }

    It 'test:ReviewQuality.DocGrounding limits official lookup to named versioned uncertainties' {
        foreach ($text in @($script:skills) + @(
                $script:planningProtocol, $script:ciSkill, $script:autopilotSkill
            )) {
            $text | Should -Match 'official'
            $text | Should -Match 'version'
            $text | Should -Match 'named consequential uncertainty'
            $text | Should -Match 'public'
            $text | Should -Match 'untrusted read-only evidence'
            $text | Should -Match 'unavailable'
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
