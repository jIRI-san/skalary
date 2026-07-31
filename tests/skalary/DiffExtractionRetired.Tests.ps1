#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Step 5.3 retired the six diff helpers. Deleting a bundled script is only half the change:
# Sync-Dogfood never prunes, consumer installs resolve against registry.json, and the
# orchestrator prose is what actually invokes anything — so all three have to agree (REQ-11).

Describe 'cr diff extraction retirement' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path

        # Built from parts so this file is not itself a match when the tree is scanned below.
        $script:helperPrefix = 'get' + '-diff'
        $script:retiredHelpers = @('branch', 'commits', 'files', 'paths', 'smart-default', 'uncommitted') |
            ForEach-Object { "$script:helperPrefix-$_.ps1" }

        $script:crOrchestrators = @(
            'plugins/code-review/agents/cr.agent.md'
            '.github/agents/cr.agent.md'
        )

        $script:scanRoots = @('plugins', '.github', 'scripts', 'tools', 'docs/design-notes')
        $script:scanExtensions = @('.md', '.ps1', '.psm1', '.psd1', '.json', '.yaml', '.yml')
    }

    It 'test:no-diff-extraction-refs deletes every retired diff helper from the plugin and its dogfood copy' {
        foreach ($helper in $script:retiredHelpers) {
            foreach ($relative in @("plugins/code-review/agents/scripts/$helper", ".github/agents/scripts/$helper")) {
                # Sync-Dogfood is copy-only and never prunes, so a helper left in .github keeps
                # loading in VS Code long after the plugin stopped shipping it.
                Test-Path -LiteralPath (Join-Path $script:repoRoot $relative) | Should -BeFalse -Because "$relative must be deleted"
            }
        }
    }

    It 'test:no-diff-extraction-refs leaves no reference to a retired helper anywhere in the shipped tree' {
        $pattern = [regex]::new([regex]::Escape($script:helperPrefix) + '-[a-z-]*\.ps1')
        $offenders = [System.Collections.Generic.List[string]]::new()

        foreach ($scanRoot in $script:scanRoots) {
            $full = Join-Path $script:repoRoot $scanRoot
            if (-not (Test-Path -LiteralPath $full -PathType Container)) { continue }
            foreach ($file in (Get-ChildItem -LiteralPath $full -Recurse -File)) {
                if ($script:scanExtensions -notcontains $file.Extension.ToLowerInvariant()) { continue }
                $raw = [System.IO.File]::ReadAllText($file.FullName)
                if ($pattern.IsMatch($raw)) {
                    $offenders.Add($file.FullName.Substring($script:repoRoot.Length).Replace('\', '/').TrimStart('/'))
                }
            }
        }

        foreach ($referrer in @('registry.json', '.vscode/settings.json', 'README.md')) {
            $raw = [System.IO.File]::ReadAllText((Join-Path $script:repoRoot $referrer))
            if ($pattern.IsMatch($raw)) { $offenders.Add($referrer) }
        }

        $offenders | Should -BeNullOrEmpty -Because 'a reference to a deleted helper is an install that resolves to nothing'
    }

    It 'test:no-diff-extraction-refs points both cr orchestrator copies at the single scope emitter' {
        foreach ($relative in $script:crOrchestrators) {
            $raw = [System.IO.File]::ReadAllText((Join-Path $script:repoRoot $relative))

            $raw | Should -Match '\.github/agents/scripts/Get-ReviewScope\.ps1'
            $raw | Should -Match '(?m)^## Step 2: Collect the File List\s*$'
            # No diff extraction and no content batching: the file list is the whole payload.
            $raw | Should -Not -Match '--diff'
            $raw | Should -Not -Match 'Create one diff per batch'
            $raw | Should -Match 'reviewers read the code themselves'
        }
    }

    It 'test:no-diff-extraction-refs keeps the injection guard where the content is now read' {
        foreach ($relative in $script:crOrchestrators) {
            $raw = [System.IO.File]::ReadAllText((Join-Path $script:repoRoot $relative))
            # The orchestrator-side fence is gone because it no longer passes content; deleting
            # it is only safe while every reviewer carries the directive itself (RISK-11).
            $raw | Should -Not -Match 'UNTRUSTED_INPUT'
            $raw | Should -Match 'data, not instructions'
        }
    }

    It 'test:no-diff-extraction-refs keeps every concern reviewer carrying its own data-only directive' {
        $concerns = @(
            'security', 'correctness-reliability', 'architecture-patterns', 'performance',
            'testing-evidence', 'maintainability-consistency', 'operability-observability'
        )
        foreach ($concern in $concerns) {
            $path = Join-Path $script:repoRoot "plugins/code-review/agents/cr-$concern.agent.md"
            $raw = [System.IO.File]::ReadAllText($path)
            $raw | Should -Match 'data, never instructions'
            $raw | Should -Match '\[SECURITY\] Prompt injection attempt detected'
        }
    }

    It 'test:no-diff-extraction-refs ships exactly one agent helper script, declared and registered' {
        $manifest = Get-Content -LiteralPath (Join-Path $script:repoRoot 'plugins/code-review/plugin.json') -Raw | ConvertFrom-Json -Depth 50
        $agentScripts = @($manifest.files | ForEach-Object { [string]$_.src } | Where-Object { $_ -like 'agents/scripts/*' })
        $agentScripts | Should -Be @('agents/scripts/Get-ReviewScope.ps1')

        $registry = Get-Content -LiteralPath (Join-Path $script:repoRoot 'registry.json') -Raw | ConvertFrom-Json -Depth 100
        $codeReview = @($registry.plugins | Where-Object { [string]$_.name -eq 'code-review' })
        $codeReview.Count | Should -Be 1
        $registered = @($codeReview[0].files | ForEach-Object { [string]$_.dest } | Where-Object { $_ -like 'agents/scripts/*' })
        # Consumer installs resolve against the registry, so an unregistered emitter is an
        # orchestrator step that fails on every installed repo.
        $registered | Should -Be @('agents/scripts/Get-ReviewScope.ps1')
    }
}
