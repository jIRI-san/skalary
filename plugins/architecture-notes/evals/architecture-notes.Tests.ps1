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
}

Describe 'architecture-contract schema evals' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..')).Path
        $script:pluginRoot = Join-Path $script:repoRoot 'plugins/architecture-notes'
        $script:contractSchemaPath = Join-Path $script:pluginRoot 'skills/architecture-notes/assets/schemas/architecture-contract.schema.json'
        $script:scaffoldScript = Join-Path $script:pluginRoot 'scripts/Copy-ArchScaffold.ps1'
        $script:assetRoot = Join-Path $script:pluginRoot 'skills/architecture-notes/assets'
        $script:contentHashScript = Join-Path $script:pluginRoot 'scripts/Get-ArchContractContentHash.ps1'

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

    It 'ContractSchema-LockedRequiresContentHash: locked contract requires lockedContentSha256' {
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
            lockedContentSha256 = ('a' * 64)
        } | ConvertTo-Json -Depth 10
        $lockedWithHash | Test-Json -SchemaFile $script:contractSchemaPath | Should -BeTrue
    }

    It 'test:ArchitectureNotes.HumanAuthorityContract rejects runner fields from the preserved contract schema' {
        $schema = Get-Content -LiteralPath $script:contractSchemaPath -Raw | ConvertFrom-Json -Depth 50
        @($schema.properties.PSObject.Properties.Name) | Should -Not -Contain 'frameworks'
        @($schema.properties.PSObject.Properties.Name) | Should -Not -Contain 'llm'
        @($schema.properties.PSObject.Properties.Name) | Should -Not -Contain 'lockedBodySha256'

        foreach ($field in @('frameworks', 'llm', 'lockedBodySha256')) {
            $contract = [ordered]@{
                id       = 'ARCH-No-Runner'
                title    = 'No runner fields'
                maturity = 'draft'
                prose    = 'Human-owned contract.'
            }
            $contract[$field] = if ($field -eq 'frameworks') { @('netarchtest') } elseif ($field -eq 'llm') { @{ promoted = $true } } else { 'a' * 64 }
            ($contract | ConvertTo-Json -Depth 10) |
                Test-Json -SchemaFile $script:contractSchemaPath -ErrorAction SilentlyContinue |
                Should -BeFalse
        }
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

            $good = & $script:validateScript -ContractPath $goodPath -SchemaPath $script:schemaPath
            $good.Valid | Should -BeTrue

            $badPath = Join-Path $dir 'bad.json'
            @{
                id       = 'ARCH-Bad-1'
                title    = 'Locked without hash'
                maturity = 'locked'
                prose    = 'Locked but missing lockedContentSha256.'
            } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $badPath

            $bad = & $script:validateScript -ContractPath $badPath -SchemaPath $script:schemaPath -NoExit
            $bad.Valid | Should -BeFalse
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

            $valid = & $script:validateScript -ContractPath $contractPath -SchemaPath $script:schemaPath -NoExit
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
            $invalid = & $script:validateScript -ContractPath $contractPath -SchemaPath $script:schemaPath -NoExit
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

    It 'ArchContract-Validate: resolves the schema from a scaffolded schemas/ dir without -SchemaPath' {
        $repo = Join-Path ([System.IO.Path]::GetTempPath()) ("arch-repo-" + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path (Join-Path $repo 'schemas/architecture') -Force)
        Copy-Item -LiteralPath $script:schemaPath -Destination (Join-Path $repo 'schemas/architecture/architecture-contract.schema.json')
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
                prose    = 'Locked but missing lockedContentSha256.'
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

Describe 'architecture-notes brownfield harvest evals' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..')).Path
        $script:pluginRoot = Join-Path $script:repoRoot 'plugins/architecture-notes'
        $script:harvestScript = Join-Path $script:pluginRoot 'scripts/Import-ArchHarvest.ps1'

        # Build a small fixture repo: a .NET project and a TS package.
        $script:fixture = Join-Path ([System.IO.Path]::GetTempPath()) ("arch-harvest-" + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path (Join-Path $script:fixture 'src/Api') -Force)
        [void](New-Item -ItemType Directory -Path (Join-Path $script:fixture 'web') -Force)
        Set-Content -LiteralPath (Join-Path $script:fixture 'src/Api/Api.csproj') -Value '<Project Sdk="Microsoft.NET.Sdk"></Project>'
        Set-Content -LiteralPath (Join-Path $script:fixture 'web/package.json') -Value '{ "name": "web-frontend" }'
        Set-Content -LiteralPath (Join-Path $script:fixture 'web/tsconfig.json') -Value '{}'

        $script:harvestResult = & $script:harvestScript -RepoRoot $script:fixture
    }

    AfterAll {
        Remove-Item -LiteralPath $script:fixture -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'Harvest-EmitsDraftOnly: every harvested contract is a valid draft' {
        Test-Path -LiteralPath $script:harvestScript -PathType Leaf | Should -BeTrue
        @($script:harvestResult.Contracts).Count | Should -BeGreaterThan 0
        foreach ($c in $script:harvestResult.Contracts) {
            $c.Maturity | Should -Be 'draft'
            $c.Valid | Should -BeTrue
            Test-Path -LiteralPath $c.Path -PathType Leaf | Should -BeTrue
        }
    }

    It 'Harvest-NoLockedOnImport: no emitted contract file has locked maturity' {
        foreach ($c in $script:harvestResult.Contracts) {
            $onDisk = Get-Content -LiteralPath $c.Path -Raw | ConvertFrom-Json
            $onDisk.maturity | Should -Be 'draft'
            $onDisk.maturity | Should -Not -Be 'locked'
        }
        @($script:harvestResult.Contracts | Where-Object { $_.Maturity -eq 'locked' }).Count | Should -Be 0
    }

    It 'Harvest-QuarantinedUntilReviewed: output is staged, marked reviewed:false, and not in the auto-load index' {
        # Output lands in the .staging quarantine, not the auto-loaded tier.
        $script:harvestResult.StagingRoot | Should -Match '\.staging$'
        $script:harvestResult.Reviewed | Should -BeFalse
        foreach ($c in $script:harvestResult.Contracts) {
            $c.Path | Should -Match '\.staging'
        }

        # Manifest carries the reviewed:false promotion gate.
        $manifestPath = $script:harvestResult.Manifest.Path
        Test-Path -LiteralPath $manifestPath -PathType Leaf | Should -BeTrue
        (Get-Content -LiteralPath $manifestPath -Raw) | Should -Match 'reviewed:\s*false'

        # Harvest must NOT create/populate the auto-loaded index — nothing enters agent context.
        $indexPath = Join-Path $script:fixture 'docs/architecture-notes/.architecture-notes.md'
        Test-Path -LiteralPath $indexPath -PathType Leaf | Should -BeFalse
    }

    It 'Harvest-QuarantinedUntilReviewed: staged notes carry no active glob auto-attach trigger' {
        @($script:harvestResult.Notes).Count | Should -BeGreaterThan 0
        foreach ($n in $script:harvestResult.Notes) {
            $body = Get-Content -LiteralPath $n.Path -Raw
            # The path-scoped auto-attach front-matter must be neutralized while quarantined.
            $body | Should -Not -Match '(?m)^globs:'
            $body | Should -Match 'quarantined:\s*true'
        }
    }

    It 'Harvest-EmitsDraftOnly: an empty repo yields a reviewed:false manifest without crashing' {
        $empty = Join-Path ([System.IO.Path]::GetTempPath()) ("arch-harvest-empty-" + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $empty -Force)
        try {
            $res = & $script:harvestScript -RepoRoot $empty
            @($res.Contracts).Count | Should -Be 0
            $res.Reviewed | Should -BeFalse
            Test-Path -LiteralPath $res.Manifest.Path -PathType Leaf | Should -BeTrue
            (Get-Content -LiteralPath $res.Manifest.Path -Raw) | Should -Match 'reviewed:\s*false'
        }
        finally {
            Remove-Item -LiteralPath $empty -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'architecture-notes human-doc generation evals' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..')).Path
        $script:pluginRoot = Join-Path $script:repoRoot 'plugins/architecture-notes'
        $script:seedScript = Join-Path $script:pluginRoot 'scripts/New-ArchSeed.ps1'
        $script:humanDocScript = Join-Path $script:pluginRoot 'scripts/New-ArchHumanDoc.ps1'
        $script:hashScript = Join-Path $script:pluginRoot 'scripts/Get-ArchContractsHash.ps1'

        # Seed a small repo so schemas/ + the human-doc skeleton exist.
        $script:fixture = Join-Path ([System.IO.Path]::GetTempPath()) ("arch-humandoc-" + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $script:fixture -Force)
        $specPath = Join-Path $script:fixture 'seed.json'
        @{
            project    = 'DocApp'
            boundaries = @(
                @{ id = 'ARCH-Domain'; title = 'Domain core'; prose = 'Domain owns rules; never references Api.'; scope = 'src/Domain/**' },
                @{ id = 'ARCH-Api'; title = 'API surface'; prose = 'Api is the only inbound surface.'; scope = 'src/Api/**' }
            )
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $specPath
        [void](& $script:seedScript -TargetRoot $script:fixture -SeedSpecPath $specPath)
    }

    AfterAll {
        Remove-Item -LiteralPath $script:fixture -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'HumanDoc-Generated: regenerates the doc from contracts and embeds a real digest' {
        Test-Path -LiteralPath $script:humanDocScript -PathType Leaf | Should -BeTrue
        $result = & $script:humanDocScript -RepoRoot $script:fixture
        $result.Action | Should -Be 'created'
        $result.Contracts | Should -Be 2
        $result.Digest | Should -Match '^[0-9a-f]{64}$'

        $body = Get-Content -LiteralPath $result.Path -Raw
        # Generated region reflects the contracts (Mermaid + component summary).
        $body | Should -Match 'Domain core'
        $body | Should -Match 'API surface'
        $body | Should -Match '```mermaid'
        # Digest marker is seeded with the computed hash, not the template placeholder.
        $body | Should -Match ("arch-contracts-sha256: " + $result.Digest)
        $body | Should -Not -Match 'arch-contracts-sha256: UNSEEDED'
    }

    It 'HumanDoc-Generated: digest changes when a contract is added, preserving hand-authored narrative' {
        $first = & $script:humanDocScript -RepoRoot $script:fixture

        # Hand-author a narrative region; the generator must preserve it.
        $docPath = $first.Path
        $doc = Get-Content -LiteralPath $docPath -Raw
        $doc = $doc.Replace('## Purpose & Scope', "## Purpose & Scope`n`nHAND_AUTHORED_MARKER preserved.")
        Set-Content -LiteralPath $docPath -Value $doc -NoNewline

        # Add a third contract → digest must change.
        $schemasDir = Join-Path $script:fixture 'schemas/architecture'
        @{ id = 'ARCH-Infra'; title = 'Infrastructure'; maturity = 'draft'; prose = 'Adapters only.' } |
            ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $schemasDir 'ARCH-Infra.json')

        $second = & $script:humanDocScript -RepoRoot $script:fixture
        $second.Digest | Should -Not -Be $first.Digest
        $second.Contracts | Should -Be 3

        $body = Get-Content -LiteralPath $docPath -Raw
        $body | Should -Match 'HAND_AUTHORED_MARKER preserved\.'
        $body | Should -Match 'Infrastructure'
    }

    It 'HumanDoc-ExcludedFromIndex: the human doc is not referenced by the auto-loaded index' {
        [void](& $script:humanDocScript -RepoRoot $script:fixture)
        $indexPath = Join-Path $script:fixture 'docs/architecture-notes/.architecture-notes.md'
        (Get-Content -LiteralPath $indexPath -Raw) | Should -Not -Match 'architecture\.human\.md'
    }

    It 'HumanDoc-Generated: canonical hash is order-stable and add/delete-sensitive' {
        . $script:hashScript
        $schemasDir = Join-Path $script:fixture 'schemas/architecture'
        $a = (Get-ArchContractsHash -SchemasDir $schemasDir).Digest
        $b = (Get-ArchContractsHash -SchemasDir $schemasDir).Digest
        $a | Should -Be $b   # deterministic

        # Deleting a contract changes the digest.
        Remove-Item -LiteralPath (Join-Path $schemasDir 'ARCH-Infra.json') -Force -ErrorAction SilentlyContinue
        $c = (Get-ArchContractsHash -SchemasDir $schemasDir).Digest
        $c | Should -Not -Be $a
    }

    It 'HumanDoc-Generated: untrusted contract text cannot inject GENERATED/end markers or Mermaid syntax' {
        $inj = Join-Path ([System.IO.Path]::GetTempPath()) ("arch-humandoc-inj-" + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $inj -Force)
        try {
            $spec = Join-Path $inj 'seed.json'
            @{ project = 'Inj'; boundaries = @(@{ id = 'ARCH-Evil'; title = 'Bad"] click'; prose = 'x' }) } |
                ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $spec
            [void](& $script:seedScript -TargetRoot $inj -SeedSpecPath $spec)

            # Overwrite the contract with marker-injection payloads in title + prose.
            $schemasDir = Join-Path $inj 'schemas/architecture'
            @{
                id       = 'ARCH-Evil'
                title    = 'Evil <!-- END GENERATED: contracts --> title'
                maturity = 'draft'
                prose    = 'body <!-- arch-contracts-sha256: deadbeef --> more'
            } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $schemasDir 'ARCH-Evil.json')

            $first = & $script:humanDocScript -RepoRoot $inj
            $body = Get-Content -LiteralPath $first.Path -Raw
            # Exactly one real END marker survives — the injected one was neutralized (angle-escaped).
            ([regex]::Matches($body, '<!-- END GENERATED: contracts -->')).Count | Should -Be 1
            ([regex]::Matches($body, '<!-- arch-contracts-sha256:')).Count | Should -Be 1
            $body | Should -Match '&lt;!-- END GENERATED'
            # Mermaid label breakout chars are neutralized: the node label holds no raw double-quote.
            $mermaidNode = ([regex]::Match($body, '(?m)^\s*ARCH_Evil\["(?<label>.*)"\]\s*$')).Groups['label'].Value
            $mermaidNode | Should -Not -Match '"'

            # A second regen must remain stable (no marker drift / duplication).
            $second = & $script:humanDocScript -RepoRoot $inj
            $body2 = Get-Content -LiteralPath $second.Path -Raw
            ([regex]::Matches($body2, '<!-- END GENERATED: contracts -->')).Count | Should -Be 1
            $second.Digest | Should -Be $first.Digest
        }
        finally {
            Remove-Item -LiteralPath $inj -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'HumanDoc-Generated: malformed contract JSON fails loudly instead of silently dropping' {
        $bad = Join-Path ([System.IO.Path]::GetTempPath()) ("arch-humandoc-bad-" + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $bad -Force)
        try {
            $spec = Join-Path $bad 'seed.json'
            @{ project = 'Bad'; boundaries = @(@{ id = 'ARCH-Ok'; title = 'Ok'; prose = 'x' }) } |
                ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $spec
            [void](& $script:seedScript -TargetRoot $bad -SeedSpecPath $spec)

            Set-Content -LiteralPath (Join-Path $bad 'schemas/ARCH-Broken.json') -Value '{ not valid json'
            { & $script:humanDocScript -RepoRoot $bad } | Should -Throw
        }
        finally {
            Remove-Item -LiteralPath $bad -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'architecture-notes human-doc staleness gate evals' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..')).Path
        $script:pluginRoot = Join-Path $script:repoRoot 'plugins/architecture-notes'
        $script:seedScript = Join-Path $script:pluginRoot 'scripts/New-ArchSeed.ps1'
        $script:humanDocScript = Join-Path $script:pluginRoot 'scripts/New-ArchHumanDoc.ps1'
        $script:freshnessScript = Join-Path $script:repoRoot 'scripts/skalary/Test-ArchDocFreshness.ps1'
    }

    It 'Staleness-FlagsDrift: file:scripts/skalary/Test-ArchDocFreshness.ps1#exists' {
        Test-Path -LiteralPath $script:freshnessScript -PathType Leaf | Should -BeTrue
    }

    It 'Staleness-FlagsDrift: passes when fresh, fails after a contract edit, passes again after regen' {
        $fx = Join-Path ([System.IO.Path]::GetTempPath()) ("arch-fresh-" + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $fx -Force)
        try {
            $spec = Join-Path $fx 'seed.json'
            @{ project = 'FreshApp'; boundaries = @(
                    @{ id = 'ARCH-Domain'; title = 'Domain core'; prose = 'Owns rules.' }
                ) } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $spec
            [void](& $script:seedScript -TargetRoot $fx -SeedSpecPath $spec)
            [void](& $script:humanDocScript -RepoRoot $fx)

            # Freshly generated doc -> pass, exit 0.
            $pass = & $script:freshnessScript -RepoRoot $fx 2>$null
            $passExit = $LASTEXITCODE
            $pass.Status | Should -Be 'pass'
            $passExit | Should -Be 0

            # Add a contract WITHOUT regenerating the doc -> drift, fail, exit 1.
            @{ id = 'ARCH-Api'; title = 'API surface'; maturity = 'draft'; prose = 'Only inbound.' } |
                ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $fx 'schemas/ARCH-Api.json')
            $drift = & $script:freshnessScript -RepoRoot $fx 2>$null
            $driftExit = $LASTEXITCODE
            $drift.Status | Should -Be 'fail'
            $drift.Expected | Should -Not -Be $drift.Actual
            $driftExit | Should -Be 1

            # Regenerate the doc -> fresh again, exit 0.
            [void](& $script:humanDocScript -RepoRoot $fx)
            $pass2 = & $script:freshnessScript -RepoRoot $fx 2>$null
            $pass2Exit = $LASTEXITCODE
            $pass2.Status | Should -Be 'pass'
            $pass2Exit | Should -Be 0
        }
        finally {
            Remove-Item -LiteralPath $fx -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Staleness-FlagsDrift: skips (no-op) when the architecture-notes tier is not seeded' {
        $empty = Join-Path ([System.IO.Path]::GetTempPath()) ("arch-noseed-" + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $empty -Force)
        try {
            $r = & $script:freshnessScript -RepoRoot $empty 2>$null
            $rExit = $LASTEXITCODE
            $r.Status | Should -Be 'skip'
            $rExit | Should -Be 0
        }
        finally {
            Remove-Item -LiteralPath $empty -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Staleness-FlagsDrift: fails when the digest marker is missing from the doc' {
        $fx = Join-Path ([System.IO.Path]::GetTempPath()) ("arch-nomarker-" + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $fx -Force)
        try {
            $spec = Join-Path $fx 'seed.json'
            @{ project = 'NoMarker'; boundaries = @(@{ id = 'ARCH-Domain'; title = 'Domain'; prose = 'x' }) } |
                ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $spec
            [void](& $script:seedScript -TargetRoot $fx -SeedSpecPath $spec)
            [void](& $script:humanDocScript -RepoRoot $fx)

            $docPath = Join-Path $fx 'docs/architecture-notes/architecture.human.md'
            $doc = Get-Content -LiteralPath $docPath -Raw
            $doc = [regex]::Replace($doc, '<!--\s*arch-contracts-sha256:[^>]*-->', '')
            Set-Content -LiteralPath $docPath -Value $doc -NoNewline

            $r = & $script:freshnessScript -RepoRoot $fx 2>$null
            $rExit = $LASTEXITCODE
            $r.Status | Should -Be 'fail'
            $rExit | Should -Be 1
            # Pin the missing-marker branch (not the stale-digest branch, which shares Status/exit):
            # its message names the missing marker and it never computed an Expected digest.
            $r.Message | Should -Match 'missing the arch-contracts-sha256 marker'
            $r.Expected | Should -BeNullOrEmpty

            # Fail-path stderr diagnostics (the CLI/CI side-channel the dual-mode pattern exists for)
            # must be emitted. [Console]::Error.WriteLine bypasses PowerShell streams, so capture it
            # out-of-process where 2>&1 merges the child's real stderr into stdout.
            $err = pwsh -NoProfile -File $script:freshnessScript -RepoRoot $fx 2>&1
            ($err -join "`n") | Should -Match '\[arch-doc-freshness\] FAIL'
        }
        finally {
            Remove-Item -LiteralPath $fx -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Staleness-FlagsDrift: fails when a duplicate/stray digest marker could mask staleness' {
        $fx = Join-Path ([System.IO.Path]::GetTempPath()) ("arch-dupmarker-" + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $fx -Force)
        try {
            $spec = Join-Path $fx 'seed.json'
            @{ project = 'DupMarker'; boundaries = @(@{ id = 'ARCH-Domain'; title = 'Domain'; prose = 'x' }) } |
                ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $spec
            [void](& $script:seedScript -TargetRoot $fx -SeedSpecPath $spec)
            [void](& $script:humanDocScript -RepoRoot $fx)

            # Inject a second, stray marker into the hand-authored narrative. A first-match reader
            # could latch onto it and false-green; the gate must reject the duplicate outright.
            $docPath = Join-Path $fx 'docs/architecture-notes/architecture.human.md'
            $doc = Get-Content -LiteralPath $docPath -Raw
            $stray = '<!-- arch-contracts-sha256: ' + ('0' * 64) + ' -->'
            Set-Content -LiteralPath $docPath -Value ($stray + "`n" + $doc) -NoNewline

            $r = & $script:freshnessScript -RepoRoot $fx 2>$null
            $rExit = $LASTEXITCODE
            $r.Status | Should -Be 'fail'
            $rExit | Should -Be 1
            $r.Message | Should -Match 'markers'
        }
        finally {
            Remove-Item -LiteralPath $fx -Recurse -Force -ErrorAction SilentlyContinue
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
        $script:cipDraftingGuide = Join-Path $script:repoRoot 'plugins/create-implementation-plan/skills/cip/assets/drafting-guide.md'
        $script:ciCrosscheckGuide = Join-Path $script:repoRoot 'plugins/continue-implementation/skills/ci/assets/crosscheck-guide.md'

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
        # /cip capture guidance points planning decisions at the ADR harvest (the capture -> ADR chain).
        (Get-Content -LiteralPath $script:cipDraftingGuide -Raw) | Should -Match '(?i)adr'

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

    It 'Adr-HarvestedAtFinalization: ADRs land quarantined (reviewed:false) under .staging, no-overwrite, index untouched' {
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
        # /ci finalization wires the (gated) harvest so decisions are recorded on the next run.
        (Get-Content -LiteralPath $script:ciCrosscheckGuide -Raw) | Should -Match 'Import-ArchAdr\.ps1'
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
