#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Stateless post-plan feedback' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:pfbPaths = @(
            'plugins/self-improvement/skills/pfb/SKILL.md',
            '.github/skills/pfb/SKILL.md'
        )
    }

    It 'test:PostPlanFeedback.Stateless retains the comparison and optional correction-plan handoff' {
        foreach ($path in $script:pfbPaths) {
            $text = Get-Content -LiteralPath (Join-Path $script:repoRoot $path) -Raw
            foreach ($section in @('Goal', 'Desired outcome', 'Success signals', 'Non-goals',
                    'Definition of done')) {
                $guide = Get-Content -LiteralPath (
                    Join-Path $script:repoRoot (
                        Split-Path -Parent $path
                    ) 'assets/feedback-guide.md'
                ) -Raw
                $guide | Should -Match ([regex]::Escape($section))
            }
            $text | Should -Match '`full`.+`partial`.+`missed`'
            $text | Should -Match '(?i)optional|If requested'
            $text | Should -Match '/cip'
            $text | Should -Match '(?i)without persistence|writes feedback state'
            $text | Should -Not -Match 'queue-guide|Update-FeedbackQueue|docs/feedback/queue'
        }
    }

    It 'test:SelfImprovement.Integration makes headless completion skip feedback state' {
        foreach ($path in @(
                'plugins/autopilot/agents/autopilot.agent.md',
                '.github/agents/autopilot.agent.md',
                'plugins/continue-implementation/skills/ci/SKILL.md',
                '.github/skills/ci/SKILL.md'
            )) {
            $text = Get-Content -LiteralPath (Join-Path $script:repoRoot $path) -Raw
            $text | Should -Match '(?i)headless.+skip'
            $text | Should -Match '(?i)never queues|never queue'
            $text | Should -Not -Match 'queue guide|Enqueue-SiDue'
        }
    }

    It 'test:SelfImprovement.ConsumerInstall declares no feedback queue or lifecycle payload' {
        $manifest = Get-Content -LiteralPath (
            Join-Path $script:repoRoot 'plugins/self-improvement/plugin.json'
        ) -Raw | ConvertFrom-Json -Depth 50
        $payload = $manifest | ConvertTo-Json -Depth 50

        $payload | Should -Not -Match 'queue|due|receipt|repair|archive|proposal-sync|cross-repo'
        @($manifest.scaffolds | Where-Object { $null -ne $_ }).Count | Should -Be 0
        @($manifest.files.dest) | Should -Contain 'skills/pfb/SKILL.md'
        @($manifest.files.dest) | Should -Contain 'skills/si/SKILL.md'
    }
}
