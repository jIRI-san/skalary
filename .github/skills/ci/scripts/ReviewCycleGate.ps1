#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Check', 'Record', 'Continue', 'Wrap')]
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

    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'PlanState.psm1') -Force -DisableNameChecking

$planDirFull = [System.IO.Path]::GetFullPath($PlanDir)
if (-not (Test-Path -LiteralPath $planDirFull -PathType Container)) {
    throw "Plan folder not found: $planDirFull"
}
$logPath = Resolve-PlanAssetPath -PlanDir $planDirFull -Kind CrLog
$raw = if (Test-Path -LiteralPath $logPath -PathType Leaf) { Get-Content -LiteralPath $logPath -Raw } else { '' }
$stagePattern = [regex]::Escape($Stage)
$provenancePattern = '(?: \[[^\]]+\])*'
$cycleMatches = [regex]::Matches($raw, "(?m)^- \[[^\]]+\] \[src:note\] \[sev:Low\]$provenancePattern review-cycle stage=$stagePattern cycle=(?<cycle>[0-9]+) outcome=(?<outcome>clean|findings)(?: .*)?$")
$cycles = @($cycleMatches | ForEach-Object { [int]$_.Groups['cycle'].Value } | Sort-Object)
$count = $cycles.Count
$latestOutcome = if ($cycleMatches.Count -gt 0) {
    [string]$cycleMatches[$cycleMatches.Count - 1].Groups['outcome'].Value
}
else {
    $null
}
if ($count -gt 0 -and (($cycles -join ',') -ne ((1..$count) -join ','))) {
    throw "Review-cycle history for '$Stage' is not the closed sequence 1..$count."
}

$decisionMatches = [regex]::Matches($raw, "(?m)^- \[[^\]]+\] \[src:note\] \[sev:Low\]$provenancePattern review-cycle-decision stage=$stagePattern after=(?<after>[0-9]+) action=(?<decision>continue|wrap)$")
$latestDecision = $null
if ($decisionMatches.Count -gt 0) {
    $match = $decisionMatches[$decisionMatches.Count - 1]
    $latestDecision = [pscustomobject]@{ After = [int]$match.Groups['after'].Value; Action = [string]$match.Groups['decision'].Value }
}

function Add-ReviewCycleNote {
    param([Parameter(Mandatory)][string]$Message)
    $writer = Join-Path $PSScriptRoot 'Add-WorkflowNote.ps1'
    if (-not (Test-Path -LiteralPath $writer -PathType Leaf)) { throw "Workflow-note writer not found: $writer" }
    $step = if ($Stage -match '^step-(?<step>.+)$') { $Matches.step } else { $null }
    & $writer -Kind CrLog -PlanDir $planDirFull -Phase $Phase -Step $step `
        -Src note -Sev Low -Concern maintainability-consistency -ReviewType cr `
        -Message $Message | Out-Null
}

function Get-ReviewCycleState {
    param([int]$CycleCount, [object]$Decision, [string]$LatestOutcome)
    if ($LatestOutcome -eq 'clean') { return 'complete' }
    if ($CycleCount -lt 3) { return 'allow' }
    if ($null -ne $Decision -and $Decision.After -eq $CycleCount) {
        if ($Decision.Action -eq 'continue') { return 'allow' }
        return 'wrap'
    }
    return 'operator-decision'
}

$state = Get-ReviewCycleState -CycleCount $count -Decision $latestDecision -LatestOutcome $latestOutcome
switch ($Action) {
    'Record' {
        if (-not $Outcome) { throw 'Record requires -Outcome clean|findings.' }
        if ($state -ne 'allow') { throw "Review cycle $($count + 1) for '$Stage' is blocked by state '$state'." }
        $next = $count + 1
        $suffix = if ([string]::IsNullOrWhiteSpace($Summary)) { '' } else { " summary=$Summary" }
        Add-ReviewCycleNote -Message "review-cycle stage=$Stage cycle=$next outcome=$Outcome$suffix"
        $count = $next
        $latestOutcome = $Outcome
        $latestDecision = $null
        $state = Get-ReviewCycleState -CycleCount $count -Decision $null -LatestOutcome $latestOutcome
    }
    'Continue' {
        if ($count -lt 3) { throw 'Continue is valid only after at least three recorded review cycles.' }
        if ($state -ne 'operator-decision') { throw "Continue cannot be recorded while state is '$state'." }
        Add-ReviewCycleNote -Message "review-cycle-decision stage=$Stage after=$count action=continue"
        $latestDecision = [pscustomobject]@{ After = $count; Action = 'continue' }
        $state = 'allow'
    }
    'Wrap' {
        if ($count -lt 3) { throw 'Wrap is valid only after at least three recorded review cycles.' }
        if ($state -ne 'operator-decision') { throw "Wrap cannot be recorded while state is '$state'." }
        Add-ReviewCycleNote -Message "review-cycle-decision stage=$Stage after=$count action=wrap"
        $latestDecision = [pscustomobject]@{ After = $count; Action = 'wrap' }
        $state = 'wrap'
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
if ($null -ne $latestDecision) {
    $result['decision'] = [ordered]@{ after = $latestDecision.After; action = $latestDecision.Action }
}

if ($Json) { return ($result | ConvertTo-Json -Depth 5 -Compress) }
return [pscustomobject]$result