#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Plan b0c0d3 REQ-18: report collation is a script both review types call, not prose each of them
# re-derives. These tests pin the two halves of that: the script is actually installed with each
# skill, and neither orchestrator describes the layout it produces.
Describe 'Build-ReviewReport bundling and callers' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:sourceScript = Join-Path $script:repoRoot 'scripts/skalary/Build-ReviewReport.ps1'

        $script:reviews = @(
            [pscustomobject]@{ Id = 'cr'; Plugin = 'code-review'; ReportTitle = 'Code Review' }
            [pscustomobject]@{ Id = 'dr'; Plugin = 'design-review'; ReportTitle = 'Design Review' }
        )

        function Script:Get-Text {
            param([Parameter(Mandatory)][string]$Relative)
            $path = Join-Path $script:repoRoot $Relative
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Expected file not found: $Relative" }
            return [System.IO.File]::ReadAllText($path)
        }
    }

    It 'test:build-reviewreport-bundled ships the formatter with both review skills, declared and registered' {
        $sourceText = [System.IO.File]::ReadAllText($script:sourceScript)
        $registry = Get-Text -Relative 'registry.json' | ConvertFrom-Json -Depth 100

        foreach ($review in $script:reviews) {
            $relative = "plugins/$($review.Plugin)/skills/$($review.Id)/scripts/Build-ReviewReport.ps1"

            # Bundled by Sync-PluginScripts, so the copy must be byte-identical to its canonical
            # source; a hand-edited copy is a second formatter with the same name.
            (Get-Text -Relative $relative) | Should -Be $sourceText
            (Get-Text -Relative ".github/skills/$($review.Id)/scripts/Build-ReviewReport.ps1") | Should -Be $sourceText

            $manifest = Get-Text -Relative "plugins/$($review.Plugin)/plugin.json" | ConvertFrom-Json -Depth 50
            @($manifest.files | ForEach-Object { [string]$_.dest }) |
                Should -Contain "skills/$($review.Id)/scripts/Build-ReviewReport.ps1"

            # Consumer installs resolve against the registry, so an unregistered bundle is a
            # collation step that fails on every installed repo.
            $plugin = @($registry.plugins | Where-Object { [string]$_.name -eq $review.Plugin })
            $plugin.Count | Should -Be 1
            @($plugin[0].files | ForEach-Object { [string]$_.dest }) |
                Should -Contain "skills/$($review.Id)/scripts/Build-ReviewReport.ps1"
        }
    }

    It 'test:ReviewReport.PayloadOwnershipAndDrift maps the complete root, plugin, dogfood, and registry closure' {
        $registry = Get-Text -Relative 'registry.json' | ConvertFrom-Json -Depth 100
        $closure = @(
            'Build-ReviewReport.ps1'
            'Get-ReviewRun.ps1'
            'Remove-ReviewRun.ps1'
            'ReviewRun.psm1'
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
                $plugin = Join-Path $script:repoRoot "plugins/$($review.Plugin)/$pluginRelative"
                $dogfood = Join-Path $script:repoRoot ".github/$pluginRelative"

                foreach ($copy in @($plugin, $dogfood)) {
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

    It 'test:build-reviewreport-bundled makes both orchestrators call the formatter and write what it returns' {
        foreach ($review in $script:reviews) {
            foreach ($tree in @("plugins/$($review.Plugin)/skills/$($review.Id)", ".github/skills/$($review.Id)")) {
                $skill = Get-Text -Relative "$tree/SKILL.md"
                $scriptPath = ".github/skills/$($review.Id)/scripts/Build-ReviewReport.ps1"

                # The findings are objects, so the documented call must keep them in-process:
                # `pwsh -File` binds every argument as a string and the script fails loud on the
                # first finding. Pin the working form, not just the script name.
                $skill | Should -Match ([regex]::Escape("& $scriptPath"))
                $skill | Should -Not -Match ([regex]::Escape("-File $scriptPath"))
                $skill | Should -Match '-Finding\s+\$findings'
                $skill | Should -Match '-Model\s+\$roster'
                $skill | Should -Match ([regex]::Escape("-ReportTitle '$($review.ReportTitle)'"))
                # The returned text is the report: transcribing or reformatting it would reintroduce
                # exactly the per-run drift the script removes.
                $skill | Should -Match 'returns\s+\*\*verbatim\*\*'
            }
        }
    }

    It 'test:build-reviewreport-bundled round-trips typed findings through each bundled copy' {
        # The documented call is only useful if objects survive it. Execute the bundled copy the way
        # the skill says to, with the object shape the collation guide defines.
        $findings = @(
            [pscustomobject]@{ Concern = 'security'; Model = 'Model A'; Severity = 'High'
                Title = 'Unvalidated path'; Body = 'Path is not confined.'; References = 'src/a.ps1' }
            [pscustomobject]@{ Concern = 'correctness-reliability'; Model = 'Model B'; Severity = 'High'
                Title = 'Unvalidated path'; Body = 'Same root cause.'; References = 'src/a.ps1' }
        )

        foreach ($review in $script:reviews) {
            $bundled = Join-Path $script:repoRoot ".github/skills/$($review.Id)/scripts/Build-ReviewReport.ps1"
            $text = & $bundled -Finding $findings -Model @('Model A', 'Model B') -Scope 'unit test' `
                -ReportTitle $review.ReportTitle -InvocationCount 2

            $text | Should -Match ([regex]::Escape("## $($review.ReportTitle)"))
            $text | Should -Match 'Unvalidated path'
            # Both models flagged one root cause: it merges to a single entry and elevates.
            @([regex]::Matches($text, '(?m)^###\s*\[\d+\]')).Count | Should -Be 1
            $text | Should -Match 'Critical'
        }
    }

    It 'test:build-reviewreport-bundled leaves the report layout to the script, never to prose' {
        # Every markdown surface a review run reads: skills, their assets, the agent shims, and the
        # prompts. If any of them re-describes the layout, two definitions exist and only one is tested.
        $surfaces = [System.Collections.Generic.List[string]]::new()
        foreach ($review in $script:reviews) {
            foreach ($root in @("plugins/$($review.Plugin)", '.github')) {
                foreach ($candidate in @(
                        "$root/skills/$($review.Id)/SKILL.md"
                        "$root/skills/$($review.Id)/assets"
                        "$root/agents/$($review.Id).agent.md"
                        "$root/prompts/$($review.Id).prompt.md"
                    )) {
                    $full = Join-Path $script:repoRoot $candidate
                    if (Test-Path -LiteralPath $full -PathType Container) {
                        foreach ($file in (Get-ChildItem -LiteralPath $full -Recurse -File -Filter '*.md')) {
                            $surfaces.Add($file.FullName)
                        }
                    }
                    elseif (Test-Path -LiteralPath $full -PathType Leaf) {
                        $surfaces.Add($full)
                    }
                }
            }
        }

        @($surfaces).Count | Should -BeGreaterThan 8

        # Layout tokens emitted by Build-ReviewReport.ps1 itself.
        $layoutPatterns = @(
            '###\s*\[\d+\]'
            '\|\s*\*\*Severity\*\*\s*\|'
            '\|\s*\*\*Models\*\*\s*\|'
            '(?m)^##\s+Recommendations\s*$'
            'sorted severity descending'
            'Repeat for each finding'
        )

        $offenders = [System.Collections.Generic.List[string]]::new()
        foreach ($file in $surfaces) {
            $raw = [System.IO.File]::ReadAllText($file)
            foreach ($pattern in $layoutPatterns) {
                if ($raw -match $pattern) {
                    $offenders.Add("$($file.Substring($script:repoRoot.Length).Replace('\','/').TrimStart('/')) :: $pattern")
                }
            }
        }

        $offenders | Should -BeNullOrEmpty -Because 'the report layout has exactly one definition: Build-ReviewReport.ps1'
    }
}
