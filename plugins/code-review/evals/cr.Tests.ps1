#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'cr structural evals' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..')).Path
        Import-Module (Join-Path $script:repoRoot 'tests/evals/EvalCommon.psm1') -Force

        $script:pluginRoot = Join-Path $script:repoRoot 'plugins/code-review'
        $manifestPath = Join-Path $script:pluginRoot 'plugin.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -Depth 50
        $script:entries = @($manifest.files)
        $script:reviewRun = Get-ReviewRunEvalContext -PluginRoot $script:pluginRoot -ReviewId cr
    }

    It 'covers orchestrator, subagents, and prompt artifacts with expected types' {
        $artifactSrcs = @($script:entries | Where-Object { [string]$_.src -match '\.(agent|prompt)\.md$' } | ForEach-Object { [string]$_.src })
        $artifactSrcs | Should -Contain 'agents/cr.agent.md'
        $artifactSrcs | Should -Contain 'agents/cr-security.agent.md'
        $artifactSrcs | Should -Contain 'agents/cr-correctness-reliability.agent.md'
        $artifactSrcs | Should -Contain 'agents/cr-architecture-patterns.agent.md'
        $artifactSrcs | Should -Contain 'agents/cr-performance.agent.md'
        $artifactSrcs | Should -Contain 'agents/cr-testing-evidence.agent.md'
        $artifactSrcs | Should -Contain 'agents/cr-maintainability-consistency.agent.md'
        $artifactSrcs | Should -Contain 'agents/cr-operability-observability.agent.md'
        $artifactSrcs | Should -Contain 'prompts/cr.prompt.md'

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

    It 'requires each helper referenced by the cr payload to exist and be declared in plugin.json' {
        # The orchestration moved from cr.agent.md into the cr skill, so the helper references live
        # wherever the workflow does; scan every markdown payload file rather than one artifact.
        $markdownSrcs = @($script:entries | Where-Object { [string]$_.src -match '\.md$' } | ForEach-Object { [string]$_.src })
        $referencedScripts = [System.Collections.Generic.List[string]]::new()
        foreach ($src in $markdownSrcs) {
            $path = Join-Path $script:pluginRoot ($src -replace '/', [System.IO.Path]::DirectorySeparatorChar)
            $body = Get-Content -LiteralPath $path -Raw
            foreach ($match in [regex]::Matches($body, '\.github/agents/scripts/(?<name>[A-Za-z][A-Za-z0-9._-]*\.ps1)')) {
                $referencedScripts.Add([string]$match.Groups['name'].Value)
            }
        }

        $referencedScripts = @($referencedScripts | Sort-Object -Unique)
        $referencedScripts.Count | Should -BeGreaterThan 0

        foreach ($scriptName in $referencedScripts) {
            $relativePath = "agents/scripts/$scriptName"
            $manifestEntries = @($script:entries | Where-Object { [string]$_.src -eq $relativePath })
            $manifestEntries.Count | Should -Be 1

            $resolved = Test-ReferencedFile -BasePath $script:pluginRoot -RelativePath $relativePath
            Test-Path -LiteralPath $resolved -PathType Leaf | Should -BeTrue
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

    It 'eval:ReviewReport.CR.WriterScope confines edits to the two computed temporary inputs' {
        Test-ReviewRunStructuralInvariant -Context $script:reviewRun -Invariant WriterScope | Should -BeTrue
    }

    It 'eval:ReviewReport.CR.FreezeBeforeDispatch requires freeze before independent dispatch and publish after it' {
        Test-ReviewRunStructuralInvariant -Context $script:reviewRun -Invariant FreezeBeforeDispatch | Should -BeTrue
    }

    It 'eval:ReviewReport.CR.IndependentDispatch forbids prior-result priming and suppression' {
        Test-ReviewRunStructuralInvariant -Context $script:reviewRun -Invariant IndependentDispatch | Should -BeTrue
    }

    It 'eval:ReviewReport.CR.CompleteDispatch requires every frozen task exactly once' {
        Test-ReviewRunStructuralInvariant -Context $script:reviewRun -Invariant CompleteDispatch | Should -BeTrue
    }

    It 'eval:ReviewReport.CR.NonzeroTaskPlan rejects zero-discovery runs' {
        Test-ReviewRunStructuralInvariant -Context $script:reviewRun -Invariant NonzeroTaskPlan | Should -BeTrue
    }

    It 'eval:ReviewReport.CR.RendererOwnedMarkdown forbids hand-built report layout' {
        Test-ReviewRunStructuralInvariant -Context $script:reviewRun -Invariant RendererOwnedMarkdown | Should -BeTrue
    }

    It 'eval:ReviewReport.CR.FixedPolicyAndRoot exposes no alternate schema policy or output root' {
        Test-ReviewRunStructuralInvariant -Context $script:reviewRun -Invariant FixedPolicyAndRoot | Should -BeTrue
    }

    It 'eval:ReviewReport.CR.DegradedArtifactPreservation surfaces exit 5 artifacts before failure propagation' {
        Test-ReviewRunStructuralInvariant -Context $script:reviewRun -Invariant DegradedArtifactPreservation | Should -BeTrue
    }

    It 'eval:ReviewReport.CR.BoundedRetry permits only corrected exit-4 retry and terminal exit-3 restart' {
        Test-ReviewRunStructuralInvariant -Context $script:reviewRun -Invariant BoundedRetry | Should -BeTrue
    }

    It 'proves the CR Fleet source, installed payload, registry, and marketplace stay aligned' {
        $manifest = Get-Content -LiteralPath (Join-Path $script:pluginRoot 'plugin.json') -Raw |
            ConvertFrom-Json -Depth 50
        Assert-FleetConsumerParity `
            -RepoRoot $script:repoRoot `
            -PluginRoot $script:pluginRoot `
            -Manifest $manifest `
            -PluginName 'code-review' `
            -RelativePath @(
            'skills/cr/SKILL.md',
            'skills/cr/assets/dispatch-guide.md',
            'skills/cr/scripts/FleetDispatch.psm1'
        ) `
            -FleetModuleDest 'skills/cr/scripts/FleetDispatch.psm1' |
            Should -BeTrue
    }

    It 'keeps CR Freeze and Fleet planning before calls while conserving frozen task authority' {
        $skill = Get-Content -LiteralPath (Join-Path $script:pluginRoot 'skills/cr/SKILL.md') -Raw
        $guide = Get-Content -LiteralPath (Join-Path $script:pluginRoot 'skills/cr/assets/dispatch-guide.md') -Raw

        $relations = @(
            @('Freeze exactly once', 'New-FleetDispatchPlan'),
            @('PreView', 'reviewer call'),
            @('Step-FleetDispatchRun', 'Complete-FleetDispatchRun'),
            @('Complete-FleetDispatchRun', 'Publish once')
        )
        foreach ($relation in $relations) {
            Assert-EvalMarkerOrder -Text $skill -BeforeMarker $relation[0] -AfterMarker $relation[1]
        }
        foreach ($marker in @($relations | ForEach-Object { $_ } | Sort-Object -Unique)) {
            $missingMarkerSkill = $skill.Replace($marker, '')
            {
                foreach ($relation in $relations) {
                    Assert-EvalMarkerOrder `
                        -Text $missingMarkerSkill `
                        -BeforeMarker $relation[0] `
                        -AfterMarker $relation[1]
                }
            } | Should -Throw
        }

        $skill | Should -Match '\.github/skills/cr/scripts/FleetDispatch\.psm1'
        $guide | Should -Not -Match '\.github/skills/(?:cr|dr)/scripts/FleetDispatch\.psm1'
        $guide | Should -Match 'selected Fleet ids to equal the frozen task ids exactly and uniquely'
        $guide | Should -Match 'Fleet planned count to equal the frozen count'
        $guide | Should -Match 'Do not add Fleet attendance to review-run schemas'
        $guide | Should -Match 'Publish, persistence, verified Summary and\s+Full reading'
    }
}
