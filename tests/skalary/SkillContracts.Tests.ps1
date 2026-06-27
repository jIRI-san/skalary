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
}
