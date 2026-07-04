#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Phase 2.6 cutover guards. The bespoke Tier-2 backend (tests/evals/EvalLlm.psm1) discovers
# cases purely by globbing plugins/*/evals/llm/*.eval.json (Invoke-LlmEvalSuite), and the waza
# runner (Invoke-WazaEvals.ps1) discovers plugins/*/evals/waza/eval.yaml. So a plugin is "on
# waza" exactly when it has a waza spec and NO legacy llm JSON — deleting the JSON is the
# cut-off. These tests lock that state so a migrated plugin can never silently regress back
# onto the legacy backend. Phase 4.2 migrated design-notes onto waza (its legacy llm JSON is
# deleted), so the deferred set is now EMPTY; EvalLlm.psm1 is kept intact until Phase 4.4
# deletes it (DR-P7: no false atomic delete).

Describe 'legacy backend cutover (plan 2.6)' {
    BeforeAll {
        $here = Split-Path -Parent $PSCommandPath
        $repoDir = (Resolve-Path (Join-Path $here '..' '..')).Path
        $script:repoDir = $repoDir
        $script:pluginsRoot = Join-Path $repoDir 'plugins'

        # No plugins remain on the legacy backend: Phase 4.2 migrated design-notes (the last
        # deferred plugin) onto waza. Keep this set EMPTY — anything with legacy JSON is now a
        # regression.
        $script:deferredPlugins = @()

        $script:pluginDirs = @(Get-ChildItem -LiteralPath $script:pluginsRoot -Directory | Sort-Object Name)

        # Mirror the legacy backend's discovery EXACTLY (EvalLlm.psm1 Invoke-LlmEvalSuite): a single
        # RECURSIVE scan of plugins/ for *.eval.json, kept when the path contains an evals/llm/
        # segment at ANY depth, attributed to the top-level plugin folder. Reimplementing this
        # non-recursively would fail-open: a nested plugins/<p>/**/evals/llm/*.eval.json would run on
        # the legacy backend yet stay invisible to these guards. Byte-for-byte parity closes that hole.
        $script:legacyLlmByPlugin = @{}
        foreach ($f in @(Get-ChildItem -LiteralPath $script:pluginsRoot -Recurse -File -Filter '*.eval.json' -ErrorAction SilentlyContinue)) {
            $norm = $f.FullName.Replace('\', '/')
            if ($norm -match '/plugins/(?<plugin>[^/]+)/.*evals/llm/.*\.eval\.json$') {
                $plugin = $Matches['plugin']
                if (-not $script:legacyLlmByPlugin.ContainsKey($plugin)) { $script:legacyLlmByPlugin[$plugin] = @() }
                $script:legacyLlmByPlugin[$plugin] += $norm
            }
        }

        function Script:Get-LegacyLlmJson {
            param([string]$PluginName)
            if ($script:legacyLlmByPlugin.ContainsKey($PluginName)) { return @($script:legacyLlmByPlugin[$PluginName]) }
            return @()
        }

        function Script:Test-HasWazaSpec {
            param([string]$PluginDir)
            return (Test-Path -LiteralPath (Join-Path $PluginDir 'evals/waza/eval.yaml') -PathType Leaf)
        }
    }

    Context 'test:migrated-off-legacy — every plugin with a waza spec has NO legacy llm JSON left' {
        It 'test:migrated-off-legacy each waza-migrated plugin has zero evals/llm/*.eval.json' {
            $offenders = @()
            foreach ($p in $script:pluginDirs) {
                if (Script:Test-HasWazaSpec -PluginDir $p.FullName) {
                    $json = @(Script:Get-LegacyLlmJson -PluginName $p.Name)
                    if ($json.Count -gt 0) {
                        $offenders += ('{0}: {1}' -f $p.Name, ($json -join ', '))
                    }
                }
            }
            $offenders -join ' | ' | Should -BeExactly ''
        }

        It 'test:migrated-off-legacy the 6 migrated plugins each ship a waza spec' {
            foreach ($name in @('code-review', 'design-review', 'autopilot', 'continue-implementation', 'create-implementation-plan', 'design-notes')) {
                (Script:Test-HasWazaSpec -PluginDir (Join-Path $script:pluginsRoot $name)) | Should -BeTrue -Because "plugin $name should be migrated to waza"
            }
        }
    }

    Context 'test:no-legacy-llm-json — only the deferred plugins may retain legacy llm JSON' {
        It 'test:no-legacy-llm-json no plugin OUTSIDE the deferred set retains evals/llm/*.eval.json' {
            $offenders = @()
            foreach ($p in $script:pluginDirs) {
                if ($script:deferredPlugins -contains $p.Name) { continue }
                $json = @(Script:Get-LegacyLlmJson -PluginName $p.Name)
                if ($json.Count -gt 0) {
                    $offenders += ('{0}: {1}' -f $p.Name, ($json -join ', '))
                }
            }
            $offenders -join ' | ' | Should -BeExactly ''
        }
    }

    Context 'test:legacy-module-intact — EvalLlm.psm1 survives until the Phase 4.4 delete (DR-P7: no false atomic delete)' {
        It 'test:legacy-module-intact tests/evals/EvalLlm.psm1 still exists (no false atomic delete)' {
            Test-Path -LiteralPath (Join-Path $script:repoDir 'tests/evals/EvalLlm.psm1') -PathType Leaf | Should -BeTrue
        }
    }
}
