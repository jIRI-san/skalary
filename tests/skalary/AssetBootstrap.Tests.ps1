#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# RISK-9: a payload that reads a file the installer never materializes fails *quietly* in a
# consumer repo — the agent reads nothing and degrades instead of erroring. These tests pin the
# scanner that closes that gap: the grammar it recognizes, the two false-positive sources it
# must ignore (fenced examples, dynamically composed paths), and the drift gate that fails.

Describe 'Asset bootstrap scanner' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:syncScript = Join-Path $script:repoRoot 'scripts/skalary/Sync-PluginScripts.ps1'

        $script:newFixture = {
            <#
            Builds a throwaway plugins/ tree. `Files` maps a manifest dest (also used as the
            source path) to the file's content; `Declared` is the subset registered in files[].
            #>
            param(
                [Parameter(Mandatory)][hashtable]$Files,
                [string[]]$Declared,
                [string]$PluginName = 'fixture'
            )

            $root = Join-Path ([System.IO.Path]::GetTempPath()) ('asset-scan-' + [System.Guid]::NewGuid().ToString('N'))
            $pluginRoot = Join-Path $root "plugins/$PluginName"
            New-Item -ItemType Directory -Path $pluginRoot -Force | Out-Null
            # Resolve-RepoRoot walks up for a .git marker; without one the sync never reaches
            # the scan and every assertion here would pass or fail for the wrong reason.
            New-Item -ItemType Directory -Path (Join-Path $root '.git') -Force | Out-Null

            foreach ($rel in $Files.Keys) {
                $path = Join-Path $pluginRoot $rel
                New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
                Set-Content -LiteralPath $path -Value $Files[$rel] -Encoding utf8NoBOM
            }

            if ($null -eq $Declared) { $Declared = @($Files.Keys) }
            $manifest = [ordered]@{
                name         = $PluginName
                version      = '1.0.0'
                description  = 'Fixture plugin.'
                author       = 'test'
                license      = 'MIT'
                tags         = @('skill')
                dependencies = @()
                status       = 'partial'
                files        = @($Declared | Sort-Object | ForEach-Object { [ordered]@{ src = $_; dest = $_ } })
            }
            Set-Content -LiteralPath (Join-Path $pluginRoot 'plugin.json') -Value ($manifest | ConvertTo-Json -Depth 10) -Encoding utf8NoBOM

            return $root
        }

        $script:invoke = {
            param([Parameter(Mandatory)][string]$Root)

            try {
                & $script:syncScript -RepoRoot $Root -WhatIf *>&1 | Out-Null
                return [pscustomobject]@{ Threw = $false; Message = '' }
            }
            catch {
                return [pscustomobject]@{ Threw = $true; Message = $_.Exception.Message }
            }
        }
    }

    It 'test:asset-refs-declared-in-files fails on a skill-relative asset missing from files[]' {
        $root = & $script:newFixture -Files @{
            'skills/demo/SKILL.md'              = "# Demo`n`nRead ./assets/missing-guide.md before acting.`n"
            'skills/demo/assets/present.md'     = "# Present`n"
        } -Declared @('skills/demo/SKILL.md', 'skills/demo/assets/present.md')

        try {
            $result = & $script:invoke -Root $root
            $result.Threw | Should -BeTrue
            $result.Message | Should -Match 'skills/demo/assets/missing-guide\.md'
            $result.Message | Should -Match 'files\[\]'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }

    It 'test:asset-refs-declared-in-files accepts a skill-relative asset that is declared' {
        $root = & $script:newFixture -Files @{
            'skills/demo/SKILL.md'          = "# Demo`n`nRead ./assets/present.md before acting.`n"
            'skills/demo/assets/present.md' = "# Present`n"
        }

        try {
            (& $script:invoke -Root $root).Threw | Should -BeFalse
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }

    It 'test:asset-refs-declared-in-files resolves ./assets against the skill root, not the containing folder' {
        # A guide that already lives under assets/ spells a sibling asset exactly as SKILL.md
        # does; resolving relative to the containing folder would look for assets/assets/.
        $root = & $script:newFixture -Files @{
            'skills/demo/SKILL.md'          = "# Demo`n`nSee ./assets/guide.md.`n"
            'skills/demo/assets/guide.md'   = "# Guide`n`nAlso see ./assets/sibling.md.`n"
            'skills/demo/assets/sibling.md' = "# Sibling`n"
        }

        try {
            (& $script:invoke -Root $root).Threw | Should -BeFalse
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }

    It 'test:asset-refs-declared-in-files fails on an undeclared installed-path literal' {
        $root = & $script:newFixture -Files @{
            'skills/demo/SKILL.md' = "# Demo`n`nRead ``.github/skills/other/assets/map.md`` first.`n"
        }

        try {
            $result = & $script:invoke -Root $root
            $result.Threw | Should -BeTrue
            $result.Message | Should -Match 'skills/other/assets/map\.md'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }

    It 'test:asset-refs-declared-in-files accepts a cross-plugin reference another plugin declares' {
        $root = & $script:newFixture -Files @{
            'skills/demo/SKILL.md' = "# Demo`n`nRead ``.github/skills/other/assets/map.md`` first.`n"
        }

        try {
            # Second plugin owns and declares the referenced asset.
            $otherRoot = Join-Path $root 'plugins/other'
            $mapPath = Join-Path $otherRoot 'skills/other/assets/map.md'
            New-Item -ItemType Directory -Path (Split-Path -Parent $mapPath) -Force | Out-Null
            Set-Content -LiteralPath $mapPath -Value "# Map`n" -Encoding utf8NoBOM
            $manifest = [ordered]@{
                name = 'other'; version = '1.0.0'; description = 'Other.'; author = 'test'
                license = 'MIT'; tags = @('skill'); dependencies = @(); status = 'partial'
                files = @([ordered]@{ src = 'skills/other/assets/map.md'; dest = 'skills/other/assets/map.md' })
            }
            Set-Content -LiteralPath (Join-Path $otherRoot 'plugin.json') -Value ($manifest | ConvertTo-Json -Depth 10) -Encoding utf8NoBOM

            (& $script:invoke -Root $root).Threw | Should -BeFalse
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }

    It 'test:scanner-grammar-ignores-fenced-examples does not flag a reference inside a fenced block' {
        $body = @(
            '# Demo'
            ''
            'The scaffold writes:'
            ''
            '```'
            'Read ./assets/example-only.md'
            '.github/skills/demo/assets/example-only.md'
            '```'
            ''
            'Read ./assets/present.md before acting.'
        ) -join "`n"

        $root = & $script:newFixture -Files @{
            'skills/demo/SKILL.md'          = $body
            'skills/demo/assets/present.md' = "# Present`n"
        }

        try {
            $result = & $script:invoke -Root $root
            $result.Threw | Should -BeFalse -Because "fenced examples are illustrative, not runtime reads: $($result.Message)"
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }

    It 'test:scanner-grammar-ignores-fenced-examples fails closed on an unterminated fence' {
        # An unclosed fence blanks every following line, so a real reference after it would be
        # invisible to the gate. A stray fence is a routine authoring slip, so it has to be an
        # error rather than a silently narrowed scan.
        $body = @(
            '# Demo'
            ''
            '```powershell'
            'Get-Content ./assets/example-only.md'
            '```'
            ''
            '```'
            'unterminated example'
            ''
            'Read ./assets/missing-guide.md before acting.'
        ) -join "`n"

        $root = & $script:newFixture -Files @{ 'skills/demo/SKILL.md' = $body }

        try {
            $result = & $script:invoke -Root $root
            $result.Threw | Should -BeTrue
            $result.Message | Should -Match 'unterminated code fence'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }

    It 'test:scanner-grammar-ignores-fenced-examples scans references after a balanced fence' {
        $body = @(
            '# Demo'
            ''
            '```powershell'
            'Get-Content ./assets/example-only.md'
            '```'
            ''
            'Read ./assets/missing-guide.md before acting.'
        ) -join "`n"

        $root = & $script:newFixture -Files @{ 'skills/demo/SKILL.md' = $body }

        try {
            $result = & $script:invoke -Root $root
            $result.Threw | Should -BeTrue
            $result.Message | Should -Match 'missing-guide\.md'
            $result.Message | Should -Not -Match 'example-only\.md'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }

    It 'test:asset-refs-declared-in-files checks a plugin-local script reference the bundler never manages' {
        # The bundler only owns scripts whose canonical source is scripts/skalary; a
        # plugin-local script (autopilot's launcher, for instance) is materialized by nothing,
        # so its files[] declaration is the only thing that installs it.
        $root = & $script:newFixture -Files @{
            'skills/demo/SKILL.md' = "# Demo`n`nRun ``.github/skills/demo/scripts/launch-local.ps1`` to start.`n"
        }

        try {
            $result = & $script:invoke -Root $root
            $result.Threw | Should -BeTrue
            $result.Message | Should -Match 'skills/demo/scripts/launch-local\.ps1'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }

    It 'test:asset-refs-declared-in-files leaves a scripts/skalary-sourced bundle reference to the bundler arm' {
        # Get-PlanState.ps1 is bundled by this same run, so failing it here would break the
        # very sync that satisfies it.
        $root = & $script:newFixture -Files @{
            'skills/demo/SKILL.md' = "# Demo`n`nRun ``.github/skills/demo/scripts/Get-PlanState.ps1``.`n"
        }

        try {
            # -WhatIf reports the missing bundle copy as bundle drift; what must not happen is
            # the asset arm claiming the reference is an undeclared runtime asset.
            $result = & $script:invoke -Root $root
            $result.Message | Should -Not -Match 'Undeclared runtime asset reference'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }

    It 'test:scanner-grammar-ignores-fenced-examples leaves a plan-folder asset path out of grammar' {
        # `assets/intent.md` without the ./ prefix names a *plan folder* asset, not a skill
        # asset; the leading ./ is the only thing separating the two, so a bare path must not
        # be resolved against the skill root.
        $root = & $script:newFixture -Files @{
            'skills/demo/SKILL.md' = "# Demo`n`nRead the plan's assets/intent.md and assets/logs/capture.md.`n"
        }

        try {
            (& $script:invoke -Root $root).Threw | Should -BeFalse
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }

    It 'test:asset-bootstrap-drift-whatif fails the repo -WhatIf gate wired into validate.ps1' {
        # The gate has to be reachable from scripts/validate.ps1, not just from a direct call.
        $validate = Get-Content -LiteralPath (Join-Path $script:repoRoot 'scripts/validate.ps1') -Raw
        $validate | Should -Match 'Sync-PluginScripts\.ps1'
        $validate | Should -Match '-WhatIf'

        { & $script:syncScript -RepoRoot $script:repoRoot -WhatIf *> $null } | Should -Not -Throw
    }

    It 'test:asset-bootstrap-drift-whatif reports drift without writing anything' {
        $root = & $script:newFixture -Files @{
            'skills/demo/SKILL.md' = "# Demo`n`nRead ./assets/missing-guide.md before acting.`n"
        }

        try {
            (& $script:invoke -Root $root).Threw | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $root 'plugins/fixture/skills/demo/assets/missing-guide.md') |
                Should -BeFalse -Because 'the gate reports, it never materializes the missing asset'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }

    It 'test:asset-refs-declared-in-files covers every payload extension the scanner claims to read' {
        # A bundled script that reads an asset is as much a runtime read as a SKILL.md that does.
        $root = & $script:newFixture -Files @{
            'skills/demo/SKILL.md'            = "# Demo`n"
            'skills/demo/scripts/Read-It.ps1' = "# Reads ./assets/missing-guide.md at runtime.`nparam()`n"
        }

        try {
            $result = & $script:invoke -Root $root
            $result.Threw | Should -BeTrue
            $result.Message | Should -Match 'missing-guide\.md'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }
}
