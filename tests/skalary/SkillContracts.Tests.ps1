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
}
