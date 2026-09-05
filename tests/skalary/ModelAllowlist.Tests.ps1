#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The model allowlist is the only thing standing between a committed agent and a model name
# the host cannot serve. Host is selected from a closed committed map — never inferred from
# folder layout — so these tests pin the fail-loud behaviour of every branch: unknown model,
# wrong name format for the host, unmapped agent, autopilot config drift, denied vendor.

Describe 'model allowlist validator' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:validator = Join-Path $script:repoRoot 'scripts/skalary/Test-ModelAllowlist.ps1'
        $script:allowlistPath = Join-Path $script:repoRoot 'tools/model-allowlist.psd1'
        $script:modelPolicy = Import-PowerShellDataFile -LiteralPath $script:allowlistPath
        $script:vsIndependentModel = [string]$modelPolicy.Aliases['alternate-model-high'].VSCode

        $script:newFixtureRoot = {
            $path = Join-Path ([System.IO.Path]::GetTempPath()) ('model-allowlist-' + [System.Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path (Join-Path $path 'plugins/sample/agents') -Force | Out-Null
            return $path
        }

        $script:newAgent = {
            param(
                [Parameter(Mandatory)][string]$Root,
                [Parameter(Mandatory)][string]$Name,
                [string]$Model,
                [string]$Body = 'Reviewer body.'
            )

            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add('---')
            $lines.Add("description: `"Fixture agent $Name.`"")
            $lines.Add("name: `"$Name`"")
            if ($PSBoundParameters.ContainsKey('Model') -and $Model) {
                $lines.Add("model: $Model")
            }
            $lines.Add('tools: [read, search]')
            $lines.Add('---')
            $lines.Add('')
            $lines.Add($Body)

            $path = Join-Path $Root "plugins/sample/agents/$Name.agent.md"
            Set-Content -LiteralPath $path -Value ($lines -join "`n") -Encoding utf8NoBOM
            return $path
        }

        $script:invoke = {
            param([Parameter(Mandatory)][string]$Root)

            # The validator reports through Write-Host (information stream), so `*>&1` is
            # required — a bare `2>&1` captures nothing and every message assertion would
            # silently pass against an empty string.
            $output = & $script:validator -RepoRoot $Root -AllowlistPath $script:allowlistPath *>&1
            return [pscustomobject]@{
                ExitCode = $LASTEXITCODE
                Output   = ($output | Out-String)
            }
        }
    }

    Context 'allowlist manifest shape' {
        It 'carries six aliases with separate host bindings plus a closed agent-to-host map' {
            $allowlist = Import-PowerShellDataFile -LiteralPath $script:allowlistPath

            @($allowlist.Aliases.Keys).Count | Should -Be 6
            $allowlist.Roles.Routine.Primary | Should -Be 'model-low'
            $allowlist.Roles.Standard.Primary | Should -Be 'model-mid'
            $allowlist.Roles.Deep.Primary | Should -Be 'model-high'
            $allowlist.Roles.Independent.Primary | Should -Be 'alternate-model-high'

            foreach ($binding in @($allowlist.Aliases.Values)) {
                $binding.VSCode | Should -Match '^.+\s\([^)]+\)$'
                $binding.Cli | Should -Not -Match '\)$'
            }

            $allowlist.AgentHosts['autopilot'] | Should -Be 'Cli'
            $allowlist.Fallback.VSCode | Should -Be 'alternate-model-mid'
        }

        It 'keeps independently installed alias assets generated from the canonical map' {
            $canonical = [System.IO.File]::ReadAllBytes($script:allowlistPath)
            foreach ($relative in @(
                    'plugins/autopilot/skills/autopilot/assets/model-aliases.psd1'
                    'plugins/code-review/skills/cr/assets/model-aliases.psd1'
                    'plugins/continue-implementation/skills/ci/assets/model-aliases.psd1'
                    'plugins/create-implementation-plan/skills/cip/assets/model-aliases.psd1'
                    'plugins/design-review/skills/dr/assets/model-aliases.psd1'
                )) {
                [System.IO.File]::ReadAllBytes((Join-Path $script:repoRoot $relative)) |
                    Should -Be $canonical -Because $relative
            }
        }
    }

    Context 'host-aware model validation' {
        It 'passes a mapped agent whose model matches its host list' {
            $root = & $script:newFixtureRoot
            try {
                & $script:newAgent -Root $root -Name 'cr-security' -Model $script:vsIndependentModel | Out-Null
                $result = & $script:invoke -Root $root
                $result.ExitCode | Should -Be 0
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'passes a model-agnostic agent that declares no model at all' {
            $root = & $script:newFixtureRoot
            try {
                & $script:newAgent -Root $root -Name 'cr-performance' | Out-Null
                $result = & $script:invoke -Root $root
                $result.ExitCode | Should -Be 0
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:model-allowlist-rejects-unknown fails on a model name absent from the list' {
            $root = & $script:newFixtureRoot
            try {
                & $script:newAgent -Root $root -Name 'cr-security' -Model 'Claude Opus 4.8 (copilot)' | Out-Null
                $result = & $script:invoke -Root $root
                $result.ExitCode | Should -Be 1
                $result.Output | Should -Match "Claude Opus 4\.8 \(copilot\)"
                $result.Output | Should -Match 'not in the VSCode allowlist'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:model-allowlist-rejects-qualified-name-on-cli-agent fails when a CLI agent carries a qualified name' {
            $root = & $script:newFixtureRoot
            try {
                # A valid qualified VS Code name is still broken for the CLI-hosted autopilot agent.
                & $script:newAgent -Root $root -Name 'autopilot' -Model $script:vsIndependentModel | Out-Null
                $result = & $script:invoke -Root $root
                $result.ExitCode | Should -Be 1
                $result.Output | Should -Match 'not in the Cli allowlist'
                $result.Output | Should -Match 'bare slug'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:model-allowlist-fails-on-unmapped-agent refuses to infer a host' {
            $root = & $script:newFixtureRoot
            try {
                & $script:newAgent -Root $root -Name 'cr-brand-new' -Model $script:vsIndependentModel | Out-Null
                $result = & $script:invoke -Root $root
                $result.ExitCode | Should -Be 1
                $result.Output | Should -Match "absent from the AgentHosts map"
                $result.Output | Should -Match 'host is never inferred from folder layout'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'autopilot runtime configuration' {
        It 'test:model-allowlist-covers-autopilot-config accepts the committed CLI slug and rejects drift' {
            $root = & $script:newFixtureRoot
            try {
                $configPath = Join-Path $root '.autopilot.json'
                Set-Content -LiteralPath $configPath -Value '{ "model": "model-low" }' -Encoding utf8NoBOM
                (& $script:invoke -Root $root).ExitCode | Should -Be 0

                # The runtime model comes from this field, not from agent frontmatter, so the
                # check has to cover it or a repointed config sails through unnoticed.
                Set-Content -LiteralPath $configPath -Value '{ "model": "gpt-5.3-codex" }' -Encoding utf8NoBOM
                $result = & $script:invoke -Root $root
                $result.ExitCode | Should -Be 1
                $result.Output | Should -Match 'gpt-5\.3-codex'
                $result.Output | Should -Match 'not in the alias map'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'covers the shipped .autopilot.json.example too' {
            $root = & $script:newFixtureRoot
            try {
                New-Item -ItemType Directory -Path (Join-Path $root 'plugins/autopilot') -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $root 'plugins/autopilot/.autopilot.json.example') `
                    -Value '{ "model": "retired-slug" }' -Encoding utf8NoBOM
                $result = & $script:invoke -Root $root
                $result.ExitCode | Should -Be 1
                $result.Output | Should -Match 'retired-slug'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'denied vendors' {
        It 'test:no-gemini-references fails on a Gemini reference anywhere in an agent file' {
            $root = & $script:newFixtureRoot
            try {
                & $script:newAgent -Root $root -Name 'cr' -Body 'Dispatch cr-gemini for the security pass.' | Out-Null
                $result = & $script:invoke -Root $root
                $result.ExitCode | Should -Be 1
                $result.Output | Should -Match 'denied model/vendor'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'committed autopilot binding' {
        It 'test:model-allowlist-covers-autopilot-config accepts the shipped alias binding unchanged' {
            $allowlist = Import-PowerShellDataFile -LiteralPath $script:allowlistPath
            $allowlist.Aliases['model-low'].Cli | Should -Not -BeNullOrEmpty

            foreach ($agent in @('plugins/autopilot/agents/autopilot.agent.md', '.github/agents/autopilot.agent.md')) {
                $raw = Get-Content -LiteralPath (Join-Path $script:repoRoot $agent) -Raw
                $raw | Should -Not -Match '(?m)^model:'
            }

            foreach ($config in @('plugins/autopilot/.autopilot.json.example', '.github/skills/autopilot/.autopilot.json.example')) {
                $parsed = Get-Content -LiteralPath (Join-Path $script:repoRoot $config) -Raw | ConvertFrom-Json
                $parsed.model | Should -Be 'model-low'
                $allowlist.Aliases.ContainsKey($parsed.model) | Should -BeTrue
            }
        }

        It 'passes the whole committed repo, agents and autopilot configs alike' {
            $result = & $script:invoke -Root $script:repoRoot
            if ($result.ExitCode -ne 0) { Write-Host $result.Output }
            $result.ExitCode | Should -Be 0
        }
    }

    Context 'dispatch roster' {
        BeforeAll {
            $script:newGuide = {
                param(
                    [Parameter(Mandatory)][string]$Root,
                    [string]$ReviewerModel = 'alternate-model-high',
                    [string]$FallbackModel = 'alternate-model-mid',
                    [switch]$OmitRosterSection
                )

                $dir = Join-Path $Root 'plugins/sample/skills/cr/assets'
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
                $heading = if ($OmitRosterSection) { '## 2. Models we like' } else { '## 2. Model roster and per-invocation override' }
                $text = @"
# Reviewer dispatch guide

$heading

| Role | Model | Notes |
|---|---|---|
| Reviewer A | ``$ReviewerModel`` | GA |
| Pro-tier fallback | ``$FallbackModel`` | GA |

## 3. Something else
"@
                Set-Content -LiteralPath (Join-Path $dir 'dispatch-guide.md') -Value $text -Encoding utf8NoBOM
            }
        }

        It 'test:model-allowlist-rejects-unknown covers the dispatched roster, not just agent frontmatter' {
            $root = & $script:newFixtureRoot
            try {
                # The concern agents are model-agnostic on purpose, so the roster in the dispatch
                # guide is the only place the dispatched model names exist.
                & $script:newGuide -Root $root -ReviewerModel 'retired-model'
                $result = & $script:invoke -Root $root
                $result.ExitCode | Should -Be 1
                $result.Output | Should -Match "dispatches model alias 'retired-model'"
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'fails when the guide fallback diverges from the allowlist fallback' {
            $root = & $script:newFixtureRoot
            try {
                & $script:newGuide -Root $root -FallbackModel 'model-high'
                $result = & $script:invoke -Root $root
                $result.ExitCode | Should -Be 1
                $result.Output | Should -Match 'Pro-tier fallback'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'fails when the roster section is renamed away instead of silently skipping the file' {
            $root = & $script:newFixtureRoot
            try {
                & $script:newGuide -Root $root -OmitRosterSection
                $result = & $script:invoke -Root $root
                $result.ExitCode | Should -Be 1
                $result.Output | Should -Match "no '## Model roster' section"
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:no-gemini-references applies the denied vendors to dispatch guides too' {
            $root = & $script:newFixtureRoot
            try {
                & $script:newGuide -Root $root -ReviewerModel 'Gemini-preview'
                $result = & $script:invoke -Root $root
                $result.ExitCode | Should -Be 1
                $result.Output | Should -Match 'denied model/vendor'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'accepts the shipped guides' {
            $result = & $script:invoke -Root $script:repoRoot
            if ($result.ExitCode -ne 0) { Write-Host $result.Output }
            $result.ExitCode | Should -Be 0
            $result.Output | Should -Match 'dispatch guide\(s\)'
        }
    }

    Context 'code-review model preferences' {
        It 'rejects an unknown configured CR role model' {
            $root = & $script:newFixtureRoot
            try {
                $assets = Join-Path $root 'plugins/code-review/skills/cr/assets'
                New-Item -ItemType Directory -Path $assets -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $assets 'model-preferences.md') -Encoding utf8NoBOM -Value @'
# Code-review model preferences

## Models

| Role | Model | Reasoning effort | Context tier |
|---|---|---|---|
| Primary | `Unknown Expensive Model (copilot)` | `high` | `default` |
| Secondary | `alternate-model-high` | `high` | `default` |
| Backup | `alternate-model-mid` | `high` | `default` |
'@
                $result = & $script:invoke -Root $root
                $result.ExitCode | Should -Be 1
                $result.Output | Should -Match "role 'Primary'.*not in the alias map"
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'hidden dogfood copies' {
        It 'scans .github/agents/ too, where the dogfood copies actually load from' {
            $root = & $script:newFixtureRoot
            try {
                # `.github` is a hidden directory: an enumeration without -Force walks straight
                # past it, and since Sync-Dogfood never prunes, a deleted plugin agent lingers
                # there indefinitely. That is precisely the drift REQ-7 exists to catch.
                New-Item -ItemType Directory -Path (Join-Path $root '.github/agents') -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $root '.github/agents/autopilot.agent.md') -Encoding utf8NoBOM -Value @"
---
description: "Dogfood copy."
name: "autopilot"
model: $($script:vsIndependentModel)
---

Body.
"@
                $result = & $script:invoke -Root $root
                $result.ExitCode | Should -Be 1
                $result.Output | Should -Match '\.github/agents/autopilot\.agent\.md'
                $result.Output | Should -Match 'not in the Cli allowlist'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
