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
}
