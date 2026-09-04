#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Skill contract token guards' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path

        function Get-SkillText {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [string]$RelativePath
            )

            $full = Join-Path $repoRoot ($RelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
            if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
                throw "Missing skill file '$RelativePath'."
            }
            return Get-Content -LiteralPath $full -Raw -Encoding utf8
        }
    }

    It 'test:ci-skill-retains-judgment keeps the resume/reset and human-stop judgment in ci/SKILL.md' {
        $text = Get-SkillText -RelativePath 'plugins/continue-implementation/skills/ci/SKILL.md'
        $text | Should -Match '(?i)resume'
        $text | Should -Match '(?i)reset'
        $text | Should -Match '\[~\]'
        $text | Should -Match '@human'
        $text | Should -Match '\[discovery\]'
    }

    It 'test:ci-skill-planstate routes ci/SKILL.md state through Get-PlanState and the validate-plan gate' {
        $text = Get-SkillText -RelativePath 'plugins/continue-implementation/skills/ci/SKILL.md'
        $text | Should -Match 'Get-PlanState'
        $text | Should -Match ([regex]::Escape(
                '.github/skills/ci/scripts/Test-Plan.ps1'
            ))
    }

    It 'test:ci-skill-epic-host-route keeps epic selection inside the fixed installed host wrapper' {
        $text = Get-SkillText -RelativePath 'plugins/continue-implementation/skills/ci/SKILL.md'
        $text | Should -Match 'Kind: epic'
        $text | Should -Match ([regex]::Escape(
                "'.github/skills/autopilot/scripts'"
            ))
        $text | Should -Match "'Invoke-EpicAutopilot\.ps1'"
        $text | Should -Match '-Epic <state\.EpicId>'
        $text | Should -Match '-Target HEAD -RepoRoot <canonical-repo-root>'
        $text | Should -Match 'Do not\s+select `NextChild`'
        $text | Should -Match 'AUTOPILOT_CONTAINER=true'
        $text | Should -Match 'preserve its exact process exit\s+status'
    }

    It 'test:cip-skill-scripts routes cip/SKILL.md through the deterministic plan scripts' {
        $text = Get-SkillText -RelativePath 'plugins/create-implementation-plan/skills/cip/SKILL.md'
        $text | Should -Match 'New-Plan'
        $text | Should -Match 'Set-PlanStage'
        $text | Should -Match 'Add-WorkflowNote'
        $text | Should -Match 'Test-Plan\.ps1'
    }

    It 'test:autopilot-plan-id resolves the plan id through the canonical scheme, not a raw NNN' {
        $text = Get-SkillText -RelativePath 'plugins/autopilot/agents/autopilot.agent.md'
        $text | Should -Match 'Resolve-Plan'
        $text | Should -Match 'plan-id'
        $text | Should -Match 'plan-<plan-id> step'
    }

    It 'test:autopilot-dual-format emits the shared golden receipt and harvests from capture.md' {
        $text = Get-SkillText -RelativePath 'plugins/autopilot/agents/autopilot.agent.md'
        $text | Should -Match 'Build-EvidenceReceipt'
        $text | Should -Match 'capture\.md'
        $text | Should -Match 'Invoke-PhaseHarvest'
    }

    It 'test:review-cycle-cap binds ci and autopilot to three cycles plus an operator decision' {
        $autopilot = Get-SkillText -RelativePath 'plugins/autopilot/agents/autopilot.agent.md'
        $execution = Get-SkillText -RelativePath 'plugins/continue-implementation/skills/ci/assets/execution-guide.md'
        $crosscheck = Get-SkillText -RelativePath 'plugins/continue-implementation/skills/ci/assets/crosscheck-guide.md'

        foreach ($text in @($autopilot, $crosscheck)) {
            $text | Should -Match 'ReviewCycleGate\.ps1'
            $text | Should -Match '(?i)three-cycle|three review cycles|three rounds'
            $text | Should -Match 'plan-finalization'
        }
        $execution | Should -Match 'not dispatched per implementation step'
        $execution | Should -Match '/cr post-phase'
        $crosscheck | Should -Match 'vscode_askQuestions'
        $crosscheck | Should -Match 'Continue looping'
        $crosscheck | Should -Match 'Wrap up'
        $crosscheck | Should -Match '@cr post-phase'
        $crosscheck | Should -Match '@cr plan-finalization branch'
        $autopilot | Should -Match 'primary-only post-phase code review'
        $autopilot | Should -Match 'Primary \+ secondary final code review'
        $autopilot | Should -Match 'exit `42`'
        $autopilot | Should -Match 'cannot grant itself continuation'
    }

    It 'test:focused-validation keeps step checks local and the complete gate at plan completion' {
        $autopilot = Get-SkillText -RelativePath 'plugins/autopilot/agents/autopilot.agent.md'
        $execution = Get-SkillText -RelativePath 'plugins/continue-implementation/skills/ci/assets/execution-guide.md'
        $crosscheck = Get-SkillText -RelativePath 'plugins/continue-implementation/skills/ci/assets/crosscheck-guide.md'
        $drafting = Get-SkillText -RelativePath 'plugins/create-implementation-plan/skills/cip/assets/drafting-guide.md'

        $autopilot | Should -Match '(?i)affected surface'
        $autopilot | Should -Match '(?i)Broad .-FullRepository.*direct operator choices'
        $execution | Should -Match '(?i)affected surface'
        $execution | Should -Match '(?i)direct consumers'
        $execution | Should -Match '(?i)Broad .-FullRepository.*direct operator invocations only'
        $crosscheck | Should -Match '(?i)Broad .-FullRepository.*direct operator choices'
        $drafting | Should -Match '(?i)focused validation'
    }

    It 'test:validation-cadence keeps routine and final validation local, focused, and operator-bounded' {
        $autopilot = Get-SkillText -RelativePath 'plugins/autopilot/agents/autopilot.agent.md'
        $execution = Get-SkillText -RelativePath 'plugins/continue-implementation/skills/ci/assets/execution-guide.md'
        $crosscheck = Get-SkillText -RelativePath 'plugins/continue-implementation/skills/ci/assets/crosscheck-guide.md'

        foreach ($text in @($autopilot, $execution, $crosscheck)) {
            $text | Should -Match '(?i)affected surface|affected-surface'
            $text | Should -Match '(?i)focused'
            $text | Should -Match '(?i)direct operator'
            $text | Should -Match '(?i)Waza'
            $text | Should -Not -Match '(?i)\bSlow\b'
        }
        $autopilot | Should -Match '(?i)never widen scope automatically'
        $execution | Should -Match '(?i)never automatically retry or widen scope'
        $crosscheck | Should -Match '(?i)never widen scope automatically'
        $autopilot | Should -Match '(?i)no hosted-workflow requirement'
        $crosscheck | Should -Match '(?i)no hosted-workflow requirement'

        $package = Get-Content -LiteralPath (Join-Path $repoRoot 'package.json') -Raw |
            ConvertFrom-Json
        [string]$package.scripts.build | Should -Match 'validate\.ps1 -Path '
        [string]$package.scripts.test | Should -Match 'Run-UnitTests\.ps1 -TestPath '
        (@($package.scripts.PSObject.Properties.Value) -join "`n") |
            Should -Not -Match 'FullRepository|Invoke-WazaEvals|Test-Evals|-Tier Slow'
        @(Get-ChildItem -LiteralPath (Join-Path $repoRoot '.github/workflows') `
                -File -ErrorAction SilentlyContinue).Count | Should -Be 0

    }

    It 'test:dogfood-no-drift keeps .github/skills/ in sync with plugins/ sources' {
        $sync = Join-Path $repoRoot 'scripts/skalary/Sync-Dogfood.ps1'
        $output = & $sync -WhatIf *>&1
        $LASTEXITCODE | Should -Be 0
        ($output -join "`n") | Should -Match 'Changed file count: 0'
    }

    It 'test:LocalFirst.HostErgonomics keeps choices equivalent and script commands directly invokable' {
        $skills = @(
            'plugins/continue-implementation/skills/ci/SKILL.md',
            'plugins/create-implementation-plan/skills/cip/SKILL.md',
            'plugins/create-implementation-plan/skills/cep/SKILL.md',
            'plugins/plugin-manager/skills/install-plugin/SKILL.md',
            'plugins/plugin-manager/skills/update-plugin/SKILL.md',
            'plugins/plugin-manager/skills/uninstall-plugin/SKILL.md',
            'plugins/process-pr-comments/skills/process-pr-comments/SKILL.md',
            'plugins/work-hierarchy-sync/skills/work-hierarchy-sync/SKILL.md'
        )

        foreach ($skill in $skills) {
            $text = Get-SkillText -RelativePath $skill
            $text | Should -Match 'VS Code'
            $text | Should -Match 'Copilot CLI'
            $text | Should -Match 'vscode_askQuestions'
            $text | Should -Match 'numbered'
            $text | Should -Match '`effort: <1-10>`'
            $text | Should -Match '`complexity: <1-10>`'
            $text | Should -Match 'same label and decision context'
            $text | Should -Not -Match '(?i)(?:pwsh|powershell)\s+(?:-NoProfile\s+)?-File\s+\.github/skills/'
            $text | Should -Not -Match '(?im)^\s*(?:pwsh|powershell)\b.*\s-File\s'

            $name = Split-Path (Split-Path $skill -Parent) -Leaf
            $installed = Get-SkillText -RelativePath ".github/skills/$name/SKILL.md"
            $installed | Should -BeExactly $text
        }

        $instructions = Get-SkillText -RelativePath '.github/copilot-instructions.md'
        $devRules = Get-SkillText -RelativePath 'docs/design-notes/project/dev-rules.design.md'
        foreach ($text in @($instructions, $devRules)) {
            $text | Should -Match 'VS Code'
            $text | Should -Match 'Copilot CLI'
            $text | Should -Match '`effort: <1-10>`'
            $text | Should -Match '`complexity: <1-10>`'
            $text | Should -Match '(?i)direct'
            $text | Should -Match '\.github/skills/'
        }

        $pluginManager = Get-SkillText -RelativePath 'docs/design-notes/architecture/plugin-manager.design.md'
        $pluginManager | Should -Match 'directly'
        $pluginManager | Should -Match 'plain path string'
        $pluginManager | Should -Match 'Get`/`Find`/`Test`/`Validate'
        $pluginManager | Should -Match 'Install`/`Uninstall`/`Update`/`Remove`/`Set'

        $ci = Get-SkillText -RelativePath 'plugins/continue-implementation/skills/ci/SKILL.md'
        foreach ($option in @(
                'Interactive \(approve each step\)',
                'Autopilot \(autoapprove\)',
                'Host autopilot',
                'Container autopilot',
                'Sandbox autopilot'
            )) {
            $pattern = '(?m)^\s*\| \*\*{0}\*\* .*\| `effort: (?:10|[1-9])` \| `complexity: (?:10|[1-9])` \|$' -f $option
            $ci | Should -Match $pattern
        }
        $ci | Should -Match '\*\*One phase\*\* \(`effort: (?:10|[1-9])`,\s*`complexity: (?:10|[1-9])`\)'
        $ci | Should -Match '\*\*Whole plan\*\* \(`effort: (?:10|[1-9])`, `complexity: (?:10|[1-9])`\)'

        $scoredSkills = @{
            'plugins/plugin-manager/skills/install-plugin/SKILL.md' =
                @('Yes — add only the listed read-only paths', 'No — keep prompting')
            'plugins/plugin-manager/skills/update-plugin/SKILL.md' =
                @('Force — overwrite local changes', 'Preserve — skip modified files')
            'plugins/plugin-manager/skills/uninstall-plugin/SKILL.md' =
                @('Proceed — remove the management skills', 'Cancel — leave them installed',
                    'Force — remove despite named dependents', 'Cancel — preserve the dependency graph',
                    'Force — overwrite local changes', 'Preserve — skip modified files')
            'plugins/process-pr-comments/skills/process-pr-comments/SKILL.md' =
                @('stop.*preserve the current worktree', 'continue-with-explicit-paths',
                    'approve-push', 'reject-push', 'approve — post this exact body',
                    'edit — revise before posting', 'skip — leave the thread unchanged')
            'plugins/work-hierarchy-sync/skills/work-hierarchy-sync/SKILL.md' =
                @('stop — leave the mapping unchanged', 'adopt-exact-issue',
                    'stop — perform no remote writes', 'apply-exact-digest')
            'plugins/create-implementation-plan/skills/cep/SKILL.md' =
                @('keep — retain the accepted cut', 'simplify — remove unnecessary mechanism',
                    'split — separate overlapping ownership', 'defer — leave optional work out')
        }
        foreach ($entry in $scoredSkills.GetEnumerator()) {
            $text = (Get-SkillText -RelativePath $entry.Key) -replace '\s+', ' '
            foreach ($label in $entry.Value) {
                $pattern = '(?s){0}.{{0,180}}`effort: (?:10|[1-9])`.{{0,80}}`complexity: (?:10|[1-9])`' -f $label
                $text | Should -Match $pattern
            }
        }

        $scoredAssets = @{
            'plugins/create-implementation-plan/skills/cip/assets/interview-guide.md' =
                @('Confirm intent — use', 'Revise intent — correct', 'Approve design — keep',
                    'Revise design — correct', 'manual — approve each step',
                    'host autopilot — run headlessly on the host',
                    'container autopilot — run in the local container',
                    'sandbox autopilot — run in the configured sandbox',
                    'phase-at-a-time — stop after one phase', 'whole-plan — continue',
                    'Confirm — draft', 'Revise — correct')
            'plugins/create-implementation-plan/skills/cip/assets/dr-guide.md' =
                @('Continue reviewing — authorize', 'Start implementation — retain')
            'plugins/create-implementation-plan/skills/cep/assets/decomposition-guide.md' =
                @('Confirm — accept this child cut', 'Revise — change the displayed cut')
            'plugins/continue-implementation/skills/ci/assets/crosscheck-guide.md' =
                @('\*\*Continue\*\*', '\*\*Revise\*\*', '\*\*Stop\*\*',
                    'Run `/pfb`', 'Skip `/pfb`', 'Run `/si`', 'Skip `/si`', 'Continue looping', 'Wrap up')
        }
        foreach ($entry in $scoredAssets.GetEnumerator()) {
            $text = Get-SkillText -RelativePath $entry.Key
            foreach ($label in $entry.Value) {
                $pattern = '(?s){0}.{{0,120}}`effort: (?:10|[1-9])`.{{0,80}}`complexity: (?:10|[1-9])`' -f $label
                $text | Should -Match $pattern
            }
        }

        foreach ($asset in @(
                'plugins/continue-implementation/skills/ci/assets/crosscheck-guide.md',
                'plugins/continue-implementation/skills/ci/assets/execution-guide.md',
                'plugins/create-implementation-plan/skills/cip/assets/drafting-guide.md',
                'plugins/create-implementation-plan/skills/cip/assets/dr-guide.md',
                'plugins/create-implementation-plan/skills/cip/assets/interview-guide.md',
                'plugins/create-implementation-plan/skills/cep/assets/decomposition-guide.md'
            )) {
            $text = Get-SkillText -RelativePath $asset
            $text | Should -Not -Match '(?i)(?:pwsh|powershell)\s+(?:-NoProfile\s+)?-File\s+\.github/skills/'
            $text | Should -Not -Match '(?m)^\s*\$\w+\s*=\s*&\s+\.github/skills/'
        }
    }

    It 'test:LocalFirst.AgentCostBudgets keeps advisory dispatch and context limits explicit' {
        $text = Get-SkillText -RelativePath 'docs/design-notes/explorations/agent-cost-optimization.design.md'

        $text | Should -Match '\*\*2 default\*\*'
        $text | Should -Match '\*\*5 maximum\*\*'
        $text | Should -Match 'Primary plus one availability fallback'
        $text | Should -Match 'At most \*\*5 supporting artifacts\*\*'
        $text | Should -Match '\*\*600-word target\*\*'
        $text | Should -Match '\*\*1,200-word cap\*\*'
        $text | Should -Match 'No policy engine, receipt, schema, telemetry pipeline, or runtime budget service'
    }

    It 'test:manifest-coverage registers every ci/cip skill asset in plugin.json files[]' {
        foreach ($plugin in @('continue-implementation', 'create-implementation-plan')) {
            $pluginRoot = Join-Path $repoRoot (Join-Path 'plugins' $plugin)
            $manifest = Get-Content -LiteralPath (Join-Path $pluginRoot 'plugin.json') -Raw | ConvertFrom-Json -Depth 100
            $declared = @($manifest.files | ForEach-Object { ($_.src -replace '\\', '/') })

            $skillsDir = Join-Path $pluginRoot 'skills'
            # Scripts are bundled by closure (`Sync-PluginScripts`), so a script can appear in the
            # bundle without anyone editing the manifest — and a bundled-but-unregistered script is
            # simply absent after install, failing at the moment its caller needs it.
            $assets = Get-ChildItem -LiteralPath $skillsDir -Recurse -File |
                Where-Object { $_.Extension -in @('.md', '.ps1', '.psm1') }
            foreach ($asset in $assets) {
                $rel = ($asset.FullName.Substring($pluginRoot.Length + 1)) -replace '\\', '/'
                $declared | Should -Contain $rel -Because "asset '$rel' must be registered in $plugin/plugin.json files[]"
            }
        }
    }
}
