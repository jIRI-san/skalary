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
        $text | Should -Match 'validate-plan'
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
        $text | Should -Match 'allowlist-clean'
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
        $autopilot | Should -Match '(?i)Full-repository validation.*explicit opt-in parameter'
        $execution | Should -Match '(?i)affected surface'
        $execution | Should -Match '(?i)direct consumers'
        $crosscheck | Should -Match '(?i)Full-repository validation.*explicit opt-in parameter'
        $drafting | Should -Match '(?i)focused validation'
    }

    It 'test:validation-cadence bounds focused Fast and reserves full and Slow for plan finalization' {
        $autopilot = Get-SkillText -RelativePath 'plugins/autopilot/agents/autopilot.agent.md'
        $execution = Get-SkillText -RelativePath 'plugins/continue-implementation/skills/ci/assets/execution-guide.md'
        $crosscheck = Get-SkillText -RelativePath 'plugins/continue-implementation/skills/ci/assets/crosscheck-guide.md'

        foreach ($text in @($autopilot, $execution, $crosscheck)) {
            $text | Should -Match '(?i)Fast'
            $text | Should -Match '(?i)Slow'
        }
        $autopilot | Should -Match '(?i)runtime observations alone never trigger a retry'
        $autopilot | Should -Match '(?i)Slow.*exactly once'
        $autopilot | Should -Match 'AUTOPILOT_CONTAINER=true'
        $autopilot | Should -Match '(?i)-FullRepository'
        $execution | Should -Match '(?i)Do not run repository-wide validation.*during a step'
        $crosscheck | Should -Match '(?i)never rerun solely because of them'
        $crosscheck | Should -Match '(?i)-TestPath'
        $crosscheck | Should -Match '(?i)-FullRepository'
        $crosscheck | Should -Match '(?i)Slow suite exactly once'
    }

    It 'test:dogfood-no-drift keeps .github/skills/ in sync with plugins/ sources' {
        $sync = Join-Path $repoRoot 'scripts/skalary/Sync-Dogfood.ps1'
        $output = & $sync -WhatIf *>&1
        $LASTEXITCODE | Should -Be 0
        ($output -join "`n") | Should -Match 'Changed file count: 0'
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
