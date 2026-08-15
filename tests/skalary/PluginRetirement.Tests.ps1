#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'plugin retirement catalog' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:historyScript = Join-Path $script:repoRoot 'scripts/skalary/Test-PluginRetirementHistory.ps1'
        $script:historyGate = Join-Path $script:repoRoot 'scripts/skalary/Invoke-PluginRetirementHistoryGate.ps1'
        $script:retirementSchema = Join-Path $script:repoRoot 'schemas/registry/plugin-retirement.schema.json'
        $script:tempRoots = [System.Collections.Generic.List[string]]::new()

        Import-Module (Join-Path $script:repoRoot 'tests/SuiteFixture.psm1') -Force -DisableNameChecking

        function New-RetirementRecord {
            param(
                [string]$Name = 'retired-example',
                [string]$Reason = 'No longer supported.'
            )

            return [ordered]@{
                name = $Name
                retiredAt = '2026-08-15T00:00:00Z'
                reason = $Reason
                payloadSets = @([ordered]@{
                        sourceKind = 'github'
                        sourceIdentity = 'github.com/example/catalog'
                        ref = 'a' * 40
                        version = '1.0.0'
                        files = @([ordered]@{ dest = 'skills/example/SKILL.md'; sha256 = 'b' * 64 })
                    })
                manualResidue = @([ordered]@{
                        kind = 'scaffold'
                        path = 'docs/example'
                        remedy = 'Remove after review.'
                    })
            }
        }

        function Write-RetirementCatalog {
            param(
                [Parameter(Mandatory)][string]$Path,
                [object[]]$Records = @()
            )

            [ordered]@{
                retiredPlugins = @($Records)
                version = 1
            } | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $Path
        }

        function New-TestRoot {
            $root = Join-Path ([System.IO.Path]::GetTempPath()) ("plugin-retirement-" + [guid]::NewGuid().ToString('N'))
            [void](New-Item -ItemType Directory -Path $root -Force)
            $script:tempRoots.Add($root)
            return $root
        }

        function New-RetirementState {
            param(
                [string]$Name = 'retired-example',
                [string]$Status = 'preview',
                [int]$FileCount = 1
            )

            $files = @(
                for ($index = 0; $index -lt $FileCount; $index++) {
                    [pscustomobject][ordered]@{
                        dest = "skills/example/file-$index.txt"
                        expectedSha256 = 'b' * 64
                        observedSha256 = $null
                        outcome = 'pending'
                    }
                }
            )
            return [pscustomobject][ordered]@{
                schemaVersion = 1
                name = $Name
                status = $Status
                transactionId = 'a' * 32
                updatedAt = '2026-08-15T00:00:00Z'
                tombstoneSha256 = 'c' * 64
                prior = [pscustomobject][ordered]@{
                    sourceIdentity = New-PluginSourceIdentity -Repository 'jIRI-san/skalary'
                    ref = 'd' * 40
                    version = '1.2.3'
                }
                affectedFiles = $files
                remedy = 'Rerun the operation to apply the preview.'
            }
        }

        function New-RemovalFixture {
            param(
                [switch]$ModifySecond
            )

            $root = New-TestRoot
            $payloadRoot = Join-Path $root '.github/skills/removal-fixture'
            [void](New-Item -ItemType Directory -Path $payloadRoot -Force)
            $firstPath = Join-Path $payloadRoot 'first.txt'
            $secondPath = Join-Path $payloadRoot 'second.txt'
            Set-Content -LiteralPath $firstPath -Value 'first' -NoNewline -Encoding utf8
            Set-Content -LiteralPath $secondPath -Value 'second' -NoNewline -Encoding utf8
            $firstSha = (Get-FileHash -LiteralPath $firstPath -Algorithm SHA256).Hash.ToLowerInvariant()
            $secondSha = (Get-FileHash -LiteralPath $secondPath -Algorithm SHA256).Hash.ToLowerInvariant()
            $sourceIdentity = New-PluginSourceIdentity -Repository 'jIRI-san/skalary'
            $receipt = [pscustomobject][ordered]@{
                name = 'removal-fixture'
                version = '1.2.3'
                sourceIdentity = $sourceIdentity
                ref = 'd' * 40
                installedAt = '2026-08-15T00:00:00Z'
                files = @(
                    [pscustomobject][ordered]@{
                        dest = 'skills/removal-fixture/first.txt'
                        sha256 = $firstSha
                        outcome = 'installed'
                    },
                    [pscustomobject][ordered]@{
                        dest = 'skills/removal-fixture/second.txt'
                        sha256 = $secondSha
                        outcome = 'installed'
                    }
                )
            }
            $receiptPath = Get-PluginReceiptPath -RepoRoot $root -PluginName 'removal-fixture'
            [void](New-Item -ItemType Directory -Path (Split-Path -Parent $receiptPath) -Force)
            Write-JsonFileStable -Path $receiptPath -InputObject $receipt
            if ($ModifySecond) {
                Set-Content -LiteralPath $secondPath -Value 'modified-second' -NoNewline -Encoding utf8
            }
            return [pscustomobject]@{
                Root = $root
                Receipt = $receipt
                ReceiptPath = $receiptPath
                FirstPath = $firstPath
                FirstSha = $firstSha
                SecondPath = $secondPath
                SecondSha = $secondSha
                SourceIdentity = $sourceIdentity
            }
        }

        function New-RemovalPayloadSet {
            param(
                [Parameter(Mandatory)]
                $Fixture,

                [switch]$IncludeSecond
            )

            $files = @([pscustomobject][ordered]@{
                    dest = 'skills/removal-fixture/first.txt'
                    sha256 = $Fixture.FirstSha
                })
            if ($IncludeSecond) {
                $files += , [pscustomobject][ordered]@{
                    dest = 'skills/removal-fixture/second.txt'
                    sha256 = $Fixture.SecondSha
                }
            }
            return [pscustomobject][ordered]@{
                sourceKind = 'github'
                sourceIdentity = 'github.com/jiri-san/skalary'
                ref = 'd' * 40
                version = '1.2.3'
                files = $files
            }
        }

        function New-SyntheticRetirementRegistry {
            param(
                [Parameter(Mandatory)]
                $Fixture,

                [string]$Name = 'removal-fixture',

                [string]$Version = '1.2.3',

                [object[]]$Files,

                [object[]]$ManualResidue = @()
            )

            if ($null -eq $Files) {
                $Files = @(
                    [pscustomobject][ordered]@{
                        dest = 'skills/removal-fixture/first.txt'
                        sha256 = $Fixture.FirstSha
                    },
                    [pscustomobject][ordered]@{
                        dest = 'skills/removal-fixture/second.txt'
                        sha256 = $Fixture.SecondSha
                    }
                )
            }
            return [pscustomobject]@{
                plugins = @()
                retiredPlugins = @([pscustomobject][ordered]@{
                        name = $Name
                        retiredAt = '2026-08-15T00:00:00Z'
                        reason = 'Synthetic retirement fixture.'
                        payloadSets = @([pscustomobject][ordered]@{
                                sourceKind = [string]$Fixture.SourceIdentity.kind
                                sourceIdentity = [string]$Fixture.SourceIdentity.identity
                                ref = 'd' * 40
                                version = $Version
                                files = $Files
                            })
                        manualResidue = $ManualResidue
                    })
            }
        }

        . (Join-Path $script:repoRoot 'scripts/skalary/_Common.ps1')
    }

    AfterAll {
        foreach ($root in $script:tempRoots) {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:PluginRetirement.RegistryContract publishes the immutable architecture-tests tombstone into skalary registry only' {
        $canonicalPath = Join-Path $script:repoRoot 'registry-retirements.json'
        $canonicalRaw = Get-Content -LiteralPath $canonicalPath -Raw
        $canonicalRaw | Test-Json -SchemaFile $script:retirementSchema | Should -BeTrue
        $canonical = $canonicalRaw | ConvertFrom-Json -Depth 100
        @($canonical.retiredPlugins).Count | Should -Be 1
        $tombstone = @($canonical.retiredPlugins)[0]
        [string]$tombstone.name | Should -Be 'architecture-tests'
        @($tombstone.payloadSets).Count | Should -Be 2
        @($tombstone.payloadSets | ForEach-Object { [string]$_.sourceIdentity } | Select-Object -Unique) |
            Should -Be @('github.com/jiri-san/skalary')
        @($tombstone.manualResidue.kind) |
            Should -Be @('scaffold', 'scaffold', 'scaffold', 'copilot-cli', 'approval-key')

        $frozenReceipt = Get-Content -LiteralPath (Join-Path $script:repoRoot 'tests/skalary/fixtures/plugin-retirement/architecture-tests-pre-cda9da-v1/receipt/architecture-tests.json') -Raw |
            ConvertFrom-Json -Depth 100
        $frozenSet = @($tombstone.payloadSets | Where-Object {
                [string]$_.ref -ceq [string]$frozenReceipt.ref -and
                [string]$_.version -ceq [string]$frozenReceipt.version
            })
        $frozenSet.Count | Should -Be 1
        @($frozenSet[0].files | ForEach-Object { "$($_.dest)|$($_.sha256)" } | Sort-Object) |
            Should -Be @($frozenReceipt.files | ForEach-Object { "$($_.dest)|$($_.sha256)" } | Sort-Object)

        $registry = Get-Content -LiteralPath (Join-Path $script:repoRoot 'registry.json') -Raw | ConvertFrom-Json -Depth 100
        @($registry.plugins.name) | Should -Not -Contain 'architecture-tests'
        @($registry.retiredPlugins).Count | Should -Be 1
        $marketplace = Get-Content -LiteralPath (Join-Path $script:repoRoot '.github/plugin/marketplace.json') -Raw |
            ConvertFrom-Json -Depth 100
        $marketplace.PSObject.Properties.Name | Should -Not -Contain 'retiredPlugins'
        @($marketplace.plugins.name) | Should -Not -Contain 'architecture-tests'
    }

    It 'test:PluginCatalog.GeneratedArtifacts keeps generated catalogs aligned with retirement sources' {
        $canonical = Get-Content -LiteralPath (Join-Path $script:repoRoot 'registry-retirements.json') -Raw |
            ConvertFrom-Json -Depth 100
        $registry = Get-Content -LiteralPath (Join-Path $script:repoRoot 'registry.json') -Raw |
            ConvertFrom-Json -Depth 100
        Get-StableJsonSha256 -InputObject @($registry.retiredPlugins) |
            Should -Be (Get-StableJsonSha256 -InputObject @($canonical.retiredPlugins))

        $marketplaceRaw = Get-Content -LiteralPath (Join-Path $script:repoRoot '.github/plugin/marketplace.json') -Raw
        $marketplaceRaw | Should -Not -Match '"retiredPlugins"'
        $output = pwsh -NoProfile -File (Join-Path $script:repoRoot 'scripts/skalary/Test-Registry.ps1') -RepoRoot $script:repoRoot 2>&1
        $LASTEXITCODE | Should -Be 0
        ($output -join "`n") | Should -Match 'Test-Registry passed'
    }

    It 'test:PluginRetirement.RegistryContract permits first publication and rejects changed or removed records' {
        $root = New-TestRoot
        $baseline = Join-Path $root 'baseline.json'
        $candidate = Join-Path $root 'candidate.json'
        Write-RetirementCatalog -Path $baseline
        Write-RetirementCatalog -Path $candidate -Records @(New-RetirementRecord)

        $first = & $script:historyScript -BaselinePath $baseline -CandidatePath $candidate -SchemaPath $script:retirementSchema
        $first.BaselineCount | Should -Be 0
        $first.CandidateCount | Should -Be 1

        Write-RetirementCatalog -Path $baseline -Records @(New-RetirementRecord)
        Write-RetirementCatalog -Path $candidate -Records @(New-RetirementRecord -Reason 'Changed reason.')
        { & $script:historyScript -BaselinePath $baseline -CandidatePath $candidate -SchemaPath $script:retirementSchema } |
            Should -Throw '*was changed*'

        Write-RetirementCatalog -Path $candidate
        { & $script:historyScript -BaselinePath $baseline -CandidatePath $candidate -SchemaPath $script:retirementSchema } |
            Should -Throw '*was removed*'
    }

    It 'test:PluginRetirement.RegistryContract rejects active-name reuse during generation' {
        $fixture = New-SkalaryFixtureRepo -ProjectRoot $script:repoRoot
        $script:tempRoots.Add($fixture)
        Write-RetirementCatalog -Path (Join-Path $fixture 'registry-retirements.json') -Records @(
            New-RetirementRecord -Name 'code-review'
        )

        $output = pwsh -NoProfile -File (Join-Path $fixture 'scripts/skalary/Build-Registry.ps1') -RepoRoot $fixture 2>&1
        $LASTEXITCODE | Should -Not -Be 0
        ($output -join "`n") | Should -Match "cannot be both active and retired"

        $validation = pwsh -NoProfile -File (Join-Path $fixture 'scripts/skalary/Test-Registry.ps1') -RepoRoot $fixture 2>&1
        $LASTEXITCODE | Should -Not -Be 0
        ($validation -join "`n") | Should -Match "cannot be both active and retired"
    }

    It 'test:PluginRetirement.RegistryContract exposes retired plugins only through direct exact lookup' {
        $root = New-TestRoot
        git -C $root init --quiet
        $registryPath = Join-Path $root 'registry.json'
        [ordered]@{
            bootstrap = @{ ref = 'main'; scriptUrl = 'https://example.invalid/bootstrap.ps1'; oneLiner = 'none' }
            generatedAt = '2026-08-15T00:00:00Z'
            plugins = @()
            retiredPlugins = @(New-RetirementRecord)
        } | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $registryPath

        $direct = @(& (Join-Path $script:repoRoot 'scripts/skalary/Find-Plugin.ps1') -Query 'retired-example' -RepoRoot $root -RegistryPath $registryPath)
        $direct.Count | Should -Be 1
        $direct[0].status | Should -Be 'retired'
        $direct[0].retired | Should -BeTrue

        @(& (Join-Path $script:repoRoot 'scripts/skalary/Find-Plugin.ps1') -Query 'retired' -RepoRoot $root -RegistryPath $registryPath).Count |
            Should -Be 0
    }

    It 'test:PluginRetirement.RegistryContract treats a resolvable missing catalog as empty and rejects unavailable baseline commits' {
        $startingCommit = (Get-Content -LiteralPath (Join-Path $script:repoRoot 'tests/skalary/fixtures/plugin-retirement/cda9da-historical-manifest.json') -Raw |
                ConvertFrom-Json).startingCommit
        $candidateSha = (git -C $script:repoRoot rev-parse HEAD).Trim()
        $result = @(& $script:historyGate -RepoRoot $script:repoRoot -BaselineSha $startingCommit -CandidateSha $candidateSha)
        $comparison = @($result | Where-Object { $_.PSObject.Properties.Name -contains 'BaselineCount' })[0]
        $comparison.BaselineCount | Should -Be 0

        {
            & $script:historyGate -RepoRoot $script:repoRoot -BaselineSha ('f' * 40) -CandidateSha $candidateSha
        } | Should -Throw '*baseline commit is unavailable*'
    }

    It 'test:PluginRetirement.RegistryContract keeps Test-Registry Git-free and wires explicit CI SHAs' {
        $testRegistryPath = Join-Path $script:repoRoot 'scripts/skalary/Test-Registry.ps1'
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($testRegistryPath, [ref]$tokens, [ref]$errors)
        @($errors).Count | Should -Be 0
        @($ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and
                    $node.GetCommandName() -eq 'git'
                }, $true)).Count | Should -Be 0

        $workflow = Get-Content -LiteralPath (Join-Path $script:repoRoot '.github/workflows/registry-ci.yml') -Raw
        $workflow | Should -Match 'github\.event\.pull_request\.base\.sha'
        $workflow | Should -Match 'github\.event\.before'
        $workflow | Should -Match 'github\.sha'
        $workflow | Should -Match 'Invoke-PluginRetirementHistoryGate\.ps1'
    }

    It 'test:PluginRetirement.InstallConfinement preserves the existing .github write boundary while retirement is catalog-only' {
        $root = New-TestRoot
        git -C $root init --quiet
        $valid = Resolve-GithubConstrainedPath -RepoRoot $root -RelativePath 'skills/example/SKILL.md'
        $valid | Should -Be (Join-Path $root '.github/skills/example/SKILL.md')

        foreach ($invalid in @('../escape', '/absolute', 'C:\rooted', '\\server\share')) {
            { Resolve-GithubConstrainedPath -RepoRoot $root -RelativePath $invalid } | Should -Throw
        }

        $contract = Get-Content -LiteralPath (Join-Path $script:repoRoot 'schemas/architecture/ARCH-Install-Confinement.json') -Raw |
            ConvertFrom-Json
        [string]$contract.prose | Should -Match 'only inside.*\.github'
        @((Get-Content -LiteralPath (Join-Path $script:repoRoot 'registry-retirements.json') -Raw |
                ConvertFrom-Json).retiredPlugins).Count | Should -Be 1
    }

    It 'test:PluginRetirement.SourceIdentityAndSecretGuard uses one credential-free versioned identity across receipts and retirement state' {
        $secret = 'SENTINEL-RETIREMENT-SECRET'
        $sha = 'e' * 40
        $github = New-PluginSourceIdentity -Repository "https://x-access-token:$secret@GitHub.com/JIRI-san/Skalary.git?token=$secret#fragment"
        $ssh = New-PluginSourceIdentity -Repository 'git@github.com:jiri-SAN/SKALARY.git'
        $localRoot = New-TestRoot
        $local = New-PluginSourceIdentity -LocalPath $localRoot

        $github.version | Should -Be 1
        $github.kind | Should -Be 'github'
        $github.identity | Should -Be 'github.com/jiri-san/skalary'
        (Test-PluginSourceIdentityEqual -Left $github -Right $ssh) | Should -BeTrue
        (New-PluginSourceIdentity -Repository 'ssh://git@github.com:22/jIRI-san/skalary.git').identity |
            Should -Be 'github.com/jiri-san/skalary'
        { New-PluginSourceIdentity -Repository 'file://github.com/jIRI-san/skalary' } | Should -Throw
        { New-PluginSourceIdentity -Repository 'foo://github.com/jIRI-san/skalary' } | Should -Throw
        $local.kind | Should -Be 'local'
        $local.identity | Should -Match '^sha256:[a-f0-9]{64}$'
        ($local | ConvertTo-Json -Compress) | Should -Not -Match ([regex]::Escape($localRoot))
        foreach ($invalidVersion in @('1', 1.1, $true)) {
            {
                Assert-PluginSourceIdentity -SourceIdentity ([pscustomobject]@{
                        version = $invalidVersion
                        kind = 'github'
                        identity = 'github.com/jiri-san/skalary'
                    })
            } | Should -Throw
        }
        foreach ($nonCanonical in @(
                [pscustomobject]@{ version = 1; kind = 'GITHUB'; identity = 'github.com/jiri-san/skalary' },
                [pscustomobject]@{ version = 1; kind = 'github'; identity = 'GitHub.com/JIRI-san/Skalary' },
                [pscustomobject]@{ version = 1; kind = 'local'; identity = "SHA256:$('A' * 64)" }
            )) {
            { Assert-PluginSourceIdentity -SourceIdentity $nonCanonical } | Should -Throw
        }

        $legacy = [pscustomobject]@{
            source = "remote:https://x-access-token:$secret@github.com/jIRI-san/skalary.git@$sha"
            ref = $sha
        }
        $upgraded = Resolve-PluginReceiptSourceIdentity -Receipt $legacy
        $upgraded.identity | Should -Be 'github.com/jiri-san/skalary'
        ($upgraded | ConvertTo-Json -Compress) | Should -Not -Match $secret

        $ambiguousError = $null
        try {
            Resolve-PluginReceiptSourceIdentity -Receipt ([pscustomobject]@{
                    source = "opaque:$secret"
                    ref = $sha
                })
        }
        catch {
            $ambiguousError = $_.Exception.Message
        }
        $ambiguousError | Should -Match 'ambiguous'
        $ambiguousError | Should -Not -Match $secret

        $receipt = [pscustomobject][ordered]@{
            name = 'retired-example'
            version = '1.2.3'
            sourceIdentity = $github
            ref = $sha
            installedAt = '2026-08-15T00:00:00Z'
            files = @([pscustomobject][ordered]@{
                    dest = 'skills/example/SKILL.md'
                    sha256 = 'f' * 64
                    outcome = 'installed'
                })
        }
        $receiptJson = $receipt | ConvertTo-Json -Depth 20
        $receiptJson | Test-Json -SchemaFile (Join-Path $script:repoRoot 'schemas/receipt/receipt.schema.json') | Should -BeTrue
        $receiptJson | Should -Not -Match $secret
        $receiptJson | Should -Not -Match ([regex]::Escape($sha + '@'))
        ($receiptJson.Replace($sha, ('a' * 64))) |
            Test-Json -SchemaFile (Join-Path $script:repoRoot 'schemas/receipt/receipt.schema.json') |
            Should -BeTrue

        foreach ($scriptName in @('Install-Plugin.ps1', 'Update-Plugin.ps1')) {
            $scriptText = Get-Content -LiteralPath (Join-Path $script:repoRoot "scripts/skalary/$scriptName") -Raw
            $scriptText | Should -Match 'New-PluginSourceIdentity'
            $scriptText | Should -Match 'sourceIdentity'
            $scriptText | Should -Not -Match 'source\s*=\s*"\$sourceLabel@'
        }
    }

    It 'test:PluginRetirement.ReconciliationStateMatrix confines and validates complete durable state while bounding summaries only' {
        $root = New-TestRoot
        [void](New-Item -ItemType Directory -Path (Join-Path $root '.github') -Force)
        $state = New-RetirementState -FileCount 12

        $statePath = Write-PluginRetirementState -RepoRoot $root -State $state
        $statePath | Should -Be (Join-Path $root '.github/.skalary/retirements/retired-example.json')
        $raw = Get-Content -LiteralPath $statePath -Raw
        $raw | Test-Json -SchemaFile (Join-Path $script:repoRoot 'schemas/retirement/retirement-state.schema.json') | Should -BeTrue

        $persisted = Read-PluginRetirementState -RepoRoot $root -PluginName 'retired-example'
        @($persisted.affectedFiles).Count | Should -Be 12
        $summary = Get-PluginRetirementSummary -State $persisted -MaxPaths 3
        $summary.totalPaths | Should -Be 12
        @($summary.paths).Count | Should -Be 3
        $summary.omittedPaths | Should -Be 9
        @((Read-PluginRetirementState -RepoRoot $root -PluginName 'retired-example').affectedFiles).Count | Should -Be 12

        foreach ($status in @('preview', 'applying', 'retired', 'residue', 'failed')) {
            { Test-PluginRetirementState -State (New-RetirementState -Status $status) } | Should -Not -Throw
        }

        $hostile = New-RetirementState
        $hostile.affectedFiles[0].dest = '../outside.txt'
        { Write-PluginRetirementState -RepoRoot $root -State $hostile } | Should -Throw
        { Get-PluginRetirementStatePath -RepoRoot $root -PluginName '../outside' } | Should -Throw
        Test-Path -LiteralPath (Join-Path $root 'outside.json') | Should -BeFalse

        if (-not $IsWindows) {
            $linkedRoot = New-TestRoot
            $outsideRoot = New-TestRoot
            [void](New-Item -ItemType Directory -Path (Join-Path $linkedRoot '.github') -Force)
            [void](New-Item -ItemType SymbolicLink -Path (Join-Path $linkedRoot '.github/.skalary') -Target $outsideRoot)
            { Write-PluginRetirementState -RepoRoot $linkedRoot -State (New-RetirementState) } | Should -Throw '*link or reparse point*'
            Test-Path -LiteralPath (Join-Path $outsideRoot 'retirements/retired-example.json') | Should -BeFalse
        }
    }

    It 'test:PluginRetirement.ReaderRemovalAndResultContract preserves modified ownership and force-removes through one primitive' {
        $fixture = New-RemovalFixture -ModifySecond
        $modifiedSha = Get-FileSha256 -Path $fixture.SecondPath
        $updatedReceipt = Read-JsonFile -Path $fixture.ReceiptPath
        $updatedReceipt.files[1].sha256 = $modifiedSha
        $updatedReceipt.files[1].outcome = 'skipped-modified'
        Write-JsonFileStable -Path $fixture.ReceiptPath -InputObject $updatedReceipt
        $result = Invoke-PluginRemovalPrimitive -RepoRoot $fixture.Root -PluginName 'removal-fixture'
        $result.RemovedCount | Should -Be 1
        $result.ModifiedCount | Should -Be 1
        Test-Path -LiteralPath $fixture.FirstPath | Should -BeFalse
        Test-Path -LiteralPath $fixture.SecondPath | Should -BeTrue

        $degraded = Read-PluginReceipt -RepoRoot $fixture.Root -PluginName 'removal-fixture'
        $degraded.degraded | Should -BeTrue
        @($degraded.files).Count | Should -Be 1
        [string]$degraded.files[0].dest | Should -Be 'skills/removal-fixture/second.txt'
        [string]$degraded.files[0].sha256 | Should -Be $modifiedSha
        [string]$degraded.files[0].outcome | Should -Be 'skipped-modified'

        $forced = Invoke-PluginRemovalPrimitive -RepoRoot $fixture.Root -PluginName 'removal-fixture' -Force
        $forced.RemovedCount | Should -Be 1
        Test-Path -LiteralPath $fixture.SecondPath | Should -BeFalse
        Test-Path -LiteralPath $fixture.ReceiptPath | Should -BeFalse
    }

    It 'test:PluginRetirement.ReaderRemovalAndResultContract derives retirement deletes from the exact tombstone and receipt intersection' {
        $fixture = New-RemovalFixture
        $payloadSet = New-RemovalPayloadSet -Fixture $fixture
        $result = Invoke-PluginRemovalPrimitive -RepoRoot $fixture.Root -PluginName 'removal-fixture' -Mode retirement -PayloadSet $payloadSet

        $result.RemovedCount | Should -Be 1
        Test-Path -LiteralPath $fixture.FirstPath | Should -BeFalse
        Test-Path -LiteralPath $fixture.SecondPath | Should -BeTrue
        $remaining = Read-PluginReceipt -RepoRoot $fixture.Root -PluginName 'removal-fixture'
        @($remaining.files).Count | Should -Be 1
        [string]$remaining.files[0].dest | Should -Be 'skills/removal-fixture/second.txt'

        $mismatch = New-RemovalFixture
        $foreign = New-RemovalPayloadSet -Fixture $mismatch -IncludeSecond
        $foreign.sourceIdentity = 'github.com/example/foreign'
        {
            Invoke-PluginRemovalPrimitive -RepoRoot $mismatch.Root -PluginName 'removal-fixture' -Mode retirement -PayloadSet $foreign
        } | Should -Throw '*source does not match*'
        Test-Path -LiteralPath $mismatch.FirstPath | Should -BeTrue
        Test-Path -LiteralPath $mismatch.SecondPath | Should -BeTrue

        $wrongVersion = New-RemovalPayloadSet -Fixture $mismatch -IncludeSecond
        $wrongVersion.version = '9.9.9'
        {
            Invoke-PluginRemovalPrimitive -RepoRoot $mismatch.Root -PluginName 'removal-fixture' -Mode retirement -PayloadSet $wrongVersion
        } | Should -Throw '*ref/version does not match*'

        $caseMismatch = New-RemovalFixture
        $casePayload = New-RemovalPayloadSet -Fixture $caseMismatch
        $casePayload.files[0].dest = 'Skills/removal-fixture/first.txt'
        $beforeReceiptSha = Get-StableJsonSha256 -InputObject (Read-JsonFile -Path $caseMismatch.ReceiptPath)
        $caseResult = Invoke-PluginRemovalPrimitive -RepoRoot $caseMismatch.Root -PluginName 'removal-fixture' -Mode retirement -PayloadSet $casePayload
        $caseResult.RemovedCount | Should -Be 0
        Test-Path -LiteralPath $caseMismatch.FirstPath | Should -BeTrue
        Get-StableJsonSha256 -InputObject (Read-JsonFile -Path $caseMismatch.ReceiptPath) | Should -Be $beforeReceiptSha
    }

    It 'test:PluginRetirement.TransactionRecovery restores exact payload and receipt at every deterministic fault seam' {
        foreach ($fault in @('after-journal', 'after-backup', 'after-delete', 'after-receipt')) {
            $fixture = New-RemovalFixture
            $receiptBefore = Get-StableJsonSha256 -InputObject (Read-JsonFile -Path $fixture.ReceiptPath)
            {
                Invoke-PluginRemovalPrimitive -RepoRoot $fixture.Root -PluginName 'removal-fixture' -FaultAt $fault
            } | Should -Throw "*Injected plugin removal fault*"

            Test-Path -LiteralPath $fixture.FirstPath | Should -BeTrue
            Test-Path -LiteralPath $fixture.SecondPath | Should -BeTrue
            Get-FileSha256 -Path $fixture.FirstPath | Should -Be $fixture.FirstSha
            Get-FileSha256 -Path $fixture.SecondPath | Should -Be $fixture.SecondSha
            Get-StableJsonSha256 -InputObject (Read-JsonFile -Path $fixture.ReceiptPath) | Should -Be $receiptBefore
            Test-Path -LiteralPath (Get-PluginRemovalJournalPath -RepoRoot $fixture.Root -PluginName 'removal-fixture') |
                Should -BeFalse
            @(Get-ChildItem -LiteralPath (Join-Path $fixture.Root '.github/.skalary/tmp') -Directory -Filter 'removal-*' -ErrorAction SilentlyContinue).Count |
                Should -Be 0
        }
    }

    It 'test:PluginRetirement.TransactionRecovery rejects hostile journals and mixed-version recovery' {
        $fixture = New-RemovalFixture
        $transactionId = 'a' * 32
        $operationRoot = ".skalary/tmp/removal-$transactionId"
        $backupRelative = "$operationRoot/backups/00000.bak"
        $backupPath = Resolve-GithubConstrainedPath -RepoRoot $fixture.Root -RelativePath $backupRelative
        [void](New-Item -ItemType Directory -Path (Split-Path -Parent $backupPath) -Force)
        Copy-Item -LiteralPath $fixture.FirstPath -Destination $backupPath
        $receiptBefore = Read-JsonFile -Path $fixture.ReceiptPath
        $receiptAfter = Read-JsonFile -Path $fixture.ReceiptPath
        $receiptAfter.files = @($receiptAfter.files[1])
        $receiptAfter | Add-Member -NotePropertyName degraded -NotePropertyValue $true
        $journal = [pscustomobject][ordered]@{
            schemaVersion = 1
            transactionId = $transactionId
            pluginName = 'removal-fixture'
            mode = 'retirement'
            sourceIdentity = $fixture.SourceIdentity
            operationRoot = $operationRoot
            receiptBefore = $receiptBefore
            receiptBeforeSha256 = Get-StableJsonSha256 -InputObject $receiptBefore
            receiptAfter = $receiptAfter
            receiptAfterSha256 = Get-StableJsonSha256 -InputObject $receiptAfter
            entries = @([pscustomobject][ordered]@{
                    dest = 'skills/removal-fixture/first.txt'
                    expectedSha256 = $fixture.FirstSha
                    originalSha256 = $fixture.FirstSha
                    backupRelativePath = $backupRelative
                    backupSha256 = $fixture.FirstSha
                    phase = 'backed-up'
                })
            updatedAt = '2026-08-15T00:00:00Z'
        }
        ($journal | ConvertTo-Json -Depth 30) |
            Test-Json -SchemaFile (Join-Path $script:repoRoot 'schemas/retirement/removal-journal.schema.json') |
            Should -BeTrue
        $embeddedSchema = Get-PluginRemovalJournalSchema | ConvertFrom-Json -Depth 100
        $publishedSchema = Get-Content -LiteralPath (Join-Path $script:repoRoot 'schemas/retirement/removal-journal.schema.json') -Raw |
            ConvertFrom-Json -Depth 100
        foreach ($metadata in @('$id', 'title', 'description')) {
            $publishedSchema.PSObject.Properties.Remove($metadata)
        }
        Get-StableJsonSha256 -InputObject $embeddedSchema |
            Should -Be (Get-StableJsonSha256 -InputObject $publishedSchema)
        [void](Write-PluginRemovalJournal -RepoRoot $fixture.Root -Journal $journal)

        $changedReceipt = Read-JsonFile -Path $fixture.ReceiptPath
        $changedReceipt.version = '2.0.0'
        Write-JsonFileStable -Path $fixture.ReceiptPath -InputObject $changedReceipt
        {
            Invoke-PluginRemovalRecovery -RepoRoot $fixture.Root -PluginName 'removal-fixture' -ExpectedSourceIdentity $fixture.SourceIdentity
        } | Should -Throw '*mixed-version rollback*'

        $journal.entries[0].backupRelativePath = '../outside.bak'
        { Test-PluginRemovalJournal -RepoRoot $fixture.Root -Journal $journal } | Should -Throw
        $journal.entries[0].backupRelativePath = $backupRelative
        $journal.entries[0].backupSha256 = 'f' * 64
        { Test-PluginRemovalJournal -RepoRoot $fixture.Root -Journal $journal } | Should -Throw '*backup hash is invalid*'

        $journal.entries[0].backupSha256 = $fixture.FirstSha
        $journal.entries[0].dest = 'workflows/unrelated.yml'
        { Test-PluginRemovalJournal -RepoRoot $fixture.Root -Journal $journal } |
            Should -Throw '*not owned by its receipt pre-state*'

        $journal.entries[0].dest = 'skills/removal-fixture/first.txt'
        {
            Invoke-PluginRemovalRecovery -RepoRoot $fixture.Root -PluginName 'removal-fixture' -ExpectedSourceIdentity $fixture.SourceIdentity -ExpectedRef ('e' * 40) -ExpectedVersion '1.2.3'
        } | Should -Throw '*immutable ref does not match*'

        $journal.receiptAfter = $null
        $journal.receiptAfterSha256 = $null
        [void](Write-PluginRemovalJournal -RepoRoot $fixture.Root -Journal $journal)
        Remove-Item -LiteralPath $fixture.ReceiptPath -Force
        { Invoke-PluginRemovalRecovery -RepoRoot $fixture.Root -PluginName 'removal-fixture' -ExpectedSourceIdentity $fixture.SourceIdentity } |
            Should -Throw '*does not cover every pre-state destination*'
    }

    It 'test:PluginRetirement.TransactionRecovery serializes removal before reading mutable authority' {
        $fixture = New-RemovalFixture
        $lockPath = Resolve-GithubConstrainedPath -RepoRoot $fixture.Root -RelativePath '.skalary/mutation.lock'
        $lockStream = [System.IO.File]::Open(
            $lockPath,
            [System.IO.FileMode]::OpenOrCreate,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None)
        try {
            { Invoke-PluginRemovalPrimitive -RepoRoot $fixture.Root -PluginName 'removal-fixture' } | Should -Throw
            Test-Path -LiteralPath $fixture.FirstPath | Should -BeTrue
            Test-Path -LiteralPath $fixture.ReceiptPath | Should -BeTrue
        }
        finally {
            $lockStream.Dispose()
        }
    }

    It 'test:PluginRetirement.TransactionRecovery rejects linked destinations before state read or mutation' -Skip:$IsWindows {
        $fixture = New-RemovalFixture
        $outside = New-TestRoot
        $outsideFile = Join-Path $outside 'first.txt'
        Set-Content -LiteralPath $outsideFile -Value 'outside' -NoNewline -Encoding utf8
        Remove-Item -LiteralPath (Split-Path -Parent $fixture.FirstPath) -Recurse -Force
        [void](New-Item -ItemType SymbolicLink -Path (Split-Path -Parent $fixture.FirstPath) -Target $outside)

        { Invoke-PluginRemovalPrimitive -RepoRoot $fixture.Root -PluginName 'removal-fixture' } |
            Should -Throw '*link or reparse point*'
        Get-Content -LiteralPath $outsideFile -Raw | Should -Be 'outside'
        Test-Path -LiteralPath (Get-PluginRemovalJournalPath -RepoRoot $fixture.Root -PluginName 'removal-fixture') |
            Should -BeFalse
    }

    It 'test:PluginRetirement.TransactionRecovery transitions failed state only after exact recovery verification' {
        $fixture = New-RemovalFixture
        $state = New-RetirementState -Name 'removal-fixture' -Status failed -FileCount 1
        $state.prior.sourceIdentity = $fixture.SourceIdentity
        $state.prior.ref = 'd' * 40
        $state.prior.version = '1.2.3'
        $state.affectedFiles[0].dest = 'skills/removal-fixture/first.txt'
        $state.affectedFiles[0].expectedSha256 = $fixture.FirstSha
        $state.affectedFiles[0].observedSha256 = $fixture.FirstSha
        $state.affectedFiles[0].outcome = 'pending'
        $state | Add-Member -NotePropertyName error -NotePropertyValue 'injected failure'
        [void](Write-PluginRetirementState -RepoRoot $fixture.Root -State $state)

        $preview = Reset-FailedPluginRetirementState -RepoRoot $fixture.Root -PluginName 'removal-fixture'
        $preview.status | Should -Be 'preview'
        $preview.PSObject.Properties.Name | Should -Not -Contain 'error'

        $state.status = 'failed'
        $state.transactionId = 'f' * 32
        $state | Add-Member -NotePropertyName error -NotePropertyValue 'second failure' -Force
        [void](Write-PluginRetirementState -RepoRoot $fixture.Root -State $state)
        Set-Content -LiteralPath $fixture.FirstPath -Value 'unexpected' -NoNewline -Encoding utf8
        { Reset-FailedPluginRetirementState -RepoRoot $fixture.Root -PluginName 'removal-fixture' } |
            Should -Throw '*content does not match*'
        (Read-PluginRetirementState -RepoRoot $fixture.Root -PluginName 'removal-fixture').status | Should -Be 'failed'
    }

    It 'test:PluginRetirement.TransactionRecovery restores a representative hard-killed delete' -Skip:$IsWindows {
        $fixture = New-RemovalFixture
        $registry = New-SyntheticRetirementRegistry -Fixture $fixture
        [void](Invoke-PluginRetirementReconciliation -RepoRoot $fixture.Root -Registry $registry -SourceIdentity $fixture.SourceIdentity)
        $applying = Read-PluginRetirementState -RepoRoot $fixture.Root -PluginName 'removal-fixture'
        $applying.status = 'applying'
        [void](Write-PluginRetirementState -RepoRoot $fixture.Root -State $applying)
        $driver = Join-Path $fixture.Root 'hard-kill-driver.ps1'
        @(
            '$ErrorActionPreference = ''Stop''',
            ". '$($script:repoRoot)/scripts/skalary/_Common.ps1'",
            "Invoke-PluginRemovalPrimitive -RepoRoot '$($fixture.Root)' -PluginName 'removal-fixture' -FaultAt 'pause-after-delete'"
        ) | Set-Content -LiteralPath $driver -Encoding utf8
        $process = Start-Process pwsh -ArgumentList @('-NoProfile', '-File', $driver) -PassThru
        try {
            $journalPath = Get-PluginRemovalJournalPath -RepoRoot $fixture.Root -PluginName 'removal-fixture'
            $deadline = [DateTimeOffset]::UtcNow.AddSeconds(10)
            $deleteObserved = $false
            while ([DateTimeOffset]::UtcNow -lt $deadline) {
                if (Test-Path -LiteralPath $journalPath -PathType Leaf) {
                    try {
                        $journal = Get-Content -LiteralPath $journalPath -Raw | ConvertFrom-Json -Depth 100
                        $deleteObserved = @($journal.entries | Where-Object { [string]$_.phase -eq 'deleted' }).Count -gt 0
                    }
                    catch {
                        $deleteObserved = $false
                    }
                    if ($deleteObserved) { break }
                }
                Start-Sleep -Milliseconds 50
            }
            $deleteObserved | Should -BeTrue
            $process.Kill($true)
            $process.WaitForExit()
        }
        finally {
            if (-not $process.HasExited) {
                $process.Kill($true)
                $process.WaitForExit()
            }
            $process.Dispose()
        }

        Test-Path -LiteralPath $fixture.FirstPath | Should -BeFalse
        $resumed = Invoke-PluginRetirementReconciliation -RepoRoot $fixture.Root -Registry $registry -SourceIdentity $fixture.SourceIdentity
        $resumed.Record.outcomes[0].outcome | Should -Be 'retired'
        Test-Path -LiteralPath $fixture.FirstPath | Should -BeFalse
        Test-Path -LiteralPath $fixture.SecondPath | Should -BeFalse
        Test-Path -LiteralPath $fixture.ReceiptPath | Should -BeFalse
        (Read-PluginRetirementState -RepoRoot $fixture.Root -PluginName 'removal-fixture').status |
            Should -Be 'retired'
    }

    It 'test:PluginRetirement.ReconciliationStateMatrix previews first, applies an exact preview, and emits one bounded aggregate' {
        $fixture = New-RemovalFixture
        $registry = New-SyntheticRetirementRegistry -Fixture $fixture

        $preview = Invoke-PluginRetirementReconciliation -RepoRoot $fixture.Root -Registry $registry -SourceIdentity $fixture.SourceIdentity
        $preview.ExitCode | Should -Be 0
        @($preview.Record.outcomes).Count | Should -Be 1
        $preview.Record.outcomes[0].outcome | Should -Be 'preview'
        $preview.Record.emittedPaths | Should -Be 2
        Test-Path -LiteralPath $fixture.FirstPath | Should -BeTrue
        Test-Path -LiteralPath $fixture.SecondPath | Should -BeTrue
        @((Read-PluginRetirementState -RepoRoot $fixture.Root -PluginName 'removal-fixture').affectedFiles).Count |
            Should -Be 2
        $emitted = @(Write-PluginRetirementRecord -Result $preview)
        $emitted.Count | Should -Be 1
        $emitted[0] | Should -Match '^RETIREMENT: \{'

        $applied = Invoke-PluginRetirementReconciliation -RepoRoot $fixture.Root -Registry $registry -SourceIdentity $fixture.SourceIdentity
        $applied.Record.outcomes[0].outcome | Should -Be 'retired'
        Test-Path -LiteralPath $fixture.FirstPath | Should -BeFalse
        Test-Path -LiteralPath $fixture.SecondPath | Should -BeFalse
        Test-Path -LiteralPath $fixture.ReceiptPath | Should -BeFalse
        (Read-PluginRetirementState -RepoRoot $fixture.Root -PluginName 'removal-fixture').status |
            Should -Be 'retired'
    }

    It 'test:PluginRetirement.ReconciliationStateMatrix refreshes stale automatic previews but explicit stale apply fails without deletion' {
        $fixture = New-RemovalFixture
        $registry = New-SyntheticRetirementRegistry -Fixture $fixture
        [void](Invoke-PluginRetirementReconciliation -RepoRoot $fixture.Root -Registry $registry -SourceIdentity $fixture.SourceIdentity)

        Set-Content -LiteralPath $fixture.FirstPath -Value 'changed-after-preview' -NoNewline -Encoding utf8
        $explicit = Invoke-PluginRetirementReconciliation -RepoRoot $fixture.Root -Registry $registry -SourceIdentity $fixture.SourceIdentity -ApplyRetirements
        $explicit.ExitCode | Should -Be 21
        $explicit.Record.outcomes[0].outcome | Should -Be 'failed'
        Test-Path -LiteralPath $fixture.FirstPath | Should -BeTrue
        Test-Path -LiteralPath $fixture.SecondPath | Should -BeTrue

        $automatic = Invoke-PluginRetirementReconciliation -RepoRoot $fixture.Root -Registry $registry -SourceIdentity $fixture.SourceIdentity
        $automatic.Record.outcomes[0].outcome | Should -Be 'preview'
        $automatic.Record.outcomes[0].remedy | Should -Match 'zero deletion'
        Test-Path -LiteralPath $fixture.FirstPath | Should -BeTrue
        Test-Path -LiteralPath $fixture.SecondPath | Should -BeTrue
        (Read-PluginRetirementState -RepoRoot $fixture.Root -PluginName 'removal-fixture').affectedFiles[0].observedSha256 |
            Should -Be (Get-FileSha256 -Path $fixture.FirstPath)
    }

    It 'test:PluginRetirement.ReconciliationStateMatrix preserves residue and covers the closed outcome table' {
        $fixture = New-RemovalFixture -ModifySecond
        $registry = New-SyntheticRetirementRegistry -Fixture $fixture
        [void](Invoke-PluginRetirementReconciliation -RepoRoot $fixture.Root -Registry $registry -SourceIdentity $fixture.SourceIdentity)
        $result = Invoke-PluginRetirementReconciliation -RepoRoot $fixture.Root -Registry $registry -SourceIdentity $fixture.SourceIdentity
        $result.Record.outcomes[0].outcome | Should -Be 'residue'
        Test-Path -LiteralPath $fixture.FirstPath | Should -BeFalse
        Test-Path -LiteralPath $fixture.SecondPath | Should -BeTrue
        $remaining = Read-PluginReceipt -RepoRoot $fixture.Root -PluginName 'removal-fixture'
        $remaining.degraded | Should -BeTrue
        $remaining.files[0].outcome | Should -Be 'skipped-modified'
        Mock Get-FileSha256 { throw 'Terminal residue replay must not hash.' }
        $replay = Invoke-PluginRetirementReconciliation -RepoRoot $fixture.Root -Registry $registry -SourceIdentity $fixture.SourceIdentity
        $replay.Record.outcomes[0].outcome | Should -Be 'residue'
        (Read-PluginRetirementState -RepoRoot $fixture.Root -PluginName 'removal-fixture').status |
            Should -Be 'residue'

        $protocol = Get-Content -LiteralPath (Join-Path $script:repoRoot 'docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/assets/decisions/retirement-protocol.md') -Raw
        $outcomes = @(Get-PluginRetirementOutcomeName)
        $outcomes.Count | Should -Be 8
        foreach ($outcome in $outcomes) {
            $protocol | Should -Match ([regex]::Escape("| ``$outcome`` |"))
        }
    }

    It 'test:PluginRetirement.ReconciliationStateMatrix distinguishes foreign, manual, no-match, and failed outcomes' {
        $foreign = New-RemovalFixture
        $foreignReceipt = Read-JsonFile -Path $foreign.ReceiptPath
        $foreignReceipt.sourceIdentity = New-PluginSourceIdentity -Repository 'example/foreign'
        Write-JsonFileStable -Path $foreign.ReceiptPath -InputObject $foreignReceipt
        $foreignRegistry = New-SyntheticRetirementRegistry -Fixture $foreign
        $foreignResult = Invoke-PluginRetirementReconciliation -RepoRoot $foreign.Root -Registry $foreignRegistry -SourceIdentity $foreign.SourceIdentity
        $foreignResult.Record.outcomes[0].outcome | Should -Be 'foreign-source'

        $manual = New-RemovalFixture
        $manualPath = Join-Path $manual.Root 'docs/manual-residue.txt'
        [void](New-Item -ItemType Directory -Path (Split-Path -Parent $manualPath) -Force)
        Set-Content -LiteralPath $manualPath -Value 'manual' -NoNewline -Encoding utf8
        $manualRegistry = New-SyntheticRetirementRegistry -Fixture $manual -Version '9.9.9' -ManualResidue @(
            [pscustomobject][ordered]@{
                kind = 'scaffold'
                path = 'docs/manual-residue.txt'
                remedy = 'Remove after review.'
            }
        )
        $manualResult = Invoke-PluginRetirementReconciliation -RepoRoot $manual.Root -Registry $manualRegistry -SourceIdentity $manual.SourceIdentity
        $manualResult.Record.outcomes[0].outcome | Should -Be 'manual-required'
        $manualResult.Record.outcomes[0].paths[0].present | Should -BeTrue
        $manualState = Read-PluginRetirementState -RepoRoot $manual.Root -PluginName 'removal-fixture'
        $manualState.terminalOutcome | Should -Be 'manual-required'
        @($manualState.manualResidue).Count | Should -Be 1
        $manualReplay = Invoke-PluginRetirementReconciliation -RepoRoot $manual.Root -Registry $manualRegistry -SourceIdentity $manual.SourceIdentity
        $manualReplay.Record.outcomes[0].outcome | Should -Be 'manual-required'

        $missing = New-RemovalFixture
        Remove-Item -LiteralPath $missing.ReceiptPath -Force
        $missingRegistry = New-SyntheticRetirementRegistry -Fixture $missing
        $direct = Invoke-PluginRetirementReconciliation -RepoRoot $missing.Root -Registry $missingRegistry -SourceIdentity $missing.SourceIdentity -DirectTarget 'removal-fixture'
        $direct.ExitCode | Should -Be 20
        $direct.Record.outcomes[0].outcome | Should -Be 'no-match'

        $applyMissingPreview = New-RemovalFixture
        $applyRegistry = New-SyntheticRetirementRegistry -Fixture $applyMissingPreview
        $failed = Invoke-PluginRetirementReconciliation -RepoRoot $applyMissingPreview.Root -Registry $applyRegistry -SourceIdentity $applyMissingPreview.SourceIdentity -ApplyRetirements
        $failed.ExitCode | Should -Be 21
        $failed.Record.outcomes[0].outcome | Should -Be 'failed'
        Test-Path -LiteralPath $applyMissingPreview.FirstPath | Should -BeTrue
    }

    It 'test:PluginRetirement.ReconciliationStateMatrix closes an applying state after committed clean removal' {
        $fixture = New-RemovalFixture
        $registry = New-SyntheticRetirementRegistry -Fixture $fixture
        [void](Invoke-PluginRetirementReconciliation -RepoRoot $fixture.Root -Registry $registry -SourceIdentity $fixture.SourceIdentity)
        $state = Read-PluginRetirementState -RepoRoot $fixture.Root -PluginName 'removal-fixture'
        $state.status = 'applying'
        [void](Write-PluginRetirementState -RepoRoot $fixture.Root -State $state)
        Remove-Item -LiteralPath $fixture.FirstPath -Force
        Remove-Item -LiteralPath $fixture.SecondPath -Force
        Remove-Item -LiteralPath $fixture.ReceiptPath -Force

        $recovered = Invoke-PluginRetirementReconciliation -RepoRoot $fixture.Root -Registry $registry -SourceIdentity $fixture.SourceIdentity
        $recovered.Record.outcomes[0].outcome | Should -Be 'retired'
        $terminal = Read-PluginRetirementState -RepoRoot $fixture.Root -PluginName 'removal-fixture'
        $terminal.status | Should -Be 'retired'
        $terminal.terminalOutcome | Should -Be 'retired'
        @($terminal.affectedFiles | Where-Object { [string]$_.outcome -eq 'removed' }).Count |
            Should -Be 2
    }

    It 'test:PluginRetirement.ReconciliationStateMatrix enforces global plugin/path caps and fair terminal replay without hashing' {
        $fixture = New-RemovalFixture
        $tombstones = @()
        for ($pluginIndex = 0; $pluginIndex -lt 10; $pluginIndex++) {
            $name = "retired-$pluginIndex"
            $files = @()
            for ($pathIndex = 0; $pathIndex -lt 10; $pathIndex++) {
                $files += , [pscustomobject][ordered]@{
                    dest = "skills/$name/file-$pathIndex.txt"
                    sha256 = 'a' * 64
                }
            }
            $registry = New-SyntheticRetirementRegistry -Fixture $fixture -Name $name -Files $files
            $tombstone = $registry.retiredPlugins[0]
            $tombstones += , $tombstone
            $state = [pscustomobject][ordered]@{
                schemaVersion = 1
                name = $name
                status = 'residue'
                transactionId = 'b' * 32
                updatedAt = '2026-08-15T00:00:00Z'
                tombstoneSha256 = Get-StableJsonSha256 -InputObject $tombstone
                prior = [pscustomobject][ordered]@{
                    sourceIdentity = $fixture.SourceIdentity
                    ref = 'd' * 40
                    version = '1.2.3'
                }
                affectedFiles = @($files | ForEach-Object {
                        [pscustomobject][ordered]@{
                            dest = [string]$_.dest
                            expectedSha256 = [string]$_.sha256
                            observedSha256 = 'c' * 64
                            outcome = 'residue'
                        }
                    })
                remedy = 'Review terminal residue.'
            }
            [void](Write-PluginRetirementState -RepoRoot $fixture.Root -State $state)
        }
        $registry = [pscustomobject]@{ plugins = @(); retiredPlugins = $tombstones }

        Mock Get-FileSha256 { throw 'Terminal replay must not hash.' }
        $first = Invoke-PluginRetirementReconciliation -RepoRoot $fixture.Root -Registry $registry -SourceIdentity $fixture.SourceIdentity
        $first.Record.processedPlugins | Should -Be 8
        $first.Record.emittedPaths | Should -Be 64
        @($first.Record.outcomes).Count | Should -Be 8

        $second = Invoke-PluginRetirementReconciliation -RepoRoot $fixture.Root -Registry $registry -SourceIdentity $fixture.SourceIdentity
        $second.Record.processedPlugins | Should -Be 8
        @($second.Record.outcomes.name) | Should -Contain 'retired-8'
        @($second.Record.outcomes.name) | Should -Contain 'retired-9'
        $cursor = Read-JsonFile -Path (Get-PluginRetirementCursorPath -RepoRoot $fixture.Root)
        [int]$cursor.nextIndex | Should -Be 6

        $third = Invoke-PluginRetirementReconciliation -RepoRoot $fixture.Root -Registry $registry -SourceIdentity $fixture.SourceIdentity
        $retiredSix = @($third.Record.outcomes | Where-Object { [string]$_.name -eq 'retired-6' })[0]
        @($retiredSix.paths.path) | Should -Contain '.github/skills/retired-6/file-4.txt'
    }
}
