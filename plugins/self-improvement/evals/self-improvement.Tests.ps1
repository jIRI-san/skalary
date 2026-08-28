#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'self-improvement structural evals' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..')).Path
        Import-Module (Join-Path $script:repoRoot 'tests/evals/EvalCommon.psm1') -Force

        $script:pluginRoot = Join-Path $script:repoRoot 'plugins/self-improvement'
        $script:manifest = Get-Content -LiteralPath (
            Join-Path $script:pluginRoot 'plugin.json'
        ) -Raw | ConvertFrom-Json -Depth 100
        $script:skills = @('pfb', 'si')
    }

    It 'test:LearningLoop.StructuralEvals validates both skills, installed links, and declared assets' {
        foreach ($skill in $script:skills) {
            $source = "skills/$skill/SKILL.md"
            $destination = $source
            @($script:manifest.files | Where-Object {
                    [string]$_.src -eq $source -and
                    [string]$_.dest -eq $destination
                }).Count | Should -Be 1

            $skillPath = Join-Path $script:pluginRoot $source
            Get-ArtifactType -DestinationPath $destination | Should -Be 'skill'
            $frontmatter = Get-PluginFrontmatter -Path $skillPath
            Test-RequiredFrontmatter -ArtifactType skill -Frontmatter $frontmatter `
                -Path $skillPath | Should -BeTrue
            [string]$frontmatter.name | Should -Be $skill
            [bool]::Parse([string]$frontmatter.'user-invocable') | Should -BeTrue
            Test-BodySection -ArtifactType skill -Path $skillPath | Should -BeTrue

            $raw = [System.IO.File]::ReadAllText($skillPath)
            foreach ($match in [regex]::Matches($raw, '\[[^\]]+\]\((?<target>[^)]+)\)')) {
                $resolved = Resolve-MarkdownLink -RepoRoot $script:repoRoot `
                    -ArtifactDestinationPath $destination `
                    -LinkTarget ([string]$match.Groups['target'].Value)
                if (-not [string]::IsNullOrWhiteSpace([string]$resolved)) {
                    Test-Path -LiteralPath $resolved | Should -BeTrue
                    $installedRoot = Join-Path $script:repoRoot '.github'
                    $installedRelative = [System.IO.Path]::GetRelativePath(
                        $installedRoot,
                        $resolved
                    ).Replace('\', '/')
                    $mapping = @(
                        $script:manifest.files |
                            Where-Object { [string]$_.dest -eq $installedRelative }
                    )
                    $mapping.Count | Should -Be 1
                    $pluginSource = Join-Path $script:pluginRoot ([string]$mapping[0].src)
                    Test-Path -LiteralPath $pluginSource -PathType Leaf | Should -BeTrue
                    (Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash |
                        Should -Be (Get-FileHash -LiteralPath $pluginSource -Algorithm SHA256).Hash
                }
            }
        }

        $declaredDestinations = @(
            $script:manifest.files |
                ForEach-Object { [string]$_.dest }
        )
        foreach ($required in @(
                'skills/pfb/assets/feedback-guide.md',
                'skills/pfb/assets/queue-guide.md',
                'skills/pfb/scripts/Update-FeedbackQueue.ps1',
                'skills/si/assets/harvest-guide.md',
                'skills/si/assets/propose-guide.md',
                'skills/si/scripts/Get-SiHarvest.ps1',
                'skills/si/scripts/Invoke-SiLifecycle.ps1',
                'skills/si/scripts/Invoke-SiProposalSync.ps1',
                'skills/si/scripts/Complete-SiProposal.ps1'
            )) {
            $declaredDestinations | Should -Contain $required
        }
    }
}
