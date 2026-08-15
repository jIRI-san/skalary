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

        . (Join-Path $script:repoRoot 'scripts/skalary/_Common.ps1')
    }

    AfterAll {
        foreach ($root in $script:tempRoots) {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:PluginRetirement.RegistryContract ships an empty valid canonical catalog into skalary registry only' {
        $canonicalPath = Join-Path $script:repoRoot 'registry-retirements.json'
        $canonicalRaw = Get-Content -LiteralPath $canonicalPath -Raw
        $canonicalRaw | Test-Json -SchemaFile $script:retirementSchema | Should -BeTrue
        $canonical = $canonicalRaw | ConvertFrom-Json -Depth 100
        @($canonical.retiredPlugins).Count | Should -Be 0

        $registry = Get-Content -LiteralPath (Join-Path $script:repoRoot 'registry.json') -Raw | ConvertFrom-Json -Depth 100
        @($registry.retiredPlugins).Count | Should -Be 0
        $marketplace = Get-Content -LiteralPath (Join-Path $script:repoRoot '.github/plugin/marketplace.json') -Raw |
            ConvertFrom-Json -Depth 100
        $marketplace.PSObject.Properties.Name | Should -Not -Contain 'retiredPlugins'
    }

    It 'test:PluginCatalog.GeneratedArtifacts keeps generated catalogs aligned with retirement sources' {
        $canonical = Get-Content -LiteralPath (Join-Path $script:repoRoot 'registry-retirements.json') -Raw |
            ConvertFrom-Json -Depth 100
        $registry = Get-Content -LiteralPath (Join-Path $script:repoRoot 'registry.json') -Raw |
            ConvertFrom-Json -Depth 100
        (@($registry.retiredPlugins) | ConvertTo-Json -Depth 100 -Compress) |
            Should -Be (@($canonical.retiredPlugins) | ConvertTo-Json -Depth 100 -Compress)

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
                ConvertFrom-Json).retiredPlugins).Count | Should -Be 0
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
                    source = "remote:https://x-access-token:$secret@github.com/jIRI-san/skalary.git"
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
}
