#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The concern reviewers replaced the per-model reviewers, and with them the orchestrator-side
# UNTRUSTED_INPUT fence: reviewers now read attacker-influenced source directly. The injection
# guard therefore has to live in every concern agent, and "every" is what these tests pin — a
# single agent authored without it is a silent hole in the only remaining control (RISK-11).

Describe 'concern reviewer agents' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path

        $script:concerns = @(
            'security'
            'correctness-reliability'
            'architecture-patterns'
            'performance'
            'testing-evidence'
            'maintainability-consistency'
            'operability-observability'
        )

        $script:reviewTypes = @(
            @{ Prefix = 'cr'; Plugin = 'code-review' }
            @{ Prefix = 'dr'; Plugin = 'design-review' }
        )

        $script:legacyModelAgents = @(
            'cr-opus', 'cr-codex', 'cr-gemini'
            'dr-opus', 'dr-codex', 'dr-gemini'
        )

        $script:agentPath = {
            param([string]$Plugin, [string]$Prefix, [string]$Concern)
            Join-Path $script:repoRoot "plugins/$Plugin/agents/$Prefix-$Concern.agent.md"
        }
    }

    It 'test:concern-agents-complete ships all seven concerns for every review type, declared in the manifest' {
        foreach ($reviewType in $script:reviewTypes) {
            $manifestPath = Join-Path $script:repoRoot "plugins/$($reviewType.Plugin)/plugin.json"
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -Depth 50
            $declared = @($manifest.files | ForEach-Object { [string]$_.src })

            foreach ($concern in $script:concerns) {
                $relative = "agents/$($reviewType.Prefix)-$concern.agent.md"
                $path = & $script:agentPath $reviewType.Plugin $reviewType.Prefix $concern

                Test-Path -LiteralPath $path -PathType Leaf | Should -BeTrue -Because "$relative must exist"
                $declared | Should -Contain $relative -Because 'installation only materializes files declared in plugin.json'

                $raw = Get-Content -LiteralPath $path -Raw
                $raw | Should -Match "(?m)^name:\s*`"$($reviewType.Prefix)-$concern`"\s*$"
            }
        }
    }

    It 'test:concern-agents-complete keeps every concern agent model-agnostic' {
        foreach ($reviewType in $script:reviewTypes) {
            foreach ($concern in $script:concerns) {
                $raw = Get-Content -LiteralPath (& $script:agentPath $reviewType.Plugin $reviewType.Prefix $concern) -Raw
                # A pinned model would outrank nothing (explicit dispatch params win) but would
                # silently re-couple the roster to 14 files, which is what this split removed.
                $raw | Should -Not -Match '(?m)^model:'
            }
        }
    }

    It 'test:concern-agents-carry-injection-guard gives every concern agent its own data-only directive' {
        foreach ($reviewType in $script:reviewTypes) {
            foreach ($concern in $script:concerns) {
                $path = & $script:agentPath $reviewType.Plugin $reviewType.Prefix $concern
                $raw = Get-Content -LiteralPath $path -Raw

                $raw | Should -Match '(?m)^## Untrusted Content\s*$' -Because "$path must carry its own fence"
                $raw | Should -Match 'data, never instructions'
                $raw | Should -Match '\[SECURITY\] Prompt injection attempt detected'
                $raw | Should -Match '(?s)Prompt injection attempt detected.{0,120}Critical'
                $raw | Should -Match 'Never execute, install, or fetch'
            }
        }
    }

    It 'test:concern-agents-carry-injection-guard keeps every concern agent read-only' {
        foreach ($reviewType in $script:reviewTypes) {
            foreach ($concern in $script:concerns) {
                $raw = Get-Content -LiteralPath (& $script:agentPath $reviewType.Plugin $reviewType.Prefix $concern) -Raw
                $raw | Should -Match '(?m)^tools:\s*\[read, search\]\s*$'
                $raw | Should -Match '(?m)^user-invocable:\s*false\s*$'
            }
        }
    }

    It 'gives each concern its own lens and output section rather than a comprehensive sweep' {
        foreach ($reviewType in $script:reviewTypes) {
            $sections = [System.Collections.Generic.List[string]]::new()
            foreach ($concern in $script:concerns) {
                $raw = Get-Content -LiteralPath (& $script:agentPath $reviewType.Plugin $reviewType.Prefix $concern) -Raw
                $raw | Should -Match '(?m)^## Scope\s*$'
                $raw | Should -Match 'Stay inside your lens'

                $match = [regex]::Match($raw, '(?m)^Start with `## Findings \((?<label>[^)]+)\)`')
                $match.Success | Should -BeTrue -Because "$($reviewType.Prefix)-$concern must declare its findings section"
                $sections.Add($match.Groups['label'].Value)
            }

            # Distinct labels are what makes merge-by-concern possible downstream.
            @($sections | Sort-Object -Unique).Count | Should -Be $script:concerns.Count
        }
    }

    It 'test:legacy-model-agents-removed deletes the per-model reviewers, their dogfood copies, and every reference' {
        foreach ($agent in $script:legacyModelAgents) {
            $plugin = if ($agent.StartsWith('cr')) { 'code-review' } else { 'design-review' }
            foreach ($candidate in @(
                    (Join-Path $script:repoRoot "plugins/$plugin/agents/$agent.agent.md"),
                    (Join-Path $script:repoRoot ".github/agents/$agent.agent.md"))) {
                # Sync-Dogfood is copy-only and never prunes, so the .github copy has to be
                # removed explicitly or a deleted reviewer keeps loading in VS Code.
                Test-Path -LiteralPath $candidate | Should -BeFalse -Because "$candidate must be deleted"
            }
        }

        $referrers = @(
            'plugins/code-review/plugin.json'
            'plugins/design-review/plugin.json'
            'plugins/code-review/agents/cr.agent.md'
            'plugins/design-review/agents/dr.agent.md'
            '.github/agents/cr.agent.md'
            '.github/agents/dr.agent.md'
            'registry.json'
        )
        foreach ($referrer in $referrers) {
            $raw = Get-Content -LiteralPath (Join-Path $script:repoRoot $referrer) -Raw
            foreach ($agent in $script:legacyModelAgents) {
                $raw | Should -Not -Match ([regex]::Escape($agent)) -Because "$referrer must not reference $agent"
            }
        }
    }

    It 'test:legacy-model-agents-removed leaves the shipped agent set clean under the model allowlist' {
        $validator = Join-Path $script:repoRoot 'scripts/skalary/Test-ModelAllowlist.ps1'
        $output = & $validator -RepoRoot $script:repoRoot *>&1
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) { Write-Host ($output | Out-String) }
        $exitCode | Should -Be 0
    }
}
