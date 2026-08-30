#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'autopilot structural evals' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..')).Path
        Import-Module (Join-Path $script:repoRoot 'tests/evals/EvalCommon.psm1') -Force

        $pluginRoot = Join-Path $script:repoRoot 'plugins/autopilot'
        $manifestPath = Join-Path $pluginRoot 'plugin.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -Depth 50
        $agentEntries = @($manifest.files | Where-Object { [string]$_.src -eq 'agents/autopilot.agent.md' })
        $agentEntries.Count | Should -Be 1

        $script:artifactPath = Join-Path $pluginRoot 'agents/autopilot.agent.md'
        $script:destinationPath = [string]$agentEntries[0].dest
    }

    It 'validates agent frontmatter, required keys, and stem alignment' {
        $artifactType = Get-ArtifactType -DestinationPath $script:destinationPath
        $artifactType | Should -Be 'agent'

        $frontmatter = Get-PluginFrontmatter -Path $script:artifactPath
        Test-RequiredFrontmatter -ArtifactType 'agent' -Frontmatter $frontmatter -Path $script:artifactPath | Should -BeTrue
        [string]$frontmatter.name | Should -Be 'autopilot'
    }

    It 'requires agent body headings and non-empty non-heading content' {
        Test-BodySection -ArtifactType 'agent' -Path $script:artifactPath | Should -BeTrue
    }

    It 'resolves markdown links and design-note references when present' {
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

    It 'proves the autopilot Fleet source, installed payload, registry, and marketplace stay aligned' {
        $registry = Get-Content -LiteralPath (Join-Path $script:repoRoot 'registry.json') -Raw |
            ConvertFrom-Json -Depth 100
        $marketplace = Get-Content -LiteralPath (Join-Path $script:repoRoot '.github/plugin/marketplace.json') -Raw |
            ConvertFrom-Json -Depth 50

        foreach ($relative in @(
                'agents/autopilot.agent.md',
                'skills/autopilot/scripts/FleetDispatch.psm1'
            )) {
            $entries = @($manifest.files | Where-Object { [string]$_.dest -eq $relative })
            $entries.Count | Should -Be 1
            $source = Join-Path $pluginRoot ([string]$entries[0].src)
            $installed = Join-Path (Join-Path $script:repoRoot '.github') $relative
            (Get-FileHash -LiteralPath $installed -Algorithm SHA256).Hash |
                Should -Be (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
        }

        $catalog = @($registry.plugins | Where-Object { [string]$_.name -eq 'autopilot' })
        $catalog.Count | Should -Be 1
        [string]$catalog[0].version | Should -Be ([string]$manifest.version)
        $fleetCatalog = @($catalog[0].files | Where-Object {
                [string]$_.dest -eq 'skills/autopilot/scripts/FleetDispatch.psm1'
            })
        $fleetCatalog.Count | Should -Be 1
        [string]$fleetCatalog[0].sha256 | Should -Be (
            (Get-FileHash -LiteralPath (Join-Path $pluginRoot 'skills/autopilot/scripts/FleetDispatch.psm1') -Algorithm SHA256).Hash.ToLowerInvariant()
        )
        $market = @($marketplace.plugins | Where-Object { [string]$_.name -eq 'autopilot' })
        $market.Count | Should -Be 1
        [string]$market[0].version | Should -Be ([string]$manifest.version)
    }

    It 'keeps the autopilot plan before calls and conserves the four-role graph and boundaries' {
        $agent = Get-Content -LiteralPath (Join-Path $pluginRoot 'agents/autopilot.agent.md') -Raw

        $agent.IndexOf('Create the fleet only after', [System.StringComparison]::Ordinal) |
            Should -BeLessThan $agent.IndexOf('New-FleetDispatchPlan', [System.StringComparison]::Ordinal)
        $agent.IndexOf('Start-FleetDispatchRun', [System.StringComparison]::Ordinal) |
            Should -BeLessThan $agent.IndexOf('PreView', [System.StringComparison]::Ordinal)
        $agent.IndexOf('PreView', [System.StringComparison]::Ordinal) |
            Should -BeLessThan $agent.IndexOf('first native role call', [System.StringComparison]::Ordinal)
        $agent.IndexOf('Step-FleetDispatchRun', [System.StringComparison]::Ordinal) |
            Should -BeLessThan $agent.IndexOf('Complete-FleetDispatchRun', [System.StringComparison]::Ordinal)

        foreach ($id in @('ci-designer', 'ci-validator', 'ci-implementor', 'ci-judge')) {
            @([regex]::Matches($agent, ('(?m)^\|\s*`' + [regex]::Escape($id) + '`\s*\|'))).Count |
                Should -Be 1 -Because "$id must have one descriptor"
        }
        $agent | Should -Match 'Implementor owns the existing implementation, focused'
        $agent | Should -Match 'Judge owns item 17 and starts only after Implementor completes'
        $agent | Should -Match 'Commit, push, phase review, harvest, and final promotion remain authoritative outside'
        $agent | Should -Match 'adds no clone,\s+credential, worktree, container, promotion, review, or persistence mechanism'
    }
}
