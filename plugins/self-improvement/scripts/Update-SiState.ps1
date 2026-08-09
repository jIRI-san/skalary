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

if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) {
    throw "Input file not found: $InputPath"
}
$request = Get-Content -LiteralPath $InputPath -Raw | ConvertFrom-Json -Depth 100
foreach ($required in @('dueId', 'runId')) {
    if ($request.PSObject.Properties.Name -notcontains $required -or [string]$request.$required -notmatch '^[0-9a-f]{64}$') {
        throw "Input requires a valid '$required'."
    }
}

$result = Invoke-SiManifestUpdate -RepoRoot $RepoRoot -Transform {
    param($manifest)
    $due = @($manifest.pending + $manifest.inFlight | Where-Object { [string]$_.dueId -eq [string]$request.dueId }) |
        Select-Object -First 1
    if ($null -eq $due) { throw "Due '$($request.dueId)' was not found." }

    $runsRoot = Resolve-SiStatePath -RepoRoot $RepoRoot -Segments @('runs')
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
    $allowedPredecessors = @{
        Begin = @('resumable')
        RecordRanking = @('resumable')
        RecordChoices = @('ranked')
        ProposalPending = @('ranked', 'proposal-pending')
        Complete = @('resumable', 'proposal-pending')
    }
    if ([string]$run.status -notin $allowedPredecessors[$Operation]) {
        throw "Operation '$Operation' is invalid from run status '$($run.status)'."
    }

    switch ($Operation) {
        'Begin' {
            $manifest.pending = @($manifest.pending | Where-Object { [string]$_.dueId -ne [string]$request.dueId })
            if (@($manifest.inFlight).Count -ge (Get-SiStateContract).Limits.ActiveInFlightRuns) {
                throw 'capacity-blocked: active in-flight run limit reached.'
            }
            if (@($manifest.inFlight | Where-Object { [string]$_.dueId -eq [string]$request.dueId }).Count -eq 0) {
                $due.status = 'in-flight'
                $due.runId = [string]$request.runId
                $manifest.inFlight = @($manifest.inFlight) + $due
            }
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
            if ($run.status -notin @('declined-before-ranking', 'no-candidates', 'completed')) {
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
    if ($Operation -eq 'Complete' -or $run.status -eq 'no-candidates') {
        $manifest.pending = @($manifest.pending | Where-Object { [string]$_.dueId -ne [string]$request.dueId })
        $manifest.inFlight = @($manifest.inFlight | Where-Object { [string]$_.dueId -ne [string]$request.dueId })
        $relative = [System.IO.Path]::GetRelativePath(
            [System.IO.Path]::GetFullPath($RepoRoot), $writtenPath
        ).Replace('\', '/')
        $reference = [pscustomobject][ordered]@{
            runId = [string]$run.runId; dueId = [string]$run.dueId; status = [string]$run.status
            path = $relative; completedAtUtc = [string]$run.completedAtUtc
        }
        $manifest.recentRuns = @($reference) + @($manifest.recentRuns | Select-Object -First 63)
    }
    return [pscustomobject]@{ Operation = $Operation; RunId = [string]$run.runId; RunPath = $writtenPath }
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
