#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'foreign consumer plugin installation' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        Import-Module (Join-Path $PSScriptRoot '..' 'ConsumerInstallFixture.psm1') -Force -DisableNameChecking
        $script:fixture = New-ConsumerInstallFixture -SourceRepoRoot $script:repoRoot
    }

    AfterAll {
        Remove-ConsumerInstallFixture -Fixture $script:fixture
    }

    It 'test:ConsumerInstall.ForeignFixtureInventory installs the manifest inventory with hashes, dependencies, and confinement intact' {
        $manifestNames = @(
            Get-ChildItem -LiteralPath (Join-Path $script:repoRoot 'plugins') -Recurse -File -Filter 'plugin.json' |
                ForEach-Object {
                    [string](Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json).name
                } |
                Sort-Object
        )
        @($script:fixture.Catalog.PluginNames | Sort-Object) | Should -Be $manifestNames
        @($script:fixture.InstallResults.Plugin | Sort-Object) | Should -Be $manifestNames
        @(
            $script:fixture.InstallResults |
                Where-Object { @($_.NewReceiptNames).Count -gt 1 }
            ).Count | Should -BeGreaterThan 0 -Because (
                'a dependent must run before its dependencies and prove production transitive installation'
            )

        $clean = Test-ConsumerInstallInventory -Fixture $script:fixture
        $clean.IsClean | Should -BeTrue -Because (
            'the production-installed fixture must exactly match active manifests: ' +
            ($clean | ConvertTo-Json -Depth 10 -Compress)
        )
        foreach ($poisonRelativePath in $script:fixture.PoisonRelativePaths) {
            $poisonPath = Join-Path $script:fixture.Root (
                $poisonRelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar
            )
            [System.IO.File]::ReadAllText($poisonPath) | Should -BeExactly 'SKALARY_SOURCE_PATH_POISON'
        }
        @(Get-ChildItem -LiteralPath (Join-Path $script:fixture.Root 'plugins') -Recurse -File -Filter 'plugin.json') |
            Should -BeNullOrEmpty -Because 'a foreign consumer must not receive source manifests or source wildcards'

        $installedFile = @($script:fixture.Catalog.Files | Where-Object { [bool]$_.Install })[0]
        $installedPath = Join-Path (Join-Path $script:fixture.Root '.github') (
            ([string]$installedFile.Dest) -replace '/', [System.IO.Path]::DirectorySeparatorChar
        )
        $originalBytes = [System.IO.File]::ReadAllBytes($installedPath)

        Remove-Item -LiteralPath $installedPath -Force
        $missing = Test-ConsumerInstallInventory -Fixture $script:fixture
        $missing.Missing | Should -Contain ([string]$installedFile.Dest)
        [System.IO.File]::WriteAllBytes($installedPath, $originalBytes)

        $extraPath = Join-Path $script:fixture.Root '.github/consumer-install-extra.txt'
        Set-Content -LiteralPath $extraPath -Value 'extra' -NoNewline -Encoding utf8NoBOM
        $extra = Test-ConsumerInstallInventory -Fixture $script:fixture
        $extra.Extra | Should -Contain 'consumer-install-extra.txt'
        Remove-Item -LiteralPath $extraPath -Force

        Set-Content -LiteralPath $installedPath -Value 'hash mismatch' -NoNewline -Encoding utf8NoBOM
        $hashMismatch = Test-ConsumerInstallInventory -Fixture $script:fixture
        $hashMismatch.HashMismatched | Should -Contain ([string]$installedFile.Dest)
        [System.IO.File]::WriteAllBytes($installedPath, $originalBytes)

        $escapedFiles = @(
            foreach ($file in @($script:fixture.Catalog.Files)) {
                if ($file -eq $installedFile) {
                    [pscustomobject]@{
                        Plugin = [string]$file.Plugin
                        Src = [string]$file.Src
                        Dest = '../consumer-install-escape.txt'
                        Sha256 = [string]$file.Sha256
                        Install = [bool]$file.Install
                        SourcePath = [string]$file.SourcePath
                    }
                }
                else {
                    $file
                }
            }
        )
        $escapedCatalog = [pscustomobject]@{
            SourceRepoRoot = $script:fixture.Catalog.SourceRepoRoot
            Plugins = $script:fixture.Catalog.Plugins
            Files = $escapedFiles
            PluginNames = $script:fixture.Catalog.PluginNames
        }
        $escaping = Test-ConsumerInstallInventory -Fixture $script:fixture -Catalog $escapedCatalog
        $escaping.Escaping | Should -Contain "$($installedFile.Plugin):../consumer-install-escape.txt"
        Test-Path -LiteralPath (Join-Path $script:fixture.Root 'consumer-install-escape.txt') |
            Should -BeFalse

        $staleRegistry = ($script:fixture.Registry | ConvertTo-Json -Depth 100) |
            ConvertFrom-Json -Depth 100
        $registryPlugin = @(
            $staleRegistry.plugins |
                Where-Object { [string]$_.name -eq [string]$installedFile.Plugin }
        )[0]
        $registryMapping = @(
            $registryPlugin.files |
                Where-Object {
                    [string]$_.src -eq [string]$installedFile.Src -and
                    [string]$_.dest -eq [string]$installedFile.Dest
                }
        )[0]
        $registryMapping.dest = "stale/$([System.IO.Path]::GetFileName([string]$installedFile.Dest))"
        $stale = Test-ConsumerInstallInventory -Fixture $script:fixture -Registry $staleRegistry
        $stale.StaleMappings.Count | Should -BeGreaterThan 0

        $duplicateRegistry = ($script:fixture.Registry | ConvertTo-Json -Depth 100) |
            ConvertFrom-Json -Depth 100
        $duplicateRegistryPlugin = @(
            $duplicateRegistry.plugins |
                Where-Object { [string]$_.name -eq [string]$installedFile.Plugin }
        )[0]
        $duplicateRegistryPlugin.files = @($duplicateRegistryPlugin.files) + @(
            $duplicateRegistryPlugin.files[0]
        )
        $duplicateMapping = Test-ConsumerInstallInventory `
            -Fixture $script:fixture `
            -Registry $duplicateRegistry
        $duplicateMapping.StaleMappings -join "`n" | Should -Match 'duplicate mapping'

        $receiptPath = Get-ChildItem -LiteralPath (
            Join-Path $script:fixture.Root '.github/.skalary/receipts'
        ) -File -Filter '*.json' | Select-Object -First 1
        $misnamedReceiptPath = Join-Path $receiptPath.DirectoryName "misnamed-$($receiptPath.Name)"
        Move-Item -LiteralPath $receiptPath.FullName -Destination $misnamedReceiptPath
        $misnamedReceipt = Test-ConsumerInstallInventory -Fixture $script:fixture
        $misnamedReceipt.ReceiptMismatches -join "`n" |
            Should -Match ([regex]::Escape("receipt file 'misnamed-$($receiptPath.Name)'"))
        Move-Item -LiteralPath $misnamedReceiptPath -Destination $receiptPath.FullName

        $receiptBytes = [System.IO.File]::ReadAllBytes($receiptPath.FullName)
        $legacyReceipt = [System.IO.File]::ReadAllText($receiptPath.FullName) |
            ConvertFrom-Json -Depth 100
        $legacyReceipt | Add-Member -NotePropertyName files -NotePropertyValue @()
        Set-Content -LiteralPath $receiptPath.FullName -Value (
            ($legacyReceipt | ConvertTo-Json -Depth 100) + "`n"
        ) -Encoding utf8NoBOM
        $duplicateReceiptResult = Test-ConsumerInstallInventory -Fixture $script:fixture
        $duplicateReceiptResult.ReceiptMismatches -join "`n" | Should -Match 'minimal receipt shape'
        [System.IO.File]::WriteAllBytes($receiptPath.FullName, $receiptBytes)

        $caseVariantGithub = Join-Path $script:fixture.Root '.GITHUB'
        if (-not (Test-Path -LiteralPath $caseVariantGithub)) {
            [void](New-Item -ItemType Directory -Path $caseVariantGithub)
            $caseVariantWrite = Join-Path $caseVariantGithub 'outside-write.txt'
            Set-Content -LiteralPath $caseVariantWrite -Value 'outside' -NoNewline -Encoding utf8NoBOM
            $caseVariantResult = Test-ConsumerInstallInventory -Fixture $script:fixture
            $caseVariantResult.OutsideWrites | Should -Contain '.GITHUB/outside-write.txt'
            Remove-Item -LiteralPath $caseVariantGithub -Recurse -Force
        }

        (Test-ConsumerInstallInventory -Fixture $script:fixture).IsClean |
            Should -BeTrue -Because 'negative probes must restore the shared foreign fixture'
    }


}
