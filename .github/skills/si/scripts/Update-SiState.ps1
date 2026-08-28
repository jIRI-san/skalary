#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$RepoRoot = (Get-Location).Path,
    [Parameter(Mandatory)]
    [ValidateSet('Begin', 'RecordRanking', 'RecordChoices', 'ProposalPending', 'Complete')]
    [string]$Operation,
    [Parameter(Mandatory)][string]$InputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'SiStateStore.psm1') -Force
$stateContract = Get-SiStateContract

if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) {
    throw "Input file not found: $InputPath"
}
$request = Get-Content -LiteralPath $InputPath -Raw | ConvertFrom-Json -Depth 100
foreach ($required in @('dueId', 'runId')) {
    if ($request.PSObject.Properties.Name -notcontains $required -or [string]$request.$required -notmatch '^[0-9a-f]{64}$') {
        throw "Input requires a valid '$required'."
    }
}

function Update-SiLifecycleManifest {
    param(
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)]$Due,
        [Parameter(Mandatory)]$Request,
        [Parameter(Mandatory)][string]$OperationName,
        [Parameter(Mandatory)]$Run,
        [Parameter(Mandatory)][string]$WrittenPath
    )

    if ($OperationName -eq 'Begin') {
        $Manifest.pending = @($Manifest.pending | Where-Object {
                [string]$_.dueId -ne [string]$Request.dueId
            })
        $existingInFlight = @($Manifest.inFlight | Where-Object {
                [string]$_.dueId -eq [string]$Request.dueId
            })
        if ($existingInFlight.Count -eq 0) {
            if (@($Manifest.inFlight).Count -ge $stateContract.Limits.ActiveInFlightRuns) {
                throw 'capacity-blocked: active in-flight run limit reached.'
            }
            $Due.status = 'in-flight'
            $Due.runId = [string]$Request.runId
            $Manifest.inFlight = @($Manifest.inFlight) + $Due
        }
    }
    if ($OperationName -eq 'Complete' -or [string]$Run.status -eq 'no-candidates') {
        $Manifest.pending = @($Manifest.pending | Where-Object {
                [string]$_.dueId -ne [string]$Request.dueId
            })
        $Manifest.inFlight = @($Manifest.inFlight | Where-Object {
                [string]$_.dueId -ne [string]$Request.dueId
            })
        $relative = [System.IO.Path]::GetRelativePath(
            [System.IO.Path]::GetFullPath($RepoRoot), $WrittenPath
        ).Replace('\', '/')
        $reference = [pscustomobject][ordered]@{
            runId = [string]$Run.runId; dueId = [string]$Run.dueId
            status = [string]$Run.status; path = $relative
            completedAtUtc = [string]$Run.completedAtUtc
        }
        $retained = [int]$stateContract.Limits.RecentRunReferences - 1
        $Manifest.recentRuns = @($reference) + @(
            $Manifest.recentRuns | Where-Object {
                [string]$_.dueId -ne [string]$Request.dueId
            } | Select-Object -First $retained
        )
    }
}

