#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'review-run consumer distribution and callers' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:reviews = @(
            [pscustomobject]@{ Id = 'cr'; Plugin = 'code-review' }
            [pscustomobject]@{ Id = 'dr'; Plugin = 'design-review' }
        )

        function Script:Get-Text {
            param([Parameter(Mandatory)][string]$Relative)
            $path = Join-Path $script:repoRoot $Relative
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                throw "Expected file not found: $Relative"
            }
            return [System.IO.File]::ReadAllText($path)
        }
    }

    It 'test:ReviewReport.PayloadOwnershipAndDrift maps the complete root, plugin, dogfood, and registry closure' {
        $registry = Get-Text -Relative 'registry.json' | ConvertFrom-Json -Depth 100
        $closure = @(
            'Build-ReviewReport.ps1'
            'Get-ReviewRun.ps1'
            'PlanState.psm1'
            'Remove-ReviewRun.ps1'
            'ReviewRun.psm1'
            'schemas/review/review-admission.schema.json'
            'schemas/review/review-limits.schema.json'
            'schemas/review/review-manifest.schema.json'
            'schemas/review/review-plan.schema.json'
            'schemas/review/review-run.schema.json'
            'schemas/review/terminal-status.schema.json'
        )

        foreach ($review in $script:reviews) {
            $manifest = Get-Text -Relative "plugins/$($review.Plugin)/plugin.json" | ConvertFrom-Json -Depth 50
            $registered = @($registry.plugins | Where-Object { [string]$_.name -eq $review.Plugin })
            $registered.Count | Should -Be 1

            foreach ($relative in $closure) {
                $canonical = if ($relative.StartsWith('schemas/review/', [System.StringComparison]::Ordinal)) {
                    Join-Path $script:repoRoot $relative
                }
                else {
                    Join-Path $script:repoRoot "scripts/skalary/$relative"
                }
                $pluginRelative = "skills/$($review.Id)/scripts/$relative"
                foreach ($copy in @(
                        (Join-Path $script:repoRoot "plugins/$($review.Plugin)/$pluginRelative"),
                        (Join-Path $script:repoRoot ".github/$pluginRelative"))) {
                    Test-Path -LiteralPath $copy -PathType Leaf | Should -BeTrue
                    (Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash |
                        Should -Be (Get-FileHash -LiteralPath $canonical -Algorithm SHA256).Hash
                }
                @($manifest.files | ForEach-Object { [string]$_.dest }) | Should -Contain $pluginRelative
                @($registered[0].files | ForEach-Object { [string]$_.dest }) | Should -Contain $pluginRelative
            }

            $manifest.PSObject.Properties.Name | Should -Not -Contain 'scriptSidecars'
            $manifest.PSObject.Properties.Name | Should -Not -Contain 'schemas'
        }
    }

    It 'test:ReviewReport.SharedCallerExitIndependenceAndAbandonment pins one lifecycle for both callers' {
        $crGuide = Get-Text -Relative 'plugins/code-review/skills/cr/assets/collation-guide.md'
        $drGuide = Get-Text -Relative 'plugins/design-review/skills/dr/assets/collation-guide.md'
        $drGuide | Should -Be $crGuide

        foreach ($required in @(
                'Get-ReviewRun\.ps1 -ListIncomplete',
                'orchestrator-interrupted',
                'Freeze before dispatch',
                'Dispatch every frozen task exactly once',
                'Do not show one reviewer''s output to another reviewer',
                'Publish once',
                '\| `0` \|',
                '\| `5` \|',
                '\| `2` \|',
                '\| `3` \|',
                '\| `4` \|',
                'new UUID',
                'narrower scope',
                'Get-ReviewRun\.ps1 -View Summary\|Full',
                'verified full detail',
                'review-run\.manifest\.json',
                'Remove-ReviewRun\.ps1')) {
            $crGuide | Should -Match $required
        }
        $crGuide.IndexOf('Freeze before dispatch') | Should -BeLessThan $crGuide.IndexOf('Independent dispatch')

        $patterns = @(
            '###\s*\[\d+\]',
            '\|\s*\*\*Severity\*\*\s*\|',
            '(?m)^##\s+Recommendations\s*$',
            'Repeat for each finding'
        )

        foreach ($review in $script:reviews) {
            $skill = Get-Text -Relative "plugins/$($review.Plugin)/skills/$($review.Id)/SKILL.md"
            $agent = Get-Text -Relative "plugins/$($review.Plugin)/agents/$($review.Id).agent.md"
            $skill | Should -Match 'finalize every earlier frozen orphan'
            $skill | Should -Match 'Freeze exactly once'
            $skill | Should -Match 'Do not include any prior reviewer''s result'
            $skill | Should -Match 'retain all\s+outputs/outcomes in memory'
            $skill | Should -Not -Match '(?i)-Finding|\[pscustomobject\]|pwsh\s+-NoProfile\s+-Command'
            $agent | Should -Match '(?m)^tools:.*\bedit\b'
            $agent | Should -Match 'Absolute edit rule'
            $agent | Should -Match 'only the two computed review-run temporary JSON inputs'

            foreach ($concern in Get-ChildItem -LiteralPath (Join-Path $script:repoRoot "plugins/$($review.Plugin)/agents") `
                    -File -Filter "$($review.Id)-*.agent.md") {
                [System.IO.File]::ReadAllText($concern.FullName) |
                    Should -Match 'Never reproduce a suspected credential value'
            }

            foreach ($root in @("plugins/$($review.Plugin)", '.github')) {
                foreach ($candidate in @(
                        "$root/skills/$($review.Id)/SKILL.md",
                        "$root/skills/$($review.Id)/assets",
                        "$root/agents/$($review.Id).agent.md",
                        "$root/prompts/$($review.Id).prompt.md")) {
                    $full = Join-Path $script:repoRoot $candidate
                    $files = if (Test-Path -LiteralPath $full -PathType Container) {
                        @(Get-ChildItem -LiteralPath $full -Recurse -File -Filter '*.md')
                    }
                    elseif (Test-Path -LiteralPath $full -PathType Leaf) {
                        @(Get-Item -LiteralPath $full)
                    }
                    else { @() }
                    @($files).Count | Should -BeGreaterThan 0 -Because "$candidate is a required caller surface"
                    foreach ($file in $files) {
                        $raw = [System.IO.File]::ReadAllText($file.FullName)
                        foreach ($pattern in $patterns) { $raw | Should -Not -Match $pattern }
                    }
                }
            }
        }
    }

    It 'test:ReviewReport.AtomicLegacyRetirement removes the object API only after both consumers are installed' {
        $writer = Get-Text -Relative 'scripts/skalary/Build-ReviewReport.ps1'
        $writer | Should -Not -Match '(?i)ParameterSetName\s*=\s*''Legacy''|-Finding\b|-Model\b|InvocationCount|ReportTitle'
        $writer | Should -Match '\[ValidateSet\(''Freeze'', ''Publish''\)\]'
        Test-Path -LiteralPath (Join-Path $script:repoRoot 'tests/skalary/Build-ReviewReport.Tests.ps1') |
            Should -BeFalse

        foreach ($review in $script:reviews) {
            foreach ($tree in @(
                    "plugins/$($review.Plugin)/skills/$($review.Id)",
                    ".github/skills/$($review.Id)")) {
                foreach ($file in Get-ChildItem -LiteralPath (Join-Path $script:repoRoot $tree) -Recurse -File) {
                    if ($file.Extension -notin @('.md', '.ps1')) { continue }
                    $text = [System.IO.File]::ReadAllText($file.FullName)
                    $text | Should -Not -Match '(?i)-Finding\b|generated\s+\[pscustomobject\]|pwsh\s+-NoProfile\s+-Command'
                }
            }
        }
    }

}
