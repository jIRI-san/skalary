#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'plugin-manager structural evals' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..')).Path
        Import-Module (Join-Path $script:repoRoot 'tests/evals/EvalCommon.psm1') -Force

        $script:pluginRoot = Join-Path $script:repoRoot 'plugins/plugin-manager'
        $script:manifest = Get-Content -LiteralPath (Join-Path $script:pluginRoot 'plugin.json') -Raw | ConvertFrom-Json -Depth 50
        $script:registry = Get-Content -LiteralPath (Join-Path $script:repoRoot 'registry.json') -Raw | ConvertFrom-Json -Depth 50
        $script:skills = @('install-plugin', 'uninstall-plugin', 'list-plugins', 'update-plugin')
    }

    It 'test:PluginManager.StructuralEvals validates each skill frontmatter, required keys, body, and links' {
        foreach ($skill in $script:skills) {
            $skillPath = Join-Path $script:pluginRoot "skills/$skill/SKILL.md"
            Test-Path -LiteralPath $skillPath -PathType Leaf | Should -BeTrue

            $dest = "skills/$skill/SKILL.md"
            (Get-ArtifactType -DestinationPath $dest) | Should -Be 'skill'

            $frontmatter = Get-PluginFrontmatter -Path $skillPath
            Test-RequiredFrontmatter -ArtifactType 'skill' -Frontmatter $frontmatter -Path $skillPath | Should -BeTrue
            [string]$frontmatter.name | Should -Be $skill
            [bool]$frontmatter.'user-invocable' | Should -BeTrue

            Test-BodySection -ArtifactType 'skill' -Path $skillPath | Should -BeTrue

            $raw = Get-Content -LiteralPath $skillPath -Raw
            foreach ($m in [regex]::Matches($raw, '\[[^\]]+\]\((?<target>[^)]+)\)')) {
                $resolved = Resolve-MarkdownLink -RepoRoot $script:repoRoot -ArtifactDestinationPath $dest -LinkTarget ([string]$m.Groups['target'].Value)
                if (-not [string]::IsNullOrWhiteSpace([string]$resolved)) {
                    Test-Path -LiteralPath $resolved -PathType Leaf | Should -BeTrue
                }
            }
        }
    }

    It 'test:PluginManager.Manifest registers all skills + bundled scripts incl _Common.ps1 with author/license' {
        $destPaths = @($script:manifest.files | ForEach-Object { [string]$_.dest })
        foreach ($skill in $script:skills) {
            $destPaths | Should -Contain "skills/$skill/SKILL.md"
            $destPaths | Should -Contain "skills/$skill/scripts/_Common.ps1"
        }
        [string]$script:manifest.name | Should -Be 'plugin-manager'
        [string]$script:manifest.author | Should -Not -BeNullOrEmpty
        [string]$script:manifest.license | Should -Not -BeNullOrEmpty
    }

    It 'test:PluginManager.Skills invokes each bundled script by installed path with -RepoRoot .' {
        $entryScript = @{
            'install-plugin'   = '.github/skills/install-plugin/scripts/Install-Plugin.ps1'
            'uninstall-plugin' = '.github/skills/uninstall-plugin/scripts/Remove-Plugin.ps1'
            'list-plugins'     = '.github/skills/list-plugins/scripts/Get-Plugin.ps1'
            'update-plugin'    = '.github/skills/update-plugin/scripts/Update-Plugin.ps1'
        }
        foreach ($skill in $script:skills) {
            $raw = Get-Content -LiteralPath (Join-Path $script:pluginRoot "skills/$skill/SKILL.md") -Raw
            $raw | Should -Match ([regex]::Escape($entryScript[$skill]))
            $raw | Should -Match '-RepoRoot \.'
            # Direct invocation only — never wrapped in `pwsh -File` (breaks auto-approval prefix match).
            $raw | Should -Not -Match 'pwsh\s+-NoProfile\s+-File'
        }
    }

    It 'test:PluginManager.BundlePresence ships _Common.ps1 in registry and the installed .github tree' {
        $pm = @($script:registry.plugins | Where-Object { [string]$_.name -eq 'plugin-manager' })
        $pm.Count | Should -Be 1
        $regDests = @($pm[0].files | ForEach-Object { [string]$_.dest })
        foreach ($skill in $script:skills) {
            $regDests | Should -Contain "skills/$skill/scripts/_Common.ps1"
            Test-Path -LiteralPath (Join-Path $script:repoRoot ".github/skills/$skill/scripts/_Common.ps1") -PathType Leaf | Should -BeTrue
        }
    }

    It 'test:PluginManager.UninstallGuard documents the dependent guard and self-removal warning' {
        $raw = Get-Content -LiteralPath (Join-Path $script:pluginRoot 'skills/uninstall-plugin/SKILL.md') -Raw
        $raw | Should -Match 'dependent'
        $raw | Should -Match 'Self-removal'
        $raw | Should -Match 'Set-ScriptApproval\.ps1 -Name <name> -RepoRoot \. -Remove'
    }

    It 'test:PluginManager.ListScope lists available and installed via Get-Plugin and Find-Plugin' {
        $raw = Get-Content -LiteralPath (Join-Path $script:pluginRoot 'skills/list-plugins/SKILL.md') -Raw
        $raw | Should -Match 'Get-Plugin\.ps1'
        $raw | Should -Match 'Find-Plugin\.ps1'
        $raw | Should -Match '-Installed'
    }

    It 'test:PluginManager.ApprovalPrompt install offers opt-in auto-approval via vscode_askQuestions + Set-ScriptApproval' {
        $install = Get-Content -LiteralPath (Join-Path $script:pluginRoot 'skills/install-plugin/SKILL.md') -Raw
        $install | Should -Match 'vscode_askQuestions'
        $install | Should -Match 'Set-ScriptApproval\.ps1'

        $uninstall = Get-Content -LiteralPath (Join-Path $script:pluginRoot 'skills/uninstall-plugin/SKILL.md') -Raw
        $uninstall | Should -Match 'Set-ScriptApproval\.ps1'
    }
}
