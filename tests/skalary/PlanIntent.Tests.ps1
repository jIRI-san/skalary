#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'direct plan intent contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:cipSkill = Join-Path $script:repoRoot 'plugins/create-implementation-plan/skills/cip/SKILL.md'
        $script:ciSkill = Join-Path $script:repoRoot 'plugins/continue-implementation/skills/ci/SKILL.md'
        $script:newPlan = Join-Path $script:repoRoot 'scripts/skalary/New-Plan.ps1'
        $script:intentSections = @(
            'Goal', 'Desired outcome', 'Success signals', 'Non-goals', 'Definition of done'
        )
    }

    It 'test:cip-intent-gate keeps intent confirmation in the active planning skill' {
        $content = Get-Content -LiteralPath $script:cipSkill -Raw
        $content | Should -Match 'Confirm current intent first'
        $content | Should -Match 'Before final drafting, confirm the current intent, requirements, risks, and decisions together'
        $content | Should -Match 'planning-confirmed marker'
    }

    It 'test:ci-reads-intent protects intent through the Git criteria baseline' {
        $content = Get-Content -LiteralPath $script:ciSkill -Raw
        $content | Should -Match 'Before any checklist, branch,\s*worktree, log, or source mutation'
        $content | Should -Match 'Test-PlanCriteriaBaseline'
        $content | Should -Match 'intent,\s*requirements, risks, or decisions'
    }

    It 'test:new-plan-scaffolds-intent writes all confirmed intent sections' {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $script:newPlan,
            [ref]$null,
            [ref]$null
        )
        $function = $ast.Find({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq 'Get-PlanAssetScaffold'
            }, $true)
        $function | Should -Not -BeNullOrEmpty
        $scaffold = & ([scriptblock]::Create(
                $function.Extent.Text + "`nGet-PlanAssetScaffold"
            ))
        $headings = @(
            [regex]::Matches(
                (($scaffold['intent.md'] -replace "`r`n", "`n")),
                '(?m)^##\s+(.+?)\s*$'
            ) | ForEach-Object { $_.Groups[1].Value }
        )
        $headings | Should -Be $script:intentSections
    }

    It 'ships the active intent contract unchanged to dogfood' {
        foreach ($relative in @(
                'skills/cip/SKILL.md',
                'skills/ci/SKILL.md'
            )) {
            $source = if ($relative.StartsWith('skills/cip/')) {
                Join-Path $script:repoRoot "plugins/create-implementation-plan/$relative"
            }
            else {
                Join-Path $script:repoRoot "plugins/continue-implementation/$relative"
            }
            $installed = Join-Path $script:repoRoot ".github/$relative"
            (Get-FileHash -LiteralPath $installed -Algorithm SHA256).Hash |
                Should -BeExactly (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
        }
    }
}
