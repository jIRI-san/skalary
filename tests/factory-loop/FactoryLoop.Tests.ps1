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

        function New-FactoryLoopRuntimeFixture {
            param([switch]$LeaveDefect, [switch]$MutateCriteriaBeforeAdmission)

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
            try {
                $checkpoint = Initialize-FactoryLoopChain -RepoRoot $demo -ChainId $chainId `
                    -WorkItemId ([string]$item.data.item.id) -PlanReference $planReference `
                    -Branch $branch -SourceSha $sourceSha
            }
            catch {
                if (-not $MutateCriteriaBeforeAdmission) { throw }
                $admissionError = $_.Exception.Message
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
    }

    It 'test:FactoryLoop.AdapterContract validates command output and propagates errors with durable operation identity' {
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

    It 'test:FactoryLoop.Restart reconciles an interruption before provider dispatch' {
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

    It 'test:FactoryLoop.Restart reconciles an interruption after provider mutation' {
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

    It 'test:FactoryLoop.PrChecks treats a failing build as a bounded repair incident' {
        $failure = New-FactoryLoopRuntimeFixture -LeaveDefect
        [void](Invoke-FactoryLoopTick -RepoRoot $failure.Root)
        $failed = Invoke-FactoryLoopTick -RepoRoot $failure.Root
        $failed.status | Should -BeExactly 'failed'
        $failed.stage | Should -BeExactly 'build-failed'
        $failed.aiCalls | Should -Be 0
    }

    It 'test:FactoryLoop.PrChecks blocks a changed pull-request head' {
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

    It 'test:FactoryLoop.PrChecks blocks a closed unmerged pull request' {
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

    It 'test:FactoryLoop.ChainLimit rejects a second active chain in the project' {
        $fixture = New-FactoryLoopRuntimeFixture
        {
            Initialize-FactoryLoopChain -RepoRoot $fixture.Root -ChainId 'second-chain' `
                -WorkItemId $fixture.WorkItemId -PlanReference '961e7d' `
                -Branch $fixture.Branch -SourceSha $fixture.SourceSha
        } | Should -Throw '*already has active factory-loop chain*'
    }
}
