#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Check', 'Record', 'Continue', 'Wrap', 'Reopen')]
    [string]$Action,

    [Parameter(Mandatory)]
    [string]$PlanDir,

    [Parameter(Mandatory)]
    [ValidateRange(0, 999)]
    [int]$Phase,

    [Parameter(Mandatory)]
    [ValidatePattern('^(?:step-[0-9]+\.[0-9]+[a-z]?|phase-[0-9]+|plan-finalization)$')]
    [string]$Stage,

    [ValidateSet('clean', 'findings')]
    [string]$Outcome,

    [string]$Summary,

    [ValidatePattern('^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')]
    [string]$ReviewRunId,

    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$')]
    [string]$OperatorAuthorization,

    [string]$Reason,

    [string]$RepoRoot,

    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'PlanEvidence.psm1') -Force -DisableNameChecking

$planDirFull = [System.IO.Path]::GetFullPath($PlanDir)
if (-not (Test-Path -LiteralPath $planDirFull -PathType Container)) {
    throw "Plan folder not found: $planDirFull"
}
$cycleState = Get-PlanReviewCycleState -PlanDir $planDirFull -Stage $Stage
$logPath = $cycleState.LogPath
$count = $cycleState.Cycles
$latestEvent = $cycleState.LatestEvent

function Add-ReviewCycleNote {
    param([Parameter(Mandatory)][string]$Message)
    $writer = Join-Path $PSScriptRoot 'Add-WorkflowNote.ps1'
    if (-not (Test-Path -LiteralPath $writer -PathType Leaf)) { throw "Workflow-note writer not found: $writer" }
    $step = if ($Stage -match '^step-(?<step>.+)$') { $Matches.step } else { $null }
    & $writer -Kind CrLog -PlanDir $planDirFull -Phase $Phase -Step $step `
        -Src note -Sev Low -Concern maintainability-consistency -ReviewType cr `
        -Message $Message | Out-Null
}

$state = $cycleState.State
switch ($Action) {
    'Record' {
        if (-not $Outcome) { throw 'Record requires -Outcome clean|findings.' }
        if ($state -ne 'allow') { throw "Review cycle $($count + 1) for '$Stage' is blocked by state '$state'." }
        if ($Outcome -eq 'clean') {
            if (-not $ReviewRunId) { throw 'Recording a clean review requires -ReviewRunId.' }
            $gitRoot = if ($RepoRoot) {
                [System.IO.Path]::GetFullPath($RepoRoot)
            }
            else {
                $resolved = (& git -C $planDirFull rev-parse --show-toplevel 2>$null)
                if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($resolved)) {
                    throw 'Recording a clean review could not resolve the repository; pass -RepoRoot.'
                }
                [System.IO.Path]::GetFullPath($resolved.Trim())
            }
            $head = (& git -C $gitRoot rev-parse HEAD 2>$null)
            if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($head)) {
                throw "Recording a clean review could not resolve HEAD under '$gitRoot'."
            }
            [void](Assert-PlanReviewResultReceipt -PlanDir $planDirFull -ReviewRunId $ReviewRunId `
                    -Commit $head.Trim().ToLowerInvariant() -RequireBranchScope:($Stage -ceq 'plan-finalization') `
                    -RepoRoot $gitRoot)
        }
        $next = $count + 1
        $run = if ($ReviewRunId) { " run=$ReviewRunId" } else { '' }
        $suffix = if ([string]::IsNullOrWhiteSpace($Summary)) { '' } else { " summary=$Summary" }
        Add-ReviewCycleNote -Message "review-cycle stage=$Stage cycle=$next outcome=$Outcome$run$suffix"
        $count = $next
        $latestEvent = $null
        $state = if ($Outcome -eq 'clean') { 'complete' } elseif ($count -lt 3) { 'allow' } else { 'operator-decision' }
    }
    'Continue' {
        if ($count -lt 3) { throw 'Continue is valid only after at least three recorded review cycles.' }
        if ($state -ne 'operator-decision') { throw "Continue cannot be recorded while state is '$state'." }
        Add-ReviewCycleNote -Message "review-cycle-decision stage=$Stage after=$count action=continue"
        $latestEvent = [pscustomobject]@{ After = $count; Action = 'continue'; Authorization = ''; Reason = '' }
        $state = 'allow'
    }
    'Wrap' {
        if ($count -lt 3) { throw 'Wrap is valid only after at least three recorded review cycles.' }
        if ($state -ne 'operator-decision') { throw "Wrap cannot be recorded while state is '$state'." }
        Add-ReviewCycleNote -Message "review-cycle-decision stage=$Stage after=$count action=wrap"
        $latestEvent = [pscustomobject]@{ After = $count; Action = 'wrap'; Authorization = ''; Reason = '' }
        $state = 'wrap'
    }
    'Reopen' {
        if ($state -notin @('wrap', 'legacy-clean')) { throw "Reopen cannot be recorded while state is '$state'." }
        if (-not $OperatorAuthorization) {
            throw 'Reopen requires explicit -OperatorAuthorization.'
        }
        if ([string]::IsNullOrWhiteSpace($Reason)) {
            throw 'Reopen requires a non-empty -Reason.'
        }
        Add-ReviewCycleNote -Message "review-cycle-remediation stage=$Stage after=$count action=reopen authorization=$OperatorAuthorization reason=$Reason"
        $latestEvent = [pscustomobject]@{
            After = $count
            Action = 'reopen'
            Authorization = $OperatorAuthorization
            Reason = $Reason
        }
        $state = 'allow'
    }
}

$result = [ordered]@{
    schema = 'skalary/review-cycle-gate@1'
    stage = $Stage
    cycles = $count
    limit = 3
    state = $state
    canReview = ($state -eq 'allow')
    operatorDecisionRequired = ($state -eq 'operator-decision')
    logPath = $logPath
}
if ($state -eq 'complete' -and $ReviewRunId) {
    $result['reviewRunId'] = $ReviewRunId
}
elseif ($state -eq 'complete' -and $cycleState.ReviewRunId) {
    $result['reviewRunId'] = $cycleState.ReviewRunId
}
if ($null -ne $latestEvent) {
    if ($latestEvent.Action -eq 'reopen') {
        $result['remediation'] = [ordered]@{
            after = $latestEvent.After
            action = $latestEvent.Action
            authorization = $latestEvent.Authorization
            reason = $latestEvent.Reason
        }
    }
    else {
        $result['decision'] = [ordered]@{ after = $latestEvent.After; action = $latestEvent.Action }
    }
}

if ($Json) { return ($result | ConvertTo-Json -Depth 5 -Compress) }
return [pscustomobject]$result