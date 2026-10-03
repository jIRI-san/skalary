#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'FactoryLoop.psm1') -DisableNameChecking

function Write-FactoryLoopCheckpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Checkpoint
    )

    $path = Resolve-FactoryLoopConsumerPath -RepoRoot $RepoRoot -RelativePath '.factory-loop/checkpoint.json'
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force)
    $temporary = "$path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        $Checkpoint.revision = [int]$Checkpoint.revision + 1
        $json = ConvertTo-Json -InputObject $Checkpoint -Depth 40
        [System.IO.File]::WriteAllText($temporary, $json, [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::Move($temporary, $path, $true)
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}

function Read-FactoryLoopCheckpoint {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepoRoot)

    $path = Resolve-FactoryLoopConsumerPath -RepoRoot $RepoRoot -RelativePath '.factory-loop/checkpoint.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw 'No active factory-loop chain. Start one explicitly before polling.'
    }
    $item = Get-Item -LiteralPath $path -Force
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or
        $item.Length -gt 1048576) {
        throw 'Factory-loop checkpoint is linked or exceeds the 1 MiB limit.'
    }
    $checkpoint = Get-Content -LiteralPath $path -Raw |
        ConvertFrom-Json -AsHashtable -Depth 40 -ErrorAction Stop
    if ($checkpoint -isnot [System.Collections.IDictionary] -or
        [int]$checkpoint.schemaVersion -ne 1 -or
        [string]$checkpoint.provider -cnotin @('loopback', 'live') -or
        [string]::IsNullOrWhiteSpace([string]$checkpoint.chainId) -or
        [string]::IsNullOrWhiteSpace([string]$checkpoint.stage)) {
        throw 'Factory-loop checkpoint has an unsupported or malformed schema.'
    }
    return $checkpoint
}

function Get-FactoryLoopCriteriaBaseline {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$PlanReference
    )
    $modulePath = Join-Path $RepoRoot '.github/skills/ci/scripts/DirectWorkflow.psm1'
    if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
        throw 'Plan criteria validator is missing from the selected repository. Run factory-loop setup to bootstrap local CI dependencies.'
    }
    Import-Module -Name $modulePath -Force -DisableNameChecking
    $baseline = Test-PlanCriteriaBaseline -RepoRoot $RepoRoot -PlanReference $PlanReference
    if ($null -eq $baseline -or [string]$baseline.Status -cne 'ready') {
        throw "Plan '$PlanReference' is not admitted by Test-PlanCriteriaBaseline."
    }
    return $baseline
}

