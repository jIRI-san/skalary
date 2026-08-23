#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# RISK-9: a payload that reads a file the installer never materializes fails *quietly* in a
# consumer repo — the agent reads nothing and degrades instead of erroring. These tests pin the
# scanner that closes that gap: the grammar it recognizes, fenced examples it must ignore,
# unsupported dynamic/source-tree references it rejects, and the drift gate that fails.

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
                name = $PluginName
                version = '1.0.0'
                description = 'Fixture plugin.'
                author = 'test'
                license = 'MIT'
                tags = @('skill')
                dependencies = @()
                status = 'partial'
                files = @($Declared | Sort-Object | ForEach-Object { [ordered]@{ src = $_; dest = $_ } })
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
            'skills/demo/SKILL.md' = "# Demo`n`nRead ./assets/missing-guide.md before acting.`n"
            'skills/demo/assets/present.md' = "# Present`n"
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
            'skills/demo/SKILL.md' = "# Demo`n`nRead ./assets/present.md before acting.`n"
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
            'skills/demo/SKILL.md' = "# Demo`n`nSee ./assets/guide.md.`n"
            'skills/demo/assets/guide.md' = "# Guide`n`nAlso see ./assets/sibling.md.`n"
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
            'skills/demo/SKILL.md' = $body
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
            'skills/demo/SKILL.md' = "# Demo`n"
            'skills/demo/scripts/Read-It.ps1' = "param()`nGet-Content './assets/missing-guide.md' -Raw`n"
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

    It 'rejects source-tree paths that cannot exist in a foreign consumer' {
        $root = & $script:newFixture -Files @{
            'skills/demo/SKILL.md' = "# Demo`n`nImport-Module ./plugins/demo/skills/demo/scripts/Read-It.psm1.`n"
        }

        try {
            $result = & $script:invoke -Root $root
            $result.Threw | Should -BeTrue
            $result.Message | Should -Match 'source-tree path'
            $result.Message | Should -Match 'plugins/demo/skills/demo/scripts/Read-It\.psm1'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }

    It 'rejects repository-root joins to authoring-only plugin paths' {
        foreach ($sourcePath in @(
                'plugins/fixture/skills/demo/scripts/Read-It.psm1',
                'scripts/skalary/Read-It.psm1'
            )) {
            $root = & $script:newFixture -Files @{
                'skills/demo/SKILL.md' = "# Demo`n"
                'skills/demo/scripts/Read-It.ps1' = (@'
param([string]$RepoRoot)
$module = Join-Path $RepoRoot '__SOURCE_PATH__'
'@).Replace('__SOURCE_PATH__', $sourcePath)
            }

            try {
                $result = & $script:invoke -Root $root
                $result.Threw | Should -BeTrue
                $result.Message | Should -Match 'joins source-tree path'
                $result.Message | Should -Match ([regex]::Escape($sourcePath))
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }
    }

    It 'keeps the documented bootstrap registry fallback outside source-script rejection' {
        $root = & $script:newFixture -Files @{
            'skills/demo/SKILL.md' = "# Demo`n"
            'skills/demo/scripts/Read-It.ps1' = @'
param([string]$RepoRoot)
$registry = Join-Path $RepoRoot 'scripts/skalary/registry.json'
'@
        }

        try {
            (& $script:invoke -Root $root).Threw | Should -BeFalse
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }

    It 'rejects dynamic composition of a supported runtime root' {
        $root = & $script:newFixture -Files @{
            'skills/demo/SKILL.md' = "# Demo`n`nUse ``Join-Path './assets' `$name`` to load the guide.`n"
        }

        try {
            $result = & $script:invoke -Root $root
            $result.Threw | Should -BeTrue
            $result.Message | Should -Match 'dynamically composes supported runtime root'
            $result.Message | Should -Match '\./assets'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }

    It 'rejects named and interpolated dynamic Join-Path arguments in PowerShell payloads' {
        foreach ($expression in @(
                'Join-Path -Path ''./assets'' -ChildPath $name',
                'Join-Path ''./assets'' "$name.md"',
                'Join-Path -Path:''./assets'' -ChildPath:$name'
            )) {
            $root = & $script:newFixture -Files @{
                'skills/demo/SKILL.md' = "# Demo`n"
                'skills/demo/scripts/Read-It.ps1' = "param([string]`$name)`n`$path = $expression`n"
            }

            try {
                $result = & $script:invoke -Root $root
                $result.Threw | Should -BeTrue
                $result.Message | Should -Match 'dynamically composes supported runtime root'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }
    }

    It 'validates literal Join-Path targets against the installed inventory' {
        foreach ($case in @(
                [pscustomobject]@{
                    Path = 'skills/demo/scripts/Read-It.ps1'
                    Content = "param()`n`$path = Join-Path './assets' 'missing-guide.md'`n"
                },
                [pscustomobject]@{
                    Path = 'skills/demo/SKILL.md'
                    Content = "# Demo`n`nLoad ``Join-Path './assets' 'missing-guide.md'`` at runtime.`n"
                }
            )) {
            $files = @{ 'skills/demo/SKILL.md' = "# Demo`n" }
            $files[[string]$case.Path] = [string]$case.Content
            $root = & $script:newFixture -Files $files

            try {
                $result = & $script:invoke -Root $root
                $result.Threw | Should -BeTrue
                $result.Message | Should -Match 'skill-relative path'
                $result.Message | Should -Match 'missing-guide\.md'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }
    }

    It 'requires literal installed sidecars to be declared or bundled' {
        $root = & $script:newFixture -Files @{
            'skills/demo/SKILL.md' = "# Demo`n"
            'skills/demo/scripts/Read-It.ps1' = "param()`n`$schema = Join-Path `$PSScriptRoot 'schemas/missing.json'`n"
        }

        try {
            $result = & $script:invoke -Root $root
            $result.Threw | Should -BeTrue
            $result.Message | Should -Match 'reads sidecar'
            $result.Message | Should -Match 'schemas/missing\.json'

            $sidecarPath = Join-Path $root 'plugins/fixture/skills/demo/scripts/schemas/missing.json'
            New-Item -ItemType Directory -Path (Split-Path -Parent $sidecarPath) -Force | Out-Null
            Set-Content -LiteralPath $sidecarPath -Value "{}" -Encoding utf8NoBOM
            $manifestPath = Join-Path $root 'plugins/fixture/plugin.json'
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -Depth 10
            $manifest.files = @($manifest.files) + @(
                [pscustomobject]@{
                    src = 'skills/demo/scripts/schemas/missing.json'
                    dest = 'skills/demo/scripts/schemas/missing.json'
                }
            )
            Set-Content -LiteralPath $manifestPath -Value (
                $manifest | ConvertTo-Json -Depth 10
            ) -Encoding utf8NoBOM

            (& $script:invoke -Root $root).Threw | Should -BeFalse
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }

    It 'rejects colon-bound named dynamic Join-Path arguments in Markdown payloads' {
        $root = & $script:newFixture -Files @{
            'skills/demo/SKILL.md' = "# Demo`n`nLoad ``Join-Path -Path:'./assets' -ChildPath:`$name`` at runtime.`n"
        }

        try {
            $result = & $script:invoke -Root $root
            $result.Threw | Should -BeTrue
            $result.Message | Should -Match 'dynamically composes supported runtime root'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }

    Context 'scaffold declarations' {
        BeforeAll {
            $script:pluginSchema = Join-Path $script:repoRoot 'schemas/plugin/plugin.schema.json'
            $script:registrySchema = Join-Path $script:repoRoot 'schemas/registry/registry.schema.json'

            $script:baseManifest = {
                param([object[]]$Scaffolds)

                $manifest = [ordered]@{
                    name = 'fixture'
                    version = '1.0.0'
                    description = 'Fixture plugin.'
                    author = 'test'
                    license = 'MIT'
                    tags = @('skill')
                    dependencies = @()
                    files = @([ordered]@{ src = 'skills/demo/SKILL.md'; dest = 'skills/demo/SKILL.md' })
                    scaffolds = $Scaffolds
                }
                return ($manifest | ConvertTo-Json -Depth 10)
            }

            $script:schemaAccepts = {
                param([string]$Json, [string]$SchemaFile)
                try { return [bool]($Json | Test-Json -SchemaFile $SchemaFile -ErrorAction Stop) }
                catch { return $false }
            }
        }

        It 'test:scaffold-literal-mode accepts a fixed path and rejects a placeholder or a confine helper' {
            $literal = [ordered]@{
                path = 'docs/feedback/queue.md'; mode = 'literal'
                owner = 'Update-FeedbackQueue.ps1'; trigger = 'first queued marker'
            }
            (& $script:schemaAccepts -Json (& $script:baseManifest -Scaffolds @($literal)) -SchemaFile $script:pluginSchema) |
                Should -BeTrue

            # A literal path with a variable segment is a parameterized path wearing the wrong
            # label — the mode is what decides whether a confine helper is required.
            $placeholder = [ordered]@{
                path = 'docs/feedback/<plan>.md'; mode = 'literal'
                owner = 'Update-FeedbackQueue.ps1'; trigger = 'first queued marker'
            }
            (& $script:schemaAccepts -Json (& $script:baseManifest -Scaffolds @($placeholder)) -SchemaFile $script:pluginSchema) |
                Should -BeFalse

            $withConfine = [ordered]@{
                path = 'docs/feedback/queue.md'; mode = 'literal'
                owner = 'Update-FeedbackQueue.ps1'; trigger = 'first queued marker'; confine = 'Resolve-RepoPath'
            }
            (& $script:schemaAccepts -Json (& $script:baseManifest -Scaffolds @($withConfine)) -SchemaFile $script:pluginSchema) |
                Should -BeFalse
        }

        It 'test:scaffold-parameterized-mode-confined requires a confine helper on every variable path' {
            $unconfined = [ordered]@{
                path = 'docs/review-ledger/<category>.md'; mode = 'parameterized'
                owner = 'Add-LedgerEntry.ps1'; trigger = 'first harvest'
            }
            (& $script:schemaAccepts -Json (& $script:baseManifest -Scaffolds @($unconfined)) -SchemaFile $script:pluginSchema) |
                Should -BeFalse

            $confined = [ordered]@{
                path = 'docs/review-ledger/<category>.md'; mode = 'parameterized'
                owner = 'Add-LedgerEntry.ps1'; trigger = 'first harvest'; confine = 'Resolve-LedgerPath'
                values = @('security', 'testing')
            }
            (& $script:schemaAccepts -Json (& $script:baseManifest -Scaffolds @($confined)) -SchemaFile $script:pluginSchema) |
                Should -BeTrue
        }

        It 'test:scaffold-parameterized-mode-confined names a helper the declaring plugin actually ships and calls' {
            # A helper that exists somewhere in the repo confines nothing if the payload that
            # performs the write never sees it: the consumer installs one plugin, not the repo.
            foreach ($manifestPath in (Get-ChildItem -LiteralPath (Join-Path $script:repoRoot 'plugins') -Recurse -File -Filter 'plugin.json')) {
                $manifest = Get-Content -LiteralPath $manifestPath.FullName -Raw | ConvertFrom-Json -Depth 20
                if ($manifest.PSObject.Properties.Name -notcontains 'scaffolds') { continue }

                $pluginRoot = Split-Path -Parent $manifestPath.FullName
                $payloadText = @(
                    foreach ($file in @($manifest.files)) {
                        $full = Join-Path $pluginRoot ($file.src -replace '/', [System.IO.Path]::DirectorySeparatorChar)
                        if (Test-Path -LiteralPath $full -PathType Leaf) { Get-Content -LiteralPath $full -Raw }
                    }
                ) -join "`n"

                foreach ($scaffold in @($manifest.scaffolds)) {
                    if ($scaffold.mode -ne 'parameterized') { continue }
                    $scaffold.confine | Should -Not -BeNullOrEmpty

                    $escaped = [regex]::Escape($scaffold.confine)
                    $payloadText | Should -Match "function\s+$escaped" `
                        -Because "plugin '$($manifest.name)' declares scaffold '$($scaffold.path)' as confined by '$($scaffold.confine)', so its payload must ship that helper"
                    # Defined but never invoked is a helper in name only.
                    ([regex]::Matches($payloadText, $escaped)).Count | Should -BeGreaterThan 1 `
                        -Because "'$($scaffold.confine)' must be called, not just defined, by plugin '$($manifest.name)'"
                }
            }
        }

        It 'test:scaffolds-reach-registry carries every declared scaffold into registry.json' {
            $registry = Get-Content -LiteralPath (Join-Path $script:repoRoot 'registry.json') -Raw | ConvertFrom-Json -Depth 30

            foreach ($manifestPath in (Get-ChildItem -LiteralPath (Join-Path $script:repoRoot 'plugins') -Recurse -File -Filter 'plugin.json')) {
                $manifest = Get-Content -LiteralPath $manifestPath.FullName -Raw | ConvertFrom-Json -Depth 20
                if ($manifest.PSObject.Properties.Name -notcontains 'scaffolds') { continue }

                $entry = @($registry.plugins) | Where-Object { $_.name -eq $manifest.name }
                $entry | Should -Not -BeNullOrEmpty
                foreach ($scaffold in @($manifest.scaffolds)) {
                    $carried = @($entry.scaffolds) | Where-Object { $_.path -eq $scaffold.path }
                    $carried | Should -Not -BeNullOrEmpty -Because "consumer installs resolve against registry.json, not plugins/"
                    $carried.mode | Should -Be $scaffold.mode
                    $carried.owner | Should -Be $scaffold.owner
                }
            }
        }

        It 'test:scaffolds-reach-registry keeps the generated registry valid against its schema' {
            $raw = Get-Content -LiteralPath (Join-Path $script:repoRoot 'registry.json') -Raw
            (& $script:schemaAccepts -Json $raw -SchemaFile $script:registrySchema) | Should -BeTrue
        }

        It 'test:asset-refs-declared-in-files accepts a scaffold path and rejects an undeclared sibling' {
            $scaffold = [ordered]@{
                path = 'docs/review-ledger/<category>.md'; mode = 'parameterized'
                owner = 'Add-LedgerEntry.ps1'; trigger = 'first harvest'; confine = 'Resolve-LedgerPath'
                values = @('security', 'testing')
            }

            $root = Join-Path ([System.IO.Path]::GetTempPath()) ('asset-scan-' + [System.Guid]::NewGuid().ToString('N'))
            $pluginRoot = Join-Path $root 'plugins/fixture'
            New-Item -ItemType Directory -Path (Join-Path $root '.git') -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $pluginRoot 'skills/demo') -Force | Out-Null

            try {
                $manifest = [ordered]@{
                    name = 'fixture'; version = '1.0.0'; description = 'Fixture.'; author = 'test'
                    license = 'MIT'; tags = @('skill'); dependencies = @(); status = 'partial'
                    files = @([ordered]@{ src = 'skills/demo/SKILL.md'; dest = 'skills/demo/SKILL.md' })
                    scaffolds = @($scaffold)
                }
                Set-Content -LiteralPath (Join-Path $pluginRoot 'plugin.json') -Value ($manifest | ConvertTo-Json -Depth 10) -Encoding utf8NoBOM

                $skillPath = Join-Path $pluginRoot 'skills/demo/SKILL.md'
                Set-Content -LiteralPath $skillPath -Value "# Demo`n`nAppend to docs/review-ledger/security.md.`n" -Encoding utf8NoBOM
                (& $script:invoke -Root $root).Threw | Should -BeFalse

                # Same root, value outside the closed domain: the declaration does not cover it.
                Set-Content -LiteralPath $skillPath -Value "# Demo`n`nAppend to docs/review-ledger/invented.md.`n" -Encoding utf8NoBOM
                $result = & $script:invoke -Root $root
                $result.Threw | Should -BeTrue
                $result.Message | Should -Match 'docs/review-ledger/invented\.md'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }

        It 'does not exempt a repository-root Join-Path from scaffold declarations' {
            $root = & $script:newFixture -Files @{
                'skills/demo/SKILL.md' = "# Demo`n"
                'skills/demo/scripts/Read-It.ps1' = @'
param([string]$RepoRoot)
$path = Join-Path $RepoRoot 'docs/undeclared/file.md'
'@
            }

            try {
                $result = & $script:invoke -Root $root
                $result.Threw | Should -BeTrue
                $result.Message | Should -Match 'docs/undeclared/file\.md'
                $result.Message | Should -Match 'no scaffolds\[\] entry declares'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }

        It 'does not let an outer sidecar join exempt a nested repository read' {
            $root = & $script:newFixture -Files @{
                'skills/demo/SKILL.md' = "# Demo`n"
                'skills/demo/scripts/Read-It.ps1' = @'
param([string]$RepoRoot)
$path = Join-Path $PSScriptRoot (Get-Content (Join-Path $RepoRoot 'docs/undeclared/file.md'))
'@
            }

            try {
                $result = & $script:invoke -Root $root
                $result.Threw | Should -BeTrue
                $result.Message | Should -Match 'docs/undeclared/file\.md'
                $result.Message | Should -Match 'no scaffolds\[\] entry declares'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }

        It 'test:asset-refs-declared-in-files rejects an undeclared scaffold root' {
            $root = & $script:newFixture -Files @{
                'skills/demo/SKILL.md' = "# Demo`n`nRead docs/some-other-tier/index.md.`n"
            }

            try {
                $result = & $script:invoke -Root $root
                $result.Threw | Should -BeTrue
                $result.Message | Should -Match 'docs/some-other-tier/index\.md'
                $result.Message | Should -Match 'no scaffolds\[\] entry declares'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }
    }
}
