#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'architecture-notes structural evals' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..')).Path
        Import-Module (Join-Path $script:repoRoot 'tests/evals/EvalCommon.psm1') -Force

        $script:pluginRoot = Join-Path $script:repoRoot 'plugins/architecture-notes'
        $script:manifestPath = Join-Path $script:pluginRoot 'plugin.json'
        $script:manifest = Get-Content -LiteralPath $script:manifestPath -Raw | ConvertFrom-Json -Depth 50

        $skillEntries = @($script:manifest.files | Where-Object { [string]$_.src -eq 'skills/architecture-notes/SKILL.md' })
        $skillEntries.Count | Should -Be 1
        $script:skillEntry = $skillEntries[0]

        $script:skillPath = Join-Path $script:pluginRoot 'skills/architecture-notes/SKILL.md'
        $script:skillDest = [string]$script:skillEntry.dest
    }

    It 'PluginManifest-ArchNotes: manifest declares required identity and every file entry exists' {
        [string]$script:manifest.name | Should -Be 'architecture-notes'
        [string]$script:manifest.version | Should -Match '^\d+\.\d+\.\d+'
        [string]$script:manifest.description | Should -Not -BeNullOrEmpty
        @($script:manifest.files).Count | Should -BeGreaterThan 0

        foreach ($entry in @($script:manifest.files)) {
            $resolved = Test-ReferencedFile -BasePath $script:pluginRoot -RelativePath ([string]$entry.src)
            Test-Path -LiteralPath $resolved -PathType Leaf | Should -BeTrue
        }
    }

    It 'PluginManifest-ArchNotes: manifest validates against schemas/plugin/plugin.schema.json' {
        $schemaPath = Join-Path $script:repoRoot 'schemas/plugin/plugin.schema.json'
        Test-Path -LiteralPath $schemaPath -PathType Leaf | Should -BeTrue
        $manifestRaw = Get-Content -LiteralPath $script:manifestPath -Raw
        { $manifestRaw | Test-Json -SchemaFile $schemaPath } | Should -Not -Throw
        $manifestRaw | Test-Json -SchemaFile $schemaPath | Should -BeTrue
    }

    It 'PluginManifest-ArchNotes: skill artifact has valid frontmatter and body structure' {
        Get-ArtifactType -DestinationPath $script:skillDest | Should -Be 'skill'
        $frontmatter = Get-PluginFrontmatter -Path $script:skillPath
        Test-RequiredFrontmatter -ArtifactType 'skill' -Frontmatter $frontmatter -Path $script:skillPath | Should -BeTrue
        [string]$frontmatter.name | Should -Be 'architecture-notes'
        Test-BodySection -ArtifactType 'skill' -Path $script:skillPath | Should -BeTrue
    }

    It 'test:ArchitectureNotes.MarkdownOnly has no generated human-document compatibility surface' {
        foreach ($relative in @(
                'scripts/New-ArchHumanDoc.ps1',
                'scripts/Get-ArchContractsHash.ps1',
                'skills/architecture-notes/assets/templates/architecture-human-doc.template.md')) {
            Test-Path -LiteralPath (Join-Path $script:pluginRoot $relative) | Should -BeFalse
        }

        @($script:manifest.files | Where-Object {
                [string]$_.dest -match 'New-ArchHumanDoc|Get-ArchContractsHash|architecture-human-doc'
            }).Count | Should -Be 0
        @($script:manifest.scaffolds | Where-Object {
                [string]$_.path -eq 'docs/architecture-notes/architecture.human.md'
            }).Count | Should -Be 0
        (Get-Content -LiteralPath $script:skillPath -Raw) |
            Should -Not -Match 'New-ArchHumanDoc|Get-ArchContractsHash|architecture\.human\.md'
    }
}

