#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The dispatch guide is the only place the fan-out rules exist: how many concerns run, against
# which models, how batching works, and what the invocation budget is. Prose drifts silently, so
# each rule that costs credits or claims a control is pinned here.

Describe 'reviewer dispatch guide' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:crGuidePath = Join-Path $script:repoRoot 'plugins/code-review/skills/cr/assets/dispatch-guide.md'
        $script:drGuidePath = Join-Path $script:repoRoot 'plugins/design-review/skills/dr/assets/dispatch-guide.md'
        $script:crMapPath = Join-Path $script:repoRoot 'plugins/code-review/skills/cr/assets/concern-ledger-map.md'
        $script:drMapPath = Join-Path $script:repoRoot 'plugins/design-review/skills/dr/assets/concern-ledger-map.md'
        $script:guide = Get-Content -LiteralPath $script:crGuidePath -Raw
        # Assertions run against whitespace-flattened text: the guide is hard-wrapped, so an
        # anchored phrase would otherwise pass or fail on where a line happens to break.
        $script:flat = [regex]::Replace($script:guide, '\s+', ' ')

        $script:concerns = @(
            'security'
            'correctness-reliability'
            'architecture-patterns'
            'performance'
            'testing-evidence'
            'maintainability-consistency'
            'operability-observability'
        )
    }

    It 'ships one shared guide, byte-identical in both review plugins' {
        # `/dr` reuses the `/cr` guide. The installer is confined to .github/, so each plugin must
        # carry its own copy — which only stays "shared" if the copies cannot drift.
        foreach ($pair in @(@($script:crGuidePath, $script:drGuidePath), @($script:crMapPath, $script:drMapPath))) {
            (Get-FileHash -LiteralPath $pair[0] -Algorithm SHA256).Hash |
                Should -Be (Get-FileHash -LiteralPath $pair[1] -Algorithm SHA256).Hash
        }
    }

    It 'declares both shared assets in both plugin manifests' {
        foreach ($case in @(
                @{ Manifest = 'plugins/code-review/plugin.json'; Skill = 'cr' },
                @{ Manifest = 'plugins/design-review/plugin.json'; Skill = 'dr' })) {
            $manifest = Get-Content -LiteralPath (Join-Path $script:repoRoot $case.Manifest) -Raw | ConvertFrom-Json -Depth 50
            $srcs = @($manifest.files | ForEach-Object { [string]$_.src })
            $srcs | Should -Contain "skills/$($case.Skill)/assets/dispatch-guide.md"
            $srcs | Should -Contain "skills/$($case.Skill)/assets/concern-ledger-map.md"
        }
    }

    It 'test:dispatch-guide-scaling-thresholds states every size tier and its concern set' {
        $script:guide | Should -Match '(?m)^## 4\. Concern selection scales with change size'
        # Small changes get the three highest-signal lenses, not the full sweep.
        $script:flat | Should -Match '≤ 3 files / ≤ 150 lines'
        $script:flat | Should -Match '4–15 files / 151–400 lines'
        $script:flat | Should -Match '> 15 files / > 400 lines'
        $script:flat | Should -Match '3 × 2 = 6'
        $script:flat | Should -Match '7 × 2 = 14'
        $script:flat | Should -Match 'concern filter'
    }

    It 'test:dispatch-guide-scaling-thresholds keeps concerns running once over the union of files' {
        # The expensive mistake is running each concern per batch: 7 x 2 x batches.
        $script:flat | Should -Match 'once over the union of the files'
        $script:flat | Should -Match 'never once per batch'
        $script:flat | Should -Match 'at most \*\*15 files per batch\*\*'
        $script:flat | Should -Match 'first match in index order'
        $script:flat | Should -Match 'H2 boundaries'
        $script:flat | Should -Match "one ``assets/`` file per batch"
    }

    It 'test:dispatch-budget-reported states the 28-invocation budget as reported, not enforced' {
        $script:flat | Should -Match 'Budget: 28 invocations'
        $script:flat | Should -Match 'reports against'
        $script:flat | Should -Match 'not an enforced gate'
        $script:flat | Should -Match 'of 28 budgeted invocations'
    }

    It 'test:declared-model-preflight-fails-loud wires the preflight to the deterministic validator' {
        $script:flat | Should -Match 'Test-ModelAllowlist\.ps1'
        $script:flat | Should -Match 'non-zero exit is \*\*fail-loud'
        $script:flat | Should -Match 'never downgrade the failure to a warning'
        $script:flat | Should -Match 'explicit model parameter'
        # The residual is documented rather than papered over with a control that cannot see it.
        $script:flat | Should -Match 'cannot observe the \*\*served\*\* model'
        $script:flat | Should -Match 'accepted, undetectable residual'
        $script:flat | Should -Match 'Claude Sonnet 4\.6 \(copilot\)'
        $script:flat | Should -Match 'as the explicit parameter'
    }

    It 'test:declared-model-preflight-fails-loud proves the named preflight actually fails loud' {
        $validator = Join-Path $script:repoRoot 'scripts/skalary/Test-ModelAllowlist.ps1'
        Test-Path -LiteralPath $validator -PathType Leaf | Should -BeTrue

        $root = Join-Path ([System.IO.Path]::GetTempPath()) ('dispatch-preflight-' + [System.Guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path (Join-Path $root 'plugins/sample/agents') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $root 'plugins/sample/agents/cr-security.agent.md') -Encoding utf8NoBOM -Value @'
---
description: "Fixture."
name: "cr-security"
model: Some Retired Model (copilot)
---

Body.
'@
            & $validator -RepoRoot $root -AllowlistPath (Join-Path $script:repoRoot 'tools/model-allowlist.psd1') *> $null
            $LASTEXITCODE | Should -Be 1
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:concern-ledger-map-total maps every concern for both review types to a real ledger file' {
        $map = Get-Content -LiteralPath $script:crMapPath -Raw

        foreach ($concern in $script:concerns) {
            $row = [regex]::Match($map, "(?m)^\|\s*``$([regex]::Escape($concern))``\s*\|\s*``(?<cr>[a-z-]+\.md)``\s*\|\s*``(?<dr>[a-z-]+\.md)``\s*\|")
            $row.Success | Should -BeTrue -Because "$concern must have a row for both review types"

            foreach ($category in @($row.Groups['cr'].Value, $row.Groups['dr'].Value)) {
                Test-Path -LiteralPath (Join-Path $script:repoRoot "docs/review-ledger/$category") -PathType Leaf |
                    Should -BeTrue -Because "$category must be a real review-ledger category"
            }
        }

        # Totality is the point: no fallback branch, no improvised category.
        ([regex]::Replace($map, '\s+', ' ')) | Should -Match 'There is no fallback branch'
    }

    It 'test:concern-ledger-map-total routes both harvest mirrors through the map, not a keyword rubric' {
        # The map only removes the judgment call if the writers actually consult it. /ci harvest and
        # its canonical autopilot mirror must both name it, in the plugin source and the installed
        # copy — a rule that reaches only one of the two is a split-brain harvest.
        foreach ($path in @('plugins/continue-implementation/skills/ci/assets/crosscheck-guide.md',
                '.github/skills/ci/assets/crosscheck-guide.md',
                'plugins/autopilot/agents/autopilot.agent.md',
                '.github/agents/autopilot.agent.md')) {
            $full = Join-Path $script:repoRoot ($path -replace '/', [System.IO.Path]::DirectorySeparatorChar)
            Test-Path -LiteralPath $full -PathType Leaf | Should -BeTrue -Because "$path must exist"
            $flat = [regex]::Replace((Get-Content -LiteralPath $full -Raw), '\s+', ' ')

            $flat | Should -Match '\.github/skills/cr/assets/concern-ledger-map\.md' -Because "$path must name the installed map path"
            $flat | Should -Match '\.github/skills/dr/assets/concern-ledger-map\.md' -Because "$path must probe the dr copy too: either review plugin ships the map"
            $flat | Should -Match '(?i)unmapped concern is a bug in that table' -Because "$path must forbid improvising a category"

            # The rubric the map replaces on the write side. The guard matches the concept, not one
            # mirror's punctuation: keyed to a single phrasing it went vacuous on the other file and
            # a restored taxonomy bullet would pass.
            $flat | Should -Not -Match '(?i)7-category (rubric|taxonomy)' -Because "$path must not keep the ad-hoc write-side rubric"
        }
    }
}
