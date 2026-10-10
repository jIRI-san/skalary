#requires -Version 7.0
[CmdletBinding(DefaultParameterSetName = 'Phase')]
param(
    [Parameter(Mandatory)][string]$IntegrationRoot,
    [Parameter(Mandatory)][string]$WorkerRoot,
    [Parameter(Mandatory)][string]$PlanReference,
    [Parameter(Mandatory)][ValidatePattern('^(?:[0-9a-f]{40}|[0-9a-f]{64})$')]
    [string]$ExpectedStartCommit,
    [Parameter(Mandatory, ParameterSetName = 'Phase')][ValidateRange(0, 999)][int]$Phase,
    [Parameter(Mandatory, ParameterSetName = 'Finalization')][switch]$Finalization
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'PlanState.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'DirectWorkflow.psm1') -Force -DisableNameChecking

function Read-Git {
    param([string]$Root, [string[]]$Argument)
    $output = @(& git -C $Root @Argument 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "Worker-result Git check failed: $($output -join ' ')" }
    return ($output -join "`n").Trim()
}

$integration = (Resolve-Path -LiteralPath $IntegrationRoot).Path
$worker = (Resolve-Path -LiteralPath $WorkerRoot).Path
foreach ($root in @($integration, $worker)) {
    $top = Read-Git $root @('rev-parse', '--show-toplevel')
    if ((Resolve-Path -LiteralPath $top).Path -ne $root) {
        throw 'Worker-result roots must be distinct repository/worktree roots.'
    }
    if (Read-Git $root @('status', '--porcelain', '--untracked-files=all')) {
        throw 'Worker-result acceptance requires clean committed worktrees.'
    }
}
if ($worker -eq $integration) { throw 'Worker must use a distinct worktree.' }
if ((Read-Git $integration @('rev-parse', 'HEAD')) -cne $ExpectedStartCommit) {
    throw 'Integration HEAD moved during worker execution.'
}
$head = Read-Git $worker @('rev-parse', 'HEAD')
Read-Git $worker @('merge-base', '--is-ancestor', $ExpectedStartCommit, $head) | Out-Null
Test-PlanCriteriaBaseline -RepoRoot $integration -PlanReference $PlanReference | Out-Null
Test-PlanCriteriaBaseline -RepoRoot $worker -PlanReference $PlanReference | Out-Null
$beforePlan = Resolve-Plan -Reference $PlanReference -RepoRoot $integration
$afterPlan = Resolve-Plan -Reference $PlanReference -RepoRoot $worker
if ($beforePlan.Id -ne $afterPlan.Id) { throw 'Worker changed plan identity.' }
$before = Get-PlanMetadata -Path (Join-Path $beforePlan.Path 'plan.md') -RepoRoot $integration
$after = Get-PlanMetadata -Path (Join-Path $afterPlan.Path 'plan.md') -RepoRoot $worker
if ($before.Steps.Count -ne $after.Steps.Count -or
    (@($before.PhaseSteps.Keys | Sort-Object) -join "`n") -cne
    (@($after.PhaseSteps.Keys | Sort-Object) -join "`n")) {
    throw 'Worker changed immutable checklist structure.'
}
$completed = [System.Collections.Generic.List[string]]::new()
for ($i = 0; $i -lt $before.Steps.Count; $i++) {
    $old = $before.Steps[$i]
    $new = $after.Steps[$i]
    if ($old.Id -cne $new.Id -or $old.Body -cne $new.Body -or $old.Phase -cne $new.Phase) {
        throw 'Worker changed immutable checklist structure.'
    }
    if ($old.Status -ceq $new.Status) { continue }
    if ($Finalization -or $old.Status -eq 'x' -or $new.Status -ne 'x' -or
        $old.Role -eq 'human' -or $old.Phase -notmatch "^##\s+Phase\s+$Phase(?:\D|$)") {
        throw "Worker changed an unauthorized checklist step '$($old.Id)'."
    }
    foreach ($dependency in $new.After) {
        $matches = @($after.Steps | Where-Object { $_.Id -eq $dependency })
        if ($matches.Count -ne 1 -or $matches[0].Status -ne 'x') {
            throw "Worker completed '$($new.Id)' without its prerequisite '$dependency'."
        }
    }
    $completed.Add($new.Id)
}
if ($Finalization) {
    if (@($before.Steps | Where-Object { $_.Status -ne 'x' }).Count -gt 0 -or
        $beforePlan.IsArchived -or -not $afterPlan.IsArchived) {
        throw 'Finalization requires all closed steps and a newly committed plan archive.'
    }
    $learning = Read-Git $worker @('show', "${head}:docs/feedback/recent-learning.md")
    if (-not $learning) { throw 'Finalization has no committed learning handoff.' }
    $source = [regex]::Match($learning, '(?m)^Source commit: `(?<head>[0-9a-f]{40}|[0-9a-f]{64})`$')
    $expectedPlanLine = "Source plan: ``$($afterPlan.Id) $($afterPlan.Slug)``"
    if (-not $source.Success -or
        -not [regex]::IsMatch($learning, '(?m)^' + [regex]::Escape($expectedPlanLine) + '$')) {
        throw 'Finalization learning does not identify this plan and a full source commit.'
    }
    $sourceHead = $source.Groups['head'].Value
    $learningCommit = Read-Git $worker @('log', '-1', '--format=%H', '--', 'docs/feedback/recent-learning.md')
    $archivePath = [System.IO.Path]::GetRelativePath($worker, $after.PlanPath).Replace('\', '/')
    $archiveCommit = Read-Git $worker @('log', '--no-renames', '--diff-filter=A', '-1', '--format=%H', '--', $archivePath)
    if ($sourceHead -eq $learningCommit -or $learningCommit -eq $archiveCommit -or
        -not $archiveCommit) {
        throw 'Finalization requires separate source, learning and archive commits in order.'
    }
    Read-Git $worker @('merge-base', '--is-ancestor', $ExpectedStartCommit, $sourceHead) | Out-Null
    Read-Git $worker @('merge-base', '--is-ancestor', $sourceHead, $learningCommit) | Out-Null
    Read-Git $worker @('merge-base', '--is-ancestor', $learningCommit, $archiveCommit) | Out-Null
    if ((Read-Git $worker @('rev-parse', "${learningCommit}^")) -cne $sourceHead) {
        throw 'Finalization learning must be committed immediately after its completed source.'
    }
    $activePath = [System.IO.Path]::GetRelativePath($integration, $before.PlanPath).Replace('\', '/')
    $sourcePlan = Read-Git $worker @('show', "${sourceHead}:${activePath}")
    if ([regex]::IsMatch($sourcePlan, '(?m)^\s*- \[(?!x\])')) {
        throw 'Finalization learning source is not a completed active plan.'
    }
    Read-Git $worker @('show', "${learningCommit}:${activePath}") | Out-Null
    $status = 'finalized'
}
else {
    if ($beforePlan.IsArchived -or $afterPlan.IsArchived) {
        throw 'A phase worker cannot archive a plan.'
    }
    $heading = @($before.PhaseSteps.Keys | Where-Object { $_ -match "^##\s+Phase\s+$Phase(?:\D|$)" })
    if ($heading.Count -ne 1) { throw 'Worker phase is not unique.' }
    foreach ($step in $before.Steps) {
        if ($step.Phase -match '^##\s+Phase\s+(\d+)' -and [int]$Matches[1] -lt $Phase -and
            $step.Status -ne 'x') {
            throw 'Worker phase was admitted before earlier phases closed.'
        }
    }
    if ($completed.Count -eq 0) { throw 'Worker produced no newly completed AI step.' }
    $status = if (@($after.PhaseSteps[$heading[0]] | Where-Object { $_.Status -ne 'x' }).Count) {
        'partial'
    } else { 'closed' }
}
[pscustomobject]@{
    Status = $status
    PlanId = $afterPlan.Id
    ExpectedStartCommit = $ExpectedStartCommit
    WorkerCommit = $head
    CompletedSteps = $completed.ToArray()
    RequiresCurrentEvidenceAndScopeReview = $true
}
