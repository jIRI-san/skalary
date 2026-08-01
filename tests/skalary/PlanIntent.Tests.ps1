#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Plan intent capture' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path

        $interviewGuidePath = Join-Path $repoRoot 'plugins/create-implementation-plan/skills/cip/assets/interview-guide.md'
        $dogfoodInterviewGuidePath = Join-Path $repoRoot '.github/skills/cip/assets/interview-guide.md'
        $cipSkillPath = Join-Path $repoRoot 'plugins/create-implementation-plan/skills/cip/SKILL.md'
        $intentTemplatePath = Join-Path $repoRoot 'plugins/create-implementation-plan/skills/cip/assets/intent-template.md'
        $dogfoodIntentTemplatePath = Join-Path $repoRoot '.github/skills/cip/assets/intent-template.md'
        $cipManifestPath = Join-Path $repoRoot 'plugins/create-implementation-plan/plugin.json'
        $ciSkillPath = Join-Path $repoRoot 'plugins/continue-implementation/skills/ci/SKILL.md'
        $executionGuidePath = Join-Path $repoRoot 'plugins/continue-implementation/skills/ci/assets/execution-guide.md'
        $crosscheckGuidePath = Join-Path $repoRoot 'plugins/continue-implementation/skills/ci/assets/crosscheck-guide.md'

        $readText = {
            param([string]$Path)
            (Get-Content -LiteralPath $Path -Raw) -replace "`r`n", "`n"
        }

        $interviewGuide = & $readText $interviewGuidePath
        $cipSkill = & $readText $cipSkillPath
        $ciSkill = & $readText $ciSkillPath
        $executionGuide = & $readText $executionGuidePath
        $crosscheckGuide = & $readText $crosscheckGuidePath

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

    Context 'intent template' {
        It 'test:cip-intent-gate ships an intent template whose sections match the gate and the scaffold' {
            Test-Path -LiteralPath $intentTemplatePath -PathType Leaf | Should -BeTrue

            $template = & $readText $intentTemplatePath
            $templateHeadings = @([regex]::Matches($template, '(?m)^##\s+(.+?)\s*$') | ForEach-Object { $_.Groups[1].Value })
            $templateHeadings | Should -Be $intentSections

            # Placeholders are what the gate blocks on; assert per section so a template shipped with a
            # bare instructional mention of TBD (and no actual placeholders) cannot pass.
            foreach ($section in $intentSections) {
                $body = [regex]::Match($template, "(?ms)^##\s+$([regex]::Escape($section))\s*`$(.*?)(?=^##\s|\z)").Groups[1].Value
                $body | Should -Match '(?m)^-?\s*TBD\s*$'
            }
        }

        It 'test:cip-intent-gate declares the intent template in the plugin manifest and installs it' {
            $manifest = Get-Content -LiteralPath $cipManifestPath -Raw | ConvertFrom-Json
            @($manifest.files | Where-Object { $_.src -eq 'skills/cip/assets/intent-template.md' }).Count | Should -Be 1

            Test-Path -LiteralPath $dogfoodIntentTemplatePath -PathType Leaf | Should -BeTrue
            (& $readText $dogfoodIntentTemplatePath) | Should -Be (& $readText $intentTemplatePath)
        }
    }

    Context 'ci reads intent' {
        It 'test:ci-reads-intent makes the intent asset a mandatory read before implementing a step' {
            $assetTable = [regex]::Match($ciSkill, '(?ms)^\s*\|\s*Asset\s*\|.*?^\s*$').Value
            $assetTable | Should -Match 'assets/intent\.md'

            $intentRow = [regex]::Match($ciSkill, '(?m)^\s*\|\s*`assets/intent\.md`\s*\|(?<when>.*?)\|\s*$').Groups['when'].Value
            $intentRow | Should -Not -BeNullOrEmpty
            $intentRow | Should -Match 'always'
            $intentRow | Should -Match 'before implementing any step'
            $intentRow | Should -Match 'crosscheck'
        }

        It 'test:ci-reads-intent anchors the execution loop on the layout-resolved intent asset' {
            $stepLoop = [regex]::Match($executionGuide, '(?ms)^##\s+Step loop\s*$(.*?)^##\s').Groups[1].Value
            $stepLoop | Should -Not -BeNullOrEmpty

            $firstItem = [regex]::Match($stepLoop, '(?ms)^1\.\s(.*?)^2\.\s').Groups[1].Value
            $firstItem | Should -Match 'intent\.md'
            $firstItem | Should -Match 'Resolve-PlanAssetPath'
        }

        It 'test:ci-reads-intent re-anchors against intent at phase and plan crosscheck' {
            foreach ($heading in @('Phase crosscheck', 'Plan crosscheck')) {
                $block = [regex]::Match($crosscheckGuide, "(?ms)^##\s+$([regex]::Escape($heading))\s*`$(.*?)^##\s").Groups[1].Value
                $block | Should -Not -BeNullOrEmpty
                $block | Should -Match 'intent'
            }

            # Re-anchoring is worthless if it happens after the phase is already declared done.
            $phaseBlock = [regex]::Match($crosscheckGuide, '(?ms)^##\s+Phase crosscheck\s*$(.*?)^##\s').Groups[1].Value
            $firstItem = [regex]::Match($phaseBlock, '(?ms)^1\.\s(.*?)^2\.\s').Groups[1].Value
            $firstItem | Should -Match 'intent'
        }

        It 'test:ci-reads-intent states the same block predicate as the cip intent gate' {
            # /cip blocks while ANY of the five sections is still TBD; /ci must refuse to guess on exactly
            # the same condition, or a partially-filled intent slips past the gate at execution time.
            $gateBlock = [regex]::Match($interviewGuide, '(?ms)^###\s+`intent`\s+gate\s*$(.*?)^###\s').Groups[1].Value
            $gateBlock | Should -Match '(?i)no\s+`?TBD`?\s+placeholder\s+in\s+any\s+of\s+the\s+five\s+sections'

            foreach ($text in @($ciSkill, $executionGuide)) {
                $text | Should -Match '(?i)missing,?\s+or\s+\*\*any\*\*\s+of\s+(its|the)\s+five\s+sections\s+is\s+still\s+a\s+`TBD`\s+placeholder'
            }
        }

        It 'test:ci-reads-intent keeps the ci intent instructions identical in the dogfood install' {
            foreach ($pair in @(
                    @{ Source = $ciSkillPath; Installed = (Join-Path $repoRoot '.github/skills/ci/SKILL.md') }
                    @{ Source = $executionGuidePath; Installed = (Join-Path $repoRoot '.github/skills/ci/assets/execution-guide.md') }
                    @{ Source = $crosscheckGuidePath; Installed = (Join-Path $repoRoot '.github/skills/ci/assets/crosscheck-guide.md') }
                )) {
                Test-Path -LiteralPath $pair.Installed -PathType Leaf | Should -BeTrue
                (& $readText $pair.Installed) | Should -Be (& $readText $pair.Source)
            }
        }
    }
}
