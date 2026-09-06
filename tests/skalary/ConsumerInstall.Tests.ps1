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
        $duplicateReceipt = [System.IO.File]::ReadAllText($receiptPath.FullName) |
            ConvertFrom-Json -Depth 100
        $duplicateReceipt.files = @($duplicateReceipt.files) + @($duplicateReceipt.files[0])
        Set-Content -LiteralPath $receiptPath.FullName -Value (
            ($duplicateReceipt | ConvertTo-Json -Depth 100) + "`n"
        ) -Encoding utf8NoBOM
        $duplicateReceiptResult = Test-ConsumerInstallInventory -Fixture $script:fixture
        $duplicateReceiptResult.ReceiptMismatches -join "`n" | Should -Match 'duplicate mapping'
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

    It 'test:ConsumerInstall.RuntimeReferenceClosure proves installed, bundled, scaffolded, missing, source, and dynamic references' {
        $closure = Test-ConsumerRuntimeReferenceClosure -Fixture $script:fixture
        $closure.IsClean | Should -BeTrue -Because (
            'the production scanner and foreign installed inventory must both close: ' +
            ($closure | ConvertTo-Json -Depth 10 -Compress)
        )

        $declaredByDest = [System.Collections.Generic.Dictionary[string, object]]::new(
            [System.StringComparer]::Ordinal
        )
        foreach ($file in @($script:fixture.Catalog.Files | Where-Object { [bool]$_.Install })) {
            $declaredByDest[[string]$file.Dest] = $file
        }

        $installedReferences = [System.Collections.Generic.List[object]]::new()
        foreach ($file in @($script:fixture.Catalog.Files)) {
            $extension = [System.IO.Path]::GetExtension([string]$file.SourcePath).ToLowerInvariant()
            if ($extension -notin @('.md', '.ps1', '.psm1', '.txt')) {
                continue
            }
            $content = [System.IO.File]::ReadAllText([string]$file.SourcePath)
            foreach ($match in [regex]::Matches(
                    $content,
                    '\.github/(?<dest>(?:skills|agents|prompts)/[A-Za-z0-9][A-Za-z0-9._/-]*\.[A-Za-z0-9]+)'
                )) {
                $dest = $match.Groups['dest'].Value
                if ($declaredByDest.ContainsKey($dest)) {
                    $installedReferences.Add($declaredByDest[$dest])
                }
            }
        }
        $installedReferences.Count | Should -BeGreaterThan 0
        foreach ($reference in @($installedReferences)) {
            $installedPath = Join-Path (Join-Path $script:fixture.Root '.github') (
                ([string]$reference.Dest) -replace '/', [System.IO.Path]::DirectorySeparatorChar
            )
            Test-Path -LiteralPath $installedPath -PathType Leaf | Should -BeTrue
        }

        $bundled = @(
            $script:fixture.Catalog.Files |
                Where-Object {
                    [bool]$_.Install -and
                    [string]$_.Dest -match '^skills/[^/]+/scripts/[^/]+\.psm?1$' -and
                    (Test-Path -LiteralPath (
                        Join-Path $script:repoRoot ([string]$_.Dest -replace '^skills/[^/]+/scripts/', 'scripts/skalary/')
                    ) -PathType Leaf)
                }
        )
        $bundled.Count | Should -BeGreaterThan 0
        foreach ($bundle in $bundled) {
            $installedPath = Join-Path (Join-Path $script:fixture.Root '.github') (
                ([string]$bundle.Dest) -replace '/', [System.IO.Path]::DirectorySeparatorChar
            )
            Test-Path -LiteralPath $installedPath -PathType Leaf | Should -BeTrue
            (Get-FileHash -LiteralPath $installedPath -Algorithm SHA256).Hash.ToLowerInvariant() |
                Should -BeExactly ([string]$bundle.Sha256)
        }

        $literalScaffolds = @(
            $script:fixture.Catalog.Plugins |
                ForEach-Object { @($_.Scaffolds) } |
                Where-Object { [string]$_.mode -eq 'literal' }
        )
        $literalScaffolds.Count | Should -BeGreaterThan 0
        @(
            $literalScaffolds |
                Where-Object {
                    -not (Test-Path -LiteralPath (
                            Join-Path $script:fixture.Root (
                                ([string]$_.path) -replace '/', [System.IO.Path]::DirectorySeparatorChar
                            )
                        ))
                }
            ).Count | Should -BeGreaterThan 0 -Because (
                'declared first-use paths remain absent until their runtime owner scaffolds them'
            )

        $missingReference = @($installedReferences)[0]
        $missingPath = Join-Path (Join-Path $script:fixture.Root '.github') (
            ([string]$missingReference.Dest) -replace '/', [System.IO.Path]::DirectorySeparatorChar
        )
        $missingBytes = [System.IO.File]::ReadAllBytes($missingPath)
        try {
            Remove-Item -LiteralPath $missingPath -Force
            $missing = Test-ConsumerRuntimeReferenceClosure -Fixture $script:fixture
            $missing.IsClean | Should -BeFalse
            $missing.Inventory.Missing | Should -Contain ([string]$missingReference.Dest)
        }
        finally {
            [System.IO.File]::WriteAllBytes($missingPath, $missingBytes)
        }

        $scanRoot = Join-Path (
            [System.IO.Path]::GetTempPath()
        ) "skalary-runtime-reference-$([System.Guid]::NewGuid().ToString('N'))"
        try {
            [void](New-Item -ItemType Directory -Path $scanRoot)
            [void](New-Item -ItemType Directory -Path (Join-Path $scanRoot '.git') -Force)
            $pluginRoot = Join-Path $scanRoot 'plugins/fixture'
            $skillPath = Join-Path $pluginRoot 'skills/demo/SKILL.md'
            [void](New-Item -ItemType Directory -Path (Split-Path -Parent $skillPath) -Force)
            $manifest = [ordered]@{
                name = 'fixture'; version = '1.0.0'; description = 'Fixture.'
                author = 'test'; license = 'MIT'; tags = @('skill'); dependencies = @()
                status = 'partial'
                files = @([ordered]@{ src = 'skills/demo/SKILL.md'; dest = 'skills/demo/SKILL.md' })
            }
            Set-Content -LiteralPath (Join-Path $pluginRoot 'plugin.json') -Value (
                $manifest | ConvertTo-Json -Depth 10
            ) -Encoding utf8NoBOM

            Set-Content -LiteralPath $skillPath -Value (
                "# Demo`n`nImport-Module ./plugins/fixture/skills/demo/scripts/SourceOnly.psm1.`n"
            ) -Encoding utf8NoBOM
            {
                & (Join-Path $script:repoRoot 'scripts/skalary/Sync-PluginScripts.ps1') `
                    -RepoRoot $scanRoot -WhatIf *> $null
            } | Should -Throw '*source-tree path*'

            Set-Content -LiteralPath $skillPath -Value (
                "# Demo`n`nLoad ``Join-Path './assets' `$name`` at runtime.`n"
            ) -Encoding utf8NoBOM
            {
                & (Join-Path $script:repoRoot 'scripts/skalary/Sync-PluginScripts.ps1') `
                    -RepoRoot $scanRoot -WhatIf *> $null
            } | Should -Throw '*dynamically composes supported runtime root*'
        }
        finally {
            Remove-Item -LiteralPath $scanRoot -Recurse -Force
        }

        (Test-ConsumerRuntimeReferenceClosure -Fixture $script:fixture).IsClean |
            Should -BeTrue -Because 'negative probes must restore the foreign fixture'
    }

    It 'test:ConsumerInstall.ActivePluginSmokeMatrix exercises one installed-only behavior per active plugin' {
        $expected = @($script:fixture.Catalog.PluginNames | Sort-Object)
        $smokes = @(Invoke-ConsumerInstalledSmokeMatrix -Fixture $script:fixture)

        @($smokes.Plugin | Sort-Object) | Should -Be $expected
        $smokes.Count | Should -Be $expected.Count
        @($smokes | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.Probe) }) |
            Should -BeNullOrEmpty -Because 'every active manifest must have an explicit behavior probe'
        foreach ($smoke in $smokes) {
            $smoke.IsClean | Should -BeTrue -Because (
                "$($smoke.Plugin) must load a manifest-hashed installed payload and complete " +
                "$($smoke.Probe) without source, network, or credentials: exit=$($smoke.ExitCode) " +
                "output=$($smoke.Output)"
            )
        }

        foreach ($poisonRelativePath in $script:fixture.PoisonRelativePaths) {
            $poisonPath = Join-Path $script:fixture.Root (
                $poisonRelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar
            )
            [System.IO.File]::ReadAllText($poisonPath) | Should -BeExactly 'SKALARY_SOURCE_PATH_POISON'
        }
        (Test-ConsumerInstallInventory -Fixture $script:fixture).IsClean |
            Should -BeTrue -Because 'installed smokes must leave the shared foreign fixture unchanged'
    }

    It 'test:EpicAutopilot.ConsumerInstall preserves epic routing across source, dogfood, and a foreign consumer' {
        $ciRelative = 'skills/ci/SKILL.md'
        $wrapperRelative = 'skills/autopilot/scripts/Invoke-EpicAutopilot.ps1'
        $sourceCi = Join-Path $script:repoRoot "plugins/continue-implementation/$ciRelative"
        $dogfoodCi = Join-Path $script:repoRoot ".github/$ciRelative"
        $foreignCi = Join-Path $script:fixture.Root ".github/$ciRelative"
        $sourceWrapper = Join-Path $script:repoRoot (
            "plugins/autopilot/$wrapperRelative"
        )
        $dogfoodWrapper = Join-Path $script:repoRoot ".github/$wrapperRelative"
        $foreignWrapper = Join-Path $script:fixture.Root ".github/$wrapperRelative"

        foreach ($path in @(
                $sourceCi,
                $dogfoodCi,
                $foreignCi,
                $sourceWrapper,
                $dogfoodWrapper,
                $foreignWrapper
            )) {
            Test-Path -LiteralPath $path -PathType Leaf | Should -BeTrue
        }
        foreach ($copy in @($dogfoodCi, $foreignCi)) {
            [System.IO.File]::ReadAllText($copy).Replace("`r`n", "`n") |
                Should -BeExactly (
                    [System.IO.File]::ReadAllText($sourceCi).Replace("`r`n", "`n")
                )
        }
        foreach ($copy in @($dogfoodWrapper, $foreignWrapper)) {
            [System.IO.File]::ReadAllText($copy).Replace("`r`n", "`n") |
                Should -BeExactly (
                    [System.IO.File]::ReadAllText($sourceWrapper).Replace("`r`n", "`n")
                )
        }

        $routeText = [System.IO.File]::ReadAllText($foreignCi)
        $routeText | Should -Match 'Kind: epic'
        $routeText | Should -Match ([regex]::Escape(
                "'.github/skills/autopilot/scripts'"
            ))
        $routeText | Should -Match "'Invoke-EpicAutopilot\.ps1'"
        $routeText | Should -Match '-Epic <state\.EpicId>'
        $routeText | Should -Match '-Target HEAD -RepoRoot <canonical-repo-root>'
        $routeText | Should -Match 'AUTOPILOT_CONTAINER=true'
        $routeText | Should -Match 'Do not\s+select `NextChild`'

        $routingRoot = Join-Path $script:fixture.Root 'epic-routing-execution'
        $originalContainerFlag = $env:AUTOPILOT_CONTAINER
        try {
            $plansRoot = Join-Path $routingRoot 'docs/implementation-plans'
            $epicDir = Join-Path $plansRoot 'epics/2026-08-31-abc123-consumer-epic'
            $childFolder = '2026-08-31-111111-consumer-child'
            $childDir = Join-Path $plansRoot $childFolder
            $launcherDir = Join-Path $routingRoot '.github/skills/autopilot/scripts'
            [void](New-Item -ItemType Directory -Path $epicDir -Force)
            [void](New-Item -ItemType Directory -Path $childDir -Force)
            [void](New-Item -ItemType Directory -Path $launcherDir -Force)
            [System.IO.File]::WriteAllText(
                (Join-Path $epicDir 'epic.md'),
                "# abc123: Consumer epic`n<!-- epic-id: abc123 -->`n"
            )
            [System.IO.File]::WriteAllText(
                (Join-Path $childDir 'plan.md'),
                @(
                    '# 111111: Consumer child'
                    '<!-- plan-id: 111111 -->'
                    '<!-- epic: abc123 -->'
                    ''
                    '## Requirements'
                    ''
                    '| ID | Requirement | Acceptance Criteria | Phases/Steps |'
                    '|----|-------------|---------------------|--------------|'
                    '| REQ-1 | Exercise routing | `test:consumer` | 1.1 |'
                    ''
                    '## Phase 1: Consumer'
                    ''
                    '- [ ] 1.1 Execute fixture (REQ-1) `S`'
                ) -join "`n"
            )
            [System.IO.File]::WriteAllText(
                (Join-Path $launcherDir 'launch.ps1'),
                @'
param(
    [string]$PlanSlug,
    [string]$Mode,
    [string]$Runtime,
    [string]$Branch,
    [string]$ExpectedStartCommit,
    [string]$Run
)
$root = (Resolve-Path (Join-Path $PSScriptRoot '../../../..')).Path
$capture = [ordered]@{
    PlanSlug = $PlanSlug
    Mode = $Mode
    Runtime = $Runtime
    Branch = $Branch
    ExpectedStartCommit = $ExpectedStartCommit
    Run = $Run
    WorkingDirectory = [System.IO.Path]::GetFullPath((Get-Location).Path)
}
[System.IO.File]::WriteAllText(
    (Join-Path $root '.git/launch-capture.json'),
    ($capture | ConvertTo-Json -Compress)
)
exit 37
'@
            )
            & git -C $routingRoot init -q -b main
            & git -C $routingRoot config user.name fixture
            & git -C $routingRoot config user.email fixture@example.invalid
            & git -C $routingRoot add .
            & git -C $routingRoot commit -q -m fixture
            $targetCommit = (& git -C $routingRoot rev-parse HEAD).Trim()

            $env:AUTOPILOT_CONTAINER = $null
            $output = @(
                & (Get-Process -Id $PID).Path -NoProfile -File $foreignWrapper `
                    -Epic abc123 -Target HEAD -RepoRoot $routingRoot 2>&1
            ) | Out-String
            $LASTEXITCODE | Should -Be 37
            $output | Should -Match '"epic":"abc123"'
            $output | Should -Match '"outcome":"exit:37"'

            $capture = Get-Content -LiteralPath (
                Join-Path $routingRoot '.git/launch-capture.json'
            ) -Raw | ConvertFrom-Json
            $capture.PlanSlug | Should -BeExactly $childFolder
            $capture.Mode | Should -BeExactly 'whole-plan'
            $capture.Runtime | Should -BeExactly 'container'
            $capture.Branch | Should -BeExactly 'main'
            $capture.ExpectedStartCommit | Should -BeExactly $targetCommit
            $capture.Run | Should -Match '^[0-9a-f-]{36}$'
            $capture.WorkingDirectory | Should -BeExactly (
                [System.IO.Path]::GetFullPath($routingRoot)
            )
        }
        finally {
            $env:AUTOPILOT_CONTAINER = $originalContainerFlag
            Remove-Item -LiteralPath $routingRoot -Recurse -Force `
                -ErrorAction SilentlyContinue
        }

        (Test-ConsumerInstallInventory -Fixture $script:fixture).IsClean |
            Should -BeTrue -Because 'the installed epic route must leave the consumer inventory intact'
    }

    It 'test:ConsumerInstall.FirstUseScaffoldLifecycle executes every declared owner safely in a foreign repo' {
        # Transactional state writers intentionally do not leave every declared path present:
        # archive journals are removed after commit, while parameterized run/receipt paths depend
        # on a selected durable record. Their dedicated SI suites exercise confinement,
        # recovery, and idempotence. This generic starter-content harness owns only persistent
        # first-use scaffolds whose complete declared shape exists after one invocation.
        $transactionalOwners = @('Write-RecentLearning.ps1')
        $allDeclaredOwners = @(
            $script:fixture.Catalog.Plugins |
                ForEach-Object { @($_.Scaffolds) } |
                ForEach-Object { [string]$_.owner } |
                Sort-Object -Unique
        )
        foreach ($owner in $transactionalOwners) {
            $allDeclaredOwners | Should -Contain $owner
        }
        $expectedOwners = @(
            $allDeclaredOwners |
                Where-Object { $_ -notin $transactionalOwners } |
                Sort-Object -Unique
        )
        $lifecycles = @(
            Invoke-ConsumerFirstUseScaffoldLifecycle `
                -Fixture $script:fixture `
                -ExcludedOwner $transactionalOwners
        )

        @($lifecycles.Owner | Sort-Object) | Should -Be $expectedOwners
        foreach ($lifecycle in $lifecycles) {
            $lifecycle.DeclaredScaffoldsPresent | Should -BeTrue -Because (
                "$($lifecycle.Owner) must materialize every scaffold declared by its manifest"
            )
            $lifecycle.StarterContent | Should -BeTrue -Because (
                "$($lifecycle.Owner) must create non-empty starter content: $($lifecycle.Output)"
            )
            $lifecycle.Idempotent | Should -BeTrue -Because (
                "$($lifecycle.Owner) must not change its scaffold on a repeated invocation"
            )
            $lifecycle.RepeatOutcomeExpected | Should -BeTrue -Because (
                "$($lifecycle.Owner) must report success or its explicit safe repeat refusal"
            )
            $lifecycle.PartialRetrySucceeded | Should -BeTrue -Because (
                "$($lifecycle.Owner) must recover any supported partially-created scaffold"
            )
            $lifecycle.ModifiedTargetPreserved | Should -BeTrue -Because (
                "$($lifecycle.Owner) must preserve consumer-owned target content"
            )
            $lifecycle.ModifiedRetryOutcomeExpected | Should -BeTrue -Because (
                "$($lifecycle.Owner) must report success or an explicit safe refusal for modified content"
            )
            $lifecycle.Confined | Should -BeTrue -Because (
                "$($lifecycle.Owner) created undeclared path(s): $($lifecycle.Created -join ', ')"
            )
            $lifecycle.HostileRefused | Should -BeTrue -Because (
                "$($lifecycle.Owner) must reject hostile input before outside-.github mutation"
            )
            $lifecycle.RetrySucceeded | Should -BeTrue -Because (
                "$($lifecycle.Owner) must succeed when retried with valid input: $($lifecycle.Output)"
            )
        }

        foreach ($poisonRelativePath in $script:fixture.PoisonRelativePaths) {
            $poisonPath = Join-Path $script:fixture.Root (
                $poisonRelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar
            )
            [System.IO.File]::ReadAllText($poisonPath) | Should -BeExactly 'SKALARY_SOURCE_PATH_POISON'
        }
        (Test-ConsumerInstallInventory -Fixture $script:fixture).IsClean |
            Should -BeTrue -Because 'owner probes must leave the shared foreign fixture unchanged'
    }

    It 'test:ConsumerInstall.DistributionDrift keeps generated distribution surfaces converged without mutation' {
        $distribution = Test-ConsumerDistributionDrift -SourceRepoRoot $script:repoRoot

        @($distribution.Checks.Name) |
            Should -Be @('plugin-script-bundles', 'registry', 'marketplace', 'dogfood')
        foreach ($check in @($distribution.Checks)) {
            $check.ExitCode | Should -Be 0 -Because (
                "$($check.Name) remains the production drift authority: $($check.Output)"
            )
        }
        $distribution.Unchanged | Should -BeTrue -Because (
            'detect-only distribution checks must not mutate distribution-owned content: ' +
            ($distribution.Changes -join '; ')
        )
    }
}
