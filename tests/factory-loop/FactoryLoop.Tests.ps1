#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'factory-loop plugin' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:pluginRoot = Join-Path $script:repoRoot 'plugins/factory-loop'
        Import-Module (Join-Path $script:pluginRoot 'skills/factory-loop/scripts/FactoryLoop.psm1') `
            -Force -DisableNameChecking
        Import-Module (Join-Path $script:pluginRoot 'skills/factory-loop/scripts/FactoryLoop.Runtime.psm1') `
            -Force -DisableNameChecking
        Import-Module (Join-Path $script:repoRoot 'scripts/skalary/SecretGuard.psm1') `
            -Force -DisableNameChecking

        function New-FactoryLoopRuntimeFixture {
            param(
                [switch]$LeaveDefect,
                [switch]$MutateCriteriaBeforeAdmission,
                [switch]$SkipChainInitialization
            )

            $demo = Join-Path $TestDrive ('runtime-' + [guid]::NewGuid().ToString('N'))
            $created = New-FactoryLoopDemoProject -DemoRoot $demo
            $planSource = Join-Path $script:repoRoot `
                'docs/implementation-plans/standalone-2026-10-03-961e7d-factory-loop-mvp'
            $planDestination = Join-Path $demo `
                'docs/implementation-plans/standalone-2026-10-03-961e7d-factory-loop-mvp'
            [void](New-Item -ItemType Directory -Path (Split-Path -Parent $planDestination) -Force)
            Copy-Item -LiteralPath $planSource -Destination $planDestination -Recurse

            $ciScripts = Join-Path $demo '.github/skills/ci/scripts'
            [void](New-Item -ItemType Directory -Path $ciScripts -Force)
            foreach ($name in @('DirectWorkflow.psm1', 'PlanState.psm1', 'SecretGuard.psm1')) {
                Copy-Item -LiteralPath (Join-Path $script:repoRoot "scripts/skalary/$name") `
                    -Destination $ciScripts
            }
            git -C $demo add -- docs .github
            git -C $demo -c user.name='Factory Loop Demo' -c user.email='factory-loop-demo@localhost' `
                commit --quiet -m 'Add confirmed plan baseline fixture'
            if ($LASTEXITCODE -ne 0) { throw 'Unable to commit the plan baseline fixture.' }

            $branch = if ($LeaveDefect) { 'feature/runtime-failure' } else { 'feature/runtime-fix' }
            git -C $demo switch -c $branch --quiet
            if ($LASTEXITCODE -ne 0) { throw 'Unable to create the runtime feature branch.' }
            if (-not $LeaveDefect) {
                $appScript = Join-Path $demo 'application/Invoke-DemoApp.ps1'
                $fixed = (Get-Content -LiteralPath $appScript -Raw).Replace(
                    '$Subtotal * (1 + $DiscountRate)',
                    '$Subtotal * (1 - $DiscountRate)'
                )
                Set-Content -LiteralPath $appScript -Value $fixed -NoNewline -Encoding utf8NoBOM
                git -C $demo add -- application/Invoke-DemoApp.ps1
                git -C $demo -c user.name='Factory Loop Demo' -c user.email='factory-loop-demo@localhost' `
                    commit --quiet -m 'Fix demo discount calculation'
                if ($LASTEXITCODE -ne 0) { throw 'Unable to commit the runtime feature change.' }
            }
            $sourceSha = (git -C $demo rev-parse HEAD).Trim()
            if ($MutateCriteriaBeforeAdmission) {
                Add-Content -LiteralPath (Join-Path $planDestination 'assets/requirements.md') `
                    -Value "`nUnconfirmed change." -Encoding utf8NoBOM
            }
            $item = Invoke-FactoryLoopLoopback -RepoRoot $demo -Domain work-item -Action create `
                -OperationId ('runtime:item:' + [guid]::NewGuid().ToString('N')) `
                -Payload @{ title = 'Runtime feature' }
            $chainId = 'chain-' + [guid]::NewGuid().ToString('N')
            $planReference = '961e7d'
            $checkpoint = $null
            $admissionError = $null
            if (-not $SkipChainInitialization) {
                try {
                    $checkpoint = Initialize-FactoryLoopChain -RepoRoot $demo -ChainId $chainId `
                        -WorkItemId ([string]$item.data.item.id) -PlanReference $planReference `
                        -Branch $branch -SourceSha $sourceSha
                }
                catch {
                    if (-not $MutateCriteriaBeforeAdmission) { throw }
                    $admissionError = $_.Exception.Message
                }
            }
            return [pscustomobject]@{
                Root = $demo
                Branch = $branch
                SourceSha = $sourceSha
                ChainId = $chainId
                WorkItemId = [string]$item.data.item.id
                Checkpoint = $checkpoint
                AdmissionError = $admissionError
            }
        }

        function Read-FactoryLoopRuntimeFixtureCheckpoint {
            param([Parameter(Mandatory)][string]$RepoRoot)
            $path = Join-Path $RepoRoot '.factory-loop/checkpoint.json'
            return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable -Depth 40
        }

        function Complete-FactoryLoopRuntimeMerge {
            param([Parameter(Mandatory)][object]$Fixture)

            $opened = Invoke-FactoryLoopTick -RepoRoot $Fixture.Root
            $opened.stage | Should -BeExactly 'awaiting-checks'
            $checked = Invoke-FactoryLoopTick -RepoRoot $Fixture.Root
            $checked.stage | Should -BeExactly 'awaiting-merge'
            git -C $Fixture.Root switch main --quiet
            if ($LASTEXITCODE -ne 0) { throw 'Unable to switch to the demo main branch.' }
            $merge = Invoke-FactoryLoopLoopback -RepoRoot $Fixture.Root -Domain pull-request `
                -Action merge -OperationId "$($Fixture.ChainId):human-merge:confirmed" `
                -Payload @{
                    pullRequestId = 'PR-0001'
                    demoRoot = $Fixture.Root
                    expectedSourceSha = $Fixture.SourceSha
                    confirmMerge = $true
                }
            if ([string]$merge.status -cne 'ok') { throw 'Demo PR merge did not succeed.' }
            $merged = Invoke-FactoryLoopTick -RepoRoot $Fixture.Root
            $merged.stage | Should -BeExactly 'test-deployment'
            return $merge
        }

        function Invoke-FactoryLoopFixtureTick {
            param(
                [Parameter(Mandatory)][string]$RepoRoot,
                [scriptblock]$Clock,
                [scriptblock]$AdapterRunner
            )

            $arguments = @{ RepoRoot = $RepoRoot }
            if ($Clock) { $arguments.Clock = $Clock }
            if ($AdapterRunner) { $arguments.AdapterRunner = $AdapterRunner }
            return Invoke-FactoryLoopTick @arguments
        }

        function New-FactoryLoopFixedClock {
            param([Parameter(Mandatory)][datetime]$Time)
            $utc = $Time.ToUniversalTime()
            $millisecond = $utc.Millisecond
            $remainingTicks = $utc.Ticks % [timespan]::TicksPerMillisecond
            return [scriptblock]::Create(
                "[datetime]::new($($utc.Year),$($utc.Month),$($utc.Day),$($utc.Hour)," +
                "$($utc.Minute),$($utc.Second),$millisecond,[datetimekind]::Utc)" +
                ".AddTicks($remainingTicks)"
            )
        }

        function Complete-FactoryLoopTestAcceptance {
            param(
                [Parameter(Mandatory)][object]$Fixture,
                [scriptblock]$Clock,
                [scriptblock]$AdapterRunner
            )

            [void](Complete-FactoryLoopRuntimeMerge -Fixture $Fixture)
            $deployment = Invoke-FactoryLoopFixtureTick -RepoRoot $Fixture.Root `
                -Clock $Clock -AdapterRunner $AdapterRunner
            $deployment.stage | Should -BeExactly 'test-deployment-check'
            $verification = Invoke-FactoryLoopFixtureTick -RepoRoot $Fixture.Root `
                -Clock $Clock -AdapterRunner $AdapterRunner
            $verification.stage | Should -BeExactly 'test-version'
            $version = Invoke-FactoryLoopFixtureTick -RepoRoot $Fixture.Root `
                -Clock $Clock -AdapterRunner $AdapterRunner
            $version.stage | Should -BeExactly 'test-acceptance'
            $acceptance = Invoke-FactoryLoopFixtureTick -RepoRoot $Fixture.Root `
                -Clock $Clock -AdapterRunner $AdapterRunner
            return $acceptance
        }

        function Complete-FactoryLoopTestProductionAcceptance {
            param([Parameter(Mandatory)][object]$Fixture)

            $clockBase = [datetime]::new(2026, 10, 3, 12, 0, 0, [datetimekind]::Utc)
            [void](Complete-FactoryLoopTestAcceptance -Fixture $Fixture `
                -Clock (New-FactoryLoopFixedClock -Time $clockBase))
            $clock = New-FactoryLoopFixedClock -Time $clockBase.AddSeconds(300)
            [void](Invoke-FactoryLoopTick -RepoRoot $Fixture.Root -Clock $clock)
            [void](Invoke-FactoryLoopTick -RepoRoot $Fixture.Root -Clock $clock)
            $checkpoint = Read-FactoryLoopRuntimeFixtureCheckpoint -RepoRoot $Fixture.Root
            [void](Invoke-FactoryLoopLoopback -RepoRoot $Fixture.Root -Domain approval `
                -Action approve -OperationId "$($Fixture.ChainId):operator:approve" `
                -Payload @{ artifactDigest = [string]$checkpoint.artifactDigest; confirm = $true })
            [void](Invoke-FactoryLoopTick -RepoRoot $Fixture.Root -Clock $clock)
            [void](Invoke-FactoryLoopTick -RepoRoot $Fixture.Root -Clock $clock)
            [void](Invoke-FactoryLoopTick -RepoRoot $Fixture.Root -Clock $clock)
            [void](Invoke-FactoryLoopTick -RepoRoot $Fixture.Root -Clock $clock)
            return Invoke-FactoryLoopTick -RepoRoot $Fixture.Root -Clock $clock
        }

        function Enable-FactoryLoopTestEvidenceBranch {
            param([Parameter(Mandatory)][string]$RepoRoot)
            $configPath = Join-Path $RepoRoot '.factory-loop/factory-loop.json'
            $config = Get-Content -LiteralPath $configPath -Raw |
                ConvertFrom-Json -AsHashtable -Depth 20
            $config.evidenceBranchDeploymentExcluded = $true
            [System.IO.File]::WriteAllText(
                $configPath,
                (ConvertTo-Json -InputObject $config -Depth 20),
                [System.Text.UTF8Encoding]::new($false)
            )
        }
    }

    It 'test:FactoryLoop.Install installs repository and global payloads whose setup assets resolve plugin-relatively' {
        $manifest = Get-Content -LiteralPath (Join-Path $script:pluginRoot 'plugin.json') -Raw |
            ConvertFrom-Json -Depth 20
        $registryEntry = Get-Content -LiteralPath (Join-Path $script:repoRoot 'registry.json') -Raw |
            ConvertFrom-Json -Depth 100 | ForEach-Object {
                @($_.plugins | Where-Object name -CEQ 'factory-loop')
            }
        $registryEntry | Should -HaveCount 1
        @($registryEntry[0].scaffolds | ForEach-Object { [string]$_.path }) |
            Should -Contain '.factory-loop/**'
        @($registryEntry[0].scaffolds | ForEach-Object { [string]$_.path }) |
            Should -Contain 'docs/factory-loop/evidence/**'
        $marketplace = Get-Content -LiteralPath (
            Join-Path $script:repoRoot '.github/plugin/marketplace.json'
        ) -Raw | ConvertFrom-Json -Depth 100
        $marketplaceEntry = @($marketplace.plugins | Where-Object name -CEQ 'factory-loop')
        $marketplaceEntry | Should -HaveCount 1
        $marketplaceEntry[0].source | Should -BeExactly 'plugins/factory-loop'
        $marketplaceEntry[0].strict | Should -BeFalse

        $consumer = Join-Path $TestDrive 'selected-consumer'
        $globalPlugin = Join-Path $TestDrive 'global-plugin'
        $consumerRoot = Join-Path $TestDrive 'foreign-repository'
        [void](New-Item -ItemType Directory -Path $consumer, $globalPlugin, $consumerRoot -Force)

        foreach ($file in @($manifest.files)) {
            $source = Join-Path $script:pluginRoot ([string]$file.src)
            $installedPath = Join-Path (Join-Path $consumer '.github') ([string]$file.dest)
            $globalPath = Join-Path $globalPlugin ([string]$file.dest)
            foreach ($destination in @($installedPath, $globalPath)) {
                [void](New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force)
                Copy-Item -LiteralPath $source -Destination $destination
            }
        }

        $installedScript = Join-Path $consumer '.github/skills/factory-loop/scripts/Setup-FactoryLoop.ps1'
        $preview = & $installedScript -Action preview -RepoRoot $consumerRoot | ConvertFrom-Json -Depth 20
        @($preview.files | Where-Object action -EQ 'create') | Should -HaveCount 6
        $applied = & $installedScript -Action apply -RepoRoot $consumerRoot `
            -ExpectedDigest $preview.digest | ConvertFrom-Json -Depth 20
        @($applied.files | Where-Object action -EQ 'preserve') | Should -HaveCount 6
        Test-Path -LiteralPath (Join-Path $consumerRoot '.factory-loop/factory-loop.json') |
            Should -BeTrue
        Test-Path -LiteralPath (Join-Path $consumerRoot '.github/skills/ci/scripts/DirectWorkflow.psm1') |
            Should -BeTrue
        $installedAdapter = Join-Path $consumer '.github/skills/factory-loop/scripts/Invoke-FactoryLoopAdapter.ps1'
        $consumerState = & $installedAdapter -Domain work-item -Action create `
            -OperationId 'installed-consumer:item:1' -RepoRoot $consumerRoot `
            -PayloadJson '{"title":"Installed local demo"}' | ConvertFrom-Json -AsHashtable -Depth 20
        $consumerState.providerId | Should -Match '^loopback:work-item:WI-'

        $globalScript = Join-Path $globalPlugin 'skills/factory-loop/scripts/Setup-FactoryLoop.ps1'
        $globalModule = Join-Path $globalPlugin 'skills/factory-loop/scripts/FactoryLoop.psm1'
        $moduleBefore = (Get-FileHash -LiteralPath $globalModule -Algorithm SHA256).Hash
        $globalPreview = & $globalScript -Action preview -RepoRoot $consumerRoot |
            ConvertFrom-Json -Depth 20
        $globalPreview.digest | Should -Be $applied.digest
        $globalAdapter = Join-Path $globalPlugin 'skills/factory-loop/scripts/Invoke-FactoryLoopAdapter.ps1'
        $globalState = & $globalAdapter -Domain work-item -Action create `
            -OperationId 'global-installed:item:1' -RepoRoot $consumerRoot `
            -PayloadJson '{"title":"Global plugin project action"}' | ConvertFrom-Json -AsHashtable -Depth 20
        $globalState.providerId | Should -Match '^loopback:work-item:WI-'
        (Get-FileHash -LiteralPath $globalModule -Algorithm SHA256).Hash | Should -Be $moduleBefore
        Test-Path -LiteralPath (Join-Path $consumerRoot '.github/skills/factory-loop/scripts/FactoryLoop.psm1') |
            Should -BeFalse
    }

    It 'test:FactoryLoop.GlobalLayout keeps explicit consumer selection and never mutates the global payload' {
        $manifest = Get-Content -LiteralPath (Join-Path $script:pluginRoot 'plugin.json') -Raw |
            ConvertFrom-Json -Depth 20
        $globalPlugin = Join-Path $TestDrive 'global-layout/copilot/factory-loop'
        $consumerRoot = Join-Path $TestDrive 'another-consumer'
        [void](New-Item -ItemType Directory -Path $globalPlugin, $consumerRoot -Force)
        foreach ($file in @($manifest.files)) {
            $source = Join-Path $script:pluginRoot ([string]$file.src)
            $destination = Join-Path $globalPlugin ([string]$file.dest)
            [void](New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force)
            Copy-Item -LiteralPath $source -Destination $destination
        }
        $payload = Join-Path $globalPlugin 'skills/factory-loop/templates/factory-loop.json'
        $before = (Get-FileHash -LiteralPath $payload -Algorithm SHA256).Hash
        $setup = Join-Path $globalPlugin 'skills/factory-loop/scripts/Setup-FactoryLoop.ps1'
        $preview = & $setup -Action preview -RepoRoot $consumerRoot | ConvertFrom-Json -Depth 20
        & $setup -Action apply -RepoRoot $consumerRoot -ExpectedDigest $preview.digest | Out-Null
        (Get-FileHash -LiteralPath $payload -Algorithm SHA256).Hash | Should -Be $before
        Test-Path -LiteralPath (Join-Path $consumerRoot 'scripts/factory-loop/FactoryLoop.Adapter.ps1') |
            Should -BeTrue
        Test-Path -LiteralPath (Join-Path $consumerRoot '.github/skills/ci/scripts/DirectWorkflow.psm1') |
            Should -BeTrue
    }

    It 'test:FactoryLoop.Setup previews, confines and preserves consumer-owned files without writing credentials' {
        $consumer = Join-Path $TestDrive 'setup-consumer'
        [void](New-Item -ItemType Directory -Path $consumer -Force)
        $preview = Get-FactoryLoopSetupPreview -RepoRoot $consumer
        @($preview.files | Where-Object action -EQ 'create') | Should -HaveCount 6
        { Invoke-FactoryLoopSetup -Action apply -RepoRoot $consumer -ExpectedDigest 'wrong' } |
            Should -Throw '*does not match the current preview*'

        $result = Invoke-FactoryLoopSetup -Action apply -RepoRoot $consumer -ExpectedDigest $preview.digest
        @($result.files | Where-Object action -EQ 'preserve') | Should -HaveCount 6
        $configPath = Join-Path $consumer '.factory-loop/factory-loop.json'
        $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json -Depth 20
        $config.pollSeconds | Should -Be 60
        $config.observationSeconds | Should -Be 300
        $config.PSObject.Properties.Name | Should -Not -Contain 'credential'
        $config.PSObject.Properties.Name | Should -Not -Contain 'token'

        Set-Content -LiteralPath $configPath -Value '{"consumerEdit":true}' -NoNewline -Encoding utf8NoBOM
        $rerun = Get-FactoryLoopSetupPreview -RepoRoot $consumer
        @($rerun.files | Where-Object action -EQ 'preserve') | Should -HaveCount 6
        Invoke-FactoryLoopSetup -Action apply -RepoRoot $consumer -ExpectedDigest $rerun.digest | Out-Null
        Get-Content -LiteralPath $configPath -Raw | Should -BeExactly '{"consumerEdit":true}'
        { Resolve-FactoryLoopConsumerPath -RepoRoot $consumer -RelativePath '../escape.txt' } |
            Should -Throw
        { Resolve-FactoryLoopConsumerPath -RepoRoot $consumer -RelativePath 'docs/other.txt' } |
            Should -Throw
        Resolve-FactoryLoopConsumerPath -RepoRoot $consumer `
            -RelativePath 'docs/factory-loop/evidence/record.json' |
            Should -Match 'docs[\\/]factory-loop[\\/]evidence[\\/]record\.json$'
    }

    It 'test:FactoryLoop.AdapterContract test:FactoryLoop.FaultMatrix rejects malformed, mismatched, and failed results' {
        $seen = [System.Collections.Generic.List[object]]::new()
        $runner = {
            param($Domain, $Action, $OperationId, $Payload)
            $seen.Add([pscustomobject]@{
                    Domain = $Domain
                    Action = $Action
                    OperationId = $OperationId
                    Payload = $Payload
                })
            @{
                schemaVersion = 1
                domain = $Domain
                action = $Action
                operationId = $OperationId
                status = 'ok'
                providerId = 'loopback:work-item-17'
                data = @{ itemId = '17' }
            }
        }.GetNewClosure()
        $result = Invoke-FactoryLoopAdapter -Domain work-item -Action create `
            -OperationId 'chain-1:item:create:1' -Payload @{ title = 'demo' } -Runner $runner
        $result.providerId | Should -BeExactly 'loopback:work-item-17'
        $seen[0].OperationId | Should -BeExactly 'chain-1:item:create:1'
        $seen[0].Payload.title | Should -BeExactly 'demo'

        $loopbackRoot = Join-Path $TestDrive 'loopback-project'
        [void](New-Item -ItemType Directory -Path $loopbackRoot -Force)
        $loopRunner = {
            param($Domain, $Action, $OperationId, $Payload)
            Invoke-FactoryLoopLoopback -RepoRoot $loopbackRoot -Domain $Domain -Action $Action `
                -OperationId $OperationId -Payload $Payload
        }.GetNewClosure()
        $first = Invoke-FactoryLoopAdapter -Domain work-item -Action create `
            -OperationId 'chain-1:work-item:create' -Payload @{ title = 'Local demo feature' } -Runner $loopRunner
        $replayed = Invoke-FactoryLoopAdapter -Domain work-item -Action create `
            -OperationId 'chain-1:work-item:create' -Payload @{ title = 'Local demo feature' } -Runner $loopRunner
        $replayed.providerId | Should -BeExactly $first.providerId
        $state = Get-Content -LiteralPath (Join-Path $loopbackRoot '.factory-loop/loopback.json') -Raw |
            ConvertFrom-Json -AsHashtable -Depth 50
        $state.simulated | Should -BeTrue
        @($state.workItems) | Should -HaveCount 1
        @($state.operations | Where-Object operationId -CEQ 'chain-1:work-item:create') |
            Should -HaveCount 1
        $adapterScript = Join-Path $script:pluginRoot `
            'skills/factory-loop/scripts/Invoke-FactoryLoopAdapter.ps1'
        $cliJson = & $adapterScript -Domain work-item -Action create `
            -OperationId 'chain-1:work-item:cli' -RepoRoot $loopbackRoot `
            -PayloadJson '{"title":"CLI-created item"}'
        $cliResult = $cliJson | ConvertFrom-Json -AsHashtable -Depth 20
        $cliResult.status | Should -BeExactly 'ok'
        $cliResult.data.item.title | Should -BeExactly 'CLI-created item'

        $mismatched = {
            @{
                schemaVersion = 1
                domain = 'work-item'
                action = 'create'
                operationId = 'different-operation'
                status = 'ok'
                providerId = 'loopback:17'
                data = @{}
            }
        }
        { Invoke-FactoryLoopAdapter -Domain work-item -Action create `
                -OperationId 'chain-1:item:create:1' -Runner $mismatched } | Should -Throw '*does not match*'

        $malformed = { '{"schemaVersion":1,' }
        { Invoke-FactoryLoopAdapter -Domain work-item -Action create `
                -OperationId 'chain-1:item:create:1' -Runner $malformed } | Should -Throw '*malformed JSON*'

        $failed = {
            @{
                schemaVersion = 1
                domain = 'work-item'
                action = 'create'
                operationId = 'chain-1:item:create:1'
                status = 'failed'
                providerId = 'loopback:work-item-17'
                errorCode = 'AccessDenied'
                data = @{}
            }
        }
        { Invoke-FactoryLoopAdapter -Domain work-item -Action create `
                -OperationId 'chain-1:item:create:1' -Runner $failed } |
            Should -Throw '*AccessDenied*'
    }

    It 'test:FactoryLoop.DemoArtifact runs real code, merges a real PR branch, and pins immutable snapshots' {
        $demo = Join-Path $TestDrive 'disposable-demo'
        $consumer = Join-Path $TestDrive 'consumer'
        [void](New-Item -ItemType Directory -Path $consumer -Force)
        $created = New-FactoryLoopDemoProject -DemoRoot $demo -ConsumerRoot $consumer
        $created.sourceSha | Should -Match '^[0-9a-f]{40}$'
        $created.acceptanceStatus | Should -BeExactly 'failed'

        $application = Join-Path $demo 'application'
        $initialDigest = Get-FactoryLoopApplicationDigest -ApplicationRoot $application
        (Test-FactoryLoopArtifactAcceptance -ArtifactPath $application `
                -ExpectedDigest $initialDigest).status | Should -BeExactly 'failed'

        git -C $demo switch -c feature/planted-bug --quiet
        $LASTEXITCODE | Should -Be 0
        $failedPr = Invoke-FactoryLoopLoopback -RepoRoot $demo -Domain pull-request -Action open `
            -OperationId 'demo:pr:planted-bug' -Payload @{
            branch = 'feature/planted-bug'
            sourceSha = $created.sourceSha
        }
        $failedCheck = Invoke-FactoryLoopLoopback -RepoRoot $demo -Domain pull-request -Action checks `
            -OperationId 'demo:checks:planted-bug' -Payload @{
            pullRequestId = $failedPr.data.pullRequest.id
            demoRoot = $demo
            evaluate = $true
        }
        $failedCheck.data.checks.status | Should -BeExactly 'failed'
        git -C $demo switch main --quiet
        $LASTEXITCODE | Should -Be 0

        git -C $demo switch -c feature/fix-discount --quiet
        $LASTEXITCODE | Should -Be 0
        $appScript = Join-Path $application 'Invoke-DemoApp.ps1'
        $fixed = (Get-Content -LiteralPath $appScript -Raw).Replace(
            '$Subtotal * (1 + $DiscountRate)',
            '$Subtotal * (1 - $DiscountRate)'
        )
        Set-Content -LiteralPath $appScript -Value $fixed -NoNewline -Encoding utf8NoBOM
        git -C $demo add --all
        git -C $demo -c user.name='Factory Loop Demo' -c user.email='factory-loop-demo@localhost' `
            commit --quiet -m 'Fix discounted total'
        $LASTEXITCODE | Should -Be 0
        $sourceSha = (git -C $demo rev-parse HEAD).Trim()
        git -C $demo switch main --quiet
        $LASTEXITCODE | Should -Be 0

        $passingPr = Invoke-FactoryLoopLoopback -RepoRoot $demo -Domain pull-request -Action open `
            -OperationId 'demo:pr:fix-discount' -Payload @{
            branch = 'feature/fix-discount'
            sourceSha = $sourceSha
        }
        $passingCheck = Invoke-FactoryLoopLoopback -RepoRoot $demo -Domain pull-request -Action checks `
            -OperationId 'demo:checks:fix-discount' -Payload @{
            pullRequestId = $passingPr.data.pullRequest.id
            demoRoot = $demo
            evaluate = $true
        }
        $passingCheck.data.checks.status | Should -BeExactly 'passed'
        $mergePayload = @{
            pullRequestId = $passingPr.data.pullRequest.id
            demoRoot = $demo
            expectedSourceSha = $sourceSha
        }
        $deniedMerge = Invoke-FactoryLoopLoopback -RepoRoot $demo -Domain pull-request -Action merge `
            -OperationId 'demo:merge:denied' -Payload $mergePayload
        $deniedMerge.status | Should -BeExactly 'blocked'
        $mergePayload.confirmMerge = $true
        $mergeResult = Invoke-FactoryLoopLoopback -RepoRoot $demo -Domain pull-request -Action merge `
            -OperationId 'demo:merge:approved' -Payload $mergePayload
        $merge = [pscustomobject]$mergeResult.data.pullRequest
        $merge.sourceSha | Should -BeExactly $sourceSha
        $merge.mergeCommit | Should -Not -BeExactly $sourceSha
        $merge.mergeCommit | Should -Match '^[0-9a-f]{40}$'

        $store = Join-Path $demo '.factory-loop/artifacts'
        $artifact = New-FactoryLoopArtifactSnapshot -ApplicationRoot $application `
            -ArtifactStore $store -SourceSha $sourceSha -MergeCommit $merge.mergeCommit
        $artifact.artifactDigest | Should -Match '^[0-9a-f]{64}$'
        $artifact.sourceSha | Should -BeExactly $sourceSha
        $artifact.mergeCommit | Should -BeExactly $merge.mergeCommit
        (Test-FactoryLoopArtifactAcceptance -ArtifactPath $artifact.artifactPath `
                -ExpectedDigest $artifact.artifactDigest).status | Should -BeExactly 'passed'

        Add-Content -LiteralPath $appScript -Value "`n# Post-snapshot working-tree change" -Encoding utf8NoBOM
        (Get-FactoryLoopApplicationDigest -ApplicationRoot $application) |
            Should -Not -BeExactly $artifact.artifactDigest
        (Get-FactoryLoopApplicationDigest -ApplicationRoot $artifact.artifactPath) |
            Should -BeExactly $artifact.artifactDigest
        (Test-FactoryLoopArtifactAcceptance -ArtifactPath $artifact.artifactPath `
                -ExpectedDigest $artifact.artifactDigest).status | Should -BeExactly 'passed'
        (Test-FactoryLoopArtifactAcceptance -ArtifactPath $artifact.artifactPath `
                -ExpectedDigest ('0' * 64)).status | Should -BeExactly 'blocked'
    }

    It 'test:FactoryLoop.Tick performs finite zero-AI polls with one chain and a 60-second default' {
        $fixture = New-FactoryLoopRuntimeFixture
        $clockValue = [datetime]::Parse('2026-10-04T03:02:01Z').ToUniversalTime()
        $expectedTimestamp = $clockValue.ToString('o')
        $clock = { $clockValue }.GetNewClosure()
        $first = Invoke-FactoryLoopTick -RepoRoot $fixture.Root -Clock $clock
        $first.outcome | Should -BeExactly 'progressed'
        $first.stage | Should -BeExactly 'awaiting-checks'
        $first.aiCalls | Should -Be 0
        $observedTimestamp = [datetime](Read-FactoryLoopRuntimeFixtureCheckpoint -RepoRoot $fixture.Root).updatedAtUtc
        $observedTimestamp.ToUniversalTime().ToString('o') | Should -BeExactly $expectedTimestamp

        $second = Invoke-FactoryLoopTick -RepoRoot $fixture.Root -Clock $clock
        $second.outcome | Should -BeExactly 'waiting-for-human-merge'
        $second.stage | Should -BeExactly 'awaiting-merge'
        $second.nextPollAfterSeconds | Should -Be 60
        $second.aiCalls | Should -Be 0

        $checkpoint = Read-FactoryLoopRuntimeFixtureCheckpoint -RepoRoot $fixture.Root
        $checkpoint.pullRequestId | Should -BeExactly 'PR-0001'
        $checkpoint.criteriaBaselineCommit | Should -Match '^[0-9a-f]{40}$'
        $checkpoint.expectedSourceSha | Should -BeExactly $fixture.SourceSha

        $lockPath = Resolve-FactoryLoopConsumerPath -RepoRoot $fixture.Root -RelativePath '.factory-loop/loop.lock'
        $lock = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::OpenOrCreate,
            [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        try {
            $lockedTick = Invoke-FactoryLoopTick -RepoRoot $fixture.Root
            $lockedTick.outcome | Should -BeExactly 'locked'
            $lockedTick.aiCalls | Should -Be 0
        }
        finally {
            $lock.Dispose()
        }
    }

    It 'test:FactoryLoop.Restart test:FactoryLoop.FaultMatrix reconciles interruption before provider dispatch' {
        $before = New-FactoryLoopRuntimeFixture
        $clockValue = [datetime]::Parse('2026-10-04T03:02:01Z').ToUniversalTime()
        $expectedTimestamp = $clockValue.ToString('o')
        $clock = { $clockValue }.GetNewClosure()
        $beforeHook = {
            param($Pending)
            [string]$Pending.requestedAtUtc | Should -BeExactly $expectedTimestamp
            throw 'interrupt-before-provider-dispatch'
        }.GetNewClosure()
        { Invoke-FactoryLoopTick -RepoRoot $before.Root -Clock $clock -BeforeDispatch $beforeHook } |
            Should -Throw '*interrupt-before-provider-dispatch*'
        $beforeCheckpoint = Read-FactoryLoopRuntimeFixtureCheckpoint -RepoRoot $before.Root
        $beforeCheckpoint.pendingOperation.operationId |
            Should -BeExactly "$($before.ChainId):pull-request:open:1"
        $beforeState = Get-Content -LiteralPath (Join-Path $before.Root '.factory-loop/loopback.json') -Raw |
            ConvertFrom-Json -AsHashtable -Depth 40
        @($beforeState.pullRequests) | Should -BeNullOrEmpty
        $beforeResume = Invoke-FactoryLoopTick -RepoRoot $before.Root -Clock $clock
        $beforeResume.pullRequestId | Should -BeExactly 'PR-0001'
    }

    It 'test:FactoryLoop.Restart test:FactoryLoop.FaultMatrix reconciles interruption after PR mutation' {
        $after = New-FactoryLoopRuntimeFixture
        $afterHook = {
            param($Result)
            throw 'interrupt-after-provider-mutation'
        }
        { Invoke-FactoryLoopTick -RepoRoot $after.Root -AfterDispatch $afterHook } |
            Should -Throw '*interrupt-after-provider-mutation*'
        $afterCheckpoint = Read-FactoryLoopRuntimeFixtureCheckpoint -RepoRoot $after.Root
        $afterCheckpoint.pendingOperation.operationId |
            Should -BeExactly "$($after.ChainId):pull-request:open:1"
        $afterState = Get-Content -LiteralPath (Join-Path $after.Root '.factory-loop/loopback.json') -Raw |
            ConvertFrom-Json -AsHashtable -Depth 40
        @($afterState.pullRequests) | Should -HaveCount 1
        $prOperation = @($afterState.operations | Where-Object {
                [string]$_.operationId -ceq "$($after.ChainId):pull-request:open:1"
            })[0]
        $providerId = [string]$prOperation.result.providerId
        $afterResume = Invoke-FactoryLoopTick -RepoRoot $after.Root
        $afterResume.providerId | Should -BeExactly $providerId
        $afterState = Get-Content -LiteralPath (Join-Path $after.Root '.factory-loop/loopback.json') -Raw |
            ConvertFrom-Json -AsHashtable -Depth 40
        @($afterState.pullRequests) | Should -HaveCount 1
        @($afterState.operations | Where-Object operationId -CEQ "$($after.ChainId):pull-request:open:1") |
            Should -HaveCount 1
    }

    It 'test:FactoryLoop.PrChecks test:FactoryLoop.FaultMatrix treats a failing build as a bounded repair incident' {
        $failure = New-FactoryLoopRuntimeFixture -LeaveDefect
        [void](Invoke-FactoryLoopTick -RepoRoot $failure.Root)
        $failed = Invoke-FactoryLoopTick -RepoRoot $failure.Root
        $failed.status | Should -BeExactly 'failed'
        $failed.stage | Should -BeExactly 'build-failed'
        $failed.aiCalls | Should -Be 0
    }

    It 'test:FactoryLoop.PrChecks test:FactoryLoop.FaultMatrix blocks a changed pull-request head' {
        $changed = New-FactoryLoopRuntimeFixture
        [void](Invoke-FactoryLoopTick -RepoRoot $changed.Root)
        $appScript = Join-Path $changed.Root 'application/Invoke-DemoApp.ps1'
        Add-Content -LiteralPath $appScript -Value "`n# New PR head" -Encoding utf8NoBOM
        git -C $changed.Root add -- application/Invoke-DemoApp.ps1
        git -C $changed.Root -c user.name='Factory Loop Demo' -c user.email='factory-loop-demo@localhost' `
            commit --quiet -m 'Move PR head after checks'
        $LASTEXITCODE | Should -Be 0
        $changedResult = Invoke-FactoryLoopTick -RepoRoot $changed.Root
        $changedResult.outcome | Should -BeExactly 'blocked'
        $changedResult.reason | Should -BeExactly 'pull-request-head-changed'
    }

    It 'test:FactoryLoop.PrChecks test:FactoryLoop.FaultMatrix blocks a closed unmerged pull request' {
        $closed = New-FactoryLoopRuntimeFixture
        [void](Invoke-FactoryLoopTick -RepoRoot $closed.Root)
        [void](Invoke-FactoryLoopTick -RepoRoot $closed.Root)
        $statePath = Join-Path $closed.Root '.factory-loop/loopback.json'
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -AsHashtable -Depth 40
        $state.pullRequests[0].status = 'closed'
        [System.IO.File]::WriteAllText(
            $statePath,
            (ConvertTo-Json -InputObject $state -Depth 40),
            [System.Text.UTF8Encoding]::new($false)
        )
        $closedResult = Invoke-FactoryLoopTick -RepoRoot $closed.Root
        $closedResult.outcome | Should -BeExactly 'blocked'
        $closedResult.reason | Should -BeExactly 'pull-request-closed-unmerged'
    }

    It 'test:FactoryLoop.CriteriaAdmission blocks changed confirmed criteria before chain creation' {
        $fixture = New-FactoryLoopRuntimeFixture -MutateCriteriaBeforeAdmission
        $fixture.AdmissionError | Should -Match 'Confirmed requirements differs from .*baseline commit'
        Test-Path -LiteralPath (Join-Path $fixture.Root '.factory-loop/checkpoint.json') |
            Should -BeFalse
        $state = Get-Content -LiteralPath (Join-Path $fixture.Root '.factory-loop/loopback.json') -Raw |
            ConvertFrom-Json -AsHashtable -Depth 40
        @($state.pullRequests) | Should -BeNullOrEmpty
    }

    It 'test:FactoryLoop.PrChecks blocks cancelled check runs instead of waiting indefinitely' {
        $fixture = New-FactoryLoopRuntimeFixture
        [void](Invoke-FactoryLoopTick -RepoRoot $fixture.Root)
        $cancelledRunner = {
            param($Domain, $Action, $OperationId, $Payload)
            return [ordered]@{
                schemaVersion = 1
                domain = $Domain
                action = $Action
                operationId = $OperationId
                status = 'ok'
                providerId = 'loopback:pull-request:PR-0001'
                data = @{
                    checks = @{
                        status = 'cancelled'
                        headSha = $fixture.SourceSha
                    }
                }
            }
        }.GetNewClosure()
        $result = Invoke-FactoryLoopTick -RepoRoot $fixture.Root -AdapterRunner $cancelledRunner
        $result.outcome | Should -BeExactly 'blocked'
        $result.reason | Should -BeExactly 'checks-cancelled'
        $result.aiCalls | Should -Be 0
    }

    It 'test:FactoryLoop.MergeGate requires human confirmation and records the real merge commit' {
        $fixture = New-FactoryLoopRuntimeFixture
        [void](Invoke-FactoryLoopTick -RepoRoot $fixture.Root)
        $checks = Invoke-FactoryLoopTick -RepoRoot $fixture.Root
        $checks.outcome | Should -BeExactly 'waiting-for-human-merge'
        $waiting = Invoke-FactoryLoopTick -RepoRoot $fixture.Root
        $waiting.status | Should -BeExactly 'open'

        $unconfirmed = Invoke-FactoryLoopLoopback -RepoRoot $fixture.Root -Domain pull-request `
            -Action merge -OperationId "$($fixture.ChainId):human-merge:unconfirmed" `
            -Payload @{ pullRequestId = 'PR-0001'; demoRoot = $fixture.Root }
        $unconfirmed.status | Should -BeExactly 'blocked'
        $unconfirmed.data.reason | Should -BeExactly 'human-merge-required'

        git -C $fixture.Root switch main --quiet
        $LASTEXITCODE | Should -Be 0
        $humanMerge = Invoke-FactoryLoopLoopback -RepoRoot $fixture.Root -Domain pull-request `
            -Action merge -OperationId "$($fixture.ChainId):human-merge:confirmed" `
            -Payload @{
                pullRequestId = 'PR-0001'
                demoRoot = $fixture.Root
                expectedSourceSha = $fixture.SourceSha
                confirmMerge = $true
            }
        $humanMerge.status | Should -BeExactly 'ok'
        $mergedTick = Invoke-FactoryLoopTick -RepoRoot $fixture.Root
        $mergedTick.stage | Should -BeExactly 'test-deployment'
        $mergedTick.mergeCommit | Should -Match '^[0-9a-f]{40}$'
        $mergedTick.aiCalls | Should -Be 0
    }

    It 'test:FactoryLoop.PlanAdmission revalidates the confirmed baseline before factory repair' {
        $fixture = New-FactoryLoopRuntimeFixture -LeaveDefect
        [void](Invoke-FactoryLoopTick -RepoRoot $fixture.Root)
        [void](Invoke-FactoryLoopTick -RepoRoot $fixture.Root)
        $requirements = Join-Path $fixture.Root `
            'docs/implementation-plans/standalone-2026-10-03-961e7d-factory-loop-mvp/assets/requirements.md'
        Add-Content -LiteralPath $requirements -Value "`nUnconfirmed repair scope." -Encoding utf8NoBOM

        {
            Start-FactoryLoopRepairInvocation -RepoRoot $fixture.Root -PlanReference '961e7d'
        } | Should -Throw '*Confirmed requirements differs from Git-filtered baseline commit*'

        $checkpoint = Read-FactoryLoopRuntimeFixtureCheckpoint -RepoRoot $fixture.Root
        $checkpoint.repairPullRequestsReserved | Should -Be 0
        $checkpoint.repairBuildLineages[0].correctiveCalls | Should -Be 0
    }

    It 'test:FactoryLoop.AgentHandoff routes only explicit repair mode through the existing launcher' {
        $launcher = Get-Content -LiteralPath (Join-Path $script:repoRoot `
            'plugins/autopilot/scripts/launch.ps1') -Raw
        $hostLauncher = Get-Content -LiteralPath (Join-Path $script:repoRoot `
            'plugins/autopilot/scripts/launch-host.ps1') -Raw
        $agent = Get-Content -LiteralPath (Join-Path $script:repoRoot `
            'plugins/autopilot/agents/autopilot.agent.md') -Raw

        $launcher | Should -Match '\[switch\]\s*\$FactoryRepair'
        $launcher | Should -Match 'Start-FactoryLoopRepairInvocation'
        $launcher.Contains("requires -Mode 'next-phase'") | Should -BeTrue
        $hostLauncher | Should -Match 'FACTORY_LOOP_REPAIR_MODE'
        $hostLauncher | Should -Match 'without closing or finalizing the plan'
        $agent | Should -Match 'Never edit plan assets, `plan\.md`'
        $agent | Should -Match 'FACTORY_LOOP_REPAIR_MODE=true'
    }

    It 'test:FactoryLoop.RepairBounds test:FactoryLoop.FaultMatrix reserves no more than two repair PRs and calls' {
        $failure = New-FactoryLoopRuntimeFixture -LeaveDefect
        [void](Invoke-FactoryLoopTick -RepoRoot $failure.Root)
        $failed = Invoke-FactoryLoopTick -RepoRoot $failure.Root
        $failed.outcome | Should -BeExactly 'build-failed'
        $failed.buildLineageId | Should -Match '^loopback:'

        $first = Start-FactoryLoopRepairInvocation -RepoRoot $failure.Root -PlanReference '961e7d'
        $second = Start-FactoryLoopRepairInvocation -RepoRoot $failure.Root -PlanReference '961e7d'
        $first.attempt | Should -Be 1
        $second.attempt | Should -Be 2
        {
            Start-FactoryLoopRepairInvocation -RepoRoot $failure.Root -PlanReference '961e7d'
        } | Should -Throw '*Factory repair budget exhausted*'

        $checkpoint = Read-FactoryLoopRuntimeFixtureCheckpoint -RepoRoot $failure.Root
        $checkpoint.repairPullRequestsReserved | Should -Be 2
        $checkpoint.repairBuildLineages[0].correctiveCalls | Should -Be 2
        $first.buildLineageId | Should -BeExactly $second.buildLineageId

        $unusual = New-FactoryLoopRuntimeFixture -LeaveDefect
        [void](Invoke-FactoryLoopTick -RepoRoot $unusual.Root)
        [void](Invoke-FactoryLoopTick -RepoRoot $unusual.Root)
        $unusualCheckpoint = Read-FactoryLoopRuntimeFixtureCheckpoint -RepoRoot $unusual.Root
        $unusualCheckpoint.repairIncidentId = '../***'
        [System.IO.File]::WriteAllText(
            (Join-Path $unusual.Root '.factory-loop/checkpoint.json'),
            (ConvertTo-Json -InputObject $unusualCheckpoint -Depth 40),
            [System.Text.UTF8Encoding]::new($false)
        )
        $safeBranch = Start-FactoryLoopRepairInvocation -RepoRoot $unusual.Root -PlanReference '961e7d'
        $safeBranch.branch | Should -Match '^factory-repair/incident-'
        git -C $unusual.Root check-ref-format --branch $safeBranch.branch
        $LASTEXITCODE | Should -Be 0
    }

    It 'test:FactoryLoop.Credits records repair calls idempotently by execution identity' {
        $planFolder = Join-Path $TestDrive 'factory-repair-plan'
        [void](New-Item -ItemType Directory -Path (Join-Path $planFolder 'assets') -Force)
        @'
# Factory repair credit fixture
<!-- plan-id: 961e7d -->
'@ | Set-Content -LiteralPath (Join-Path $planFolder 'plan.md') -Encoding utf8NoBOM
        $usagePath = Join-Path $TestDrive 'factory-repair-usage.json'
        @{
            totalNanoAiu = 500000000
            tokenDetails = @{
                input = @{ tokenCount = 10 }
                cache_read = @{ tokenCount = 0 }
                cache_write = @{ tokenCount = 0 }
                output = @{ tokenCount = 5 }
            }
            sessionStartTime = '2026-09-05T17:28:57.320Z'
            modelMetrics = @{ 'gpt-5.6-luna' = @{ totalNanoAiu = 500000000 } }
        } | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath $usagePath -Encoding utf8NoBOM

        $recorder = Join-Path $script:repoRoot 'plugins/autopilot/scripts/Record-AiCreditUsage.ps1'
        1..2 | ForEach-Object {
            & $recorder -PlanFolder $planFolder -UsagePath $usagePath `
                -Target factory-repair-call-1 -Runtime host `
                -ModelAlias primary-model-low -ContextTier default | Out-Null
        }
        $ledger = Get-Content -LiteralPath (Join-Path $planFolder 'assets/ai-credits.json') -Raw |
            ConvertFrom-Json -Depth 20
        @($ledger.executions) | Should -HaveCount 1
        $ledger.executions[0].target | Should -BeExactly 'factory-repair-call-1'
        $ledger.totalNanoAiu | Should -Be 500000000
    }

    It 'test:FactoryLoop.DeploymentIdentity test:FactoryLoop.FaultMatrix pins deployment and version to the merge artifact' {
        $fixture = New-FactoryLoopRuntimeFixture
        [void](Complete-FactoryLoopRuntimeMerge -Fixture $fixture)

        $triggered = Invoke-FactoryLoopTick -RepoRoot $fixture.Root
        $triggered.stage | Should -BeExactly 'test-deployment-check'
        $triggered.artifactDigest | Should -Match '^[0-9a-f]{64}$'
        $checkpoint = Read-FactoryLoopRuntimeFixtureCheckpoint -RepoRoot $fixture.Root
        $checkpoint.artifactPath | Should -Match ([regex]::Escape($checkpoint.artifactDigest) + '$')
        Test-Path -LiteralPath (Join-Path $checkpoint.artifactPath 'Invoke-Acceptance.ps1') |
            Should -BeTrue

        $app = Join-Path $fixture.Root 'application/Invoke-DemoApp.ps1'
        Add-Content -LiteralPath $app -Value "`n# A later working-tree edit." -Encoding utf8NoBOM
        $checkpoint.artifactPath | Should -Match ([regex]::Escape($checkpoint.artifactDigest) + '$')

        [void](Invoke-FactoryLoopTick -RepoRoot $fixture.Root)
        $statePath = Join-Path $fixture.Root '.factory-loop/loopback.json'
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -AsHashtable -Depth 40
        $state.deployments[0].version = 'superseded-version'
        [System.IO.File]::WriteAllText(
            $statePath,
            (ConvertTo-Json -InputObject $state -Depth 40),
            [System.Text.UTF8Encoding]::new($false)
        )
        $version = Invoke-FactoryLoopTick -RepoRoot $fixture.Root
        $version.outcome | Should -BeExactly 'blocked'
        $version.reason | Should -BeExactly 'test-running-version-does-not-match-artifact'
    }

    It 'test:FactoryLoop.Acceptance runs the real test application from its immutable artifact' {
        $fixture = New-FactoryLoopRuntimeFixture
        $accepted = Complete-FactoryLoopTestAcceptance -Fixture $fixture
        $accepted.outcome | Should -BeExactly 'test-acceptance-passed'
        $accepted.stage | Should -BeExactly 'telemetry-observation'
        $checkpoint = Read-FactoryLoopRuntimeFixtureCheckpoint -RepoRoot $fixture.Root
        $state = Get-Content -LiteralPath (Join-Path $fixture.Root '.factory-loop/loopback.json') -Raw |
            ConvertFrom-Json -AsHashtable -Depth 50
        $state.acceptances[0].status | Should -BeExactly 'passed'
        $state.acceptances[0].artifactDigest | Should -BeExactly $checkpoint.artifactDigest
        $state.acceptances[0].environment | Should -BeExactly 'test'
    }

    It 'test:FactoryLoop.Telemetry test:FactoryLoop.FaultMatrix observes without sleeps and blocks missing access' {
        $clockBase = [datetime]::new(2026, 10, 3, 12, 0, 0, [datetimekind]::Utc)
        $clock = New-FactoryLoopFixedClock -Time $clockBase
        $fixture = New-FactoryLoopRuntimeFixture
        [void](Complete-FactoryLoopTestAcceptance -Fixture $fixture -Clock $clock)
        $checkpoint = Read-FactoryLoopRuntimeFixtureCheckpoint -RepoRoot $fixture.Root
        $checkpoint.observationSeconds | Should -Be 300
        $almostDone = Invoke-FactoryLoopTick -RepoRoot $fixture.Root `
            -Clock (New-FactoryLoopFixedClock -Time $clockBase.AddSeconds(299))
        $almostDone.stage | Should -BeExactly 'telemetry-observation'
        $observed = Invoke-FactoryLoopTick -RepoRoot $fixture.Root `
            -Clock (New-FactoryLoopFixedClock -Time $clockBase.AddSeconds(300))
        $observed.stage | Should -BeExactly 'awaiting-production-approval'
        $observed.outcome | Should -BeExactly 'test-accepted'
        $observed.aiCalls | Should -Be 0

        $blockedFixture = New-FactoryLoopRuntimeFixture
        $blockedAdapter = {
            param($Domain, $Action, $OperationId, $Payload)
            if ($Domain -ceq 'telemetry') {
                $Payload.accessible = $false
            }
            Invoke-FactoryLoopLoopback -RepoRoot $blockedFixture.Root -Domain $Domain `
                -Action $Action -OperationId $OperationId -Payload $Payload
        }.GetNewClosure()
        [void](Complete-FactoryLoopTestAcceptance -Fixture $blockedFixture `
            -Clock $clock -AdapterRunner $blockedAdapter)
        $access = Invoke-FactoryLoopTick -RepoRoot $blockedFixture.Root `
            -Clock $clock -AdapterRunner $blockedAdapter
        $access.outcome | Should -BeExactly 'blocked'
        $access.reason | Should -BeExactly 'telemetry-access-or-coverage-inconclusive'
    }

    It 'test:FactoryLoop.ProductionApproval requires and binds human approval to the exact artifact' {
        $clockBase = [datetime]::new(2026, 10, 3, 12, 0, 0, [datetimekind]::Utc)
        $fixture = New-FactoryLoopRuntimeFixture
        [void](Complete-FactoryLoopTestAcceptance -Fixture $fixture `
            -Clock (New-FactoryLoopFixedClock -Time $clockBase))
        $clock = New-FactoryLoopFixedClock -Time $clockBase.AddSeconds(300)
        $telemetry = Invoke-FactoryLoopTick -RepoRoot $fixture.Root -Clock $clock
        $telemetry.stage | Should -BeExactly 'awaiting-production-approval'
        $pending = Invoke-FactoryLoopTick -RepoRoot $fixture.Root -Clock $clock
        $pending.outcome | Should -BeExactly 'waiting-for-production-approval'
        $pending.aiCalls | Should -Be 0

        $checkpoint = Read-FactoryLoopRuntimeFixtureCheckpoint -RepoRoot $fixture.Root
        $approved = Invoke-FactoryLoopLoopback -RepoRoot $fixture.Root -Domain approval `
            -Action approve -OperationId 'operator:approve:exact-artifact' `
            -Payload @{ artifactDigest = [string]$checkpoint.artifactDigest; confirm = $true }
        $approved.status | Should -BeExactly 'ok'
        $promotion = Invoke-FactoryLoopTick -RepoRoot $fixture.Root -Clock $clock
        $promotion.stage | Should -BeExactly 'production-deployment'

        $prodDeployment = Invoke-FactoryLoopTick -RepoRoot $fixture.Root -Clock $clock
        $prodDeployment.stage | Should -BeExactly 'production-deployment-check'
        [void](Invoke-FactoryLoopTick -RepoRoot $fixture.Root -Clock $clock)
        [void](Invoke-FactoryLoopTick -RepoRoot $fixture.Root -Clock $clock)
        $prodAcceptance = Invoke-FactoryLoopTick -RepoRoot $fixture.Root -Clock $clock
        $prodAcceptance.stage | Should -BeExactly 'awaiting-evidence'
        $final = Read-FactoryLoopRuntimeFixtureCheckpoint -RepoRoot $fixture.Root
        $final.artifactDigest | Should -BeExactly $checkpoint.artifactDigest
        $final.productionDeploymentProviderId | Should -Not -BeNullOrEmpty
        $state = Get-Content -LiteralPath (Join-Path $fixture.Root '.factory-loop/loopback.json') -Raw |
            ConvertFrom-Json -AsHashtable -Depth 50
        @($state.acceptances | Where-Object environment -CEQ 'prod' |
            Where-Object artifactDigest -CEQ $checkpoint.artifactDigest) | Should -HaveCount 1
    }

    It 'test:FactoryLoop.ProductionApproval test:FactoryLoop.FaultMatrix blocks a declined production request' {
        $clockBase = [datetime]::new(2026, 10, 3, 12, 0, 0, [datetimekind]::Utc)
        $clock = New-FactoryLoopFixedClock -Time $clockBase
        $fixture = New-FactoryLoopRuntimeFixture
        [void](Complete-FactoryLoopTestAcceptance -Fixture $fixture -Clock $clock)
        $clock = New-FactoryLoopFixedClock -Time $clockBase.AddSeconds(300)
        [void](Invoke-FactoryLoopTick -RepoRoot $fixture.Root -Clock $clock)
        $pending = Invoke-FactoryLoopTick -RepoRoot $fixture.Root -Clock $clock
        $checkpoint = Read-FactoryLoopRuntimeFixtureCheckpoint -RepoRoot $fixture.Root
        [void](Invoke-FactoryLoopLoopback -RepoRoot $fixture.Root -Domain approval `
            -Action decline -OperationId 'operator:decline:exact-artifact' `
            -Payload @{ artifactDigest = [string]$checkpoint.artifactDigest; confirm = $true })
        $declined = Invoke-FactoryLoopTick -RepoRoot $fixture.Root -Clock $clock
        $declined.outcome | Should -BeExactly 'blocked'
        $declined.reason | Should -BeExactly 'production-promotion-declined'
        (Read-FactoryLoopRuntimeFixtureCheckpoint -RepoRoot $fixture.Root).stage |
            Should -BeExactly 'blocked'
    }

    It 'test:FactoryLoop.InaccessibleProduction test:FactoryLoop.FaultMatrix blocks a promotion without deployment access' {
        $clockBase = [datetime]::new(2026, 10, 3, 12, 0, 0, [datetimekind]::Utc)
        $clock = New-FactoryLoopFixedClock -Time $clockBase
        $fixture = New-FactoryLoopRuntimeFixture
        [void](Complete-FactoryLoopTestAcceptance -Fixture $fixture -Clock $clock)
        $clock = New-FactoryLoopFixedClock -Time $clockBase.AddSeconds(300)
        [void](Invoke-FactoryLoopTick -RepoRoot $fixture.Root -Clock $clock)
        [void](Invoke-FactoryLoopTick -RepoRoot $fixture.Root -Clock $clock)
        $checkpoint = Read-FactoryLoopRuntimeFixtureCheckpoint -RepoRoot $fixture.Root
        [void](Invoke-FactoryLoopLoopback -RepoRoot $fixture.Root -Domain approval `
            -Action approve -OperationId 'operator:approve:exact-artifact' `
            -Payload @{ artifactDigest = [string]$checkpoint.artifactDigest; confirm = $true })
        [void](Invoke-FactoryLoopTick -RepoRoot $fixture.Root -Clock $clock)
        $blockedAdapter = {
            param($Domain, $Action, $OperationId, $Payload)
            if ($Domain -ceq 'deployment' -and $Action -ceq 'trigger' -and
                $Payload.environment -ceq 'prod') {
                return @{
                    schemaVersion = 1
                    domain = $Domain
                    action = $Action
                    operationId = $OperationId
                    status = 'blocked'
                    providerId = 'loopback:deployment'
                    data = @{ reason = 'access-unavailable' }
                }
            }
            Invoke-FactoryLoopLoopback -RepoRoot $fixture.Root -Domain $Domain `
                -Action $Action -OperationId $OperationId -Payload $Payload
        }.GetNewClosure()
        $blocked = Invoke-FactoryLoopTick -RepoRoot $fixture.Root `
            -Clock $clock -AdapterRunner $blockedAdapter
        $blocked.outcome | Should -BeExactly 'blocked'
        $blocked.reason | Should -BeExactly 'production-deployment-identity-unavailable'
    }

    It 'test:FactoryLoop.Evidence commits sanitized version-bound evidence before closing the item' {
        $fixture = New-FactoryLoopRuntimeFixture
        $accepted = Complete-FactoryLoopTestProductionAcceptance -Fixture $fixture
        $accepted.stage | Should -BeExactly 'awaiting-evidence'
        Enable-FactoryLoopTestEvidenceBranch -RepoRoot $fixture.Root

        $recordedAt = [datetime]::new(2026, 10, 3, 12, 6, 0, [datetimekind]::Utc)
        $evidenceClock = New-FactoryLoopFixedClock -Time $recordedAt
        $evidenceReady = Invoke-FactoryLoopTick -RepoRoot $fixture.Root -Clock $evidenceClock
        $evidenceReady.stage | Should -BeExactly 'publishing-evidence'
        $checkpoint = Read-FactoryLoopRuntimeFixtureCheckpoint -RepoRoot $fixture.Root
        $checkpoint.evidenceBranch | Should -Match '^factory-loop-evidence/'
        $checkpoint.evidenceCommit | Should -Match '^[0-9a-f]{40}$'
        $checkpoint.evidencePath | Should -Match '^docs/factory-loop/evidence/[0-9a-f]{64}\.json$'
        ([datetime]$checkpoint.evidenceRecordedAtUtc).ToUniversalTime().ToString('o') |
            Should -BeExactly $recordedAt.ToString('o')
        git -C $fixture.Root merge-base --is-ancestor $checkpoint.mergeCommit $checkpoint.evidenceCommit
        $LASTEXITCODE | Should -Be 0
        $evidenceJson = (git -C $fixture.Root show "$($checkpoint.evidenceCommit):$($checkpoint.evidencePath)") -join "`n"
        $evidence = $evidenceJson | ConvertFrom-Json -Depth 20
        $evidence.artifactDigest | Should -BeExactly $checkpoint.artifactDigest
        $evidence.workItemId | Should -BeExactly $checkpoint.workItemId
        $evidence.mergeCommit | Should -BeExactly $checkpoint.mergeCommit
        $evidence.testAcceptance | Should -BeExactly 'passed'
        $evidence.productionAcceptance | Should -BeExactly 'passed'
        ([datetime]$evidence.evidenceRecordedAtUtc).ToUniversalTime().ToString('o') |
            Should -BeExactly $recordedAt.ToString('o')
        @(Find-HighConfidenceSecret -Value $evidenceJson) | Should -BeNullOrEmpty

        $published = Invoke-FactoryLoopTick -RepoRoot $fixture.Root
        $published.stage | Should -BeExactly 'closing-work-item'
        $completed = Invoke-FactoryLoopTick -RepoRoot $fixture.Root
        $completed.outcome | Should -BeExactly 'completed'
        $completed.status | Should -BeExactly 'completed'
        $completed.evidenceBranch | Should -BeExactly $checkpoint.evidenceBranch
        $completed.evidenceCommit | Should -BeExactly $checkpoint.evidenceCommit

        $state = Get-Content -LiteralPath (Join-Path $fixture.Root '.factory-loop/loopback.json') -Raw |
            ConvertFrom-Json -AsHashtable -Depth 50
        @($state.evidence | Where-Object {
                [string]$_.artifactDigest -ceq [string]$checkpoint.artifactDigest
            }) | Should -HaveCount 1
        @($state.workItems | Where-Object {
                [string]$_.id -ceq [string]$checkpoint.workItemId -and [string]$_.status -ceq 'closed'
            }) | Should -HaveCount 1
        (Invoke-FactoryLoopTick -RepoRoot $fixture.Root).outcome | Should -BeExactly 'completed'
    }

    It 'test:FactoryLoop.Evidence refuses symlinked evidence directories' {
        $worktree = Join-Path $TestDrive ('evidence-link-' + [guid]::NewGuid().ToString('N'))
        $outside = Join-Path $TestDrive ('evidence-outside-' + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $worktree -Force)
        [void](New-Item -ItemType Directory -Path $outside -Force)
        $docsPath = Join-Path $worktree 'docs'
        if ($IsWindows) {
            [void](New-Item -ItemType Junction -Path $docsPath -Target $outside)
        }
        else {
            [void][System.IO.Directory]::CreateSymbolicLink($docsPath, $outside)
        }

        $runtimeModule = Get-Module -Name FactoryLoop.Runtime
        {
            & $runtimeModule {
                param($root)
                Resolve-FactoryLoopEvidencePath -Worktree $root -EvidenceKey ('a' * 64)
            } $worktree
        } | Should -Throw '*symbolic links or reparse points*'
        (Test-Path -LiteralPath (Join-Path $outside 'factory-loop')) | Should -BeFalse
    }

    It 'test:FactoryLoop.Evidence hashes provider IDs instead of using them as path components' {
        $fixture = New-FactoryLoopRuntimeFixture
        [void](Complete-FactoryLoopTestProductionAcceptance -Fixture $fixture)
        Enable-FactoryLoopTestEvidenceBranch -RepoRoot $fixture.Root
        $checkpoint = Read-FactoryLoopRuntimeFixtureCheckpoint -RepoRoot $fixture.Root
        $checkpoint.workItemId = '..\..\..\..\outside'
        $checkpoint.evidenceRecordedAtUtc = (
            [datetime]::new(2026, 10, 3, 12, 6, 0, [datetimekind]::Utc).ToString('o')
        )
        $configuration = Get-Content -LiteralPath (
            Join-Path $fixture.Root '.factory-loop/factory-loop.json'
        ) -Raw | ConvertFrom-Json -AsHashtable -Depth 20
        $runtimeModule = Get-Module -Name FactoryLoop.Runtime
        $evidence = & $runtimeModule {
            param($root, $chain, $config)
            New-FactoryLoopEvidenceCommit -RepoRoot $root -Checkpoint $chain -Configuration $config
        } $fixture.Root $checkpoint $configuration

        $evidence.relativePath | Should -Match '^docs/factory-loop/evidence/[0-9a-f]{64}\.json$'
        $escapedPath = Join-Path (Split-Path $fixture.Root -Parent) `
            "outside-$($checkpoint.artifactDigest).json"
        (Test-Path -LiteralPath $escapedPath) | Should -BeFalse
        $evidenceJson = (git -C $fixture.Root show "$($evidence.commit):$($evidence.relativePath)") -join "`n"
        $record = $evidenceJson | ConvertFrom-Json -Depth 20
        $record.workItemId | Should -BeExactly '..\..\..\..\outside'
    }

    It 'test:FactoryLoop.Completion blocks until the evidence branch exclusion is verified' {
        $fixture = New-FactoryLoopRuntimeFixture
        [void](Complete-FactoryLoopTestProductionAcceptance -Fixture $fixture)
        $blocked = Invoke-FactoryLoopTick -RepoRoot $fixture.Root
        $blocked.outcome | Should -BeExactly 'blocked'
        $blocked.reason | Should -BeExactly 'evidence-branch-deployment-exclusion-unverified'
        (Read-FactoryLoopRuntimeFixtureCheckpoint -RepoRoot $fixture.Root).stage |
            Should -BeExactly 'blocked'
    }

    It 'test:FactoryLoop.Restart test:FactoryLoop.FaultMatrix reconciles evidence and closure crashes' {
        $fixture = New-FactoryLoopRuntimeFixture
        [void](Complete-FactoryLoopTestProductionAcceptance -Fixture $fixture)
        Enable-FactoryLoopTestEvidenceBranch -RepoRoot $fixture.Root
        [void](Invoke-FactoryLoopTick -RepoRoot $fixture.Root)

        $afterEvidencePublish = {
            param($Result)
            if ([string]$Result.domain -ceq 'evidence' -and [string]$Result.action -ceq 'publish') {
                throw 'interrupt-after-evidence-publish'
            }
        }
        { Invoke-FactoryLoopTick -RepoRoot $fixture.Root -AfterDispatch $afterEvidencePublish } |
            Should -Throw '*interrupt-after-evidence-publish*'
        $pendingPublish = Read-FactoryLoopRuntimeFixtureCheckpoint -RepoRoot $fixture.Root
        $pendingPublish.pendingOperation.operationId |
            Should -BeExactly "$($fixture.ChainId):evidence:publish:$($pendingPublish.artifactDigest)"
        $recordedAt = ([datetime]$pendingPublish.evidenceRecordedAtUtc).ToUniversalTime().ToString('o')
        $recordedAt | Should -Not -BeNullOrEmpty
        [void](Invoke-FactoryLoopTick -RepoRoot $fixture.Root)
        (Read-FactoryLoopRuntimeFixtureCheckpoint -RepoRoot $fixture.Root).stage |
            Should -BeExactly 'closing-work-item'
        $recoveredCheckpoint = Read-FactoryLoopRuntimeFixtureCheckpoint -RepoRoot $fixture.Root
        ([datetime]$recoveredCheckpoint.evidenceRecordedAtUtc).ToUniversalTime().ToString('o') |
            Should -BeExactly $recordedAt

        $afterClose = {
            param($Result)
            if ([string]$Result.domain -ceq 'work-item' -and [string]$Result.action -ceq 'close') {
                throw 'interrupt-after-work-item-close'
            }
        }
        { Invoke-FactoryLoopTick -RepoRoot $fixture.Root -AfterDispatch $afterClose } |
            Should -Throw '*interrupt-after-work-item-close*'
        $pendingClose = Read-FactoryLoopRuntimeFixtureCheckpoint -RepoRoot $fixture.Root
        $pendingClose.pendingOperation.operationId |
            Should -BeExactly "$($fixture.ChainId):work-item:close:$($pendingClose.workItemId):$($pendingClose.artifactDigest)"
        $recovered = Invoke-FactoryLoopTick -RepoRoot $fixture.Root
        $recovered.outcome | Should -BeExactly 'completed'
        $state = Get-Content -LiteralPath (Join-Path $fixture.Root '.factory-loop/loopback.json') -Raw |
            ConvertFrom-Json -AsHashtable -Depth 50
        @($state.evidence | Where-Object {
                [string]$_.artifactDigest -ceq [string]$pendingClose.artifactDigest
            }) | Should -HaveCount 1
        @($state.operations | Where-Object {
                [string]$_.operationId -ceq [string]$pendingClose.pendingOperation.operationId
            }) | Should -HaveCount 1
    }

    It 'test:FactoryLoop.EndToEnd replays the installed global runtime through immutable production evidence' {
            $manifest = Get-Content -LiteralPath (Join-Path $script:pluginRoot 'plugin.json') -Raw |
                ConvertFrom-Json -Depth 30
            $globalPlugin = Join-Path $TestDrive 'installed-global/factory-loop'
            [void](New-Item -ItemType Directory -Path $globalPlugin -Force)
            foreach ($file in @($manifest.files)) {
                $source = Join-Path $script:pluginRoot ([string]$file.src)
                $destination = Join-Path $globalPlugin ([string]$file.dest)
                [void](New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force)
                Copy-Item -LiteralPath $source -Destination $destination
            }

            $fixture = New-FactoryLoopRuntimeFixture -SkipChainInitialization
            $startScript = Join-Path $globalPlugin 'skills/factory-loop/scripts/Start-FactoryLoopChain.ps1'
            $started = & $startScript -RepoRoot $fixture.Root -ChainId $fixture.ChainId `
                -WorkItemId $fixture.WorkItemId -PlanReference '961e7d' `
                -Branch $fixture.Branch -SourceSha $fixture.SourceSha | ConvertFrom-Json -AsHashtable -Depth 20
            $started.chainId | Should -BeExactly $fixture.ChainId

            $runtimePath = Join-Path $globalPlugin 'skills/factory-loop/scripts/FactoryLoop.Runtime.psm1'
            $runtime = Import-Module -Name $runtimePath -Force -PassThru -DisableNameChecking
            $tick = {
                param($RepoRoot, $Clock)
                Invoke-FactoryLoopTick -RepoRoot $RepoRoot -Clock $Clock
            }.GetNewClosure()
            $tickOnce = {
                param($Clock)
                & $runtime $tick $fixture.Root $Clock
            }.GetNewClosure()

            $adapterScript = Join-Path $globalPlugin 'skills/factory-loop/scripts/Invoke-FactoryLoopAdapter.ps1'
            $adapter = {
                param($Domain, $Action, $OperationId, $Payload)
                & $adapterScript -RepoRoot $fixture.Root -Domain $Domain -Action $Action `
                    -OperationId $OperationId -PayloadJson (ConvertTo-Json -InputObject $Payload -Depth 20 -Compress) |
                    ConvertFrom-Json -AsHashtable -Depth 30
            }.GetNewClosure()
            $clockBase = [datetime]::new(2026, 10, 3, 12, 0, 0, [datetimekind]::Utc)
            $clock = New-FactoryLoopFixedClock -Time $clockBase
            @((Get-Module -Name $runtime.Name | Where-Object { $_.Path -ceq $runtimePath })) |
                Should -HaveCount 1

            $opened = & $tickOnce $clock
            $opened.stage | Should -BeExactly 'awaiting-checks'
            $checked = & $tickOnce $clock
            $checked.stage | Should -BeExactly 'awaiting-merge'
            git -C $fixture.Root switch main --quiet
            if ($LASTEXITCODE -ne 0) { throw 'Unable to switch to main for the installed demo merge.' }
            $merged = & $adapter 'pull-request' 'merge' "$($fixture.ChainId):installed-human-merge" @{
                pullRequestId = 'PR-0001'
                demoRoot = $fixture.Root
                expectedSourceSha = $fixture.SourceSha
                confirmMerge = $true
            }
            $merged.status | Should -BeExactly 'ok'
            $mergeCommit = [string]$merged.data.pullRequest.mergeCommit
            $mergeCommit | Should -Not -BeExactly $fixture.SourceSha

            [void](& $tickOnce $clock)
            [void](& $tickOnce $clock)
            [void](& $tickOnce $clock)
            [void](& $tickOnce $clock)
            $testAccepted = & $tickOnce $clock
            $testAccepted.stage | Should -BeExactly 'telemetry-observation'
            $checkpoint = Read-FactoryLoopRuntimeFixtureCheckpoint -RepoRoot $fixture.Root
            $checkpoint.artifactDigest | Should -Match '^[0-9a-f]{64}$'
            $checkpoint.mergeCommit | Should -BeExactly $mergeCommit
            (Test-FactoryLoopArtifactAcceptance -ArtifactPath $checkpoint.artifactPath `
                    -ExpectedDigest $checkpoint.artifactDigest -Environment test).status | Should -BeExactly 'passed'

            $productionClock = New-FactoryLoopFixedClock -Time $clockBase.AddSeconds(300)
            $telemetry = & $tickOnce $productionClock
            $telemetry.stage | Should -BeExactly 'awaiting-production-approval'
            [void](& $tickOnce $productionClock)
            $approval = & $adapter 'approval' 'approve' "$($fixture.ChainId):installed-operator-approval" @{
                artifactDigest = [string]$checkpoint.artifactDigest
                confirm = $true
            }
            $approval.status | Should -BeExactly 'ok'
            [void](& $tickOnce $productionClock)
            [void](& $tickOnce $productionClock)
            [void](& $tickOnce $productionClock)
            [void](& $tickOnce $productionClock)
            $productionAccepted = & $tickOnce $productionClock
            $productionAccepted.stage | Should -BeExactly 'awaiting-evidence'

            Enable-FactoryLoopTestEvidenceBranch -RepoRoot $fixture.Root
            $evidence = & $tickOnce $clock
            $evidence.stage | Should -BeExactly 'publishing-evidence'
            $evidence = & $tickOnce $clock
            $evidence.stage | Should -BeExactly 'closing-work-item'
            $completed = & $tickOnce $clock
            $completed.outcome | Should -BeExactly 'completed'
            $completed.artifactDigest | Should -BeExactly $checkpoint.artifactDigest
            $completed.evidenceCommit | Should -Match '^[0-9a-f]{40}$'

            $state = Get-Content -LiteralPath (Join-Path $fixture.Root '.factory-loop/loopback.json') -Raw |
                ConvertFrom-Json -AsHashtable -Depth 50
            @($state.acceptances | Where-Object {
                    [string]$_.artifactDigest -ceq [string]$checkpoint.artifactDigest -and
                    [string]$_.status -ceq 'passed'
                }) | Should -HaveCount 2
            git -C $fixture.Root merge-base --is-ancestor $completed.evidenceCommit main
            $LASTEXITCODE | Should -Not -Be 0
            git -C $fixture.Root status --porcelain | Should -BeNullOrEmpty
    }

    It 'test:FactoryLoop.EndToEnd test:FactoryLoop.FaultMatrix completes a deployed-defect repair through closure' {
        $fixture = New-FactoryLoopRuntimeFixture
        $acceptanceFailure = [hashtable]::Synchronized(@{ ArtifactDigest = $null })
        $failedAcceptanceAdapter = {
            param($Domain, $Action, $OperationId, $Payload)
            if ($Domain -ceq 'acceptance' -and $Payload.environment -ceq 'test') {
                if ($null -eq $acceptanceFailure.ArtifactDigest) {
                    $acceptanceFailure.ArtifactDigest = [string]$Payload.artifactDigest
                }
                $result = Invoke-FactoryLoopLoopback -RepoRoot $fixture.Root -Domain $Domain `
                    -Action $Action -OperationId $OperationId -Payload $Payload
                if ([string]$Payload.artifactDigest -ceq [string]$acceptanceFailure.ArtifactDigest) {
                    $result.data.acceptance.status = 'failed'
                    $statePath = Join-Path $fixture.Root '.factory-loop/loopback.json'
                    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -AsHashtable -Depth 50
                    $record = @($state.acceptances | Where-Object {
                            [string]$_.operationId -ceq $OperationId
                        } | Select-Object -Last 1)
                    if ($record.Count -ne 1) { throw 'Unable to record the injected acceptance failure.' }
                    $record[0].status = 'failed'
                    Set-Content -LiteralPath $statePath -Value ($state | ConvertTo-Json -Depth 50) `
                        -Encoding utf8NoBOM
                }
                return $result
            }
            Invoke-FactoryLoopLoopback -RepoRoot $fixture.Root -Domain $Domain `
                -Action $Action -OperationId $OperationId -Payload $Payload
        }.GetNewClosure()
        $bug = Complete-FactoryLoopTestAcceptance -Fixture $fixture `
            -AdapterRunner $failedAcceptanceAdapter
        $bug.outcome | Should -BeExactly 'bug-opened'
        $bug.stage | Should -BeExactly 'repair-needed'
        $bug.bugWorkItemId | Should -Match '^WI-'

        $waiting = Invoke-FactoryLoopFixtureTick -RepoRoot $fixture.Root `
            -AdapterRunner $failedAcceptanceAdapter
        $waiting.stage | Should -BeExactly 'repair-needed'
        $waiting.bugWorkItemId | Should -BeExactly $bug.bugWorkItemId
        $state = Get-Content -LiteralPath (Join-Path $fixture.Root '.factory-loop/loopback.json') -Raw |
            ConvertFrom-Json -AsHashtable -Depth 50
        @($state.workItems | Where-Object { [string]$_.dedupeKey -like '*bug:*' }) |
            Should -HaveCount 1

        $checkpoint = Read-FactoryLoopRuntimeFixtureCheckpoint -RepoRoot $fixture.Root
        $lineage = [string]$checkpoint.repairBuildLineageId
        $invocation = Start-FactoryLoopRepairInvocation -RepoRoot $fixture.Root `
            -PlanReference '961e7d'
        $invocation.incidentId | Should -BeExactly $fixture.WorkItemId
        git -C $fixture.Root switch $invocation.branch --quiet
        if ($LASTEXITCODE -ne 0) { throw 'Unable to switch to the acceptance repair branch.' }
        $appScript = Join-Path $fixture.Root 'application/Invoke-DemoApp.ps1'
        $fixed = (Get-Content -LiteralPath $appScript -Raw).Replace(
            '$Subtotal * (1 - $DiscountRate)',
            '$Subtotal - ($Subtotal * $DiscountRate)'
        )
        $fixed | Should -Not -BeExactly (Get-Content -LiteralPath $appScript -Raw)
        Set-Content -LiteralPath $appScript -Value $fixed -NoNewline -Encoding utf8NoBOM
        git -C $fixture.Root add -- application/Invoke-DemoApp.ps1
        git -C $fixture.Root -c user.name='Factory Loop Demo' `
            -c user.email='factory-loop-demo@localhost' commit --quiet -m 'Repair failed acceptance'
        if ($LASTEXITCODE -ne 0) { throw 'Unable to commit the acceptance repair.' }
        $repairSha = (git -C $fixture.Root rev-parse HEAD).Trim()
        [void](Register-FactoryLoopRepairPullRequest -RepoRoot $fixture.Root `
            -IncidentId $fixture.WorkItemId -BuildLineageId $lineage `
            -Branch $invocation.branch -SourceSha $repairSha)
        [void](Invoke-FactoryLoopTick -RepoRoot $fixture.Root `
            -AdapterRunner $failedAcceptanceAdapter)
        $repairChecks = Invoke-FactoryLoopTick -RepoRoot $fixture.Root `
            -AdapterRunner $failedAcceptanceAdapter
        $repairChecks.stage | Should -BeExactly 'awaiting-merge'

        git -C $fixture.Root switch main --quiet
        if ($LASTEXITCODE -ne 0) { throw 'Unable to switch to main for the repair merge.' }
        [void](Invoke-FactoryLoopLoopback -RepoRoot $fixture.Root -Domain pull-request `
            -Action merge -OperationId "$($fixture.ChainId):human-merge:repair" `
            -Payload @{
                pullRequestId = 'PR-0002'
                demoRoot = $fixture.Root
                expectedSourceSha = $repairSha
                confirmMerge = $true
            })
        $clockBase = [datetime]::new(2026, 10, 3, 12, 0, 0, [datetimekind]::Utc)
        $testDeployment = Invoke-FactoryLoopTick -RepoRoot $fixture.Root `
            -Clock (New-FactoryLoopFixedClock -Time $clockBase) `
            -AdapterRunner $failedAcceptanceAdapter
        $testDeployment.stage | Should -BeExactly 'test-deployment'
        [void](Invoke-FactoryLoopTick -RepoRoot $fixture.Root `
            -Clock (New-FactoryLoopFixedClock -Time $clockBase) -AdapterRunner $failedAcceptanceAdapter)
        [void](Invoke-FactoryLoopTick -RepoRoot $fixture.Root `
            -Clock (New-FactoryLoopFixedClock -Time $clockBase) -AdapterRunner $failedAcceptanceAdapter)
        [void](Invoke-FactoryLoopTick -RepoRoot $fixture.Root `
            -Clock (New-FactoryLoopFixedClock -Time $clockBase) -AdapterRunner $failedAcceptanceAdapter)
        $repairedAcceptance = Invoke-FactoryLoopTick -RepoRoot $fixture.Root `
            -Clock (New-FactoryLoopFixedClock -Time $clockBase) -AdapterRunner $failedAcceptanceAdapter
        $repairedAcceptance.outcome | Should -BeExactly 'test-acceptance-passed'
        $checkpoint = Read-FactoryLoopRuntimeFixtureCheckpoint -RepoRoot $fixture.Root
        $checkpoint.artifactDigest | Should -Not -BeExactly $acceptanceFailure.ArtifactDigest
        $state = Get-Content -LiteralPath (Join-Path $fixture.Root '.factory-loop/loopback.json') -Raw |
            ConvertFrom-Json -AsHashtable -Depth 50
        @($state.workItems | Where-Object {
                [string]$_.id -ceq [string]$bug.bugWorkItemId -and [string]$_.status -ceq 'open'
            }) | Should -HaveCount 1

        $clock = New-FactoryLoopFixedClock -Time $clockBase.AddSeconds(300)
        [void](Invoke-FactoryLoopTick -RepoRoot $fixture.Root -Clock $clock -AdapterRunner $failedAcceptanceAdapter)
        [void](Invoke-FactoryLoopTick -RepoRoot $fixture.Root -Clock $clock -AdapterRunner $failedAcceptanceAdapter)
        $checkpoint = Read-FactoryLoopRuntimeFixtureCheckpoint -RepoRoot $fixture.Root
        [void](Invoke-FactoryLoopLoopback -RepoRoot $fixture.Root -Domain approval `
            -Action approve -OperationId "$($fixture.ChainId):operator:approve-repaired-artifact" `
            -Payload @{ artifactDigest = [string]$checkpoint.artifactDigest; confirm = $true })
        [void](Invoke-FactoryLoopTick -RepoRoot $fixture.Root -Clock $clock -AdapterRunner $failedAcceptanceAdapter)
        [void](Invoke-FactoryLoopTick -RepoRoot $fixture.Root -Clock $clock -AdapterRunner $failedAcceptanceAdapter)
        [void](Invoke-FactoryLoopTick -RepoRoot $fixture.Root -Clock $clock -AdapterRunner $failedAcceptanceAdapter)
        [void](Invoke-FactoryLoopTick -RepoRoot $fixture.Root -Clock $clock -AdapterRunner $failedAcceptanceAdapter)
        $prodAccepted = Invoke-FactoryLoopTick -RepoRoot $fixture.Root `
            -Clock $clock -AdapterRunner $failedAcceptanceAdapter
        $prodAccepted.stage | Should -BeExactly 'awaiting-evidence'

        Enable-FactoryLoopTestEvidenceBranch -RepoRoot $fixture.Root
        [void](Invoke-FactoryLoopTick -RepoRoot $fixture.Root -AdapterRunner $failedAcceptanceAdapter)
        [void](Invoke-FactoryLoopTick -RepoRoot $fixture.Root -AdapterRunner $failedAcceptanceAdapter)
        $bugClosed = Invoke-FactoryLoopTick -RepoRoot $fixture.Root -AdapterRunner $failedAcceptanceAdapter
        $bugClosed.stage | Should -BeExactly 'closing-work-item'
        $completed = Invoke-FactoryLoopTick -RepoRoot $fixture.Root -AdapterRunner $failedAcceptanceAdapter
        $completed.outcome | Should -BeExactly 'completed'
        $state = Get-Content -LiteralPath (Join-Path $fixture.Root '.factory-loop/loopback.json') -Raw |
            ConvertFrom-Json -AsHashtable -Depth 50
        @($state.workItems | Where-Object {
                [string]$_.id -ceq [string]$bug.bugWorkItemId -and [string]$_.status -ceq 'closed'
            }) | Should -HaveCount 1
    }

    It 'test:FactoryLoop.RepairSuccessor reserves and registers a separate source-pinned repair PR' {
        $fixture = New-FactoryLoopRuntimeFixture -LeaveDefect
        [void](Invoke-FactoryLoopTick -RepoRoot $fixture.Root)
        $failed = Invoke-FactoryLoopTick -RepoRoot $fixture.Root
        $failed.outcome | Should -BeExactly 'build-failed'
        $checkpoint = Read-FactoryLoopRuntimeFixtureCheckpoint -RepoRoot $fixture.Root
        $lineage = [string]$checkpoint.repairBuildLineageId

        $invocation = Start-FactoryLoopRepairInvocation -RepoRoot $fixture.Root `
            -PlanReference '961e7d'
        $invocation.branch | Should -BeExactly "factory-repair/$($fixture.WorkItemId)/1"
        $invocation.sourceSha | Should -BeExactly $fixture.SourceSha
        $checkpoint = Read-FactoryLoopRuntimeFixtureCheckpoint -RepoRoot $fixture.Root
        $checkpoint.repairPullRequestsReserved | Should -Be 1

        git -C $fixture.Root switch $invocation.branch --quiet
        if ($LASTEXITCODE -ne 0) { throw 'Unable to switch to the separate repair branch.' }
        $appScript = Join-Path $fixture.Root 'application/Invoke-DemoApp.ps1'
        $fixed = (Get-Content -LiteralPath $appScript -Raw).Replace(
            '$Subtotal * (1 + $DiscountRate)',
            '$Subtotal * (1 - $DiscountRate)'
        )
        Set-Content -LiteralPath $appScript -Value $fixed -NoNewline -Encoding utf8NoBOM
        git -C $fixture.Root add -- application/Invoke-DemoApp.ps1
        git -C $fixture.Root -c user.name='Factory Loop Demo' `
            -c user.email='factory-loop-demo@localhost' commit --quiet -m 'Repair failed build check'
        if ($LASTEXITCODE -ne 0) { throw 'Unable to commit the repair fix.' }
        $repairSha = (git -C $fixture.Root rev-parse HEAD).Trim()

        $registered = Register-FactoryLoopRepairPullRequest -RepoRoot $fixture.Root `
            -IncidentId $fixture.WorkItemId -BuildLineageId $lineage `
            -Branch $invocation.branch -SourceSha $repairSha
        $registered.pullRequestSequence | Should -Be 2
        $registered.outcome | Should -BeExactly 'repair-pr-registered'
        (Read-FactoryLoopRuntimeFixtureCheckpoint -RepoRoot $fixture.Root).stage |
            Should -BeExactly 'create-pr'
        $retry = Register-FactoryLoopRepairPullRequest -RepoRoot $fixture.Root `
            -IncidentId $fixture.WorkItemId -BuildLineageId $lineage `
            -Branch $invocation.branch -SourceSha $repairSha
        $retry.pullRequestSequence | Should -Be $registered.pullRequestSequence
        { Register-FactoryLoopRepairPullRequest -RepoRoot $fixture.Root `
                -IncidentId $fixture.WorkItemId -BuildLineageId 'other-lineage' `
                -Branch $invocation.branch -SourceSha $repairSha } |
            Should -Throw '*does not match the registered incident*'

        $opened = Invoke-FactoryLoopTick -RepoRoot $fixture.Root
        $opened.pullRequestId | Should -BeExactly 'PR-0002'
        $opened.stage | Should -BeExactly 'awaiting-checks'
        $state = Get-Content -LiteralPath (Join-Path $fixture.Root '.factory-loop/loopback.json') -Raw |
            ConvertFrom-Json -AsHashtable -Depth 50
        $repairPr = @($state.pullRequests | Where-Object id -CEQ 'PR-0002')[0]
        $repairPr.branch | Should -BeExactly $invocation.branch
        $repairPr.sourceSha | Should -BeExactly $repairSha
        $repairPr.sourceSha | Should -Not -BeExactly $fixture.SourceSha

        $checks = Invoke-FactoryLoopTick -RepoRoot $fixture.Root
        $checks.outcome | Should -BeExactly 'waiting-for-human-merge'
        $checks.stage | Should -BeExactly 'awaiting-merge'
        (Read-FactoryLoopRuntimeFixtureCheckpoint -RepoRoot $fixture.Root).repairBuildLineageId |
            Should -BeExactly $lineage
    }

    It 'test:FactoryLoop.ChainLimit rejects a second active chain in the project' {
        $fixture = New-FactoryLoopRuntimeFixture
        {
            Initialize-FactoryLoopChain -RepoRoot $fixture.Root -ChainId 'second-chain' `
                -WorkItemId $fixture.WorkItemId -PlanReference '961e7d' `
                -Branch $fixture.Branch -SourceSha $fixture.SourceSha
        } | Should -Throw '*already has active factory-loop chain*'
    }
}
