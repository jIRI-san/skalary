#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'architecture-tests structural evals' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..')).Path
        Import-Module (Join-Path $script:repoRoot 'tests/evals/EvalCommon.psm1') -Force

        $script:pluginRoot = Join-Path $script:repoRoot 'plugins/architecture-tests'
        $script:manifestPath = Join-Path $script:pluginRoot 'plugin.json'
        $script:manifest = Get-Content -LiteralPath $script:manifestPath -Raw | ConvertFrom-Json -Depth 50

        $skillEntries = @($script:manifest.files | Where-Object { [string]$_.src -eq 'skills/architecture-tests/SKILL.md' })
        $skillEntries.Count | Should -Be 1
        $script:skillEntry = $skillEntries[0]
        $script:skillPath = Join-Path $script:pluginRoot 'skills/architecture-tests/SKILL.md'
        $script:skillDest = [string]$script:skillEntry.dest

        $script:runnerCanonical = Join-Path $script:repoRoot 'scripts/skalary/Invoke-ArchTests.ps1'
        $script:runnerBundled = Join-Path $script:pluginRoot 'skills/architecture-tests/scripts/Invoke-ArchTests.ps1'
        $script:receiptSchema = Join-Path $script:pluginRoot 'skills/architecture-tests/assets/schemas/arch-test-receipt.schema.json'
        $script:configSchema = Join-Path $script:pluginRoot 'skills/architecture-tests/assets/schemas/arch-test-config.schema.json'

        # Dot-source the runner for its functions (main is guarded against dot-source).
        . $script:runnerCanonical
    }

    It 'PluginManifest-ArchTests: manifest declares required identity and every file entry exists' {
        [string]$script:manifest.name | Should -Be 'architecture-tests'
        [string]$script:manifest.version | Should -Match '^\d+\.\d+\.\d+'
        [string]$script:manifest.description | Should -Not -BeNullOrEmpty
        @($script:manifest.files).Count | Should -BeGreaterThan 0

        foreach ($entry in @($script:manifest.files)) {
            $resolved = Test-ReferencedFile -BasePath $script:pluginRoot -RelativePath ([string]$entry.src)
            Test-Path -LiteralPath $resolved -PathType Leaf | Should -BeTrue
        }
    }

    It 'PluginManifest-ArchTests: manifest validates against schemas/plugin.schema.json' {
        $schemaPath = Join-Path $script:repoRoot 'schemas/plugin.schema.json'
        Test-Path -LiteralPath $schemaPath -PathType Leaf | Should -BeTrue
        $manifestRaw = Get-Content -LiteralPath $script:manifestPath -Raw
        { $manifestRaw | Test-Json -SchemaFile $schemaPath } | Should -Not -Throw
        $manifestRaw | Test-Json -SchemaFile $schemaPath | Should -BeTrue
    }

    It 'PluginManifest-ArchTests: skill artifact has valid frontmatter and body structure' {
        Get-ArtifactType -DestinationPath $script:skillDest | Should -Be 'skill'
        $frontmatter = Get-PluginFrontmatter -Path $script:skillPath
        Test-RequiredFrontmatter -ArtifactType 'skill' -Frontmatter $frontmatter -Path $script:skillPath | Should -BeTrue
        [string]$frontmatter.name | Should -Be 'architecture-tests'
        Test-BodySection -ArtifactType 'skill' -Path $script:skillPath | Should -BeTrue
    }

    It 'Runner-CanonicalSourceBundled: canonical runner exists, bundled copy is byte-identical, no plugin-local second source' {
        Test-Path -LiteralPath $script:runnerCanonical -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $script:runnerBundled -PathType Leaf | Should -BeTrue

        $canonicalHash = (Get-FileHash -LiteralPath $script:runnerCanonical -Algorithm SHA256).Hash
        $bundledHash = (Get-FileHash -LiteralPath $script:runnerBundled -Algorithm SHA256).Hash
        $bundledHash | Should -Be $canonicalHash

        # There must be exactly one authored source of truth: the plugin must NOT carry its own
        # authored copy under plugins/architecture-tests/scripts/ that the drift gate cannot cover.
        $pluginLocal = Join-Path $script:pluginRoot 'scripts/Invoke-ArchTests.ps1'
        Test-Path -LiteralPath $pluginLocal -PathType Leaf | Should -BeFalse

        # REQ-17: the runner records a parent commit (file-level contains-check).
        (Get-Content -LiteralPath $script:runnerCanonical -Raw) | Should -Match 'commit'
    }

    It 'Receipt-BoundToContractAndTreeHash: receipt binds contractId + 64-hex sourcesHash + 40-hex parentCommit; editing a source changes the hash' {
        $srcDir = Join-Path $TestDrive 'srcA'
        [void](New-Item -ItemType Directory -Path $srcDir -Force)
        $f = Join-Path $srcDir 'component.cs'
        Set-Content -LiteralPath $f -Value 'namespace A { class C {} }' -NoNewline

        $h1 = Get-ArchTestSourcesHash -Paths @('srcA') -RepoRoot $TestDrive
        $h1.Digest | Should -Match '^[0-9a-f]{64}$'
        $h1.Count | Should -Be 1

        $receipt = New-ArchTestReceipt -ContractId 'ARCH-Sample-1' -Maturity 'draft' -Adapter 'netarchtest' `
            -Verdict 'skip-absent-toolchain' -Ran $false -ParentCommit ('a' * 40) -SourcesHash $h1.Digest
        $receipt.contractId | Should -Be 'ARCH-Sample-1'
        $receipt.sourcesHash | Should -Match '^[0-9a-f]{64}$'
        $receipt.parentCommit | Should -Match '^[a-f0-9]{40}$'

        $json = $receipt | ConvertTo-Json -Depth 12
        { $json | Test-Json -SchemaFile $script:receiptSchema } | Should -Not -Throw
        $json | Test-Json -SchemaFile $script:receiptSchema | Should -BeTrue

        # Edit the source -> the freshness-bound hash must change.
        Set-Content -LiteralPath $f -Value 'namespace A { class C { int x; } }' -NoNewline
        $h2 = Get-ArchTestSourcesHash -Paths @('srcA') -RepoRoot $TestDrive
        $h2.Digest | Should -Not -Be $h1.Digest
    }

    It 'Receipt-FailureTaxonomy: schema accepts the four verdicts, rejects unknown; gate mapping honours maturity' {
        foreach ($verdict in @('pass', 'fail', 'skip-absent-toolchain', 'error')) {
            $ranForVerdict = ($verdict -eq 'pass')
            $r = New-ArchTestReceipt -ContractId 'ARCH-Tax-1' -Maturity 'draft' -Adapter 'netarchtest' `
                -Verdict $verdict -Ran $ranForVerdict -ParentCommit ('b' * 40) -SourcesHash ('c' * 64)
            $rjson = $r | ConvertTo-Json -Depth 12
            $rjson | Test-Json -SchemaFile $script:receiptSchema | Should -BeTrue
        }

        $bad = @{
            schemaVersion = '1'; contractId = 'ARCH-Tax-1'; maturity = 'draft'; adapter = 'netarchtest'
            verdict = 'flaky'; ran = $false; parentCommit = ('b' * 40); sourcesHash = ('c' * 64)
            generatedAt = '2026-01-01T00:00:00Z'
        } | ConvertTo-Json -Depth 12
        $bad | Test-Json -SchemaFile $script:receiptSchema -ErrorAction SilentlyContinue | Should -BeFalse

        # Locked: only a real pass greens; everything else blocks.
        Get-ArchGateOutcome -Maturity 'locked' -Verdict 'pass' -Ran $true | Should -Be 'pass'
        Get-ArchGateOutcome -Maturity 'locked' -Verdict 'fail' -Ran $false | Should -Be 'block'
        Get-ArchGateOutcome -Maturity 'locked' -Verdict 'error' -Ran $true | Should -Be 'block'
        # Draft/provisional: non-pass warns.
        Get-ArchGateOutcome -Maturity 'draft' -Verdict 'fail' -Ran $false | Should -Be 'warn'
        Get-ArchGateOutcome -Maturity 'provisional' -Verdict 'error' -Ran $true | Should -Be 'warn'
        Get-ArchGateOutcome -Maturity 'draft' -Verdict 'pass' -Ran $true | Should -Be 'pass'
    }

    It 'Receipt-PassRequiresRan: a pass that did not run is refused and never greens a locked gate' {
        # New-ArchTestReceipt refuses to mint a false-green.
        { New-ArchTestReceipt -ContractId 'ARCH-Pass-1' -Maturity 'locked' -Adapter 'netarchtest' `
                -Verdict 'pass' -Ran $false -ParentCommit ('a' * 40) -SourcesHash ('c' * 64) } | Should -Throw

        # The gate refuses to green a pass with ran=false.
        Get-ArchGateOutcome -Maturity 'locked' -Verdict 'pass' -Ran $false | Should -Be 'block'
        Get-ArchGateOutcome -Maturity 'draft' -Verdict 'pass' -Ran $false | Should -Be 'warn'

        # The schema also rejects verdict=pass with ran=false.
        $bad = @{
            schemaVersion = '1'; contractId = 'ARCH-Pass-1'; maturity = 'locked'; adapter = 'netarchtest'
            verdict = 'pass'; ran = $false; parentCommit = ('a' * 40); sourcesHash = ('c' * 64)
            generatedAt = '2026-01-01T00:00:00Z'
        } | ConvertTo-Json -Depth 12
        $bad | Test-Json -SchemaFile $script:receiptSchema -ErrorAction SilentlyContinue | Should -BeFalse
    }

    It 'Receipt-ParentCommitAcceptsSha256: parent commit accepts both 40-hex and 64-hex OIDs' {
        $r40 = New-ArchTestReceipt -ContractId 'ARCH-Oid-1' -Maturity 'draft' -Adapter 'netarchtest' `
            -Verdict 'skip-absent-toolchain' -Ran $false -ParentCommit ('a' * 40) -SourcesHash ('c' * 64)
        ($r40 | ConvertTo-Json -Depth 12) | Test-Json -SchemaFile $script:receiptSchema | Should -BeTrue

        $r64 = New-ArchTestReceipt -ContractId 'ARCH-Oid-1' -Maturity 'draft' -Adapter 'netarchtest' `
            -Verdict 'skip-absent-toolchain' -Ran $false -ParentCommit ('a' * 64) -SourcesHash ('c' * 64)
        ($r64 | ConvertTo-Json -Depth 12) | Test-Json -SchemaFile $script:receiptSchema | Should -BeTrue
    }

    It 'Receipt-SkipIsNotPass: a locked contract with skip-absent-toolchain blocks, never greens' {
        Get-ArchGateOutcome -Maturity 'locked' -Verdict 'skip-absent-toolchain' -Ran $false | Should -Be 'block'
        Get-ArchGateOutcome -Maturity 'locked' -Verdict 'skip-absent-toolchain' -Ran $false | Should -Not -Be 'pass'
        # Advisory maturities still only warn on skip.
        Get-ArchGateOutcome -Maturity 'draft' -Verdict 'skip-absent-toolchain' -Ran $false | Should -Be 'warn'
    }

    It 'Hash-BindingInvalidatesReceipt: repointing the adapter changes sourcesHash even with identical targets' {
        $srcDir = Join-Path $TestDrive 'srcBind'
        [void](New-Item -ItemType Directory -Path $srcDir -Force)
        Set-Content -LiteralPath (Join-Path $srcDir 'a.cs') -Value 'class A {}' -NoNewline

        $checkA = [pscustomobject]@{ contractId = 'ARCH-Bind-1'; adapter = 'netarchtest'; targets = @('srcBind') }
        $checkB = [pscustomobject]@{ contractId = 'ARCH-Bind-1'; adapter = 'ts-arch'; targets = @('srcBind') }

        $bindA = Get-ArchTestCheckBinding -Check $checkA -Maturity 'locked'
        $bindB = Get-ArchTestCheckBinding -Check $checkB -Maturity 'locked'

        $hA = Get-ArchTestSourcesHash -Paths @('srcBind') -RepoRoot $TestDrive -ExtraContent @{ ("$([char]0)binding") = $bindA }
        $hB = Get-ArchTestSourcesHash -Paths @('srcBind') -RepoRoot $TestDrive -ExtraContent @{ ("$([char]0)binding") = $bindB }
        $hA.Digest | Should -Not -Be $hB.Digest
    }

    It 'Receipt-SurvivesOwnCommit: sourcesHash is stable when the receipt file itself is added to the tree' {
        $srcDir = Join-Path $TestDrive 'srcB'
        [void](New-Item -ItemType Directory -Path $srcDir -Force)
        Set-Content -LiteralPath (Join-Path $srcDir 'a.cs') -Value 'class A {}' -NoNewline

        $before = Get-ArchTestSourcesHash -Paths @('srcB') -RepoRoot $TestDrive

        # Simulate committing the receipt beside evidence: a receipt file lands OUTSIDE the target set.
        $receiptDir = Join-Path $TestDrive 'docs/architecture-notes/receipts'
        [void](New-Item -ItemType Directory -Path $receiptDir -Force)
        Set-Content -LiteralPath (Join-Path $receiptDir 'ARCH-Sample-1.arch-receipt.json') -Value '{"schemaVersion":"1"}' -NoNewline

        $after = Get-ArchTestSourcesHash -Paths @('srcB') -RepoRoot $TestDrive
        $after.Digest | Should -Be $before.Digest
    }

    It 'ConfigSchema-Valid: config schema parses, enforces per-adapter requirements and maturity enum' {
        Test-Path -LiteralPath $script:configSchema -PathType Leaf | Should -BeTrue
        $cfg = @{
            version = '1'
            checks  = @(
                @{ contractId = 'ARCH-Sample-1'; adapter = 'netarchtest'; maturity = 'locked'; testProject = 'tests/Arch.csproj'; targets = @('src/Domain') }
            )
        } | ConvertTo-Json -Depth 10
        { $cfg | Test-Json -SchemaFile $script:configSchema } | Should -Not -Throw
        $cfg | Test-Json -SchemaFile $script:configSchema | Should -BeTrue

        $badAdapter = @{
            version = '1'
            checks  = @(@{ contractId = 'ARCH-Sample-1'; adapter = 'made-up' })
        } | ConvertTo-Json -Depth 10
        $badAdapter | Test-Json -SchemaFile $script:configSchema -ErrorAction SilentlyContinue | Should -BeFalse

        # Deterministic adapter without testProject/spec is rejected.
        $noSpec = @{
            version = '1'
            checks  = @(@{ contractId = 'ARCH-Sample-1'; adapter = 'netarchtest'; targets = @('src/Domain') })
        } | ConvertTo-Json -Depth 10
        $noSpec | Test-Json -SchemaFile $script:configSchema -ErrorAction SilentlyContinue | Should -BeFalse

        # semantic-eval without provider is rejected.
        $noProvider = @{
            version = '1'
            checks  = @(@{ contractId = 'ARCH-Sample-1'; adapter = 'semantic-eval'; targets = @('src/Domain') })
        } | ConvertTo-Json -Depth 10
        $noProvider | Test-Json -SchemaFile $script:configSchema -ErrorAction SilentlyContinue | Should -BeFalse

        # Out-of-enum maturity is rejected.
        $badMaturity = @{
            version = '1'
            checks  = @(@{ contractId = 'ARCH-Sample-1'; adapter = 'netarchtest'; maturity = 'frozen'; spec = 'a.spec' })
        } | ConvertTo-Json -Depth 10
        $badMaturity | Test-Json -SchemaFile $script:configSchema -ErrorAction SilentlyContinue | Should -BeFalse
    }

    It 'Runner-EndToEnd: a locked check with no adapter blocks, writes a schema-valid receipt, and is HEAD-independent' {
        # A throwaway git repo so Resolve-ArchTestParentCommit works and we can move HEAD.
        $repo = Join-Path $TestDrive 'e2e'
        [void](New-Item -ItemType Directory -Path $repo -Force)
        Push-Location $repo
        try {
            git init -q 2>&1 | Out-Null
            git config user.email 'a@b.c' 2>&1 | Out-Null
            git config user.name 'Test' 2>&1 | Out-Null

            $srcDir = Join-Path $repo 'src'
            [void](New-Item -ItemType Directory -Path $srcDir -Force)
            Set-Content -LiteralPath (Join-Path $srcDir 'a.cs') -Value 'class A {}' -NoNewline
            $contract = Join-Path $repo 'contract.json'
            Set-Content -LiteralPath $contract -Value '{"id":"ARCH-E2E-1"}' -NoNewline

            $cfgObj = @{ version = '1'; checks = @(@{ contractId = 'ARCH-E2E-1'; adapter = 'netarchtest'; maturity = 'locked'; contractPath = 'contract.json'; testProject = 'tests/Arch.csproj'; targets = @('src') }) }
            $cfgPath = Join-Path $repo 'arch-test-config.json'
            Set-Content -LiteralPath $cfgPath -Value ($cfgObj | ConvertTo-Json -Depth 8)

            git add -A 2>&1 | Out-Null
            git commit -q -m 'initial' 2>&1 | Out-Null

            $receiptDir = Join-Path $repo 'receipts'
            $summary = Invoke-ArchTests -ConfigPath $cfgPath -RepoRoot $repo -ReceiptDir $receiptDir

            # Locked + skip-absent-toolchain must block, never green.
            $summary.Blocked | Should -Be 1
            $summary.Passed | Should -Be 0
            $summary.Checks[0].Verdict | Should -Be 'skip-absent-toolchain'
            $summary.Checks[0].Outcome | Should -Be 'block'

            $receiptPath = Join-Path $receiptDir 'ARCH-E2E-1.arch-receipt.json'
            Test-Path -LiteralPath $receiptPath -PathType Leaf | Should -BeTrue
            $receiptRaw = Get-Content -LiteralPath $receiptPath -Raw
            $receiptRaw | Test-Json -SchemaFile $script:receiptSchema | Should -BeTrue
            $hashBefore = ($receiptRaw | ConvertFrom-Json).sourcesHash

            # Move HEAD without touching any source -> freshness (sourcesHash) is unchanged.
            Set-Content -LiteralPath (Join-Path $repo 'unrelated.txt') -Value 'x' -NoNewline
            git add -A 2>&1 | Out-Null
            git commit -q -m 'unrelated' 2>&1 | Out-Null

            $summary2 = Invoke-ArchTests -ConfigPath $cfgPath -RepoRoot $repo -ReceiptDir $receiptDir
            $summary2.Checks[0].SourcesHash | Should -Be $hashBefore
        }
        finally {
            Pop-Location
        }
    }
}
