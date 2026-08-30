#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'ci structural evals' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..')).Path
        Import-Module (Join-Path $script:repoRoot 'tests/evals/EvalCommon.psm1') -Force

        $pluginRoot = Join-Path $script:repoRoot 'plugins/continue-implementation'
        $manifestPath = Join-Path $pluginRoot 'plugin.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -Depth 50
        $skillEntries = @($manifest.files | Where-Object { [string]$_.src -eq 'skills/ci/SKILL.md' })
        $skillEntries.Count | Should -Be 1

        $script:artifactPath = Join-Path $pluginRoot 'skills/ci/SKILL.md'
        $script:destinationPath = [string]$skillEntries[0].dest
    }

    It 'validates skill frontmatter, required keys, and folder-name alignment' {
        $artifactType = Get-ArtifactType -DestinationPath $script:destinationPath
        $artifactType | Should -Be 'skill'

        $frontmatter = Get-PluginFrontmatter -Path $script:artifactPath
        Test-RequiredFrontmatter -ArtifactType 'skill' -Frontmatter $frontmatter -Path $script:artifactPath | Should -BeTrue
        [string]$frontmatter.name | Should -Be 'ci'
    }

    It 'requires skill body headings and step procedure content' {
        Test-BodySection -ArtifactType 'skill' -Path $script:artifactPath | Should -BeTrue
    }

    It 'resolves markdown links from the simulated install base' {
        $raw = Get-Content -LiteralPath $script:artifactPath -Raw
        $linkMatches = [regex]::Matches($raw, '\[[^\]]+\]\((?<target>[^)]+)\)')

        $resolvedTargets = [System.Collections.Generic.List[string]]::new()
        foreach ($match in $linkMatches) {
            $target = [string]$match.Groups['target'].Value
            $resolved = Resolve-MarkdownLink -RepoRoot $script:repoRoot -ArtifactDestinationPath $script:destinationPath -LinkTarget $target
            if (-not [string]::IsNullOrWhiteSpace([string]$resolved)) {
                Test-Path -LiteralPath $resolved -PathType Leaf | Should -BeTrue
                $resolvedTargets.Add(([string]$resolved).Replace('\', '/'))
            }
        }

        $designNoteLinksInArtifact = @($linkMatches | Where-Object { [string]$_.Groups['target'].Value -match 'docs/design-notes/' }).Count
        if ($designNoteLinksInArtifact -gt 0) {
            @($resolvedTargets | Where-Object { $_ -match '/docs/design-notes/' }).Count | Should -BeGreaterThan 0
        }
    }

    It 'proves the CI Fleet source, installed payload, registry, and marketplace stay aligned' {
        Assert-FleetConsumerParity `
            -RepoRoot $script:repoRoot `
            -PluginRoot $pluginRoot `
            -Manifest $manifest `
            -PluginName 'continue-implementation' `
            -RelativePath @(
            'skills/ci/SKILL.md',
            'skills/ci/assets/fleet-dispatch-guide.md',
            'skills/ci/scripts/FleetDispatch.psm1'
        ) `
            -FleetModuleDest 'skills/ci/scripts/FleetDispatch.psm1' |
            Should -BeTrue
    }

    It 'keeps the in-session CI plan before calls and conserves the four-role graph' {
        $skill = Get-Content -LiteralPath (Join-Path $pluginRoot 'skills/ci/SKILL.md') -Raw
        $guide = Get-Content -LiteralPath (Join-Path $pluginRoot 'skills/ci/assets/fleet-dispatch-guide.md') -Raw

        $skillRelations = @(, @('phase admission', 'Implementation-role fleet dispatch'))
        $guideRelations = @(
            @('New-FleetDispatchPlan', 'Start-FleetDispatchRun'),
            @('PreView', 'Invoke only'),
            @('Step-FleetDispatchRun', 'Complete-FleetDispatchRun')
        )
        foreach ($relation in $skillRelations) {
            Assert-EvalMarkerOrder `
                -Text $skill `
                -BeforeMarker $relation[0] `
                -AfterMarker $relation[1] `
                -Comparison OrdinalIgnoreCase
        }
        foreach ($relation in $guideRelations) {
            Assert-EvalMarkerOrder -Text $guide -BeforeMarker $relation[0] -AfterMarker $relation[1]
        }
        foreach ($marker in @($skillRelations | ForEach-Object { $_ } | Sort-Object -Unique)) {
            $missingMarkerSkill = $skill.Replace($marker, '', [System.StringComparison]::OrdinalIgnoreCase)
            {
                foreach ($relation in $skillRelations) {
                    Assert-EvalMarkerOrder `
                        -Text $missingMarkerSkill `
                        -BeforeMarker $relation[0] `
                        -AfterMarker $relation[1] `
                        -Comparison OrdinalIgnoreCase
                }
            } | Should -Throw
        }
        foreach ($marker in @($guideRelations | ForEach-Object { $_ } | Sort-Object -Unique)) {
            $missingMarkerGuide = $guide.Replace($marker, '')
            {
                foreach ($relation in $guideRelations) {
                    Assert-EvalMarkerOrder `
                        -Text $missingMarkerGuide `
                        -BeforeMarker $relation[0] `
                        -AfterMarker $relation[1]
                }
            } | Should -Throw
        }

        foreach ($id in @('ci-designer', 'ci-validator', 'ci-implementor', 'ci-judge')) {
            @([regex]::Matches($guide, ('(?m)^\|\s*`' + [regex]::Escape($id) + '`\s*\|'))).Count |
                Should -Be 1 -Because "$id must have one descriptor"
        }
        $guide | Should -Match 'Implementor runs the existing edit, focused build/test, formatting, design-note, and fix loop only'
        $guide | Should -Match 'Judge validates acceptance only after Implementor completes'
        $guide | Should -Match 'Commit and phase promotion remain outside dispatch'
        $guide | Should -Match 'adds no clone,\s+credential,\s+worktree,\s+container'
        $guide | Should -Match 'record attendance\s+through the existing Capture path'
        $guide | Should -Match 'Capture only closed task outcomes and counts'
        $guide | Should -Match 'other host diagnostics into model-facing workflow context'
        $skill | Should -Match 'Do not create an implementation-role fleet in `/ci` on this\s+path'
    }
}
