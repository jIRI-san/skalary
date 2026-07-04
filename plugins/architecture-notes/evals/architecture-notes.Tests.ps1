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

    It 'PluginManifest-ArchNotes: manifest validates against schemas/plugin.schema.json' {
        $schemaPath = Join-Path $script:repoRoot 'schemas/plugin.schema.json'
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
}

Describe 'architecture-contract schema evals' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..')).Path
        $script:pluginRoot = Join-Path $script:repoRoot 'plugins/architecture-notes'
        $script:contractSchemaPath = Join-Path $script:pluginRoot 'skills/architecture-notes/assets/schemas/architecture-contract.schema.json'
        $script:scaffoldScript = Join-Path $script:pluginRoot 'scripts/Copy-ArchScaffold.ps1'
        $script:assetRoot = Join-Path $script:pluginRoot 'skills/architecture-notes/assets'

        $script:validContract = @{
            id       = 'ARCH-Sample-1'
            title    = 'Sample contract'
            maturity = 'draft'
            rules    = @(
                @{ id = 'no-domain-to-infra'; kind = 'forbidden-dependency'; description = 'Domain must not depend on Infrastructure.' }
            )
        } | ConvertTo-Json -Depth 10
    }

    It 'ContractSchema-Valid: schema file parses, declares maturity enum, and accepts a valid contract' {
        Test-Path -LiteralPath $script:contractSchemaPath -PathType Leaf | Should -BeTrue
        $schema = Get-Content -LiteralPath $script:contractSchemaPath -Raw | ConvertFrom-Json -Depth 50
        @($schema.properties.maturity.enum) | Should -Contain 'locked'
        @($schema.properties.maturity.enum) | Should -Contain 'draft'
        @($schema.properties.maturity.enum) | Should -Contain 'provisional'

        { $script:validContract | Test-Json -SchemaFile $script:contractSchemaPath } | Should -Not -Throw
        $script:validContract | Test-Json -SchemaFile $script:contractSchemaPath | Should -BeTrue
    }

    It 'ContractSchema-RejectsUnknownMaturity: an out-of-enum maturity fails validation' {
        $bad = @{
            id       = 'ARCH-Sample-2'
            title    = 'Bad maturity'
            maturity = 'frozen'
            prose    = 'Some component description.'
        } | ConvertTo-Json -Depth 10

        $bad | Test-Json -SchemaFile $script:contractSchemaPath -ErrorAction SilentlyContinue | Should -BeFalse
    }

    It 'ContractSchema-LockedRequiresBodyHash: locked contract without lockedBodySha256 fails, with a valid hash passes' {
        $lockedNoHash = @{
            id       = 'ARCH-Locked-1'
            title    = 'Locked without hash'
            maturity = 'locked'
            prose    = 'A locked component description.'
        } | ConvertTo-Json -Depth 10
        $lockedNoHash | Test-Json -SchemaFile $script:contractSchemaPath -ErrorAction SilentlyContinue | Should -BeFalse

        $lockedWithHash = @{
            id               = 'ARCH-Locked-1'
            title            = 'Locked with hash'
            maturity         = 'locked'
            prose            = 'A locked component description.'
            lockedBodySha256 = ('a' * 64)
        } | ConvertTo-Json -Depth 10
        $lockedWithHash | Test-Json -SchemaFile $script:contractSchemaPath | Should -BeTrue
    }

    It 'Schema-ScaffoldsOnInitNoOverwrite: scaffolds the schema, then never overwrites an existing target' {
        Test-Path -LiteralPath $script:scaffoldScript -PathType Leaf | Should -BeTrue
        $target = Join-Path ([System.IO.Path]::GetTempPath()) ("arch-scaffold-" + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $target -Force)
        try {
            $first = & $script:scaffoldScript -TargetRoot $target -AssetRoot $script:assetRoot
            $created = @($first | Where-Object { $_.Path -like '*architecture-contract.schema.json' })
            $created.Count | Should -Be 1
            $created[0].Action | Should -Be 'created'
            Test-Path -LiteralPath $created[0].Path -PathType Leaf | Should -BeTrue

            $sentinel = '{ "sentinel": true }'
            Set-Content -LiteralPath $created[0].Path -Value $sentinel -NoNewline

            $second = & $script:scaffoldScript -TargetRoot $target -AssetRoot $script:assetRoot
            $rerun = @($second | Where-Object { $_.Path -like '*architecture-contract.schema.json' })
            $rerun.Count | Should -Be 1
            $rerun[0].Action | Should -Be 'skipped'
            (Get-Content -LiteralPath $created[0].Path -Raw) | Should -Be $sentinel
        }
        finally {
            Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Schema-ScaffoldsResolvesAssetRootFromScriptLocation: locates assets without an explicit -AssetRoot' {
        $target = Join-Path ([System.IO.Path]::GetTempPath()) ("arch-scaffold-auto-" + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $target -Force)
        try {
            $result = & $script:scaffoldScript -TargetRoot $target
            $created = @($result | Where-Object { $_.Path -like '*architecture-contract.schema.json' })
            $created.Count | Should -Be 1
            $created[0].Action | Should -Be 'created'
            Test-Path -LiteralPath $created[0].Path -PathType Leaf | Should -BeTrue
        }
        finally {
            Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
        }
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

    It 'TierTemplates-Exist: index, arch-note, and human-doc templates all exist' {
        foreach ($name in @(
                'architecture-notes-index.template.md',
                'architecture-note.template.md',
                'architecture-human-doc.template.md')) {
            Test-Path -LiteralPath (Join-Path $script:templatesDir $name) -PathType Leaf | Should -BeTrue
        }
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
        $script:schemaPath = Join-Path $script:pluginRoot 'skills/architecture-notes/assets/schemas/architecture-contract.schema.json'
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

            $good = & $script:validateScript -ContractPath $goodPath -SchemaPath $script:schemaPath
            $good.Valid | Should -BeTrue

            $badPath = Join-Path $dir 'bad.json'
            @{
                id       = 'ARCH-Bad-1'
                title    = 'Locked without hash'
                maturity = 'locked'
                prose    = 'Locked but missing lockedBodySha256.'
            } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $badPath

            $bad = & $script:validateScript -ContractPath $badPath -SchemaPath $script:schemaPath
            $bad.Valid | Should -BeFalse
        }
        finally {
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'ArchContract-Validate: resolves the schema from a scaffolded schemas/ dir without -SchemaPath' {
        $repo = Join-Path ([System.IO.Path]::GetTempPath()) ("arch-repo-" + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path (Join-Path $repo 'schemas') -Force)
        Copy-Item -LiteralPath $script:schemaPath -Destination (Join-Path $repo 'schemas/architecture-contract.schema.json')
        try {
            $contractPath = Join-Path $repo 'contract.json'
            @{
                id       = 'ARCH-Resolve-1'
                title    = 'Resolved via walk-up'
                maturity = 'draft'
                prose    = 'A valid boundary.'
            } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $contractPath

            $result = & $script:validateScript -ContractPath $contractPath
            $result.Valid | Should -BeTrue
            $result.SchemaPath | Should -Match 'architecture-contract\.schema\.json$'
        }
        finally {
            Remove-Item -LiteralPath $repo -Recurse -Force -ErrorAction SilentlyContinue
        }
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
                prose    = 'Locked but missing lockedBodySha256.'
            } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $badPath

            $out = pwsh -NoProfile -File $script:validateScript -ContractPath $badPath -SchemaPath $script:schemaPath 2>&1
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

    It 'Greenfield-SeedsDraftContracts: interview guide ships and seed produces valid draft contracts + human doc' {
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
            foreach ($c in $result.Contracts) {
                $c.Maturity | Should -Be 'draft'
                $c.Valid | Should -BeTrue
                Test-Path -LiteralPath $c.Path -PathType Leaf | Should -BeTrue
            }
            # No locked contract is ever seeded.
            @($result.Contracts | Where-Object { $_.Maturity -eq 'locked' }).Count | Should -Be 0

            # Human doc skeleton exists and is excluded from the auto-loaded index.
            Test-Path -LiteralPath $result.HumanDoc.Path -PathType Leaf | Should -BeTrue
            $indexPath = Join-Path $target 'docs/architecture-notes/.architecture-notes.md'
            (Get-Content -LiteralPath $indexPath -Raw) | Should -Not -Match 'architecture\.human\.md'
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
        }
        finally {
            Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
