#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Phase 2.6 cutover guards. The bespoke Tier-2 backend (tests/evals/EvalLlm.psm1) discovers
# cases purely by globbing plugins/*/evals/llm/*.eval.json (Invoke-LlmEvalSuite), and the waza
# runner (Invoke-WazaEvals.ps1) discovers plugins/*/evals/waza/eval.yaml. So a plugin is "on
# waza" exactly when it has a waza spec and NO legacy llm JSON — deleting the JSON is the
# cut-off. These tests lock that state so a migrated plugin can never silently regress back
# onto the legacy backend, while KEEPING EvalLlm.psm1 + the deferred design-notes cases intact
# until Phase 4 (DR-P7: no false atomic delete; RISK-14: design-notes coverage not orphaned).

Describe 'legacy backend cutover (plan 2.6)' {
    BeforeAll {
        $here = Split-Path -Parent $PSCommandPath
        $repoDir = (Resolve-Path (Join-Path $here '..' '..')).Path
        $script:repoDir = $repoDir
        $script:pluginsRoot = Join-Path $repoDir 'plugins'

        # Plugins deliberately still on the legacy backend (Tier-2 not yet migrated). design-notes
        # ships 3 prompt-artifact cases excluded from waza until the prompts->skills workstream
        # (plan §7 / Phase 4). Keep this set TIGHT — anything else with legacy JSON is a regression.
        $script:deferredPlugins = @('design-notes')

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

        It 'test:migrated-off-legacy the 5 migrated plugins each ship a waza spec' {
            foreach ($name in @('code-review', 'design-review', 'autopilot', 'continue-implementation', 'create-implementation-plan')) {
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

    Context 'test:legacy-module-intact — EvalLlm.psm1 + deferred coverage survive (DR-P7 / RISK-14; full delete is 4.4)' {
        It 'test:legacy-module-intact tests/evals/EvalLlm.psm1 still exists (no false atomic delete)' {
            Test-Path -LiteralPath (Join-Path $script:repoDir 'tests/evals/EvalLlm.psm1') -PathType Leaf | Should -BeTrue
        }

        It 'test:legacy-module-intact the deferred design-notes plugin still carries its legacy llm cases (coverage not orphaned)' {
            $json = @(Script:Get-LegacyLlmJson -PluginName 'design-notes')
            $json.Count | Should -BeGreaterThan 0
        }
    }
}
