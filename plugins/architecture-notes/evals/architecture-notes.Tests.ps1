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