$result = Invoke-SiManifestUpdate -RepoRoot $RepoRoot -Transform {
    param($manifest, $attempt, $prepared)
    $activeDue = @($manifest.pending + $manifest.inFlight | Where-Object {
            [string]$_.dueId -eq [string]$request.dueId
        })
    if ($activeDue.Count -ne 1) {
        throw "Due '$($request.dueId)' must have exactly one active manifest entry."
    }
    $due = $activeDue[0]
    if ([string]$due.status -eq 'in-flight' -and
        [string]$due.runId -ne [string]$request.runId) {
        throw "Due '$($request.dueId)' is already bound to run '$($due.runId)'."
    }
    if ($Operation -ne 'Begin' -and
        ([string]$due.status -ne 'in-flight' -or
            [string]$due.runId -ne [string]$request.runId)) {
        throw "Operation '$Operation' requires due '$($request.dueId)' to be bound in-flight to run '$($request.runId)'."
    }

    if ($null -ne $prepared) {
        Update-SiLifecycleManifest -Manifest $manifest -Due $due -Request $request `
            -OperationName $Operation -Run $prepared.Run -WrittenPath $prepared.RunPath
        return $prepared
    }

    $runsRoot = Resolve-SiStatePath -RepoRoot $RepoRoot `
        -Segments @($stateContract.Topology.ActiveRunsSegments)
    $existingRuns = @(Get-ChildItem -LiteralPath $runsRoot -Filter "$($request.runId).json" `
            -Recurse -File -ErrorAction SilentlyContinue)
    if ($existingRuns.Count -gt 1) {
        throw "Run '$($request.runId)' exists at multiple active paths."
    }
    $runPath = if ($existingRuns.Count -eq 1) {
        $existingRuns[0].FullName
    }
    else {
        Get-SiRunPath -RepoRoot $RepoRoot -RunId ([string]$request.runId) `
            -Timestamp $(if ($request.PSObject.Properties.Name -contains 'createdAtUtc') { [datetime]$request.createdAtUtc } else { [datetime]::UtcNow })
    }
    $run = if (Test-Path -LiteralPath $runPath -PathType Leaf) {
        Get-Content -LiteralPath $runPath -Raw | ConvertFrom-Json -Depth 100
    }
    else {
        $now = [datetime]::UtcNow.ToString('o')
        [pscustomobject][ordered]@{
            schemaVersion = 2; runId = [string]$request.runId; dueId = [string]$request.dueId
            status = 'resumable'; createdAtUtc = $now; updatedAtUtc = $now; completedAtUtc = $null
            provenance = [pscustomobject][ordered]@{
                repoId = [string]$due.repoId; planId = [string]$due.planId
                sourceCommit = [string]$due.sourceCommit
                pinnedBaseOid = [string]$request.pinnedBaseOid
                resolverReceiptId = $null
            }
            rankedSet = [pscustomobject][ordered]@{
                count = 0
                digest = ('0' * 64)
                candidates = @()
            }
            choices = @()
            proposalPr = $null
        }
    }
    $runExists = Test-Path -LiteralPath $runPath -PathType Leaf
    if (-not $runExists -and $Operation -ne 'Begin') {
        throw "$Operation requires an existing resumable run."
    }
    if ([string]$run.dueId -ne [string]$request.dueId) {
        throw "Run '$($request.runId)' belongs to due '$($run.dueId)', not '$($request.dueId)'."
    }
    if ($Operation -eq 'Begin' -and
        ($request.PSObject.Properties.Name -notcontains 'pinnedBaseOid' -or
            [string]$request.pinnedBaseOid -notmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$')) {
        throw 'Begin requires a valid pinnedBaseOid.'
    }
    $previousStatus = [string]$run.status
    if ([string]$run.status -notin [string[]]$stateContract.Transitions.$Operation) {
        throw "Operation '$Operation' is invalid from run status '$($run.status)'."
    }

    switch ($Operation) {
        'Begin' {
        }
        'RecordRanking' {
            foreach ($required in @('resolverReceiptId', 'rankedSet')) {
                if ($request.PSObject.Properties.Name -notcontains $required) { throw "RecordRanking requires '$required'." }
            }
            $run.provenance.resolverReceiptId = [string]$request.resolverReceiptId
            $run.rankedSet = $request.rankedSet
            $run.status = if ([int]$request.rankedSet.count -eq 0) { 'no-candidates' } else { 'ranked' }
            if ($run.status -eq 'no-candidates') {
                $run.completedAtUtc = [datetime]::UtcNow.ToString('o')
            }
        }
        'RecordChoices' {
            if ($request.PSObject.Properties.Name -notcontains 'choices') { throw 'RecordChoices requires choices.' }
            $run.choices = @($request.choices)
            $run.status = 'proposal-pending'
        }
        'ProposalPending' {
            $run.status = 'proposal-pending'
            if ($request.PSObject.Properties.Name -contains 'proposalPr') { $run.proposalPr = $request.proposalPr }
        }
        'Complete' {
            if ($request.PSObject.Properties.Name -contains 'choices') { $run.choices = @($request.choices) }
            if ($request.PSObject.Properties.Name -contains 'proposalPr') { $run.proposalPr = $request.proposalPr }
            $run.status = if ($request.PSObject.Properties.Name -contains 'status') { [string]$request.status } else { 'completed' }
            if (-not (Test-SiRunStatus -Status ([string]$run.status) -Set Terminal)) {
                throw "Complete status '$($run.status)' is invalid."
            }
            if (($previousStatus -eq 'resumable' -and $run.status -ne 'declined-before-ranking') -or
                ($previousStatus -eq 'proposal-pending' -and $run.status -ne 'completed')) {
                throw "Complete transition '$previousStatus' -> '$($run.status)' is invalid."
            }
            $run.completedAtUtc = [datetime]::UtcNow.ToString('o')
        }
    }
    $run.updatedAtUtc = [datetime]::UtcNow.ToString('o')

    # Run first, manifest second. A crash leaves a repairable orphan, never a consumed due without its audit record.
    $writtenPath = Write-SiRun -RepoRoot $RepoRoot -Run $run
    Update-SiLifecycleManifest -Manifest $manifest -Due $due -Request $request `
        -OperationName $Operation -Run $run -WrittenPath $writtenPath
    return [pscustomobject]@{
        Operation = $Operation
        RunId = [string]$run.runId
        RunPath = $writtenPath
        Run = $run
    }
}
if ($result.Status -ne 'complete') {
    Write-Error "Update-SiState failed with status '$($result.Status)'."
}
return [pscustomobject]@{
    Status = $result.Status
    Operation = $Operation
    RunId = [string]$request.runId
    Attempts = $result.Attempts
}