function Test-FactoryLoopCriteriaBaselineUnchanged {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Checkpoint
    )

    $directWorkflowPath = Join-Path $RepoRoot '.github/skills/ci/scripts/DirectWorkflow.psm1'
    if (-not (Test-Path -LiteralPath $directWorkflowPath -PathType Leaf)) {
        throw 'Plan criteria validator is missing; run factory-loop setup to bootstrap local CI dependencies.'
    }
    $planStatePath = Join-Path (Split-Path -Parent $directWorkflowPath) 'PlanState.psm1'
    if (-not (Test-Path -LiteralPath $planStatePath -PathType Leaf)) {
        throw "Plan criteria dependency is missing: $planStatePath"
    }
    Import-Module -Name $planStatePath -Force -DisableNameChecking

    $root = [System.IO.Path]::GetFullPath($RepoRoot)
    $plan = Resolve-Plan -Reference ([string]$Checkpoint.planReference) -RepoRoot $root
    $planPath = Join-Path $plan.Path 'plan.md'
    $context = New-PlanConfinementContext -PlanDir $plan.Path -RepoRoot $root
    $confinedPlan = Resolve-ConfinedPlanPath -Context $context -Path $planPath -PathType Leaf
    $relativePlanPath = [System.IO.Path]::GetRelativePath($root, $confinedPlan.Item.FullName).Replace('\', '/')
    $planText = Get-Content -LiteralPath $confinedPlan.Item.FullName -Raw
    $marker = (Get-PlanHeaderMarkers -Content $planText).PlanningConfirmed
    if ([string]$marker -cne [string]$Checkpoint.criteriaMarker) { return $false }

    $relativeAssets = [System.Collections.Generic.List[string]]::new()
    foreach ($kind in @('Intent', 'Requirements', 'Risks', 'Decisions')) {
        $currentAsset = Resolve-PlanAssetPath -PlanDir $plan.Path -Kind $kind -RepoRoot $root
        $confinedAsset = Resolve-ConfinedPlanPath -Context $context -Path $currentAsset -PathType Leaf
        $relativeAssets.Add(
            [System.IO.Path]::GetRelativePath($root, $confinedAsset.Item.FullName).Replace('\', '/')
        )
    }

    $headPlan = @(& git -C $root show "HEAD`:$relativePlanPath" 2>$null)
    if ($LASTEXITCODE -ne 0 -or
        [string](Get-PlanHeaderMarkers -Content ($headPlan -join "`n")).PlanningConfirmed -cne
        [string]$Checkpoint.criteriaMarker) {
        return $false
    }
    $indexPlan = @(& git -C $root show ":$relativePlanPath" 2>$null)
    if ($LASTEXITCODE -ne 0 -or
        [string](Get-PlanHeaderMarkers -Content ($indexPlan -join "`n")).PlanningConfirmed -cne
        [string]$Checkpoint.criteriaMarker) {
        return $false
    }
    $criteriaDiff = & git -C $root diff --quiet ([string]$Checkpoint.criteriaBaselineCommit) -- `
        $relativeAssets.ToArray()
    $diffExitCode = $LASTEXITCODE
    if ($diffExitCode -gt 1) {
        throw "Unable to compare confirmed criteria with baseline commit '$($Checkpoint.criteriaBaselineCommit)'."
    }
    if ($diffExitCode -ne 0) { return $false }
    return $true
}

function Read-FactoryLoopConfiguration {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepoRoot)

    $path = Resolve-FactoryLoopConsumerPath -RepoRoot $RepoRoot -RelativePath '.factory-loop/factory-loop.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Factory-loop configuration is missing. Run Setup-FactoryLoop.ps1 for the selected repository."
    }
    $item = Get-Item -LiteralPath $path -Force
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or
        $item.Length -gt 65536) {
        throw 'Factory-loop configuration is linked or exceeds the 65536-byte limit.'
    }
    $config = Get-Content -LiteralPath $path -Raw |
        ConvertFrom-Json -AsHashtable -Depth 20 -ErrorAction Stop
    if ($config -isnot [System.Collections.IDictionary] -or
        [int]$config.schemaVersion -ne 1 -or
        [int]$config.pollSeconds -lt 1 -or [int]$config.pollSeconds -gt 86400 -or
        [int]$config.observationSeconds -lt 1 -or [int]$config.observationSeconds -gt 86400 -or
        [string]$config.mode -cnotin @('loopback', 'live')) {
        throw 'Factory-loop configuration has an unsupported schema, mode, or interval.'
    }
    $configJson = ConvertTo-Json -InputObject $config -Depth 20 -Compress
    if ($configJson -match '(?i)"[^"]*(?:credential|secret|token|password|passphrase)[^"]*"\s*:') {
        throw 'Factory-loop configuration cannot contain credential or secret fields.'
    }
    return $config
}

function Initialize-FactoryLoopChain {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$ChainId,
        [Parameter(Mandatory)][string]$WorkItemId,
        [Parameter(Mandatory)][string]$PlanReference,
        [Parameter(Mandatory)][string]$Branch,
        [Parameter(Mandatory)][string]$SourceSha,
        [scriptblock]$Clock = { [datetime]::UtcNow }
    )

    if ($ChainId -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$') {
        throw 'Chain ID must be a stable identifier of at most 80 characters.'
    }
    if ($Branch -notmatch '^feature/[A-Za-z0-9][A-Za-z0-9._/-]{0,100}$' -or
        $Branch.Contains('..') -or $Branch.Contains('//') -or $Branch.EndsWith('/')) {
        throw 'Chain branch must be a bounded feature/* Git branch.'
    }
    if ($SourceSha -cnotmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$' -or
        [string]::IsNullOrWhiteSpace($WorkItemId)) {
        throw 'Chain requires a full source commit ID and work-item provider ID.'
    }
    $root = [System.IO.Path]::GetFullPath($RepoRoot)
    $config = Read-FactoryLoopConfiguration -RepoRoot $root
    if ([string]$config.mode -cne 'loopback') {
        throw 'Live adapter dispatch is not available yet; select loopback mode for the MVP demo.'
    }
    $criteria = Get-FactoryLoopCriteriaBaseline -RepoRoot $root -PlanReference $PlanReference
    $branchHead = (git -C $root rev-parse $Branch).Trim()
    if ($LASTEXITCODE -ne 0 -or $branchHead -cne $SourceSha) {
        throw 'The selected implementation branch no longer points at the reviewed source SHA.'
    }

    $path = Resolve-FactoryLoopConsumerPath -RepoRoot $root -RelativePath '.factory-loop/checkpoint.json'
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $existing = Read-FactoryLoopCheckpoint -RepoRoot $root
        if ([string]$existing.chainId -ceq $ChainId -and
            [string]$existing.workItemId -ceq $WorkItemId -and
            [string]$existing.planReference -ceq $PlanReference) {
            return $existing
        }
        if ([string]$existing.status -cne 'completed') {
            throw "Project already has active factory-loop chain '$($existing.chainId)' at stage '$($existing.stage)'."
        }
    }

    $checkpoint = [ordered]@{
        schemaVersion = 1
        revision = 0
        provider = 'loopback'
        simulated = $true
        chainId = $ChainId
        status = 'active'
        stage = 'create-pr'
        workItemId = $WorkItemId
        planReference = $PlanReference
        criteriaBaselineCommit = [string]$criteria.BaselineCommit
        criteriaMarker = [string]$criteria.Marker
        branch = $Branch
        expectedSourceSha = $SourceSha
        pullRequestId = $null
        pullRequestProviderId = $null
        mergeCommit = $null
        pendingOperation = $null
        pollCount = 0
        pollSeconds = [int]$config.pollSeconds
        observationSeconds = [int]$config.observationSeconds
        createdAtUtc = ([datetime](& $Clock)).ToUniversalTime().ToString('o')
        updatedAtUtc = ([datetime](& $Clock)).ToUniversalTime().ToString('o')
        outcome = 'running'
        reason = $null
    }
    Write-FactoryLoopCheckpoint -RepoRoot $root -Checkpoint $checkpoint
    return $checkpoint
}

function Invoke-FactoryLoopRecordedMutation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Checkpoint,
        [Parameter(Mandatory)][string]$Domain,
        [Parameter(Mandatory)][string]$Action,
        [Parameter(Mandatory)][string]$OperationId,
        [Parameter(Mandatory)][hashtable]$Payload,
        [Parameter(Mandatory)][scriptblock]$AdapterRunner,
        [scriptblock]$Clock = { [datetime]::UtcNow },
        [scriptblock]$BeforeDispatch,
        [scriptblock]$AfterDispatch
    )

    if ($null -ne $Checkpoint.pendingOperation) {
        $pending = $Checkpoint.pendingOperation
        if ([string]$pending.domain -cne $Domain -or
            [string]$pending.action -cne $Action -or
            [string]$pending.operationId -cne $OperationId) {
            throw 'Checkpoint has an unresolved mutation for a different operation; reconcile it before proceeding.'
        }
        $Payload = $pending.payload
    }
    else {
        $Checkpoint.pendingOperation = [ordered]@{
            domain = $Domain
            action = $Action
            operationId = $OperationId
            payload = $Payload
            requestedAtUtc = ([datetime](& $Clock)).ToUniversalTime().ToString('o')
        }
        $Checkpoint.updatedAtUtc = ([datetime](& $Clock)).ToUniversalTime().ToString('o')
        Write-FactoryLoopCheckpoint -RepoRoot $RepoRoot -Checkpoint $Checkpoint
    }

    if ($BeforeDispatch) { & $BeforeDispatch $Checkpoint.pendingOperation }
    $result = & $AdapterRunner $Domain $Action $OperationId $Payload
    if ($AfterDispatch) { & $AfterDispatch $result }
    return ConvertFrom-FactoryLoopAdapterResult -Result $result -Domain $Domain `
        -Action $Action -OperationId $OperationId
}

function Invoke-FactoryLoopTick {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [scriptblock]$Clock = { [datetime]::UtcNow },
        [scriptblock]$AdapterRunner,
        [scriptblock]$BeforeDispatch,
        [scriptblock]$AfterDispatch
    )

    $root = [System.IO.Path]::GetFullPath($RepoRoot)
    $lockPath = Resolve-FactoryLoopConsumerPath -RepoRoot $root -RelativePath '.factory-loop/loop.lock'
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $lockPath) -Force)
    $lockStream = $null
    try {
        try {
            $lockStream = [System.IO.File]::Open(
                $lockPath,
                [System.IO.FileMode]::OpenOrCreate,
                [System.IO.FileAccess]::ReadWrite,
                [System.IO.FileShare]::None
            )
        }
        catch [System.IO.IOException] {
            return [pscustomobject]@{ outcome = 'locked'; status = 'waiting'; aiCalls = 0 }
        }
        $lockStream.SetLength(0)
        $lockBytes = [System.Text.Encoding]::UTF8.GetBytes(
            "pid=$PID`nstarted=$(([datetime](& $Clock)).ToUniversalTime().ToString('o'))"
        )
        $lockStream.Write($lockBytes, 0, $lockBytes.Length)
        $lockStream.Flush($true)

        $checkpoint = Read-FactoryLoopCheckpoint -RepoRoot $root
        if ([string]$checkpoint.status -ceq 'completed') {
            return [pscustomobject]@{ outcome = 'completed'; status = 'completed'; stage = [string]$checkpoint.stage; aiCalls = 0 }
        }

        $baselineRequired = [string]$checkpoint.stage -ceq 'create-pr' -or
            $null -ne $checkpoint.pendingOperation
        if ($baselineRequired -and
            -not (Test-FactoryLoopCriteriaBaselineUnchanged -RepoRoot $root -Checkpoint $checkpoint)) {
            $checkpoint.status = 'blocked'
            $checkpoint.outcome = 'blocked'
            $checkpoint.reason = 'confirmed-criteria-baseline-changed'
            $checkpoint.updatedAtUtc = ([datetime](& $Clock)).ToUniversalTime().ToString('o')
            Write-FactoryLoopCheckpoint -RepoRoot $root -Checkpoint $checkpoint
            return [pscustomobject]@{ outcome = 'blocked'; status = 'blocked'; reason = [string]$checkpoint.reason; aiCalls = 0 }
        }

        if (-not $AdapterRunner) {
            $AdapterRunner = {
                param($Domain, $Action, $OperationId, $Payload)
                Invoke-FactoryLoopLoopback -RepoRoot $root -Domain $Domain -Action $Action `
                    -OperationId $OperationId -Payload $Payload
            }.GetNewClosure()
        }
        $checkpoint.pollCount = [int]$checkpoint.pollCount + 1
        $checkpoint.updatedAtUtc = ([datetime](& $Clock)).ToUniversalTime().ToString('o')
        switch ([string]$checkpoint.stage) {
            'create-pr' {
                $operationId = "$($checkpoint.chainId):pull-request:open:1"
                $payload = @{
                    itemId = [string]$checkpoint.workItemId
                    branch = [string]$checkpoint.branch
                    sourceSha = [string]$checkpoint.expectedSourceSha
                }
                $result = Invoke-FactoryLoopRecordedMutation -RepoRoot $root `
                    -Checkpoint $checkpoint -Domain pull-request -Action open `
                    -OperationId $operationId -Payload $payload -AdapterRunner $AdapterRunner `
                    -Clock $Clock -BeforeDispatch $BeforeDispatch -AfterDispatch $AfterDispatch
                if ([string]$result.status -cne 'ok' -or
                    [string]$result.data.pullRequest.sourceSha -cne [string]$checkpoint.expectedSourceSha) {
                    return [pscustomobject]@{
                        outcome = 'blocked'
                        status = [string]$result.status
                        reason = 'pull-request-open-not-reconciled'
                        aiCalls = 0
                    }
                }
                $checkpoint.pullRequestId = [string]$result.data.pullRequest.id
                $checkpoint.pullRequestProviderId = [string]$result.providerId
                $checkpoint.pendingOperation = $null
                $checkpoint.stage = 'awaiting-checks'
                $checkpoint.updatedAtUtc = ([datetime](& $Clock)).ToUniversalTime().ToString('o')
                Write-FactoryLoopCheckpoint -RepoRoot $root -Checkpoint $checkpoint
                return [pscustomobject]@{
                    outcome = 'progressed'
                    status = 'waiting'
                    stage = [string]$checkpoint.stage
                    pullRequestId = [string]$checkpoint.pullRequestId
                    providerId = [string]$checkpoint.pullRequestProviderId
                    aiCalls = 0
                }
            }
            'awaiting-checks' {
                $operationId = "$($checkpoint.chainId):pull-request:checks:$($checkpoint.pollCount)"
                $result = & $AdapterRunner 'pull-request' 'checks' $operationId @{
                    pullRequestId = [string]$checkpoint.pullRequestId
                    demoRoot = $root
                    evaluate = $true
                }
                $result = ConvertFrom-FactoryLoopAdapterResult -Result $result -Domain pull-request `
                    -Action checks -OperationId $operationId
                $checks = $result.data.checks
                if ([string]$result.status -ceq 'blocked' -or [string]$checks.status -ceq 'blocked') {
                    $checkpoint.status = 'blocked'
                    $checkpoint.stage = 'blocked'
                    $checkpoint.outcome = 'blocked'
                    $checkpoint.reason = if ($checks.reason) { [string]$checks.reason } else { 'pull-request-check-inconclusive' }
                }
                elseif ([string]$checks.headSha -cne [string]$checkpoint.expectedSourceSha) {
                    $checkpoint.status = 'blocked'
                    $checkpoint.stage = 'blocked'
                    $checkpoint.outcome = 'blocked'
                    $checkpoint.reason = 'pull-request-head-changed'
                }
                elseif ([string]$checks.status -ceq 'failed') {
                    $checkpoint.stage = 'build-failed'
                    $checkpoint.outcome = 'build-failed'
                    $checkpoint.reason = 'checks-failed'
                }
                elseif ([string]$checks.status -cin @('cancelled', 'canceled', 'superseded')) {
                    $checkpoint.status = 'blocked'
                    $checkpoint.stage = 'blocked'
                    $checkpoint.outcome = 'blocked'
                    $checkpoint.reason = 'checks-cancelled'
                }
                elseif ([string]$checks.status -ceq 'passed') {
                    $checkpoint.stage = 'awaiting-merge'
                    $checkpoint.outcome = 'waiting-for-human-merge'
                    $checkpoint.reason = $null
                }
                elseif ([string]$checks.status -ceq 'pending') {
                    $checkpoint.outcome = 'waiting-for-checks'
                }
                else {
                    $checkpoint.status = 'blocked'
                    $checkpoint.stage = 'blocked'
                    $checkpoint.outcome = 'blocked'
                    $checkpoint.reason = 'checks-status-unknown'
                }
                $checkpoint.updatedAtUtc = ([datetime](& $Clock)).ToUniversalTime().ToString('o')
                Write-FactoryLoopCheckpoint -RepoRoot $root -Checkpoint $checkpoint
                return [pscustomobject]@{
                    outcome = [string]$checkpoint.outcome
                    status = [string]$checks.status
                    stage = [string]$checkpoint.stage
                    reason = [string]$checkpoint.reason
                    artifactDigest = if ($null -ne $checks.PSObject.Properties['artifactDigest']) {
                        [string]$checks.artifactDigest
                    } else { $null }
                    nextPollAfterSeconds = [int]$checkpoint.pollSeconds
                    aiCalls = 0
                }
            }
            'awaiting-merge' {
                $operationId = "$($checkpoint.chainId):pull-request:read:$($checkpoint.pollCount)"
                $result = & $AdapterRunner 'pull-request' 'read' $operationId @{
                    pullRequestId = [string]$checkpoint.pullRequestId
                }
                $result = ConvertFrom-FactoryLoopAdapterResult -Result $result -Domain pull-request `
                    -Action read -OperationId $operationId
                $pr = $result.data.pullRequest
                if ([string]$result.providerId -cne [string]$checkpoint.pullRequestProviderId -or
                    [string]$pr.sourceSha -cne [string]$checkpoint.expectedSourceSha) {
                    $checkpoint.status = 'blocked'
                    $checkpoint.stage = 'blocked'
                    $checkpoint.outcome = 'blocked'
                    $checkpoint.reason = 'pull-request-identity-or-head-changed'
                }
                elseif ([string]$pr.status -ceq 'closed') {
                    $checkpoint.status = 'blocked'
                    $checkpoint.stage = 'blocked'
                    $checkpoint.outcome = 'blocked'
                    $checkpoint.reason = 'pull-request-closed-unmerged'
                }
                elseif ([string]$pr.status -ceq 'merged') {
                    if ([string]$pr.mergeCommit -cnotmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$') {
                        throw 'Merged pull request is missing its actual merge commit identity.'
                    }
                    $checkpoint.mergeCommit = [string]$pr.mergeCommit
                    $checkpoint.stage = 'test-deployment'
                    $checkpoint.outcome = 'progressed'
                    $checkpoint.reason = $null
                }
                else {
                    $checkpoint.outcome = 'waiting-for-human-merge'
                }
                $checkpoint.updatedAtUtc = ([datetime](& $Clock)).ToUniversalTime().ToString('o')
                Write-FactoryLoopCheckpoint -RepoRoot $root -Checkpoint $checkpoint
                return [pscustomobject]@{
                    outcome = [string]$checkpoint.outcome
                    status = [string]$pr.status
                    stage = [string]$checkpoint.stage
                    mergeCommit = [string]$checkpoint.mergeCommit
                    reason = [string]$checkpoint.reason
                    nextPollAfterSeconds = [int]$checkpoint.pollSeconds
                    aiCalls = 0
                }
            }
            'test-deployment' {
                return [pscustomobject]@{
                    outcome = 'waiting-for-test-deployment'
                    status = 'waiting'
                    stage = [string]$checkpoint.stage
                    mergeCommit = [string]$checkpoint.mergeCommit
                    nextPollAfterSeconds = [int]$checkpoint.pollSeconds
                    aiCalls = 0
                }
            }
            'build-failed' {
                return [pscustomobject]@{
                    outcome = 'build-failed'
                    status = 'blocked'
                    stage = [string]$checkpoint.stage
                    reason = [string]$checkpoint.reason
                    aiCalls = 0
                }
            }
            'blocked' {
                return [pscustomobject]@{
                    outcome = 'blocked'
                    status = 'blocked'
                    stage = [string]$checkpoint.stage
                    reason = [string]$checkpoint.reason
                    aiCalls = 0
                }
            }
            default { throw "Unsupported factory-loop checkpoint stage '$($checkpoint.stage)'." }
        }
    }
    finally {
        if ($null -ne $lockStream) { $lockStream.Dispose() }
    }
}

Export-ModuleMember -Function @(
    'Initialize-FactoryLoopChain',
    'Invoke-FactoryLoopTick'
)
