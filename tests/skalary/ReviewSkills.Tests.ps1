#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Plan b0c0d3 REQ-12: /cr and /dr are skills that own the orchestration; the agents are shims that
# read the skill by path and keep their handoff buttons; the prompts are shortcuts into the skills.
Describe 'Review skills, shims, and prompts' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path

        $script:reviews = @(
            [pscustomobject]@{
                Id = 'cr'
                Plugin = 'code-review'
                Handoff = 'Fix selected findings'
                Concerns = @('cr-security', 'cr-correctness-reliability', 'cr-architecture-patterns',
                    'cr-performance', 'cr-testing-evidence', 'cr-maintainability-consistency',
                    'cr-operability-observability')
            }
            [pscustomobject]@{
                Id = 'dr'
                Plugin = 'design-review'
                Handoff = 'Update plan'
                Concerns = @('dr-security', 'dr-correctness-reliability', 'dr-architecture-patterns',
                    'dr-performance', 'dr-testing-evidence', 'dr-maintainability-consistency',
                    'dr-operability-observability')
            }
        )

        function Script:Get-RepoText {
            param([Parameter(Mandatory)][string]$Relative)
            $path = Join-Path $script:repoRoot $Relative
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                throw "Expected file not found: $Relative"
            }
            return [System.IO.File]::ReadAllText($path)
        }

        function Script:Get-Body {
            param([Parameter(Mandatory)][string]$Text)
            return ($Text -replace '(?s)^---\r?\n.*?\r?\n---\r?\n?', '')
        }

        function Script:Get-ManifestDests {
            param([Parameter(Mandatory)][string]$Plugin)
            $manifest = Get-RepoText -Relative "plugins/$Plugin/plugin.json" | ConvertFrom-Json -Depth 50
            return @($manifest.files | ForEach-Object { [string]$_.dest })
        }
    }

    It 'test:cr-dr-skill-shim-parity ships a skill that owns the orchestration, installed in both trees' {
        foreach ($review in $script:reviews) {
            $id = $review.Id
            $skillRelative = "plugins/$($review.Plugin)/skills/$id/SKILL.md"
            $skill = Get-RepoText -Relative $skillRelative

            # The skill, not the agent, is what a CLI run can execute, so it must carry the workflow:
            # locate the scope, dispatch the concerns, collate through the formatter.
            $skill | Should -Match "(?m)^name:\s*$id\s*$"
            $skill | Should -Match '(?m)^user-invocable:\s*true\s*$'
            (Get-Body -Text $skill) | Should -Match "\./assets/dispatch-guide\.md"
            (Get-Body -Text $skill) | Should -Match "\.github/skills/$id/scripts/Build-ReviewReport\.ps1"
            (Get-Body -Text $skill) | Should -Match '(?m)^##\s+Step\s+\d'

            # Installation must materialize it: declared in the manifest and present in the dogfood tree.
            (Get-ManifestDests -Plugin $review.Plugin) | Should -Contain "skills/$id/SKILL.md"
            $dogfood = Get-RepoText -Relative ".github/skills/$id/SKILL.md"
            $dogfood | Should -Be $skill
        }
    }

    It 'test:cr-dr-skill-shim-parity reduces both agents to shims that read the skill and keep their handoff' {
        foreach ($review in $script:reviews) {
            $id = $review.Id
            foreach ($relative in @("plugins/$($review.Plugin)/agents/$id.agent.md", ".github/agents/$id.agent.md")) {
                $raw = Get-RepoText -Relative $relative
                $body = Get-Body -Text $raw

                # Delegation, not duplication: the shim names the skill by path...
                $body | Should -Match "skills/$id/SKILL\.md"

                # ...and carries none of the workflow the skill owns. Every token below is a step the
                # skill (or one of its assets) defines; restating any of it here creates a second copy
                # that drifts silently.
                foreach ($owned in @('Get-ReviewScope', 'dispatch-guide', 'Build-ReviewReport',
                        'concern-ledger-map', 'Recommendations', 'UNTRUSTED_INPUT')) {
                    $body | Should -Not -Match ([regex]::Escape($owned)) -Because "$relative must delegate '$owned' to the skill"
                }
                $body | Should -Not -Match '(?m)^\|\s*\*\*Severity\*\*' -Because "$relative must not restate the report layout"

                # The shim exists for what a skill cannot express: the handoff button and the
                # subagent roster the orchestrator is allowed to dispatch.
                $raw | Should -Match ([regex]::Escape("label: $($review.Handoff)"))
                foreach ($concern in $review.Concerns) {
                    $raw | Should -Match ([regex]::Escape($concern))
                }
            }
        }
    }

    It 'test:cr-dr-skill-shim-parity gives cr and dr the same shape' {
        $shapes = foreach ($review in $script:reviews) {
            $skillBody = Get-Body -Text (Get-RepoText -Relative "plugins/$($review.Plugin)/skills/$($review.Id)/SKILL.md")
            $agentBody = Get-Body -Text (Get-RepoText -Relative "plugins/$($review.Plugin)/agents/$($review.Id).agent.md")
            [pscustomobject]@{
                SkillSteps = @([regex]::Matches($skillBody, '(?m)^##\s+Step\s+\d')).Count -ge 5
                SkillCollates = $skillBody -match 'Build-ReviewReport'
                AgentIsThin = @(($agentBody -split "`r?`n") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -le 30
                PromptDelegates = (Get-Body -Text (Get-RepoText -Relative "plugins/$($review.Plugin)/prompts/$($review.Id).prompt.md")) -match "skills/$($review.Id)/SKILL\.md"
            }
        }

        # Parity is the point: one review type quietly keeping its logic in the agent would make the
        # CLI and VS Code entry points behave differently for the same review.
        @($shapes | Where-Object { -not $_.SkillSteps }) | Should -BeNullOrEmpty
        @($shapes | Where-Object { -not $_.SkillCollates }) | Should -BeNullOrEmpty
        @($shapes | Where-Object { -not $_.AgentIsThin }) | Should -BeNullOrEmpty
        @($shapes | Where-Object { -not $_.PromptDelegates }) | Should -BeNullOrEmpty
    }

    It 'test:cr-dr-skill-shim-parity shares one dispatch and collation definition across both skills' {
        # Dispatch policy and report collation are shared contracts; two copies that can drift are
        # how one review type ends up on a different roster or budget than the other.
        foreach ($asset in @('dispatch-guide.md', 'collation-guide.md', 'concern-ledger-map.md')) {
            $cr = Get-RepoText -Relative "plugins/code-review/skills/cr/assets/$asset"
            $dr = Get-RepoText -Relative "plugins/design-review/skills/dr/assets/$asset"
            $dr | Should -Be $cr -Because "$asset must be byte-identical across the two review skills"
        }
    }
}
