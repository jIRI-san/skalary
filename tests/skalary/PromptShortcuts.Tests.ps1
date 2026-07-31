#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Plan b0c0d3 REQ-12: a prompt is a shortcut into a skill, never a second copy of the workflow.
# The skill is the CLI-usable definition; a prompt that carries its own procedure drifts from it
# silently and only in VS Code.
Describe 'Prompts are thin skill shortcuts' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:pluginsRoot = Join-Path $script:repoRoot 'plugins'

        $script:prompts = foreach ($manifestPath in (Get-ChildItem -LiteralPath $script:pluginsRoot -Recurse -File -Filter 'plugin.json' | Sort-Object FullName)) {
            $pluginRoot = Split-Path -Parent $manifestPath.FullName
            $manifest = Get-Content -LiteralPath $manifestPath.FullName -Raw | ConvertFrom-Json -Depth 50
            foreach ($file in @($manifest.files)) {
                $src = [string]$file.src
                if ($src -notmatch '\.prompt\.md$') { continue }
                [pscustomobject]@{
                    Plugin = [string]$manifest.name
                    PluginRoot = $pluginRoot
                    Src = $src
                    Dest = [string]$file.dest
                    Path = Join-Path $pluginRoot ($src -replace '/', [System.IO.Path]::DirectorySeparatorChar)
                }
            }
        }

        $script:prompts = @($script:prompts)
    }

    It 'test:prompts-are-thin-shortcuts finds every shipped prompt' {
        # Discovery is manifest-driven, so a new prompt is covered the moment it is installable.
        # The named five from the audit must be present; cr/dr joined them when their skills landed.
        $names = @($script:prompts | ForEach-Object { [System.IO.Path]::GetFileName($_.Src) } | Sort-Object -Unique)
        foreach ($expected in @('can.prompt.md', 'cdn.prompt.md', 'cr.prompt.md', 'design-notes.prompt.md',
                'dr.prompt.md', 'uan.prompt.md', 'udn.prompt.md')) {
            $names | Should -Contain $expected
        }
    }

    It 'test:prompts-are-thin-shortcuts points every prompt at a skill its own plugin installs' {
        foreach ($prompt in $script:prompts) {
            $body = (Get-Content -LiteralPath $prompt.Path -Raw) -replace '(?s)^---\r?\n.*?\r?\n---\r?\n?', ''

            $skillMatches = @([regex]::Matches($body, 'skills/(?<skill>[a-z0-9][a-z0-9-]*)/SKILL\.md'))
            $skillMatches.Count | Should -BeGreaterThan 0 -Because "$($prompt.Src) must name the skill that owns the workflow"

            foreach ($skill in @($skillMatches | ForEach-Object { [string]$_.Groups['skill'].Value } | Sort-Object -Unique)) {
                # Source of truth and installed copy: a shortcut whose target the plugin does not
                # ship resolves to nothing in a consumer repo.
                Test-Path -LiteralPath (Join-Path $prompt.PluginRoot "skills/$skill/SKILL.md") -PathType Leaf |
                    Should -BeTrue -Because "$($prompt.Plugin) must ship skills/$skill/SKILL.md"
                Test-Path -LiteralPath (Join-Path $script:repoRoot ".github/skills/$skill/SKILL.md") -PathType Leaf |
                    Should -BeTrue -Because ".github/skills/$skill/SKILL.md must exist for $($prompt.Src)"
            }
        }
    }

    It 'test:prompts-are-thin-shortcuts keeps the workflow in the skill, not the prompt' {
        foreach ($prompt in $script:prompts) {
            $body = (Get-Content -LiteralPath $prompt.Path -Raw) -replace '(?s)^---\r?\n.*?\r?\n---\r?\n?', ''
            $lines = @(($body -split "`r?`n") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

            # A shortcut presets an operation and passes the argument through; anything longer is a
            # workflow the skill already owns.
            $lines.Count | Should -BeLessOrEqual 20 -Because "$($prompt.Src) should stay a shortcut"

            # Structural markers of an owned workflow: its own step headings or an executable recipe.
            $body | Should -Not -Match '(?m)^#{2,6}\s+Step\s+\d' -Because "$($prompt.Src) must not define its own steps"
            $body | Should -Not -Match '(?m)^\s*```(powershell|pwsh|bash|sh)' -Because "$($prompt.Src) must not carry its own command recipe"
        }
    }

    It 'test:prompts-are-thin-shortcuts names each prompt after its file and installs it under prompts/' {
        foreach ($prompt in $script:prompts) {
            $raw = Get-Content -LiteralPath $prompt.Path -Raw
            $expectedName = [System.IO.Path]::GetFileName($prompt.Src) -replace '\.prompt\.md$', ''

            $raw | Should -Match "(?m)^name:\s*`"?$([regex]::Escape($expectedName))`"?\s*$"
            $raw | Should -Match '(?m)^description:\s*\S'
            $raw | Should -Match '(?m)^agent:\s*\S'
            $prompt.Dest | Should -Be "prompts/$expectedName.prompt.md"
        }
    }
}
