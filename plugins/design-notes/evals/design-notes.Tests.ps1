#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'design-notes structural evals' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..')).Path
        Import-Module (Join-Path $script:repoRoot 'tests/evals/EvalCommon.psm1') -Force

        $script:pluginRoot = Join-Path $script:repoRoot 'plugins/design-notes'
        $manifestPath = Join-Path $script:pluginRoot 'plugin.json'
        $script:manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -Depth 50
    }

    It 'validates the design-notes skill: frontmatter, name, body, and link resolution' {
        $src = 'skills/design-notes/SKILL.md'
        $entries = @($script:manifest.files | Where-Object { [string]$_.src -eq $src })
        $entries.Count | Should -Be 1
        $destinationPath = [string]$entries[0].dest
        $artifactPath = Join-Path $script:pluginRoot $src

        Get-ArtifactType -DestinationPath $destinationPath | Should -Be 'skill'

        $frontmatter = Get-PluginFrontmatter -Path $artifactPath
        Test-RequiredFrontmatter -ArtifactType 'skill' -Frontmatter $frontmatter -Path $artifactPath | Should -BeTrue
        [string]$frontmatter.name | Should -Be 'design-notes'

        Test-BodySection -ArtifactType 'skill' -Path $artifactPath | Should -BeTrue

        $raw = Get-Content -LiteralPath $artifactPath -Raw
        $linkMatches = [regex]::Matches($raw, '\[[^\]]+\]\((?<target>[^)]+)\)')
        @($linkMatches).Count | Should -BeGreaterThan 0

        $resolvedTargets = [System.Collections.Generic.List[string]]::new()
        foreach ($match in $linkMatches) {
            $target = [string]$match.Groups['target'].Value
            $resolved = Resolve-MarkdownLink -RepoRoot $script:repoRoot -ArtifactDestinationPath $destinationPath -LinkTarget $target
            if (-not [string]::IsNullOrWhiteSpace([string]$resolved)) {
                Test-Path -LiteralPath $resolved -PathType Leaf | Should -BeTrue
                $resolvedTargets.Add(([string]$resolved).Replace('\', '/'))
            }
        }

        # The skill delegates scaffold writes to the installed owner and still links the governance index.
        $raw | Should -Match ([regex]::Escape('.github/skills/design-notes/scripts/Initialize-DesignNotes.ps1'))
        @(
            $script:manifest.files |
                Where-Object {
                    [string]$_.src -ceq 'skills/design-notes/scripts/Initialize-DesignNotes.ps1' -and
                    [string]$_.dest -ceq 'skills/design-notes/scripts/Initialize-DesignNotes.ps1'
                }
        ).Count | Should -Be 1
        @($resolvedTargets | Where-Object { $_ -match '/docs/design-notes/' }).Count | Should -BeGreaterThan 0
    }

    It 'validates each shortcut prompt: frontmatter, name slug, body, and delegation to the skill' -TestCases @(
        @{ Src = 'prompts/design-notes.prompt.md'; Slug = 'design-notes' }
        @{ Src = 'prompts/cdn.prompt.md'; Slug = 'cdn' }
        @{ Src = 'prompts/udn.prompt.md'; Slug = 'udn' }
    ) {
        param($Src, $Slug)

        $entries = @($script:manifest.files | Where-Object { [string]$_.src -eq $Src })
        $entries.Count | Should -Be 1
        $destinationPath = [string]$entries[0].dest
        $artifactPath = Join-Path $script:pluginRoot $Src

        Get-ArtifactType -DestinationPath $destinationPath | Should -Be 'prompt'

        $frontmatter = Get-PluginFrontmatter -Path $artifactPath
        Test-RequiredFrontmatter -ArtifactType 'prompt' -Frontmatter $frontmatter -Path $artifactPath | Should -BeTrue
        [string]$frontmatter.name | Should -Be $Slug

        Test-BodySection -ArtifactType 'prompt' -Path $artifactPath | Should -BeTrue

        $raw = Get-Content -LiteralPath $artifactPath -Raw
        $linkMatches = [regex]::Matches($raw, '\[[^\]]+\]\((?<target>[^)]+)\)')
        @($linkMatches).Count | Should -BeGreaterThan 0

        $resolvedTargets = [System.Collections.Generic.List[string]]::new()
        foreach ($match in $linkMatches) {
            $target = [string]$match.Groups['target'].Value
            $resolved = Resolve-MarkdownLink -RepoRoot $script:repoRoot -ArtifactDestinationPath $destinationPath -LinkTarget $target
            if (-not [string]::IsNullOrWhiteSpace([string]$resolved)) {
                Test-Path -LiteralPath $resolved -PathType Leaf | Should -BeTrue
                $resolvedTargets.Add(([string]$resolved).Replace('\', '/'))
            }
        }

        # Each shortcut prompt must delegate to the design-notes skill.
        @($resolvedTargets | Where-Object { $_ -match '/skills/design-notes/SKILL\.md$' }).Count | Should -BeGreaterThan 0
    }

    It 'ships both bootstrap template assets as skill payload files' -TestCases @(
        @{ Src = 'skills/design-notes/assets/templates/design-notes-index.template.md' }
        @{ Src = 'skills/design-notes/assets/templates/design-note-writing-style.template.md' }
    ) {
        param($Src)

        $entries = @($script:manifest.files | Where-Object { [string]$_.src -eq $Src })
        $entries.Count | Should -Be 1

        $resolved = Test-ReferencedFile -BasePath $script:pluginRoot -RelativePath $Src
        [string]$resolved.Replace('\', '/') | Should -Match ([regex]::Escape($Src) + '$')
        Test-Path -LiteralPath (Join-Path $script:pluginRoot $Src) -PathType Leaf | Should -BeTrue

        $initializer = Get-Content -LiteralPath (
            Join-Path $script:pluginRoot 'skills/design-notes/scripts/Initialize-DesignNotes.ps1'
        ) -Raw
        $initializer | Should -Match ([regex]::Escape([System.IO.Path]::GetFileName($Src)))
    }
}
