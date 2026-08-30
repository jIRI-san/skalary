#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'cip structural evals' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..')).Path
        Import-Module (Join-Path $script:repoRoot 'tests/evals/EvalCommon.psm1') -Force

        $pluginRoot = Join-Path $script:repoRoot 'plugins/create-implementation-plan'
        $manifestPath = Join-Path $pluginRoot 'plugin.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -Depth 50

        $skillEntries = @($manifest.files | Where-Object { [string]$_.src -eq 'skills/cip/SKILL.md' })
        $skillEntries.Count | Should -Be 1
        $script:skillEntry = $skillEntries[0]

        # The same source template is also installed under skills/cep/, so `src` alone is no
        # longer unique — the cip install is identified by its destination.
        $assetEntries = @($manifest.files | Where-Object { [string]$_.dest -eq 'skills/cip/assets/plan-template.md' })
        $assetEntries.Count | Should -Be 1
        $script:assetEntry = $assetEntries[0]

        $script:artifactPath = Join-Path $pluginRoot 'skills/cip/SKILL.md'
        $script:assetPath = Join-Path $pluginRoot 'skills/cip/assets/plan-template.md'
        $script:destinationPath = [string]$script:skillEntry.dest
    }

    It 'validates skill frontmatter, required keys, and folder-name alignment' {
        $artifactType = Get-ArtifactType -DestinationPath $script:destinationPath
        $artifactType | Should -Be 'skill'

        $frontmatter = Get-PluginFrontmatter -Path $script:artifactPath
        Test-RequiredFrontmatter -ArtifactType 'skill' -Frontmatter $frontmatter -Path $script:artifactPath | Should -BeTrue
        [string]$frontmatter.name | Should -Be 'cip'
    }

    It 'requires skill body headings and step procedure content' {
        Test-BodySection -ArtifactType 'skill' -Path $script:artifactPath | Should -BeTrue
    }

    It 'requires known referenced asset to exist in plugin payload' {
        $resolved = Test-ReferencedFile -BasePath $pluginRoot -RelativePath ([string]$script:assetEntry.src)
        [string]$resolved.Replace('\', '/') | Should -Match '/plugins/create-implementation-plan/skills/cip/assets/plan-template.md$'
        Test-Path -LiteralPath $script:assetPath -PathType Leaf | Should -BeTrue
    }

    It 'resolves internal markdown links from simulated install path' {
        $raw = Get-Content -LiteralPath $script:artifactPath -Raw
        $linkMatches = [regex]::Matches($raw, '\[[^\]]+\]\((?<target>[^)]+)\)')

        foreach ($match in $linkMatches) {
            $target = [string]$match.Groups['target'].Value
            $resolved = Resolve-MarkdownLink -RepoRoot $script:repoRoot -ArtifactDestinationPath $script:destinationPath -LinkTarget $target
            if (-not [string]::IsNullOrWhiteSpace([string]$resolved)) {
                Test-Path -LiteralPath $resolved -PathType Leaf | Should -BeTrue
            }
        }
    }

    It 'proves the CIP Fleet source, installed payload, registry, and marketplace stay aligned' {
        $manifest = Get-Content -LiteralPath (Join-Path $pluginRoot 'plugin.json') -Raw |
            ConvertFrom-Json -Depth 50
        Assert-FleetConsumerParity `
            -RepoRoot $script:repoRoot `
            -PluginRoot $pluginRoot `
            -Manifest $manifest `
            -PluginName 'create-implementation-plan' `
            -RelativePath @(
            'skills/cip/SKILL.md',
            'skills/cip/assets/fleet-dispatch-guide.md',
            'skills/cip/scripts/FleetDispatch.psm1'
        ) `
            -FleetModuleDest 'skills/cip/scripts/FleetDispatch.psm1' |
            Should -BeTrue
    }

    It 'keeps the CIP plan before native calls and conserves each declared role' {
        $skill = Get-Content -LiteralPath (Join-Path $pluginRoot 'skills/cip/SKILL.md') -Raw
        $guide = Get-Content -LiteralPath (Join-Path $pluginRoot 'skills/cip/assets/fleet-dispatch-guide.md') -Raw

        $skillRelations = @(, @('After the intent checkpoint is confirmed', 'Planning-role fleet dispatch'))
        $guideRelations = @(
            @('New-FleetDispatchPlan', 'Start-FleetDispatchRun'),
            @('PreView', 'Invoke only'),
            @('Step-FleetDispatchRun', 'Complete-FleetDispatchRun'),
            @('Complete-FleetDispatchRun', 'FinalView')
        )
        foreach ($relation in $skillRelations) {
            Assert-EvalMarkerOrder -Text $skill -BeforeMarker $relation[0] -AfterMarker $relation[1]
        }
        foreach ($relation in $guideRelations) {
            Assert-EvalMarkerOrder -Text $guide -BeforeMarker $relation[0] -AfterMarker $relation[1]
        }
        foreach ($marker in @($skillRelations | ForEach-Object { $_ } | Sort-Object -Unique)) {
            $missingMarkerSkill = $skill.Replace($marker, '')
            {
                foreach ($relation in $skillRelations) {
                    Assert-EvalMarkerOrder `
                        -Text $missingMarkerSkill `
                        -BeforeMarker $relation[0] `
                        -AfterMarker $relation[1]
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

        foreach ($id in @('cip-designer', 'cip-requirements-validator', 'cip-judge')) {
            @([regex]::Matches($guide, ('(?m)^\|\s*`' + [regex]::Escape($id) + '`\s*\|'))).Count |
                Should -Be 1 -Because "$id must have one descriptor"
        }
        $guide | Should -Match 'Judge completed'
        $guide | Should -Match 'explicit-throttle retry'
        $guide | Should -Match 'does not replace a role prompt, change its tool set, or select another model'
        $guide | Should -Match 'Capture writer'
    }

    It 'keeps the CEP epic-review handoff installed but explicitly inactive' {
        $manifest = Get-Content -LiteralPath (Join-Path $pluginRoot 'plugin.json') -Raw |
            ConvertFrom-Json -Depth 50
        $source = Join-Path $pluginRoot 'skills/cep/assets/decomposition-guide.md'
        $installed = Join-Path $script:repoRoot '.github/skills/cep/assets/decomposition-guide.md'
        $guide = Get-Content -LiteralPath $source -Raw

        (Get-FileHash -LiteralPath $installed -Algorithm SHA256).Hash |
            Should -Be (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
        @($manifest.files | Where-Object {
                [string]$_.dest -eq 'skills/cep/scripts/FleetDispatch.psm1'
            }).Count | Should -Be 0
        Test-Path -LiteralPath (Join-Path $script:repoRoot '.github/skills/cep/scripts/FleetDispatch.psm1') |
            Should -BeFalse
        $guide | Should -Match 'Epic-review extension handoff \(inactive\)'
        $guide | Should -Match 'activates\s+nothing in the current `/cep`'
        $guide | Should -Match '25aa23 epic-coherency-review'
        $guide | Should -Match 'remains the owner'
        $guide | Should -Not -Match 'Import\s+.*FleetDispatch\.psm1'
    }
}
