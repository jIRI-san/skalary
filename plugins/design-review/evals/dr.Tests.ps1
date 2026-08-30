#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'dr structural evals' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..')).Path
        Import-Module (Join-Path $script:repoRoot 'tests/evals/EvalCommon.psm1') -Force

        $script:pluginRoot = Join-Path $script:repoRoot 'plugins/design-review'
        $manifestPath = Join-Path $script:pluginRoot 'plugin.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -Depth 50
        $script:entries = @($manifest.files)
        $script:reviewRun = Get-ReviewRunEvalContext -PluginRoot $script:pluginRoot -ReviewId dr
    }

    It 'covers orchestrator, subagents, and prompt artifacts with expected types' {
        $artifactSrcs = @($script:entries | Where-Object { [string]$_.src -match '\.(agent|prompt)\.md$' } | ForEach-Object { [string]$_.src })
        $artifactSrcs | Should -Contain 'agents/dr.agent.md'
        $artifactSrcs | Should -Contain 'agents/dr-security.agent.md'
        $artifactSrcs | Should -Contain 'agents/dr-correctness-reliability.agent.md'
        $artifactSrcs | Should -Contain 'agents/dr-architecture-patterns.agent.md'
        $artifactSrcs | Should -Contain 'agents/dr-performance.agent.md'
        $artifactSrcs | Should -Contain 'agents/dr-testing-evidence.agent.md'
        $artifactSrcs | Should -Contain 'agents/dr-maintainability-consistency.agent.md'
        $artifactSrcs | Should -Contain 'agents/dr-operability-observability.agent.md'
        $artifactSrcs | Should -Contain 'prompts/dr.prompt.md'

        foreach ($entry in @($script:entries | Where-Object { [string]$_.src -match '\.(agent|prompt)\.md$' })) {
            $src = [string]$entry.src
            $dest = [string]$entry.dest
            $path = Join-Path $script:pluginRoot ($src -replace '/', [System.IO.Path]::DirectorySeparatorChar)

            $artifactType = Get-ArtifactType -DestinationPath $dest
            if ($src.EndsWith('.agent.md', [System.StringComparison]::OrdinalIgnoreCase)) {
                $artifactType | Should -Be 'agent'
            }
            elseif ($src.EndsWith('.prompt.md', [System.StringComparison]::OrdinalIgnoreCase)) {
                $artifactType | Should -Be 'prompt'
            }

            $frontmatter = Get-PluginFrontmatter -Path $path
            Test-RequiredFrontmatter -ArtifactType $artifactType -Frontmatter $frontmatter -Path $path | Should -BeTrue

            $expectedName = if ($artifactType -eq 'agent') {
                [System.IO.Path]::GetFileName($src) -replace '\.agent\.md$', ''
            }
            else {
                [System.IO.Path]::GetFileName($src) -replace '\.prompt\.md$', ''
            }
            [string]$frontmatter.name | Should -Be $expectedName
            Test-BodySection -ArtifactType $artifactType -Path $path | Should -BeTrue
        }
    }

    It 'resolves markdown links across the bundle when link targets are real repo paths' {
        $markdownEntries = @($script:entries | Where-Object { [string]$_.src -match '\.(agent|prompt)\.md$' })
        $resolvedDesignNotePaths = [System.Collections.Generic.List[string]]::new()
        foreach ($entry in $markdownEntries) {
            $path = Join-Path $script:pluginRoot (([string]$entry.src) -replace '/', [System.IO.Path]::DirectorySeparatorChar)
            $raw = Get-Content -LiteralPath $path -Raw
            $linkMatches = [regex]::Matches($raw, '\[[^\]]+\]\((?<target>[^)]+)\)')

            foreach ($match in $linkMatches) {
                $target = [string]$match.Groups['target'].Value
                if ($target -match '^src/path/') {
                    continue
                }

                $resolved = Resolve-MarkdownLink -RepoRoot $script:repoRoot -ArtifactDestinationPath ([string]$entry.dest) -LinkTarget $target
                if (-not [string]::IsNullOrWhiteSpace([string]$resolved)) {
                    Test-Path -LiteralPath $resolved -PathType Leaf | Should -BeTrue
                }
            }

            $designNoteMatches = [regex]::Matches($raw, '(?<path>docs/design-notes/[A-Za-z0-9._\-/]+\.md)')
            foreach ($designNoteMatch in $designNoteMatches) {
                $designNotePath = [string]$designNoteMatch.Groups['path'].Value
                $resolved = Resolve-MarkdownLink -RepoRoot $script:repoRoot -ArtifactDestinationPath ([string]$entry.dest) -LinkTarget ('/' + $designNotePath)
                Test-Path -LiteralPath $resolved -PathType Leaf | Should -BeTrue
                $resolvedDesignNotePaths.Add(([string]$resolved).Replace('\', '/'))
            }
        }

        @($resolvedDesignNotePaths | Sort-Object -Unique).Count | Should -BeGreaterThan 0
    }

    It 'eval:ReviewReport.DR.WriterScope confines edits to the two computed temporary inputs' {
        Test-ReviewRunStructuralInvariant -Context $script:reviewRun -Invariant WriterScope | Should -BeTrue
    }

    It 'eval:ReviewReport.DR.FreezeBeforeDispatch requires freeze before independent dispatch and publish after it' {
        Test-ReviewRunStructuralInvariant -Context $script:reviewRun -Invariant FreezeBeforeDispatch | Should -BeTrue
    }

    It 'eval:ReviewReport.DR.IndependentDispatch forbids prior-result priming and suppression' {
        Test-ReviewRunStructuralInvariant -Context $script:reviewRun -Invariant IndependentDispatch | Should -BeTrue
    }

    It 'eval:ReviewReport.DR.CompleteDispatch requires every frozen task exactly once' {
        Test-ReviewRunStructuralInvariant -Context $script:reviewRun -Invariant CompleteDispatch | Should -BeTrue
    }

    It 'eval:ReviewReport.DR.NonzeroTaskPlan rejects zero-discovery runs' {
        Test-ReviewRunStructuralInvariant -Context $script:reviewRun -Invariant NonzeroTaskPlan | Should -BeTrue
    }

    It 'eval:ReviewReport.DR.RendererOwnedMarkdown forbids hand-built report layout' {
        Test-ReviewRunStructuralInvariant -Context $script:reviewRun -Invariant RendererOwnedMarkdown | Should -BeTrue
    }

    It 'eval:ReviewReport.DR.FixedPolicyAndRoot exposes no alternate schema policy or output root' {
        Test-ReviewRunStructuralInvariant -Context $script:reviewRun -Invariant FixedPolicyAndRoot | Should -BeTrue
    }

    It 'eval:ReviewReport.DR.DegradedArtifactPreservation surfaces exit 5 artifacts before failure propagation' {
        Test-ReviewRunStructuralInvariant -Context $script:reviewRun -Invariant DegradedArtifactPreservation | Should -BeTrue
    }

    It 'eval:ReviewReport.DR.BoundedRetry permits only corrected exit-4 retry and terminal exit-3 restart' {
        Test-ReviewRunStructuralInvariant -Context $script:reviewRun -Invariant BoundedRetry | Should -BeTrue
    }

    It 'proves the DR Fleet source, installed payload, registry, and marketplace stay aligned' {
        $manifest = Get-Content -LiteralPath (Join-Path $script:pluginRoot 'plugin.json') -Raw |
            ConvertFrom-Json -Depth 50
        $registry = Get-Content -LiteralPath (Join-Path $script:repoRoot 'registry.json') -Raw |
            ConvertFrom-Json -Depth 100
        $marketplace = Get-Content -LiteralPath (Join-Path $script:repoRoot '.github/plugin/marketplace.json') -Raw |
            ConvertFrom-Json -Depth 50

        foreach ($relative in @(
                'skills/dr/SKILL.md',
                'skills/dr/assets/dispatch-guide.md',
                'skills/dr/scripts/FleetDispatch.psm1'
            )) {
            $entries = @($manifest.files | Where-Object { [string]$_.dest -eq $relative })
            $entries.Count | Should -Be 1
            $source = Join-Path $script:pluginRoot ([string]$entries[0].src)
            $installed = Join-Path (Join-Path $script:repoRoot '.github') $relative
            (Get-FileHash -LiteralPath $installed -Algorithm SHA256).Hash |
                Should -Be (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
        }

        $catalog = @($registry.plugins | Where-Object { [string]$_.name -eq 'design-review' })
        $catalog.Count | Should -Be 1
        [string]$catalog[0].version | Should -Be ([string]$manifest.version)
        $fleetCatalog = @($catalog[0].files | Where-Object { [string]$_.dest -eq 'skills/dr/scripts/FleetDispatch.psm1' })
        $fleetCatalog.Count | Should -Be 1
        [string]$fleetCatalog[0].sha256 | Should -Be (
            (Get-FileHash -LiteralPath (Join-Path $script:pluginRoot 'skills/dr/scripts/FleetDispatch.psm1') -Algorithm SHA256).Hash.ToLowerInvariant()
        )
        $market = @($marketplace.plugins | Where-Object { [string]$_.name -eq 'design-review' })
        $market.Count | Should -Be 1
        [string]$market[0].version | Should -Be ([string]$manifest.version)
    }

    It 'keeps DR Freeze and Fleet planning before calls while conserving frozen task authority' {
        $skill = Get-Content -LiteralPath (Join-Path $script:pluginRoot 'skills/dr/SKILL.md') -Raw
        $guide = Get-Content -LiteralPath (Join-Path $script:pluginRoot 'skills/dr/assets/dispatch-guide.md') -Raw

        $skill.IndexOf('Freeze exactly once', [System.StringComparison]::Ordinal) |
            Should -BeLessThan $skill.IndexOf('New-FleetDispatchPlan', [System.StringComparison]::Ordinal)
        $skill.IndexOf('PreView', [System.StringComparison]::Ordinal) |
            Should -BeLessThan $skill.IndexOf('reviewer call', [System.StringComparison]::Ordinal)
        $skill.IndexOf('Step-FleetDispatchRun', [System.StringComparison]::Ordinal) |
            Should -BeLessThan $skill.IndexOf('Complete-FleetDispatchRun', [System.StringComparison]::Ordinal)
        $skill.IndexOf('Complete-FleetDispatchRun', [System.StringComparison]::Ordinal) |
            Should -BeLessThan $skill.IndexOf('Publish once', [System.StringComparison]::Ordinal)

        $skill | Should -Match '\.github/skills/dr/scripts/FleetDispatch\.psm1'
        $guide | Should -Not -Match '\.github/skills/(?:cr|dr)/scripts/FleetDispatch\.psm1'
        $guide | Should -Match 'selected Fleet ids to equal the frozen task ids exactly and uniquely'
        $guide | Should -Match 'Fleet planned count to equal the frozen count'
        $guide | Should -Match 'Do not add Fleet attendance to review-run schemas'
        $guide | Should -Match 'Publish, persistence, verified Summary and\s+Full reading'
    }
}
