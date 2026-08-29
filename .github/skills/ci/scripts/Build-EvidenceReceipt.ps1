#requires -Version 7.0
[CmdletBinding()]
param(
    [AllowEmptyCollection()]
    [object[]]$Result = @(),

    [string[]]$StructuredTestResultPath = @(),

    [string]$Commit,

    [int]$Phase,

    [string]$PlanDir,

    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$receiptPath = $null
$metadata = $null
if ($PlanDir) {
    Import-Module (Join-Path $PSScriptRoot 'PlanState.psm1') -DisableNameChecking
    $metadata = Get-PlanMetadata -Path (Join-Path $PlanDir 'plan.md') -RepoRoot $RepoRoot
}
Import-Module (Join-Path $PSScriptRoot 'PlanEvidence.psm1') -DisableNameChecking
if ($metadata) {
    $receiptPath = Resolve-PlanEvidenceAssetPath -PlanMetadata $metadata -Kind Evidence
}
if ($StructuredTestResultPath.Count -gt 0 -and -not $metadata) {
    throw 'Build-EvidenceReceipt requires -PlanDir when -StructuredTestResultPath is supplied.'
}

$allResults = [System.Collections.Generic.List[object]]::new()
$allResults.AddRange([object[]]$Result)
foreach ($path in $StructuredTestResultPath) {
    $allResults.AddRange([object[]]@(
            ConvertFrom-StructuredTestEvidenceResult -Path $path -PlanMetadata $metadata
        ))
}
if ($allResults.Count -eq 0) {
    throw 'Build-EvidenceReceipt requires at least one result.'
}

if (-not $Commit) {
    $repoRootPath = [System.IO.Path]::GetFullPath($RepoRoot)
    $Commit = (& git -C $repoRootPath rev-parse HEAD 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($Commit)) {
        throw 'Build-EvidenceReceipt could not resolve HEAD; pass -Commit explicitly.'
    }
    $Commit = $Commit.Trim()
}
if ($Commit -notmatch '^[0-9a-fA-F]{40}$') {
    throw "Build-EvidenceReceipt requires a full 40-hex commit, got '$Commit'."
}
$Commit = $Commit.ToLowerInvariant()

$dash = [char]0x2014
$sep = " $dash "

$lines = [System.Collections.Generic.List[string]]::new()
$reqOrder = [System.Collections.Generic.List[string]]::new()
$reqStatus = [ordered]@{}
$outcomes = [System.Collections.Generic.List[object]]::new()
$waivers = if ($metadata) { @(Get-PlanEvidenceWaiver -PlanMetadata $metadata -PlanDirectory $PlanDir) } else { @() }
$seenResults = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

foreach ($item in $allResults) {
    $normalized = ConvertTo-PlanEvidenceResult -InputObject $item
    $req = $normalized.Req
    $marker = $normalized.Marker
    $resultKey = "$req|$marker"
    if (-not $seenResults.Add($resultKey)) {
        throw "Duplicate evidence result '$resultKey'."
    }

    $status = $normalized.Status
    $detail = $normalized.Note
    $matchingWaivers = @($waivers | Where-Object {
            $_.Applies -and $_.Requirement -ceq $req -and $_.Marker -ceq $marker -and $_.Outcome -ceq $status
        })
    if ($matchingWaivers.Count -gt 1) {
        throw "Multiple evidence waivers apply to '$resultKey'."
    }
    if ($status -eq 'waived') {
        throw "Evidence result '$resultKey' claims waived without an exact skipped/degraded source outcome."
    }
    if ($matchingWaivers.Count -eq 1) {
        $sourceStatus = $status
        $status = 'waived'
        $detail = "from ${sourceStatus}: $($matchingWaivers[0].Reason)"
    }

    if ($status -eq 'passed') {
        $glyph = [char]0x2713
    }
    elseif ($status -eq 'waived') {
        $glyph = [char]0x2298
    }
    else {
        $glyph = [char]0x2717
    }

    $resultText = if ($detail) { "${status}: $detail" } else { $status }

    $lines.Add("$glyph $req$sep$marker$sep$resultText$sep$Commit")
    $outcomes.Add([pscustomobject]@{
            Req = $req
            Marker = $marker
            Status = $status
            Success = ($status -in @('passed', 'waived'))
            Note = $detail
        })

    if (-not $reqStatus.Contains($req)) {
        $reqOrder.Add($req)
        $reqStatus[$req] = $true
    }
    if ($status -notin @('passed', 'waived')) {
        $reqStatus[$req] = $false
    }
}

$textLines = [System.Collections.Generic.List[string]]::new()
if ($PSBoundParameters.ContainsKey('Phase')) {
    $textLines.Add("Phase $Phase Crosscheck:")
}
$textLines.AddRange($lines)

$allPassed = $true
foreach ($req in $reqOrder) {
    if (-not $reqStatus[$req]) { $allPassed = $false; break }
}

return [pscustomobject]@{
    Commit      = $Commit
    Lines       = $lines.ToArray()
    Text        = ($textLines -join "`n")
    Outcomes    = $outcomes.ToArray()
    ReqStatus   = $reqStatus
    AllPassed   = ($reqOrder.Count -gt 0 -and $allPassed)
    ReceiptPath = $receiptPath
}
