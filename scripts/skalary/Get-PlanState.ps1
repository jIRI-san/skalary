#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string]$Reference,

    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path,

    [switch]$HasUncommittedChanges,

    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'PlanState.psm1') -Force -DisableNameChecking

$repoRootPath = [System.IO.Path]::GetFullPath($RepoRoot)

$plan = Resolve-Plan -Reference $Reference -RepoRoot $repoRootPath
$planFile = Join-Path $plan.Path 'plan.md'
if (-not (Test-Path -LiteralPath $planFile -PathType Leaf)) {
    throw "Resolved plan '$($plan.Id)' has no plan.md at $planFile."
}

$metadata = Get-PlanMetadata -Path $planFile -RepoRoot $repoRootPath
$markers = Get-PlanHeaderMarkers -Path $planFile
$progress = Get-PlanProgress -Metadata $metadata

if ($PSBoundParameters.ContainsKey('HasUncommittedChanges')) {
    $dirty = [bool]$HasUncommittedChanges
}
else {
    $dirty = $false
    try {
        $status = & git -C $repoRootPath status --porcelain 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(($status -join ''))) {
            $dirty = $true
        }
    }
    catch {
        $dirty = $false
    }
}

$next = Get-NextStep -Metadata $metadata -HasUncommittedChanges:$dirty

$state = [pscustomobject]@{
    PlanId                = if ($markers.PlanId) { $markers.PlanId } else { $plan.Id }
    Reference             = $Reference
    FolderName            = $plan.FolderName
    PlanFile              = $planFile
    Scheme                = $plan.Scheme
    IsArchived            = $plan.IsArchived
    HasUncommittedChanges = $dirty
    Markers               = [pscustomobject]@{
        ExecutionMode = $markers.ExecutionMode
        Scope         = $markers.Scope
        CipStage      = $markers.CipStage
        DependsOn     = @($markers.DependsOn)
    }
    Progress              = [pscustomobject]@{
        Total         = $progress.Total
        Completed     = $progress.Completed
        InProgress    = $progress.InProgress
        Pending       = $progress.Pending
        Percent       = $progress.Percent
        CurrentPhase  = $progress.CurrentPhase
        LastCompleted = $progress.LastCompleted
        IsComplete    = $progress.IsComplete
    }
    NextStep              = [pscustomobject]@{
        Id             = $next.Id
        Status         = $next.Status
        IsHuman        = $next.IsHuman
        IsDiscovery    = $next.IsDiscovery
        Detail         = $next.Detail
        BlockedByAfter = $next.BlockedByAfter
        UnmetAfter     = @($next.UnmetAfter)
        IsComplete     = $next.IsComplete
    }
}

if ($Json) {
    return ($state | ConvertTo-Json -Depth 6)
}

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add("Plan:       $($state.PlanId)  ($($state.FolderName))")
$lines.Add("Scheme:     $($state.Scheme)$(if ($state.IsArchived) { ' (archived)' } else { '' })")
$lines.Add("Mode:       $($state.Markers.ExecutionMode)   Scope: $($state.Markers.Scope)   Stage: $($state.Markers.CipStage)")
if ($state.Markers.DependsOn.Count -gt 0) {
    $lines.Add("Depends-on: $($state.Markers.DependsOn -join ', ')")
}
$lines.Add("Progress:   $($state.Progress.Completed)/$($state.Progress.Total) done ($($state.Progress.Percent)%)  in-progress=$($state.Progress.InProgress)  pending=$($state.Progress.Pending)")
$lines.Add("Phase:      $($state.Progress.CurrentPhase)")
$lines.Add("Last done:  $(if ($state.Progress.LastCompleted) { $state.Progress.LastCompleted } else { '(none)' })")
$lines.Add("Dirty tree: $($state.HasUncommittedChanges)")
if ($state.NextStep.IsComplete) {
    $lines.Add("Next step:  (none — all steps complete)")
}
else {
    $flags = @()
    if ($state.NextStep.IsHuman) { $flags += '@human' }
    if ($state.NextStep.IsDiscovery) { $flags += '[discovery]' }
    if ($state.NextStep.BlockedByAfter) { $flags += "blocked-by-after: $($state.NextStep.UnmetAfter -join ', ')" }
    $flagText = if ($flags.Count -gt 0) { "  [$($flags -join '; ')]" } else { '' }
    $lines.Add("Next step:  $($state.NextStep.Id) (status '$($state.NextStep.Status)')$flagText")

    # An @human step is an operator handoff: print its full detail block, not just the title, so the
    # round-trip is single-pass (the same block the human-step-detail gate requires).
    if ($state.NextStep.IsHuman) {
        $lines.Add('Handoff:')
        if ([string]::IsNullOrWhiteSpace($state.NextStep.Detail)) {
            $lines.Add('  (no <details> block on this step — it does not satisfy the human-step-detail gate)')
        }
        else {
            foreach ($detailLine in ($state.NextStep.Detail -replace "`r`n", "`n").Split("`n")) {
                $lines.Add("  $detailLine".TrimEnd())
            }
        }
    }
}

return ($lines -join [Environment]::NewLine)
