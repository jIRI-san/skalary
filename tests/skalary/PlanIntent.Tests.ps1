#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Plan intent capture' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path

        $interviewGuidePath = Join-Path $repoRoot 'plugins/create-implementation-plan/skills/cip/assets/interview-guide.md'
        $dogfoodInterviewGuidePath = Join-Path $repoRoot '.github/skills/cip/assets/interview-guide.md'
        $cipSkillPath = Join-Path $repoRoot 'plugins/create-implementation-plan/skills/cip/SKILL.md'

        $readText = {
            param([string]$Path)
            (Get-Content -LiteralPath $Path -Raw) -replace "`r`n", "`n"
        }

        $interviewGuide = & $readText $interviewGuidePath
        $cipSkill = & $readText $cipSkillPath

        # The five intent sections are the contract shared by the interview gate, the template, and the
        # New-Plan scaffold. Asserting the set (not the prose) keeps the test an invariant, not a snapshot.
        $intentSections = @('Goal', 'Desired outcome', 'Success signals', 'Non-goals', 'Definition of done')
    }

    Context 'interview guide' {
        It 'test:cip-intent-gate declares a blocking intent gate covering all five intent sections' {
            $interviewGuide | Should -Match '(?m)^###\s+`intent`\s+gate\s*$'

            $gateBlock = [regex]::Match($interviewGuide, '(?ms)^###\s+`intent`\s+gate\s*$(.*?)^###\s').Groups[1].Value
            $gateBlock | Should -Not -BeNullOrEmpty
            foreach ($section in $intentSections) {
                $gateBlock | Should -Match ([regex]::Escape($section))
            }

            $gateBlock | Should -Match 'intent\.md'
            $gateBlock | Should -Match 'blocks drafting'
            # Layout-resolved, never hand-built: every other asset instruction in these guides carries the
            # same caveat, and a hard-coded assets/ path breaks resumed legacy plans.
            $gateBlock | Should -Match 'Resolve-PlanAssetPath'
        }

        It 'test:cip-intent-gate section list matches the intent asset New-Plan scaffolds' {
            # The gate is only enforceable if the sections it demands are the sections the scaffold writes;
            # binding them here makes a rename on either side fail loud instead of silently disarming the gate.
            $newPlanScript = Join-Path $repoRoot 'scripts/skalary/New-Plan.ps1'
            $scaffold = & {
                $ast = [System.Management.Automation.Language.Parser]::ParseFile($newPlanScript, [ref]$null, [ref]$null)
                $fn = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-PlanAssetScaffold' }, $true)
                $fn | Should -Not -BeNullOrEmpty
                & ([scriptblock]::Create($fn.Extent.Text + "`nGet-PlanAssetScaffold"))
            }

            $scaffoldHeadings = @([regex]::Matches(($scaffold['intent.md'] -replace "`r`n", "`n"), '(?m)^##\s+(.+?)\s*$') |
                    ForEach-Object { $_.Groups[1].Value })
            $scaffoldHeadings | Should -Be $intentSections

            $gateBlock = [regex]::Match($interviewGuide, '(?ms)^###\s+`intent`\s+gate\s*$(.*?)^###\s').Groups[1].Value
            foreach ($section in $scaffoldHeadings) {
                $gateBlock | Should -Match ([regex]::Escape($section))
            }
        }

        It 'test:cip-intent-gate asks the intent questions before the rest of the question bank' {
            $questionBank = [regex]::Match($interviewGuide, '(?ms)^##\s+Question Bank\s*$(.*)$').Groups[1].Value
            $questionBank | Should -Not -BeNullOrEmpty

            $intentIndex = $questionBank.IndexOf('**Intent**')
            $goalsIndex = $questionBank.IndexOf('**Goals & scope**')
            $intentIndex | Should -BeGreaterThan -1
            $goalsIndex | Should -BeGreaterThan -1
            $intentIndex | Should -BeLessThan $goalsIndex
        }

        It 'test:cip-intent-gate wires intent into the pre-draft gate and the interview close' {
            $preDraftBlock = [regex]::Match($interviewGuide, '(?ms)^###\s+`pre-draft`\s+gate\s*$(.*?)^##\s').Groups[1].Value
            $preDraftBlock | Should -Match 'intent'

            $closing = [regex]::Match($interviewGuide, '(?ms)^##\s+Closing the interview\s*$(.*)$').Groups[1].Value
            $closing | Should -Match '`intent` gate'
        }

        It 'test:cip-intent-gate ships the same interview guide to the dogfood install' {
            Test-Path -LiteralPath $dogfoodInterviewGuidePath -PathType Leaf | Should -BeTrue
            (& $readText $dogfoodInterviewGuidePath) | Should -Be $interviewGuide
        }
    }

    Context 'cip orchestrator' {
        It 'test:cip-intent-gate routes the cip skill through the intent gate before drafting' {
            $stepTwo = [regex]::Match($cipSkill, '(?ms)^##\s+Step 2:.*?$(.*?)^##\s+Step 3:').Groups[1].Value
            $stepTwo | Should -Not -BeNullOrEmpty
            # The gate has to sit in a numbered orchestration step, not only in the prose summary.
            $stepTwo | Should -Match '(?m)^\d+\..*`intent`'
            $stepTwo | Should -Match 'intent\.md'
        }
    }
}
