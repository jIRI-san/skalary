#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'architecture-tests retirement lifecycle' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:fixtureRoot = Join-Path $script:repoRoot 'tests/skalary/fixtures/plugin-retirement/architecture-tests-pre-cda9da-v1'
        $script:tempRoots = [System.Collections.Generic.List[string]]::new()

        . (Join-Path $script:repoRoot 'scripts/skalary/_Common.ps1')

        $script:registry = Read-JsonFile -Path (Join-Path $script:repoRoot 'registry.json')
        $script:tombstone = @($script:registry.retiredPlugins | Where-Object {
                [string]$_.name -ceq 'architecture-tests'
            })[0]
        $script:sourceIdentity = New-PluginSourceIdentity -Repository 'jIRI-san/skalary'

        function New-ArchitectureTestsConsumer {
            param(
                [switch]$ManualResidue,
                [ValidateRange(1, 14)]
                [int]$FileCount = 2
            )

            $root = Join-Path ([System.IO.Path]::GetTempPath()) ("architecture-retirement-" + [guid]::NewGuid().ToString('N'))
            [void](New-Item -ItemType Directory -Path $root)
            $script:tempRoots.Add($root)
            git -C $root init --quiet
            git -C $root config user.email 'fixture@example.invalid'
            git -C $root config user.name 'Fixture'

            $payloadParent = Join-Path $root '.github/skills'
            [void](New-Item -ItemType Directory -Path $payloadParent -Force)

            $receiptPath = Join-Path $root '.github/.skalary/receipts/architecture-tests.json'
            [void](New-Item -ItemType Directory -Path (Split-Path -Parent $receiptPath) -Force)
            $receipt = Read-JsonFile -Path (Join-Path $script:fixtureRoot 'receipt/architecture-tests.json')
            $receipt.files = @($receipt.files | Select-Object -First $FileCount)
            foreach ($entry in $receipt.files) {
                $relative = ([string]$entry.dest).Substring('skills/architecture-tests/'.Length)
                $source = Join-Path $script:fixtureRoot "installed-payload/architecture-tests/$relative"
                $destination = Join-Path $root ".github/$([string]$entry.dest)"
                [void](New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force)
                Copy-Item -LiteralPath $source -Destination $destination
            }
            Write-JsonFileStable -Path $receiptPath -InputObject $receipt

            $manualPaths = [ordered]@{}
            $userHome = Join-Path $root 'user-home'
            [void](New-Item -ItemType Directory -Path $userHome)
            if ($ManualResidue) {
                $manualPaths.Config = Join-Path $root 'docs/architecture-notes/arch-test-config.json'
                $manualPaths.Receipt = Join-Path $root 'docs/architecture-notes/receipts/ARCH-Legacy.arch-receipt.json'
                $manualPaths.Approval = Join-Path $root '.vscode/settings.json'
                $manualPaths.Cli = Join-Path $userHome '.copilot/installed-plugins/skalary/architecture-tests/sentinel.txt'
                foreach ($path in $manualPaths.Values) {
                    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force)
                }
                Set-Content -LiteralPath $manualPaths.Config -Value '{"legacy":"config"}' -NoNewline
                Set-Content -LiteralPath $manualPaths.Receipt -Value '{"legacy":"receipt"}' -NoNewline
                Set-Content -LiteralPath $manualPaths.Approval `
                    -Value '{"chat.tools.terminal.autoApprove":{".github/skills/architecture-tests/scripts/Get-ArchReviewReport.ps1":true}}' `
                    -NoNewline
                Set-Content -LiteralPath $manualPaths.Cli -Value 'cli sentinel' -NoNewline
            }

            return [pscustomobject]@{
                Root = $root
                PayloadRoot = Join-Path $root '.github/skills/architecture-tests'
                ReceiptPath = $receiptPath
                ManualPaths = $manualPaths
                UserHome = $userHome
            }
        }

        function Get-PayloadFiles {
            param([Parameter(Mandatory)]$Consumer)

            return @(
                Get-ChildItem -LiteralPath $Consumer.PayloadRoot -File -Recurse |
                    Sort-Object FullName
            )
        }

        function Invoke-RealReconciliation {
            param(
                [Parameter(Mandatory)]$Consumer,
                [switch]$ApplyRetirements,
                [string]$DirectTarget
            )

            return Invoke-PluginRetirementReconciliation `
                -RepoRoot $Consumer.Root `
                -Registry $script:registry `
                -SourceIdentity $script:sourceIdentity `
                -ApplyRetirements:$ApplyRetirements `
                -DirectTarget $DirectTarget `
                -UserHome $Consumer.UserHome
        }
    }

    AfterAll {
        foreach ($root in $script:tempRoots) {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:PluginRetirement.ReaderRemovalAndResultContract proves the frozen old installer cannot claim retirement' {
        $consumer = New-ArchitectureTestsConsumer -FileCount 14
        $before = @(Get-PayloadFiles -Consumer $consumer | ForEach-Object {
                "$([System.IO.Path]::GetRelativePath($consumer.PayloadRoot, $_.FullName))|$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)"
            })
        $oldInstaller = Join-Path $script:fixtureRoot 'bootstrap/scripts/skalary/Install-Plugin.ps1'

        $output = @(
            & pwsh -NoProfile -File $oldInstaller `
                -Name plugin-manager `
                -RepoRoot $consumer.Root `
                -Source $script:repoRoot `
                -Ref HEAD 2>&1
        )

        $LASTEXITCODE | Should -Be 0
        ($output -join "`n") | Should -Not -Match 'RETIREMENT:'
        $after = @(Get-PayloadFiles -Consumer $consumer | ForEach-Object {
                "$([System.IO.Path]::GetRelativePath($consumer.PayloadRoot, $_.FullName))|$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)"
            })
        $after | Should -Be $before
        Test-Path -LiteralPath $consumer.ReceiptPath -PathType Leaf | Should -BeTrue
    }

    It 'test:PluginRetirement.ReconciliationStateMatrix previews, refreshes stale input without deletion, then preserves residue' {
        $consumer = New-ArchitectureTestsConsumer
        $files = @(Get-PayloadFiles -Consumer $consumer)
        $preview = Invoke-RealReconciliation -Consumer $consumer
        $preview.Record.outcomes[0].outcome | Should -Be 'preview'
        @(Get-PayloadFiles -Consumer $consumer).Count | Should -Be $files.Count

        $changedPath = $files[0].FullName
        Set-Content -LiteralPath $changedPath -Value 'consumer modification' -NoNewline
        $refreshed = Invoke-RealReconciliation -Consumer $consumer
        $refreshed.Record.outcomes[0].outcome | Should -Be 'preview'
        $refreshed.Record.outcomes[0].remedy | Should -Match 'zero deletion'
        @(Get-PayloadFiles -Consumer $consumer).Count | Should -Be $files.Count

        $applied = Invoke-RealReconciliation -Consumer $consumer
        $applied.Record.outcomes[0].outcome | Should -Be 'residue'
        Test-Path -LiteralPath $changedPath -PathType Leaf | Should -BeTrue
        @(Get-PayloadFiles -Consumer $consumer).Count | Should -Be 1
        $receipt = Read-PluginReceipt -RepoRoot $consumer.Root -PluginName 'architecture-tests'
        $receipt.degraded | Should -BeTrue
        @($receipt.files).Count | Should -Be 1
        $receipt.files[0].outcome | Should -Be 'skipped-modified'
    }

    It 'test:PluginRetirement.ReconciliationStateMatrix retires only the real tombstone and receipt intersection' {
        $consumer = New-ArchitectureTestsConsumer
        $extraPath = Join-Path $consumer.PayloadRoot 'consumer-owned.txt'
        Set-Content -LiteralPath $extraPath -Value 'consumer owned' -NoNewline
        $extraHash = Get-FileSha256 -Path $extraPath
        $receipt = Read-JsonFile -Path $consumer.ReceiptPath
        $receipt.files += , [pscustomobject][ordered]@{
            dest = 'skills/architecture-tests/consumer-owned.txt'
            sha256 = $extraHash
            outcome = 'installed'
        }
        Write-JsonFileStable -Path $consumer.ReceiptPath -InputObject $receipt

        (Invoke-RealReconciliation -Consumer $consumer).Record.outcomes[0].outcome | Should -Be 'preview'
        $result = Invoke-RealReconciliation -Consumer $consumer
        $result.Record.outcomes[0].outcome | Should -Be 'retired'
        Test-Path -LiteralPath $extraPath -PathType Leaf | Should -BeTrue
        (Get-FileSha256 -Path $extraPath) | Should -Be $extraHash
        $remaining = Read-PluginReceipt -RepoRoot $consumer.Root -PluginName 'architecture-tests'
        @($remaining.files).Count | Should -Be 1
        $remaining.files[0].dest | Should -Be 'skills/architecture-tests/consumer-owned.txt'
    }

    It 'test:PluginRetirement.ReconciliationStateMatrix reports foreign, manual-required, and recovered real states' {
        $foreign = New-ArchitectureTestsConsumer
        $foreignReceipt = Read-JsonFile -Path $foreign.ReceiptPath
        $foreignReceipt | Add-Member -NotePropertyName sourceIdentity `
            -NotePropertyValue (New-PluginSourceIdentity -Repository 'example/foreign') -Force
        Write-JsonFileStable -Path $foreign.ReceiptPath -InputObject $foreignReceipt
        (Invoke-RealReconciliation -Consumer $foreign).Record.outcomes[0].outcome |
            Should -Be 'foreign-source'
        @(Get-PayloadFiles -Consumer $foreign).Count | Should -BeGreaterThan 0

        $manual = New-ArchitectureTestsConsumer
        $manualReceipt = Read-JsonFile -Path $manual.ReceiptPath
        $manualReceipt.version = '9.9.9'
        Write-JsonFileStable -Path $manual.ReceiptPath -InputObject $manualReceipt
        $manualResult = Invoke-RealReconciliation -Consumer $manual
        $manualResult.Record.outcomes[0].outcome | Should -Be 'manual-required'
        @(Get-PayloadFiles -Consumer $manual).Count | Should -BeGreaterThan 0

        $recovered = New-ArchitectureTestsConsumer
        [void](Invoke-RealReconciliation -Consumer $recovered)
        $failedState = Read-PluginRetirementState -RepoRoot $recovered.Root -PluginName 'architecture-tests'
        $failedState.status = 'failed'
        $failedState | Add-Member -NotePropertyName error -NotePropertyValue 'injected rollback-complete failure'
        Write-PluginRetirementState -RepoRoot $recovered.Root -State $failedState
        $recoveredResult = Invoke-RealReconciliation -Consumer $recovered
        $recoveredResult.Record.outcomes[0].outcome | Should -Be 'recovered'
        (Read-PluginRetirementState -RepoRoot $recovered.Root -PluginName 'architecture-tests').status |
            Should -Be 'preview'
        @(Get-PayloadFiles -Consumer $recovered).Count | Should -BeGreaterThan 0
    }

    It 'test:PluginRetirement.ReaderRemovalAndResultContract repeatedly reports manual residue without mutating it' {
        $consumer = New-ArchitectureTestsConsumer -ManualResidue
        $before = @{}
        foreach ($path in $consumer.ManualPaths.Values) {
            $before[$path] = Get-FileSha256 -Path $path
        }

        [void](Invoke-RealReconciliation -Consumer $consumer)
        $retired = Invoke-RealReconciliation -Consumer $consumer
        $retired.Record.outcomes[0].outcome | Should -Be 'retired'
        $reported = @($retired.Record.outcomes[0].paths)
        $expectedReportedPaths = @($script:tombstone.manualResidue.path)
        @($reported.path | Sort-Object) | Should -Be @($expectedReportedPaths | Sort-Object)
        @($reported.kind | Sort-Object -Unique) |
            Should -Be @('approval-key', 'copilot-cli', 'scaffold')
        @($reported | Where-Object { [string]$_.path -eq '.vscode/settings.json' })[0].present |
            Should -BeTrue
        @($reported | Where-Object { [string]$_.kind -eq 'copilot-cli' })[0].present |
            Should -BeTrue

        $replayed = Invoke-RealReconciliation -Consumer $consumer
        $replayed.Record.outcomes[0].outcome | Should -Be 'retired'
        @($replayed.Record.outcomes[0].paths.path | Sort-Object) |
            Should -Be @($expectedReportedPaths | Sort-Object)
        foreach ($path in $consumer.ManualPaths.Values) {
            Test-Path -LiteralPath $path | Should -BeTrue
            (Get-FileSha256 -Path $path) | Should -Be $before[$path]
        }
    }

    It 'test:PluginRetirement.ReaderRemovalAndResultContract returns exit 20 for a direct real retired target' {
        $consumer = New-ArchitectureTestsConsumer
        Remove-Item -LiteralPath $consumer.PayloadRoot -Recurse -Force
        Remove-Item -LiteralPath $consumer.ReceiptPath -Force
        $installer = Join-Path $script:repoRoot 'scripts/skalary/Install-Plugin.ps1'

        $output = @(
            & pwsh -NoProfile -File $installer `
                -Name architecture-tests `
                -RepoRoot $consumer.Root `
                -Source $script:repoRoot `
                -Ref HEAD 2>&1
        )

        $LASTEXITCODE | Should -Be 20
        ($output -join "`n") | Should -Match 'RETIREMENT:'
        ($output -join "`n") | Should -Match '"outcome":"no-match"'
        Test-Path -LiteralPath $consumer.PayloadRoot | Should -BeFalse
    }

    It 'test:ArchitectureTestRetirement.RuntimeSurfaceAbsent keeps fresh consumers runtime-free' {
        @($script:registry.plugins.name) | Should -Not -Contain 'architecture-tests'
        $marketplace = Read-JsonFile -Path (Join-Path $script:repoRoot '.github/plugin/marketplace.json')
        @($marketplace.plugins.name) | Should -Not -Contain 'architecture-tests'

        foreach ($path in @(
                'plugins/architecture-tests',
                '.github/skills/architecture-tests',
                'scripts/skalary/Invoke-ArchTests.ps1',
                'scripts/skalary/Invoke-ArchAdapter.ps1',
                'scripts/skalary/Get-ArchReviewReport.ps1',
                'scripts/skalary/Assert-ArchLock.ps1',
                'scripts/skalary/ArchReceipt.psm1',
                'docs/design-notes/architecture/architecture-tests.design.md')) {
            Test-Path -LiteralPath (Join-Path $script:repoRoot $path) | Should -BeFalse
        }

        $marketplaceRaw = Get-Content -LiteralPath (Join-Path $script:repoRoot '.github/plugin/marketplace.json') -Raw
        $marketplaceRaw | Should -Not -Match 'architecture-tests|retiredPlugins'
    }
}