Describe 'architecture-notes tier template evals' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..')).Path
        $script:pluginRoot = Join-Path $script:repoRoot 'plugins/architecture-notes'
        $script:templatesDir = Join-Path $script:pluginRoot 'skills/architecture-notes/assets/templates'
        $script:scaffoldScript = Join-Path $script:pluginRoot 'scripts/Copy-ArchScaffold.ps1'
        $script:assetRoot = Join-Path $script:pluginRoot 'skills/architecture-notes/assets'
        $script:indexRelPath = 'docs/architecture-notes/.architecture-notes.md'
    }

    It 'TierTemplates-Exist: index and arch-note templates exist without generated mirrors' {
        foreach ($name in @(
                'architecture-notes-index.template.md',
                'architecture-note.template.md')) {
            Test-Path -LiteralPath (Join-Path $script:templatesDir $name) -PathType Leaf | Should -BeTrue
        }
        Test-Path -LiteralPath (
            Join-Path $script:templatesDir 'architecture-human-doc.template.md'
        ) | Should -BeFalse
    }

    It 'Init-ScaffoldsTier: scaffolds the .architecture-notes.md index into docs/architecture-notes/' {
        $target = Join-Path ([System.IO.Path]::GetTempPath()) ("arch-tier-" + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $target -Force)
        try {
            $result = & $script:scaffoldScript -TargetRoot $target -AssetRoot $script:assetRoot
            $indexPath = Join-Path $target $script:indexRelPath
            $entry = @($result | Where-Object { $_.Path -eq $indexPath })
            $entry.Count | Should -Be 1
            $entry[0].Action | Should -Be 'created'
            Test-Path -LiteralPath $indexPath -PathType Leaf | Should -BeTrue
            (Get-Content -LiteralPath $indexPath -Raw) | Should -Match '# Architecture Notes'
        }
        finally {
            Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Init-NoOverwrite: an existing .architecture-notes.md index is never overwritten' {
        $target = Join-Path ([System.IO.Path]::GetTempPath()) ("arch-tier-" + [guid]::NewGuid().ToString('N'))
        $indexPath = Join-Path $target $script:indexRelPath
        [void](New-Item -ItemType Directory -Path (Split-Path -Parent $indexPath) -Force)
        $sentinel = '# my own architecture index'
        Set-Content -LiteralPath $indexPath -Value $sentinel -NoNewline
        try {
            $result = & $script:scaffoldScript -TargetRoot $target -AssetRoot $script:assetRoot
            $entry = @($result | Where-Object { $_.Path -eq $indexPath })
            $entry.Count | Should -Be 1
            $entry[0].Action | Should -Be 'skipped'
            (Get-Content -LiteralPath $indexPath -Raw) | Should -Be $sentinel
        }
        finally {
            Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'architecture contract validation gate evals' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..')).Path
        $script:pluginRoot = Join-Path $script:repoRoot 'plugins/architecture-notes'
        $script:validateScript = Join-Path $script:pluginRoot 'scripts/Test-ArchContract.ps1'
        $script:contentHashScript = Join-Path $script:pluginRoot 'scripts/Get-ArchContractContentHash.ps1'
    }

    It 'ArchContract-Validate: accepts a valid draft contract and rejects an invalid one' {
        Test-Path -LiteralPath $script:validateScript -PathType Leaf | Should -BeTrue
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("arch-contract-" + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $dir -Force)
        try {
            $goodPath = Join-Path $dir 'good.json'
            @{
                id       = 'ARCH-Good-1'
                title    = 'Good draft contract'
                maturity = 'draft'
                prose    = 'A valid component boundary description.'
            } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $goodPath

            $good = & $script:validateScript -ContractPath $goodPath
            $good.Valid | Should -BeTrue

            $badPath = Join-Path $dir 'bad.json'
            @{
                id       = 'ARCH-Bad-1'
                title    = 'Locked without hash'
                maturity = 'locked'
                prose    = 'Locked but missing lockedContentSha256.'
            } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $badPath

            $bad = & $script:validateScript -ContractPath $badPath -NoExit
            $bad.Valid | Should -BeFalse

            $nullPath = Join-Path $dir 'null.json'
            Set-Content -LiteralPath $nullPath -Value 'null'
            $nullContract = & $script:validateScript -ContractPath $nullPath -NoExit
            $nullContract.Valid | Should -BeFalse
            ($nullContract.Errors -join "`n") | Should -Match 'root must be a JSON object'
        }
        finally {
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:ArchitectureNotes.HumanAuthorityContract pins every locked field through one canonical helper' {
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("arch-locked-" + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $dir -Force)
        try {
            $contractPath = Join-Path $dir 'locked.json'
            $contract = [ordered]@{
                title               = 'Pinned contract'
                id                  = 'ARCH-Pinned'
                prose               = 'The reviewed boundary.'
                maturity            = 'locked'
                lockedContentSha256 = '0' * 64
            }
            $contract | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $contractPath
            $digest = (& $script:contentHashScript -ContractPath $contractPath).Digest
            $contract.lockedContentSha256 = $digest
            $contract | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $contractPath

            $valid = & $script:validateScript -ContractPath $contractPath -NoExit
            $valid.Valid | Should -BeTrue

            $reorderedPath = Join-Path $dir 'reordered.json'
            [ordered]@{
                lockedContentSha256 = 'f' * 64
                maturity            = 'locked'
                prose               = 'The reviewed boundary.'
                id                  = 'ARCH-Pinned'
                title               = 'Pinned contract'
            } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reorderedPath
            (& $script:contentHashScript -ContractPath $reorderedPath).Digest | Should -Be $digest

            $arrayPath = Join-Path $dir 'array.json'
            $scalarPath = Join-Path $dir 'scalar.json'
            Set-Content -LiteralPath $arrayPath -Value '{"id":"ARCH-Shape","title":"Shape","maturity":"draft","rules":[{"id":"r","description":"d","extra":[1],"empty":[],"object":{}}]}' -NoNewline
            Set-Content -LiteralPath $scalarPath -Value '{"id":"ARCH-Shape","title":"Shape","maturity":"draft","rules":[{"id":"r","description":"d","extra":1,"empty":null,"object":[]}]}' -NoNewline
            $arrayHash = (& $script:contentHashScript -ContractPath $arrayPath).Digest
            $scalarHash = (& $script:contentHashScript -ContractPath $scalarPath).Digest
            $arrayHash | Should -Not -Be $scalarHash
            (& $script:contentHashScript -ContractPath $arrayPath).CanonicalJson |
                Should -Be '{"id":"ARCH-Shape","maturity":"draft","rules":[{"description":"d","empty":[],"extra":[1],"id":"r","object":{}}],"title":"Shape"}'

            $contract.prose = 'Mutated boundary.'
            $contract | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $contractPath
            $invalid = & $script:validateScript -ContractPath $contractPath -NoExit
            $invalid.Valid | Should -BeFalse
            ($invalid.Errors -join "`n") | Should -Match 'lockedContentSha256 mismatch'
        }
        finally {
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:ArchitectureNotes.HumanAuthorityContract states human promotion as reviewer policy, not identity proof' {
        $skill = Get-Content -LiteralPath (Join-Path $script:pluginRoot 'skills/architecture-notes/SKILL.md') -Raw
        $skill | Should -Match 'reviewer-enforced policy'
        $skill | Should -Match 'not machine-authenticated identity'
        $skill | Should -Not -Match 'Audit locked promotions by authorship'
    }

    It 'test:ArchitectureNotes.PreservedWorkflow reviews contract integrity without runner or receipt semantics' {
        $skill = Get-Content -LiteralPath (Join-Path $script:pluginRoot 'skills/architecture-notes/SKILL.md') -Raw
        $skill | Should -Match 'locked digest mismatch as blocking integrity drift'
        $skill | Should -Match 'Test-ArchContract\.ps1'
        $skill | Should -Not -Match 'architecture-tests|runner-receipt|fitness coverage|arch-test config'
    }

    It 'ArchContract-Validate: CLI (pwsh -File) invocation exits 1 and reports errors on invalid input' {
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("arch-cli-" + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $dir -Force)
        try {
            $badPath = Join-Path $dir 'bad.json'
            @{
                id       = 'ARCH-Cli-1'
                title    = 'Locked without hash'
                maturity = 'locked'
                prose    = 'Locked but missing lockedContentSha256.'
            } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $badPath

            $out = pwsh -NoProfile -File $script:validateScript -ContractPath $badPath 2>&1
            $LASTEXITCODE | Should -Be 1
            ($out -join "`n") | Should -Match 'invalid'
        }
        finally {
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'architecture-notes prompt wrapper evals' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..')).Path
        $script:promptsDir = Join-Path $script:repoRoot 'plugins/architecture-notes/prompts'
    }

    It 'Prompts-DeferToSkill: /can and /uan exist and defer to the architecture-notes skill' {
        $opMap = @{ can = 'create'; uan = 'update' }
        foreach ($name in @('can', 'uan')) {
            $path = Join-Path $script:promptsDir "$name.prompt.md"
            Test-Path -LiteralPath $path -PathType Leaf | Should -BeTrue
            $body = Get-Content -LiteralPath $path -Raw
            $namePattern = '(?m)^name:\s*' + $name
            $body | Should -Match $namePattern
            # Thin wrapper: must reference the skill it defers to.
            $body | Should -Match 'architecture-notes'
            $body | Should -Match 'skill'
            # Must preset the correct operation (guards against wrapper copy-paste mixups).
            $body | Should -Match ('operation \*\*' + $opMap[$name] + '\*\*')
        }
    }
}

Describe 'architecture-notes greenfield seeding evals' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..')).Path
        $script:pluginRoot = Join-Path $script:repoRoot 'plugins/architecture-notes'
        $script:seedScript = Join-Path $script:pluginRoot 'scripts/New-ArchSeed.ps1'
        $script:guidePath = Join-Path $script:pluginRoot 'skills/architecture-notes/assets/interview-guide.md'
    }

    It 'test:ArchitectureNotes.PreservedWorkflow seeds self-contained draft Markdown contracts' {
        Test-Path -LiteralPath $script:guidePath -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $script:seedScript -PathType Leaf | Should -BeTrue

        $target = Join-Path ([System.IO.Path]::GetTempPath()) ("arch-seed-" + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $target -Force)
        try {
            $specPath = Join-Path $target 'seed.json'
            @{
                project    = 'SeedApp'
                systemType = 'web service'
                boundaries = @(
                    @{ id = 'ARCH-Domain-Isolation'; title = 'Domain isolation'; prose = 'Domain owns rules; never references Api or Infrastructure.'; scope = 'src/Domain/**' },
                    @{ id = 'ARCH-Api-Boundary'; title = 'API boundary'; prose = 'Api is the only inbound surface; it must not contain business rules.'; scope = 'src/Api/**' }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $specPath

            $result = & $script:seedScript -TargetRoot $target -SeedSpecPath $specPath

            @($result.Contracts).Count | Should -Be 2
            $expected = @{
                'ARCH-Domain-Isolation' = @{
                    Prose = 'Domain owns rules; never references Api or Infrastructure.'
                    Scope = 'src/Domain/**'
                    Note = 'arch-domain-isolation.md'
                }
                'ARCH-Api-Boundary' = @{
                    Prose = 'Api is the only inbound surface; it must not contain business rules.'
                    Scope = 'src/Api/**'
                    Note = 'arch-api-boundary.md'
                }
            }
            foreach ($c in $result.Contracts) {
                $c.Maturity | Should -Be 'draft'
                Test-Path -LiteralPath $c.Path -PathType Leaf | Should -BeTrue
                $c.Path | Should -Be (Join-Path $target "docs/architecture-notes/$($expected[$c.Id].Note)")
                $body = Get-Content -LiteralPath $c.Path -Raw
                $body | Should -Match ([regex]::Escape($c.Id))
                $body | Should -Match ([regex]::Escape($expected[$c.Id].Prose))
                $body | Should -Match ([regex]::Escape($expected[$c.Id].Scope))
                $body | Should -Not -Match '<SUBSYSTEM>|<SCOPE_GLOB>|<CONTRACT_ID>|<BOUNDARY_PROSE>|<invariant>|<component>'
            }
            # No locked contract is ever seeded.
            @($result.Contracts | Where-Object { $_.Maturity -eq 'locked' }).Count | Should -Be 0

            Test-Path -LiteralPath (Join-Path $target 'schemas') | Should -BeFalse
            $indexPath = Join-Path $target 'docs/architecture-notes/.architecture-notes.md'
            $index = Get-Content -LiteralPath $indexPath -Raw
            foreach ($c in $result.Contracts) {
                $index | Should -Match ([regex]::Escape($c.Id))
                $index | Should -Match ([regex]::Escape($c.Note))
            }
            $index | Should -Match '(?s)## Decision Records \(active\).*\| _none yet_ \|'
        }
        finally {
            Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Greenfield-SeedsDraftContracts: rejects a seed-spec with more than 2 boundaries' {
        $target = Join-Path ([System.IO.Path]::GetTempPath()) ("arch-seed-rej-" + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $target -Force)
        try {
            $specPath = Join-Path $target 'seed.json'
            @{
                project    = 'TooMany'
                boundaries = @(
                    @{ id = 'ARCH-A'; title = 'A'; prose = 'a' },
                    @{ id = 'ARCH-B'; title = 'B'; prose = 'b' },
                    @{ id = 'ARCH-C'; title = 'C'; prose = 'c' }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $specPath

            { & $script:seedScript -TargetRoot $target -SeedSpecPath $specPath } | Should -Throw
        }
        finally {
            Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Greenfield-SeedsDraftContracts: rejects missing boundaries and duplicate ids without scaffolding' {
        $target = Join-Path ([System.IO.Path]::GetTempPath()) ("arch-seed-guard-" + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $target -Force)
        try {
            $missingSpec = Join-Path $target 'missing.json'
            @{ project = 'NoBoundaries' } | ConvertTo-Json | Set-Content -LiteralPath $missingSpec
            { & $script:seedScript -TargetRoot $target -SeedSpecPath $missingSpec } | Should -Throw
            # Nothing should have been scaffolded on invalid input.
            Test-Path -LiteralPath (Join-Path $target 'schemas') | Should -BeFalse

            $dupSpec = Join-Path $target 'dup.json'
            @{
                project    = 'Dup'
                boundaries = @(
                    @{ id = 'ARCH-Auth'; title = 'A'; prose = 'a' },
                    @{ id = 'arch-auth'; title = 'B'; prose = 'b' }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $dupSpec
            { & $script:seedScript -TargetRoot $target -SeedSpecPath $dupSpec } | Should -Throw

            $unsafeSpec = Join-Path $target 'unsafe.json'
            @{ project = 'Unsafe'; boundaries = @(
                    @{ id = 'ARCH-Unsafe'; title = 'Break: YAML'; prose = 'x'; scope = 'src/**' }
                ) } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $unsafeSpec
            { & $script:seedScript -TargetRoot $target -SeedSpecPath $unsafeSpec } | Should -Throw
            Test-Path -LiteralPath (Join-Path $target 'docs') | Should -BeFalse
        }
        finally {
            Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'architecture ADR loop evals (REQ-13)' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..')).Path
        $script:pluginRoot = Join-Path $script:repoRoot 'plugins/architecture-notes'
        $script:adrScript = Join-Path $script:pluginRoot 'scripts/Import-ArchAdr.ps1'
        $script:adrTemplate = Join-Path $script:pluginRoot 'skills/architecture-notes/assets/adr-template.md'
        $script:indexTemplate = Join-Path $script:pluginRoot 'skills/architecture-notes/assets/templates/architecture-notes-index.template.md'
        $script:skillPath = Join-Path $script:pluginRoot 'skills/architecture-notes/SKILL.md'

        function New-AdrFixture {
            $repo = Join-Path ([System.IO.Path]::GetTempPath()) ("arch-adr-" + [guid]::NewGuid().ToString('N'))
            $planDir = Join-Path $repo 'docs/implementation-plans/2026-01-01-abc123-sample'
            $decisions = Join-Path $planDir 'decisions'
            [void](New-Item -ItemType Directory -Path $decisions -Force)
            $decisionBody = "# Decision: Sample Choice`n`n## Context`nSome forces at play.`n`n## Decision`nWe chose X over Y.`n"
            Set-Content -LiteralPath (Join-Path $decisions 'sample-choice.md') -Value $decisionBody -NoNewline
            return [pscustomobject]@{ Repo = $repo; PlanDir = $planDir }
        }
    }

    It 'Adr-CapturedDuringPlanning: a planning decision record is recognized and turned into a proposed ADR' {
        Test-Path -LiteralPath $script:adrTemplate -PathType Leaf | Should -BeTrue
        $tpl = Get-Content -LiteralPath $script:adrTemplate -Raw
        $tpl | Should -Match '(?m)^status:\s*proposed'
        $tpl | Should -Match '(?m)^reviewed:\s*false'
        # The architecture-notes skill owns the explicit decision-record harvest.
        (Get-Content -LiteralPath $script:skillPath -Raw) | Should -Match '(?i)adr-harvest'

        $fx = New-AdrFixture
        try {
            $r = & $script:adrScript -PlanDir $fx.PlanDir -RepoRoot $fx.Repo
            @($r.Adrs).Count | Should -Be 1
            $r.Adrs[0].Id | Should -Be 'ADR-sample-choice'
            $r.Adrs[0].Title | Should -Be 'Sample Choice'
            $r.Adrs[0].Source | Should -Match 'decisions/sample-choice\.md$'
            $r.Adrs[0].Action | Should -Be 'created'
        }
        finally {
            Remove-Item -LiteralPath $fx.Repo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:ArchitectureNotes.PreservedWorkflow harvests ADRs into quarantine without auto-loading them' {
        $fx = New-AdrFixture
        try {
            $r = & $script:adrScript -PlanDir $fx.PlanDir -RepoRoot $fx.Repo
            $r.Reviewed | Should -BeFalse

            $adrPath = Join-Path $fx.Repo 'docs/architecture-notes/.staging/adr/ADR-sample-choice.md'
            Test-Path -LiteralPath $adrPath -PathType Leaf | Should -BeTrue
            $adr = Get-Content -LiteralPath $adrPath -Raw
            $adr | Should -Match '(?m)^reviewed:\s*false'
            $adr | Should -Match '(?m)^status:\s*proposed'
            $adr | Should -Match 'ADR-sample-choice: Sample Choice'
            # The harvested decision prose is preserved under ## Source (provenance).
            $adr | Should -Match 'We chose X over Y'

            # The manifest is the promotion gate (reviewed:false).
            $manifest = Join-Path $fx.Repo 'docs/architecture-notes/.staging/ADR-HARVEST.md'
            Test-Path -LiteralPath $manifest -PathType Leaf | Should -BeTrue
            (Get-Content -LiteralPath $manifest -Raw) | Should -Match '(?m)^reviewed:\s*false'

            # Harvest NEVER writes the auto-loaded index — promotion is a separate human action.
            Test-Path -LiteralPath (Join-Path $fx.Repo 'docs/architecture-notes/.architecture-notes.md') -PathType Leaf | Should -BeFalse

            # No-overwrite: a second run leaves an edited staged ADR untouched.
            Set-Content -LiteralPath $adrPath -Value 'SENTINEL' -NoNewline
            $r2 = & $script:adrScript -PlanDir $fx.PlanDir -RepoRoot $fx.Repo
            $r2.Adrs[0].Action | Should -Be 'skipped'
            (Get-Content -LiteralPath $adrPath -Raw) | Should -Be 'SENTINEL'
        }
        finally {
            Remove-Item -LiteralPath $fx.Repo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Adr-AutoLoadedNextRun: harvested ADRs are gated out of auto-load until promoted into the index Decision Records table' {
        # The index (the auto-load surface) carries the Decision Records (active) table — the promotion target.
        (Get-Content -LiteralPath $script:indexTemplate -Raw) | Should -Match '## Decision Records \(active\)'

        $fx = New-AdrFixture
        try {
            [void](& $script:adrScript -PlanDir $fx.PlanDir -RepoRoot $fx.Repo)
            $adrPath = Join-Path $fx.Repo 'docs/architecture-notes/.staging/adr/ADR-sample-choice.md'
            # A harvested ADR lives under .staging (NOT referenced by the index) and carries no globs,
            # so it cannot be auto-loaded or glob-attached into context before human promotion.
            Test-Path -LiteralPath $adrPath -PathType Leaf | Should -BeTrue
            $adr = Get-Content -LiteralPath $adrPath -Raw
            # Scope the globs check to the top-of-file frontmatter block only: a body that merely
            # discusses "globs:" must not false-red the containment assertion.
            $fm = if ($adr -match '(?s)^---\r?\n(.*?)\r?\n---') { $Matches[1] } else { '' }
            $fm | Should -Not -Match '(?m)^\s*globs:'
        }
        finally {
            Remove-Item -LiteralPath $fx.Repo -Recurse -Force -ErrorAction SilentlyContinue
        }

        # The SKILL documents promotion-before-auto-load and the superseded-ADR lifecycle bounding.
        # The rare-operation detail lives in the tier-operations asset the SKILL defers to, so the
        # contract is read across both — pinning it to SKILL.md alone would fail the moment detail
        # moves into assets/, which the skill-size cap requires it to do.
        $skill = Get-Content -LiteralPath $script:skillPath -Raw
        $skill | Should -Match 'adr-harvest'
        $skill | Should -Match 'tier-operations-guide\.md'

        $tierGuidePath = Join-Path (Split-Path -Parent $script:skillPath) 'assets/tier-operations-guide.md'
        Test-Path -LiteralPath $tierGuidePath -PathType Leaf | Should -BeTrue
        $adrContract = $skill + "`n" + (Get-Content -LiteralPath $tierGuidePath -Raw)
        $adrContract | Should -Match '(?i)auto-loaded by .*/cip'
        $adrContract | Should -Match '(?i)superseded'
        $adrContract | Should -Match 'Import-ArchAdr\.ps1'
    }

    It 'Adr-RejectsFrontmatterEscape: an untrusted decision body that embeds its own globs frontmatter cannot escape into the ADR frontmatter' {
        $repo = Join-Path ([System.IO.Path]::GetTempPath()) ("arch-adr-esc-" + [guid]::NewGuid().ToString('N'))
        $planDir = Join-Path $repo 'docs/implementation-plans/2026-01-01-abc123-sample'
        $decisions = Join-Path $planDir 'decisions'
        [void](New-Item -ItemType Directory -Path $decisions -Force)
        # Hostile decision body: leads with its own YAML frontmatter fence declaring a broad glob.
        $hostile = "---`nglobs:`n  - `"**`"`n---`n# Decision: Hostile`n`n## Decision`nDo the thing.`n"
        Set-Content -LiteralPath (Join-Path $decisions 'hostile.md') -Value $hostile -NoNewline
        try {
            [void](& $script:adrScript -PlanDir $planDir -RepoRoot $repo)
            $adrPath = Join-Path $repo 'docs/architecture-notes/.staging/adr/ADR-hostile.md'
            Test-Path -LiteralPath $adrPath -PathType Leaf | Should -BeTrue
            $adr = Get-Content -LiteralPath $adrPath -Raw
            # The ADR's own top frontmatter is the template's (reviewed:false, NO globs) — the hostile
            # fence never became the file's frontmatter (it was substituted end-of-file under ## Source).
            $fm = if ($adr -match '(?s)^---\r?\n(.*?)\r?\n---') { $Matches[1] } else { '' }
            $fm | Should -Match '(?m)^reviewed:\s*false'
            $fm | Should -Not -Match '(?m)^\s*globs:'
            # The hostile globs block survives only as inert data under ## Source.
            $sourceSection = ($adr -split '(?m)^## Source\s*$', 2)[-1]
            $sourceSection | Should -Match 'globs:'
        }
        finally {
            Remove-Item -LiteralPath $repo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
