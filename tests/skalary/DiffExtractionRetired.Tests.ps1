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

        # The cr orchestration surface moved into the skill (plan b0c0d3 step 6.1/6.3); the agent is
        # a shim. Both installed trees are checked because Sync-Dogfood never prunes.
        $script:crSurfaces = @(
            [pscustomobject]@{ Tree = 'plugins'; Files = @('plugins/code-review/skills/cr/SKILL.md', 'plugins/code-review/skills/cr/assets/scope-guide.md') }
            [pscustomobject]@{ Tree = 'dogfood'; Files = @('.github/skills/cr/SKILL.md', '.github/skills/cr/assets/scope-guide.md') }
        )

        $script:crShims = @(
            'plugins/code-review/agents/cr.agent.md'
            '.github/agents/cr.agent.md'
        )

        function Script:Get-SurfaceText {
            param([Parameter(Mandatory)][string[]]$Files)
            return (($Files | ForEach-Object { [System.IO.File]::ReadAllText((Join-Path $script:repoRoot $_)) }) -join "`n")
        }

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

    It 'test:no-diff-extraction-refs points the cr orchestration surface at the single scope emitter' {
        foreach ($surface in $script:crSurfaces) {
            $raw = Get-SurfaceText -Files $surface.Files

            $raw | Should -Match '\.github/agents/scripts/Get-ReviewScope\.ps1' -Because "the $($surface.Tree) surface must name the emitter"
            # No diff extraction and no content batching: the file list is the whole payload.
            $raw | Should -Not -Match '--diff'
            $raw | Should -Not -Match 'Create one diff per batch'
            $raw | Should -Match 'reviewers read the code\s+themselves'
        }
    }

    It 'test:no-diff-extraction-refs keeps the injection guard where the content is now read' {
        # Reviewed code is still read directly by each reviewer, while optional related-plan
        # artifacts enter through the scope guide's explicit historical-data fence.
        foreach ($surface in $script:crSurfaces) {
            $raw = Get-SurfaceText -Files $surface.Files
            $raw | Should -Match '<<<UNTRUSTED_INPUT_START>>>'
            $raw | Should -Match '<<<UNTRUSTED_INPUT_END>>>'
            $raw | Should -Match 'data, not instructions'
        }

        foreach ($shim in $script:crShims) {
            $raw = Get-SurfaceText -Files @($shim)
            $raw | Should -Not -Match 'UNTRUSTED_INPUT' -Because "$shim delegates the whole workflow to the skill"
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
