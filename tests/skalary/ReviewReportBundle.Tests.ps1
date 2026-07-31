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

    It 'test:build-reviewreport-bundled makes both orchestrators call the formatter and write what it returns' {
        foreach ($review in $script:reviews) {
            foreach ($tree in @("plugins/$($review.Plugin)/skills/$($review.Id)", ".github/skills/$($review.Id)")) {
                $skill = Get-Text -Relative "$tree/SKILL.md"

                $skill | Should -Match ([regex]::Escape(".github/skills/$($review.Id)/scripts/Build-ReviewReport.ps1"))
                $skill | Should -Match '-Finding\s+\$findings'
                $skill | Should -Match '-Model\s+\$roster'
                $skill | Should -Match ([regex]::Escape("-ReportTitle '$($review.ReportTitle)'"))
                # The returned text is the report: transcribing or reformatting it would reintroduce
                # exactly the per-run drift the script removes.
                $skill | Should -Match 'returns\s+\*\*verbatim\*\*'
            }
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
