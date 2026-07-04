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

    It 'Runner-EndToEnd: a locked check whose reviewed body is missing is lock-invalidated (blocks), writes a schema-valid receipt, and is HEAD-independent' {
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
            Set-Content -LiteralPath $contract -Value '{"id":"ARCH-E2E-1","maturity":"locked"}' -NoNewline

            $cfgObj = @{ version = '1'; checks = @(@{ contractId = 'ARCH-E2E-1'; adapter = 'netarchtest'; maturity = 'locked'; contractPath = 'contract.json'; testProject = 'tests/Arch.csproj'; targets = @('src') }) }
            $cfgPath = Join-Path $repo 'arch-test-config.json'
            Set-Content -LiteralPath $cfgPath -Value ($cfgObj | ConvertTo-Json -Depth 8)

            git add -A 2>&1 | Out-Null
            git commit -q -m 'initial' 2>&1 | Out-Null

            $receiptDir = Join-Path $repo 'receipts'
            $summary = Invoke-ArchTests -ConfigPath $cfgPath -RepoRoot $repo -ReceiptDir $receiptDir

            # Locked with a missing reviewed body -> lock-invalidated -> error -> block, never green.
            $summary.Blocked | Should -Be 1
            $summary.Passed | Should -Be 0
            $summary.Checks[0].Verdict | Should -Be 'error'
            $summary.Checks[0].Outcome | Should -Be 'block'

            $receiptPath = Join-Path $receiptDir 'ARCH-E2E-1.arch-receipt.json'
            Test-Path -LiteralPath $receiptPath -PathType Leaf | Should -BeTrue
            $receiptRaw = Get-Content -LiteralPath $receiptPath -Raw
            $receiptRaw | Test-Json -SchemaFile $script:receiptSchema | Should -BeTrue
            $receiptObj = $receiptRaw | ConvertFrom-Json
            $receiptObj.lockDecision | Should -Be 'lock-invalidated'
            $hashBefore = $receiptObj.sourcesHash

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

    Context 'lock-before-execute gate (REQ-18) and pluggable adapters (REQ-9)' {
        BeforeAll {
            $script:netArchAdapter = Join-Path $script:pluginRoot 'scripts/adapters/NetArchTest.Adapter.ps1'
            $script:netArchFixture = Join-Path $script:pluginRoot 'evals/fixtures/netarchtest'
        }

        It 'Lockgate-BodyHashCanonicalComputeVerify: one canonical body hash, deterministic and add/edit/delete-sensitive' {
            $root = Join-Path $TestDrive 'bh'
            [void](New-Item -ItemType Directory -Path $root -Force)
            $body = Join-Path $root 'Body.cs'
            Set-Content -LiteralPath $body -Value 'namespace X { class Y {} }' -NoNewline

            $h1 = Get-ArchLockedBodyHash -Paths @($body) -RepoRoot $root
            $h2 = Get-ArchLockedBodyHash -Paths @($body) -RepoRoot $root
            $h1 | Should -Match '^[0-9a-f]{64}$'
            $h2 | Should -Be $h1

            Set-Content -LiteralPath $body -Value 'namespace X { class Z {} }' -NoNewline
            (Get-ArchLockedBodyHash -Paths @($body) -RepoRoot $root) | Should -Not -Be $h1
        }

        It 'Lockgate-DraftBodiesNotExecuted: a draft/provisional contract body is never executed (skip-not-locked)' {
            $root = Join-Path $TestDrive 'draft'
            [void](New-Item -ItemType Directory -Path $root -Force)
            $body = Join-Path $root 'Body.cs'
            Set-Content -LiteralPath $body -Value 'class A {}' -NoNewline

            foreach ($m in @('draft', 'provisional')) {
                $c = [pscustomobject]@{ id = 'ARCH-Draft-1'; maturity = $m }
                $d = Get-ArchLockExecutionDecision -Contract $c -BodyPaths @($body) -RepoRoot $root
                $d.Decision | Should -Be 'skip-not-locked'
            }
        }

        It 'Lockgate-BodyHashVerified: a locked contract executes only when the recomputed body hash matches' {
            $root = Join-Path $TestDrive 'ok'
            [void](New-Item -ItemType Directory -Path $root -Force)
            $body = Join-Path $root 'Body.cs'
            Set-Content -LiteralPath $body -Value 'class A {}' -NoNewline
            $h = Get-ArchLockedBodyHash -Paths @($body) -RepoRoot $root

            $c = [pscustomobject]@{ id = 'ARCH-Ok-1'; maturity = 'locked'; lockedBodySha256 = $h }
            (Get-ArchLockExecutionDecision -Contract $c -BodyPaths @($body) -RepoRoot $root).Decision | Should -Be 'execute'
        }

        It 'Lockgate-MutatedBodyNotExecuted: editing a locked body after lock yields lock-invalidated (not execute)' {
            $root = Join-Path $TestDrive 'mut'
            [void](New-Item -ItemType Directory -Path $root -Force)
            $body = Join-Path $root 'Body.cs'
            Set-Content -LiteralPath $body -Value 'class A {}' -NoNewline
            $h = Get-ArchLockedBodyHash -Paths @($body) -RepoRoot $root
            $c = [pscustomobject]@{ id = 'ARCH-Mut-1'; maturity = 'locked'; lockedBodySha256 = $h }

            # Mutate the reviewed body after locking.
            Set-Content -LiteralPath $body -Value 'class A { int x; }' -NoNewline
            $d = Get-ArchLockExecutionDecision -Contract $c -BodyPaths @($body) -RepoRoot $root
            $d.Decision | Should -Be 'lock-invalidated'
            $d.Decision | Should -Not -Be 'execute'
        }

        It 'Lockgate-LockInvalidatedStateFlagged: lock-invalidated maps to a blocking error and carries a drift finding' {
            $root = Join-Path $TestDrive 'inv'
            [void](New-Item -ItemType Directory -Path $root -Force)
            $body = Join-Path $root 'Body.cs'
            Set-Content -LiteralPath $body -Value 'class A {}' -NoNewline
            # Locked contract whose recorded hash does not match the on-disk body.
            $c = [pscustomobject]@{ id = 'ARCH-Inv-1'; maturity = 'locked'; lockedBodySha256 = ('d' * 64) }

            $res = Invoke-ArchTestAdapter -AdapterName 'netarchtest' -Contract $c -BodyPaths @($body) -RepoRoot $root -AdapterRoot (Join-Path $root 'noadapters')
            $res.decision | Should -Be 'lock-invalidated'
            $res.status | Should -Be 'error'
            $res.ran | Should -BeFalse
            @($res.findings).Count | Should -BeGreaterThan 0
            # A locked error blocks — never a false-green.
            Get-ArchGateOutcome -Maturity 'locked' -Verdict $res.status -Ran $res.ran | Should -Be 'block'
        }

        It 'Lockgate-AutonomousContextDetected: autonomy is a concrete signal (explicit flag or env var), not self-assessment' {
            Test-ArchAutonomousContext -Explicit $true | Should -BeTrue
            Test-ArchAutonomousContext -Explicit $false | Should -BeFalse

            $name = 'SKALARY_ARCH_AUTONOMOUS'
            $old = [System.Environment]::GetEnvironmentVariable($name)
            try {
                [System.Environment]::SetEnvironmentVariable($name, '1')
                Test-ArchAutonomousContext | Should -BeTrue
                [System.Environment]::SetEnvironmentVariable($name, 'false')
                Test-ArchAutonomousContext | Should -BeFalse
                [System.Environment]::SetEnvironmentVariable($name, $null)
                Test-ArchAutonomousContext | Should -BeFalse
            }
            finally {
                [System.Environment]::SetEnvironmentVariable($name, $old)
            }
        }

        It 'Lockgate-WriteGateRefusesLockedWithoutHumanSignal: a locked write is refused in an autonomous context' {
            Test-ArchLockWriteAllowed -Maturity 'locked' -Autonomous $true | Should -BeFalse
            Test-ArchLockWriteAllowed -Maturity 'locked' -Autonomous $false | Should -BeTrue
            # Non-locked writes are always allowed.
            Test-ArchLockWriteAllowed -Maturity 'draft' -Autonomous $true | Should -BeTrue
        }

        It 'Lockgate-AgentCannotSelfPromote: draft->locked in an autonomous context is refused' {
            # No proposal sink -> hard refusal.
            { Assert-ArchLockTransition -ContractId 'ARCH-Promo-1' -FromMaturity 'draft' -ToMaturity 'locked' -Autonomous $true } | Should -Throw

            # Human context -> allowed.
            $ok = Assert-ArchLockTransition -ContractId 'ARCH-Promo-1' -FromMaturity 'draft' -ToMaturity 'locked' -Autonomous $false
            $ok.Allowed | Should -BeTrue
        }

        It 'Lockgate-DemotionIsHumanOnly: locked->draft in an autonomous context is refused' {
            { Assert-ArchLockTransition -ContractId 'ARCH-Demo-1' -FromMaturity 'locked' -ToMaturity 'draft' -Autonomous $true } | Should -Throw
            $ok = Assert-ArchLockTransition -ContractId 'ARCH-Demo-1' -FromMaturity 'locked' -ToMaturity 'draft' -Autonomous $false
            $ok.Allowed | Should -BeTrue
        }

        It 'Lockgate-PromotionProposalRecorded: an autonomous run records a proposal instead of mutating lock state' {
            $proposalDir = Join-Path $TestDrive 'proposals'
            $r = Assert-ArchLockTransition -ContractId 'ARCH-Prop-1' -FromMaturity 'draft' -ToMaturity 'locked' `
                -Autonomous $true -ProposalDir $proposalDir -ComputedBodyHash ('e' * 64)
            $r.Allowed | Should -BeFalse
            $r.Autonomous | Should -BeTrue
            Test-Path -LiteralPath $r.ProposalPath -PathType Leaf | Should -BeTrue

            $proposal = Get-Content -LiteralPath $r.ProposalPath -Raw | ConvertFrom-Json
            $proposal.kind | Should -Be 'arch-promotion-proposal'
            $proposal.contractId | Should -Be 'ARCH-Prop-1'
            $proposal.fromMaturity | Should -Be 'draft'
            $proposal.toMaturity | Should -Be 'locked'
            $proposal.computedBodyHash | Should -Be ('e' * 64)
        }

        It 'Adapter-Interface-Pluggable: the dispatcher routes to any adapter by name without dispatcher changes' {
            $root = Join-Path $TestDrive 'plug'
            [void](New-Item -ItemType Directory -Path $root -Force)
            $adRoot = Join-Path $root 'adapters'
            [void](New-Item -ItemType Directory -Path $adRoot -Force)
            $body = Join-Path $root 'Body.cs'
            Set-Content -LiteralPath $body -Value 'class A {}' -NoNewline
            $h = Get-ArchLockedBodyHash -Paths @($body) -RepoRoot $root

            @'
function Invoke-StubAdapter {
    param([hashtable]$Context)
    [pscustomobject]@{ status = 'pass'; ran = $true; findings = @(); artifacts = @("stub:$($Context.ContractId)") }
}
'@ | Set-Content -LiteralPath (Join-Path $adRoot 'Stub.Adapter.ps1')

            $c = [pscustomobject]@{ id = 'ARCH-Plug-1'; maturity = 'locked'; lockedBodySha256 = $h }
            $res = Invoke-ArchTestAdapter -AdapterName 'Stub' -Contract $c -BodyPaths @($body) -RepoRoot $root -AdapterRoot $adRoot
            $res.status | Should -Be 'pass'
            $res.ran | Should -BeTrue
            $res.decision | Should -Be 'execute'
            @($res.artifacts) | Should -Contain 'stub:ARCH-Plug-1'
        }

        It 'Adapter-EnforcesResultContract: an out-of-taxonomy adapter status is rejected (no false-green)' {
            $root = Join-Path $TestDrive 'bad'
            [void](New-Item -ItemType Directory -Path $root -Force)
            $adRoot = Join-Path $root 'adapters'
            [void](New-Item -ItemType Directory -Path $adRoot -Force)
            $body = Join-Path $root 'Body.cs'
            Set-Content -LiteralPath $body -Value 'class A {}' -NoNewline
            $h = Get-ArchLockedBodyHash -Paths @($body) -RepoRoot $root

            @'
function Invoke-BogusAdapter {
    param([hashtable]$Context)
    [pscustomobject]@{ status = 'green'; ran = $true; findings = @(); artifacts = @() }
}
'@ | Set-Content -LiteralPath (Join-Path $adRoot 'Bogus.Adapter.ps1')

            $c = [pscustomobject]@{ id = 'ARCH-Bad-1'; maturity = 'locked'; lockedBodySha256 = $h }
            { Invoke-ArchTestAdapter -AdapterName 'Bogus' -Contract $c -BodyPaths @($body) -RepoRoot $root -AdapterRoot $adRoot } | Should -Throw
        }

        It 'Adapter-OnlyLockedBodiesExecute: the dispatcher never loads an adapter for a non-locked contract' {
            $root = Join-Path $TestDrive 'onlylocked'
            [void](New-Item -ItemType Directory -Path $root -Force)
            $adRoot = Join-Path $root 'adapters'
            [void](New-Item -ItemType Directory -Path $adRoot -Force)
            $body = Join-Path $root 'Body.cs'
            Set-Content -LiteralPath $body -Value 'class A {}' -NoNewline

            # An adapter that would throw if it were ever invoked.
            @'
function Invoke-BoomAdapter {
    param([hashtable]$Context)
    throw 'adapter must not run for a non-locked contract'
}
'@ | Set-Content -LiteralPath (Join-Path $adRoot 'Boom.Adapter.ps1')

            $c = [pscustomobject]@{ id = 'ARCH-Only-1'; maturity = 'draft' }
            $res = Invoke-ArchTestAdapter -AdapterName 'Boom' -Contract $c -BodyPaths @($body) -RepoRoot $root -AdapterRoot $adRoot
            $res.status | Should -Be 'skip-absent-toolchain'
            $res.ran | Should -BeFalse
            $res.decision | Should -Be 'skip-not-locked'
        }

        It 'Adapter-ParsesResultContract: the NetArchTest adapter parses a TRX into the strict result contract' {
            Test-Path -LiteralPath $script:netArchAdapter -PathType Leaf | Should -BeTrue
            . $script:netArchAdapter

            $trxPass = '<?xml version="1.0"?><TestRun xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010"><Results><UnitTestResult testName="T1" outcome="Passed"/></Results></TestRun>'
            $p = ConvertFrom-NetArchTestTrx -Xml $trxPass
            $p.status | Should -Be 'pass'
            $p.ran | Should -BeTrue

            $trxFail = '<?xml version="1.0"?><TestRun xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010"><Results><UnitTestResult testName="T1" outcome="Passed"/><UnitTestResult testName="T2" outcome="Failed"><Output><ErrorInfo><Message>layer boundary violation</Message></ErrorInfo></Output></UnitTestResult></Results></TestRun>'
            $f = ConvertFrom-NetArchTestTrx -Xml $trxFail
            $f.status | Should -Be 'fail'
            @($f.findings).Count | Should -Be 1
            [string]$f.findings[0].test | Should -Be 'T2'
            [string]$f.findings[0].message | Should -Match 'layer boundary'

            # A locked run that executed zero tests is an error, not a green.
            $trxEmpty = '<?xml version="1.0"?><TestRun xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010"><Results></Results></TestRun>'
            (ConvertFrom-NetArchTestTrx -Xml $trxEmpty).status | Should -Be 'error'

            # Non-Passed/non-Failed terminal outcomes must NEVER be reported as a pass (passing allow-list).
            foreach ($o in @('Error', 'Timeout', 'Aborted', 'NotExecuted', 'Inconclusive')) {
                $trx = "<?xml version=`"1.0`"?><TestRun xmlns=`"http://microsoft.com/schemas/VisualStudio/TeamTest/2010`"><Results><UnitTestResult testName=`"T1`" outcome=`"Passed`"/><UnitTestResult testName=`"T2`" outcome=`"$o`"/></Results></TestRun>"
                $r = ConvertFrom-NetArchTestTrx -Xml $trx
                $r.status | Should -Not -Be 'pass'
                $r.status | Should -Be 'error'
            }
        }

        It 'Adapter-NetArchTest-SkipsWithoutToolchain: absent dotnet yields skip-absent-toolchain, never a fail or false pass' {
            . $script:netArchAdapter
            if (Get-Command dotnet -ErrorAction SilentlyContinue) {
                Set-ItResult -Skipped -Because 'dotnet is present; real-run detection is covered by the 4.3 fixture'
                return
            }
            $ctx = @{ ContractId = 'ARCH-Net-1'; TargetRoot = $TestDrive; RepoRoot = $TestDrive; BodyPaths = @((Join-Path $TestDrive 'Arch.csproj')) }
            $res = Invoke-NetArchTestAdapter -Context $ctx
            $res.status | Should -Be 'skip-absent-toolchain'
            $res.ran | Should -BeFalse
        }

        It 'Adapter-CanonicalCommandDeterministic: the dotnet test command line is pure, deterministic string construction' {
            . $script:netArchAdapter
            $cmd = Get-NetArchTestCommand -TestProject 'tests/Arch.csproj' -TrxPath 'out.trx'
            $cmd[0] | Should -Be 'test'
            $cmd | Should -Contain 'tests/Arch.csproj'
            ($cmd -join ' ') | Should -Match 'trx;LogFileName=out\.trx'
        }

        It 'Adapter-RejectsNonBooleanRan: an adapter returning ran=''false'' (string) is refused, not coerced to a pass' {
            $root = Join-Path $TestDrive 'ranstr'
            [void](New-Item -ItemType Directory -Path $root -Force)
            $adRoot = Join-Path $root 'adapters'
            [void](New-Item -ItemType Directory -Path $adRoot -Force)
            $body = Join-Path $root 'Body.cs'
            Set-Content -LiteralPath $body -Value 'class A {}' -NoNewline
            $h = Get-ArchLockedBodyHash -Paths @($body) -RepoRoot $root

            @'
function Invoke-LiarAdapter {
    param([hashtable]$Context)
    [pscustomobject]@{ status = 'pass'; ran = 'false'; findings = @(); artifacts = @() }
}
'@ | Set-Content -LiteralPath (Join-Path $adRoot 'Liar.Adapter.ps1')

            $c = [pscustomobject]@{ id = 'ARCH-Ran-1'; maturity = 'locked'; lockedBodySha256 = $h }
            { Invoke-ArchTestAdapter -AdapterName 'Liar' -Contract $c -BodyPaths @($body) -RepoRoot $root -AdapterRoot $adRoot } | Should -Throw
        }

        It 'Lockgate-EmptyBodySetInvalidatesLock: a locked contract whose body resolves to zero files is lock-invalidated' {
            $root = Join-Path $TestDrive 'emptybody'
            [void](New-Item -ItemType Directory -Path $root -Force)
            # Recorded hash is the constant empty-input SHA-256; there is no reviewed body on disk.
            $emptyHash = Get-ArchLockedBodyHash -Paths @() -RepoRoot $root
            $c = [pscustomobject]@{ id = 'ARCH-Empty-1'; maturity = 'locked'; lockedBodySha256 = $emptyHash }
            $d = Get-ArchLockExecutionDecision -Contract $c -BodyPaths @((Join-Path $root 'missing')) -RepoRoot $root
            $d.Decision | Should -Be 'lock-invalidated'
            $d.Decision | Should -Not -Be 'execute'
        }

        It 'Lockgate-MutatedCsprojSiblingInvalidatesLock: editing a .cs sibling under a locked csproj body invalidates the lock' {
            # The runner hashes the csproj's DIRECTORY (full source closure), so a .cs edit must break the lock.
            $repo = Join-Path $TestDrive 'csproj'
            $proj = Join-Path $repo 'tests/Arch'
            [void](New-Item -ItemType Directory -Path $proj -Force)
            Set-Content -LiteralPath (Join-Path $proj 'Arch.csproj') -Value '<Project/>' -NoNewline
            Set-Content -LiteralPath (Join-Path $proj 'Rules.cs') -Value 'class Rules { void R() {} }' -NoNewline

            # Body path resolution mirrors the runner: a .csproj expands to its directory.
            $bodyDir = 'tests/Arch'
            $h = Get-ArchLockedBodyHash -Paths @($bodyDir) -RepoRoot $repo
            $c = [pscustomobject]@{ id = 'ARCH-Csproj-1'; maturity = 'locked'; lockedBodySha256 = $h }
            (Get-ArchLockExecutionDecision -Contract $c -BodyPaths @($bodyDir) -RepoRoot $repo).Decision | Should -Be 'execute'

            # Weaken the reviewed assertion body without touching the csproj.
            Set-Content -LiteralPath (Join-Path $proj 'Rules.cs') -Value 'class Rules { void R() { /* gutted */ } }' -NoNewline
            (Get-ArchLockExecutionDecision -Contract $c -BodyPaths @($bodyDir) -RepoRoot $repo).Decision | Should -Be 'lock-invalidated'
        }

        It 'Runner-MaturityGovernedByContract: a config maturity that disagrees with the contract file is a hard error' {
            $repo = Join-Path $TestDrive 'gov'
            [void](New-Item -ItemType Directory -Path $repo -Force)
            Push-Location $repo
            try {
                git init -q 2>&1 | Out-Null
                git config user.email 'a@b.c' 2>&1 | Out-Null
                git config user.name 'Test' 2>&1 | Out-Null
                Set-Content -LiteralPath (Join-Path $repo 'contract.json') -Value '{"id":"ARCH-Gov-1","maturity":"locked"}' -NoNewline

                # Config claims draft while the reviewed contract is locked -> refuse (no silent downgrade).
                $cfgObj = @{ version = '1'; checks = @(@{ contractId = 'ARCH-Gov-1'; adapter = 'netarchtest'; maturity = 'draft'; contractPath = 'contract.json'; spec = 'x.spec' }) }
                $cfgPath = Join-Path $repo 'arch-test-config.json'
                Set-Content -LiteralPath $cfgPath -Value ($cfgObj | ConvertTo-Json -Depth 8)
                git add -A 2>&1 | Out-Null
                git commit -q -m 'initial' 2>&1 | Out-Null

                { Invoke-ArchTests -ConfigPath $cfgPath -RepoRoot $repo -ReceiptDir (Join-Path $repo 'r') } | Should -Throw
            }
            finally {
                Pop-Location
            }
        }

        It 'Lockgate-TransitionRefusedViaEnvSignal: the concrete env autonomous signal (not a param) drives locked-transition refusal' {
            $name = 'SKALARY_ARCH_AUTONOMOUS'
            $old = [System.Environment]::GetEnvironmentVariable($name)
            try {
                [System.Environment]::SetEnvironmentVariable($name, '1')
                # No -Autonomous param supplied: the env var alone must force refusal.
                { Assert-ArchLockTransition -ContractId 'ARCH-Env-1' -FromMaturity 'draft' -ToMaturity 'locked' } | Should -Throw
                # An explicit $false must NOT clear an env-detected autonomous context (anti-self-promotion fail-safe).
                { Assert-ArchLockTransition -ContractId 'ARCH-Env-1' -FromMaturity 'draft' -ToMaturity 'locked' -Autonomous $false } | Should -Throw
                Test-ArchLockWriteAllowed -Maturity 'locked' -Autonomous $false | Should -BeFalse
            }
            finally {
                [System.Environment]::SetEnvironmentVariable($name, $old)
            }
        }

        It 'Lockgate-BuildOutputsExcludedFromBodyHash: bin/obj/node_modules never affect a locked body hash' {
            # A real build writes bin/obj into a csproj directory AFTER lock time. Those must not invalidate the lock.
            $root = Join-Path $TestDrive 'buildout'
            $proj = Join-Path $root 'tests/Arch'
            [void](New-Item -ItemType Directory -Path $proj -Force)
            Set-Content -LiteralPath (Join-Path $proj 'Arch.csproj') -Value '<Project/>' -NoNewline
            Set-Content -LiteralPath (Join-Path $proj 'Rules.cs') -Value 'class Rules {}' -NoNewline

            $before = Get-ArchLockedBodyHash -Paths @('tests/Arch') -RepoRoot $root

            foreach ($d in @('bin/Debug/net9.0', 'obj', 'node_modules/pkg')) {
                $od = Join-Path $proj $d
                [void](New-Item -ItemType Directory -Path $od -Force)
                Set-Content -LiteralPath (Join-Path $od 'artifact.dll') -Value 'BINARY' -NoNewline
            }

            $after = Get-ArchLockedBodyHash -Paths @('tests/Arch') -RepoRoot $root
            $after | Should -Be $before

            # Editing a committed source under the same directory still invalidates it.
            Set-Content -LiteralPath (Join-Path $proj 'Rules.cs') -Value 'class Rules { void M() {} }' -NoNewline
            (Get-ArchLockedBodyHash -Paths @('tests/Arch') -RepoRoot $root) | Should -Not -Be $before
        }

        It 'Adapter-NetArchTest-DetectsViolation: a real NetArchTest run against the committed fixture reports a deterministic fail (opt-in)' {
            # Opt-in only: real toolchain runs are gated so structural evals / npm test stay hermetic (never shell dotnet).
            $optIn = $script:ArchLockTruthy -contains ([string][System.Environment]::GetEnvironmentVariable('SKALARY_ARCH_REAL_RUN')).ToLowerInvariant()
            if (-not $optIn) {
                Set-ItResult -Skipped -Because 'SKALARY_ARCH_REAL_RUN not set; the real dotnet run is opt-in (see evals/fixtures/netarchtest/README.md)'
                return
            }
            if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
                Set-ItResult -Skipped -Because 'dotnet toolchain absent'
                return
            }
            . $script:netArchAdapter

            $fixture = (Resolve-Path -LiteralPath $script:netArchFixture).Path
            $proj = Join-Path $fixture 'tests/Sample.ArchTests/Sample.ArchTests.csproj'

            # Deterministic restore from the committed lock files proves reproducibility before executing.
            & dotnet restore $proj --locked-mode 2>&1 | Out-Null
            $LASTEXITCODE | Should -Be 0

            # The lock gate must green (execute) against the committed contract before the adapter runs.
            $contract = Get-Content -LiteralPath (Join-Path $fixture 'arch-contract.json') -Raw | ConvertFrom-Json
            $decision = Get-ArchLockExecutionDecision -Contract $contract -BodyPaths @('tests/Sample.ArchTests') -RepoRoot $fixture
            $decision.Decision | Should -Be 'execute'

            $ctx = @{ ContractId = 'ARCH-Fixture-Layering'; TargetRoot = (Join-Path $fixture 'src'); RepoRoot = $fixture; BodyPaths = @($proj) }
            $res = Invoke-NetArchTestAdapter -Context $ctx
            $res.status | Should -Be 'fail'
            $res.ran | Should -BeTrue
            @($res.findings).Count | Should -BeGreaterThan 0
            ($res.findings | ForEach-Object { [string]$_.message }) -join ' ' | Should -Match 'Sample\.Domain\.Order'
        }
    }
}
