#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Learning loop distribution contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:pluginNames = @(
            'autopilot',
            'continue-implementation',
            'self-improvement'
        )
        $script:manifests = @{}
        foreach ($name in $script:pluginNames) {
            $script:manifests[$name] = Get-Content -LiteralPath (
                Join-Path $script:repoRoot "plugins/$name/plugin.json"
            ) -Raw | ConvertFrom-Json -Depth 100
        }

        $script:registry = Get-Content -LiteralPath (
            Join-Path $script:repoRoot 'registry.json'
        ) -Raw | ConvertFrom-Json -Depth 100
        $script:marketplace = Get-Content -LiteralPath (
            Join-Path $script:repoRoot '.github/plugin/marketplace.json'
        ) -Raw | ConvertFrom-Json -Depth 100

        $script:siSchemas = @(
            'manifest.schema.json',
            'repair-observation.schema.json',
            'repair-receipt.schema.json',
            'resolver-receipt.schema.json',
            'run.schema.json'
        )
        $script:siScripts = @(
            'Archive-SiState.ps1',
            'Complete-SiProposal.ps1',
            'Enqueue-SiDue.ps1',
            'Get-SiHarvest.ps1',
            'Get-SiState.ps1',
            'Invoke-SiLifecycle.ps1',
            'Invoke-SiProposalSync.ps1',
            'Repair-SiState.ps1',
            'SiResolverReceipt.psm1',
            'SiStateStore.psm1',
            'Test-SiResolverReceipt.ps1',
            'Update-SiState.ps1'
        )
        $script:sharedHarvestFiles = @(
            'AtomicStore.psm1',
            'Invoke-PhaseHarvest.ps1',
            'LedgerStore.psm1',
            'PlanState.psm1'
        )

        function Script:Get-NormalizedRelativeFiles {
            param([Parameter(Mandatory)][string]$Root)

            $names = [string[]]@(
                Get-ChildItem -LiteralPath $Root -File |
                    ForEach-Object Name
            )
            [Array]::Sort($names, [System.StringComparer]::Ordinal)
            return $names
        }

        function Script:Assert-ByteIdentical {
            param(
                [Parameter(Mandatory)][string]$Expected,
                [Parameter(Mandatory)][string]$Actual,
                [Parameter(Mandatory)][string]$Because
            )

            Test-Path -LiteralPath $Actual -PathType Leaf |
                Should -BeTrue -Because $Because
            (Get-FileHash -LiteralPath $Actual -Algorithm SHA256).Hash |
                Should -Be (Get-FileHash -LiteralPath $Expected -Algorithm SHA256).Hash `
                    -Because $Because
        }
    }

    It 'test:LearningLoop.PayloadOwnershipAndDrift keeps ownership, bundles, installs, and catalogs synchronized' {
        @($script:manifests.autopilot.dependencies) |
            Should -Contain 'self-improvement'
        @($script:manifests.'continue-implementation'.dependencies) |
            Should -Contain 'autopilot'

        $siRoot = Join-Path $script:repoRoot 'plugins/self-improvement'
        (Get-NormalizedRelativeFiles -Root (Join-Path $siRoot 'schemas')) |
            Should -Be $script:siSchemas
        (Get-NormalizedRelativeFiles -Root (Join-Path $siRoot 'scripts')) |
            Should -Be $script:siScripts

        foreach ($name in $script:siSchemas) {
            $source = "schemas/$name"
            $destination = "skills/si/schemas/$name"
            $entries = @(
                $script:manifests.'self-improvement'.files |
                    Where-Object {
                        [string]$_.src -eq $source -and
                        [string]$_.dest -eq $destination
                    }
            )
            $entries.Count | Should -Be 1
            Assert-ByteIdentical -Expected (Join-Path $siRoot $source) `
                -Actual (Join-Path $script:repoRoot ".github/$destination") `
                -Because "self-improvement must solely own and install $name"
        }

        foreach ($name in $script:siScripts) {
            $source = "scripts/$name"
            $destination = "skills/si/scripts/$name"
            $entries = @(
                $script:manifests.'self-improvement'.files |
                    Where-Object {
                        [string]$_.src -eq $source -and
                        [string]$_.dest -eq $destination
                    }
            )
            $entries.Count | Should -Be 1
            Test-Path -LiteralPath (Join-Path $script:repoRoot "scripts/skalary/$name") |
                Should -BeFalse -Because "$name is plugin-canonical, not a shared root bundle"
            Assert-ByteIdentical -Expected (Join-Path $siRoot $source) `
                -Actual (Join-Path $script:repoRoot ".github/$destination") `
                -Because "the installed SI lifecycle payload must match its plugin-owned source"
        }

        foreach ($consumer in @(
                @{ Plugin = 'autopilot'; Skill = 'autopilot' },
                @{ Plugin = 'continue-implementation'; Skill = 'ci' }
            )) {
            $manifest = $script:manifests[$consumer.Plugin]
            foreach ($name in $script:sharedHarvestFiles) {
                $source = Join-Path $script:repoRoot "scripts/skalary/$name"
                $pluginRelative = "skills/$($consumer.Skill)/scripts/$name"
                $pluginCopy = Join-Path $script:repoRoot "plugins/$($consumer.Plugin)/$pluginRelative"
                $installedCopy = Join-Path $script:repoRoot ".github/$pluginRelative"
                @($manifest.files | Where-Object {
                        [string]$_.src -eq $pluginRelative -and
                        [string]$_.dest -eq $pluginRelative
                    }).Count | Should -Be 1
                Assert-ByteIdentical -Expected $source -Actual $pluginCopy `
                    -Because "$($consumer.Plugin) must carry the root-canonical $name bundle"
                Assert-ByteIdentical -Expected $pluginCopy -Actual $installedCopy `
                    -Because "$($consumer.Plugin) dogfood install must carry $name unchanged"
            }
        }

        $agent = [System.IO.File]::ReadAllText(
            (Join-Path $script:repoRoot 'plugins/autopilot/agents/autopilot.agent.md')
        )
        $agent | Should -Match ([regex]::Escape(
                '.github/skills/autopilot/scripts/Invoke-PhaseHarvest.ps1'
            ))
        $agent | Should -Match ([regex]::Escape(
                '.github/skills/si/scripts/Enqueue-SiDue.ps1'
            ))
        $agent | Should -Match 'Workflow carve-out:.+Invoke-PhaseHarvest\.ps1'
        $agent | Should -Match 'Workflow carve-out:.+Enqueue-SiDue\.ps1'

        $ciGuide = [System.IO.File]::ReadAllText(
            (Join-Path $script:repoRoot (
                'plugins/continue-implementation/skills/ci/assets/crosscheck-guide.md'
            ))
        )
        $ciGuide | Should -Match ([regex]::Escape(
                '.github/skills/ci/scripts/Invoke-PhaseHarvest.ps1'
            ))
        $ciGuide | Should -Match ([regex]::Escape(
                '.github/skills/si/scripts/Invoke-SiLifecycle.ps1'
            ))

        $siSkill = [System.IO.File]::ReadAllText(
            (Join-Path $siRoot 'skills/si/SKILL.md')
        )
        $harvestGuide = [System.IO.File]::ReadAllText(
            (Join-Path $siRoot 'skills/si/assets/harvest-guide.md')
        )
        $siSkill | Should -Match '(?s)Invoke only installed.*Get-SiHarvest\.ps1'
        $harvestGuide | Should -Match 'only executable allowed to read harvest free text'
        foreach ($scriptFile in @(
                Get-ChildItem -LiteralPath (Join-Path $siRoot 'scripts') -File |
                    Where-Object {
                        $_.Extension -in @('.ps1', '.psm1') -and
                        $_.Name -ne 'Get-SiHarvest.ps1'
                    }
            )) {
            [System.IO.File]::ReadAllText($scriptFile.FullName) |
                Should -Not -Match (
                    'docs/review-ledger|docs/feedback/queue|' +
                    'LearningOverflowRoot|HarvestReceiptRoot'
                )
        }

        $receiptScaffolds = @(
            'docs/implementation-plans/<plan>/assets/harvest-receipts/**',
            'docs/implementation-plans/<plan>/harvest-receipts/**'
        )
        foreach ($plugin in @('autopilot', 'continue-implementation')) {
            $declaredScaffolds = @($script:manifests[$plugin].scaffolds.path)
            foreach ($path in $receiptScaffolds) {
                $declaredScaffolds | Should -Contain $path
            }
        }
        $expectedSiScaffolds = @(
            'docs/feedback/queue.md',
            'docs/self-improvement/archive/<yyyy>/<mm>/<run>.json',
            'docs/self-improvement/backups/<observation>/**',
            'docs/self-improvement/harvest-index.json',
            'docs/self-improvement/quarantine/<observation>/**',
            'docs/self-improvement/quarantine/index.json',
            'docs/self-improvement/repair-observations/<observation>.json',
            'docs/self-improvement/repair-receipts',
            'docs/self-improvement/repair-receipts/<receipt>.json',
            'docs/self-improvement/resolver-receipts',
            'docs/self-improvement/resolver-receipts/<receipt>.json',
            'docs/self-improvement/runs/<yyyy>/<mm>/<run>.json',
            'docs/self-improvement/state.json'
        )
        @($script:manifests.'self-improvement'.scaffolds.path | Sort-Object) |
            Should -Be @($expectedSiScaffolds | Sort-Object)

        foreach ($pluginName in $script:pluginNames) {
            $manifest = $script:manifests[$pluginName]
            $registryEntry = @(
                $script:registry.plugins |
                    Where-Object { [string]$_.name -eq $pluginName }
            )
            $marketplaceEntry = @(
                $script:marketplace.plugins |
                    Where-Object { [string]$_.name -eq $pluginName }
            )
            $registryEntry.Count | Should -Be 1
            $marketplaceEntry.Count | Should -Be 1
            [string]$registryEntry[0].version | Should -Be ([string]$manifest.version)
            [string]$marketplaceEntry[0].version | Should -Be ([string]$manifest.version)
            [string]$marketplaceEntry[0].source | Should -Be "plugins/$pluginName"
            @($registryEntry[0].dependencies | Sort-Object) |
                Should -Be @($manifest.dependencies | Sort-Object)
            @($registryEntry[0].files).Count | Should -Be @($manifest.files).Count
            @($registryEntry[0].scaffolds).Count | Should -Be @($manifest.scaffolds).Count

            foreach ($scaffold in @($manifest.scaffolds)) {
                $catalogScaffold = @(
                    $registryEntry[0].scaffolds |
                        Where-Object { [string]$_.path -eq [string]$scaffold.path }
                )
                $catalogScaffold.Count | Should -Be 1
                @($catalogScaffold[0].PSObject.Properties.Name | Sort-Object) |
                    Should -Be @($scaffold.PSObject.Properties.Name | Sort-Object)
                foreach ($property in $scaffold.PSObject.Properties.Name) {
                    ($catalogScaffold[0].$property | ConvertTo-Json -Depth 20 -Compress) |
                        Should -Be ($scaffold.$property | ConvertTo-Json -Depth 20 -Compress)
                }
            }

            foreach ($file in @($manifest.files)) {
                $source = Join-Path $script:repoRoot "plugins/$pluginName/$($file.src)"
                $installed = Join-Path $script:repoRoot ".github/$($file.dest)"
                Assert-ByteIdentical -Expected $source -Actual $installed `
                    -Because "$pluginName payload '$($file.dest)' must match dogfood"

                $catalogFile = @(
                    $registryEntry[0].files |
                        Where-Object {
                            [string]$_.src -eq [string]$file.src -and
                            [string]$_.dest -eq [string]$file.dest
                        }
                )
                $catalogFile.Count | Should -Be 1
                [string]$catalogFile[0].sha256 |
                    Should -Be (
                        (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
                    )
            }
        }

        $duplicateDestinations = @(
            $script:registry.plugins.files |
                Group-Object -Property dest |
                Where-Object Count -GT 1
        )
        $duplicateDestinations.Count | Should -Be 0

        $validate = [System.IO.File]::ReadAllText(
            (Join-Path $script:repoRoot 'scripts/validate.ps1')
        )
        $package = Get-Content -LiteralPath (
            Join-Path $script:repoRoot 'package.json'
        ) -Raw | ConvertFrom-Json
        $validate | Should -Not -Match 'LearningLoop|self-improvement[\\/]evals'
        [string]$package.scripts.build | Should -Not -Match 'npm run eval'
        [string]$package.scripts.test | Should -Not -Match 'npm run eval'
    }
}
