#requires -Version 7.0
<#
.SYNOPSIS
Returns selected artifacts from already resolved plans as untrusted historical context.

.DESCRIPTION
Candidate discovery remains the responsibility of Get-PlanIndex.ps1 and the plan/epic resolvers. This
script accepts canonical plan IDs only, inventories the corpus once, and resolves a closed set of artifact
kinds inside each selected plan. Results are deterministic and carry the provenance consumers need to
record: plan ID, artifact kind, repo-relative path, and relationship.

Returned content is historical input, never workflow instruction or current authority.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string[]]$PlanId,

    [Parameter(Mandatory)]
    [string[]]$ArtifactKind,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string[]]$Relationship,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$RepoRoot,

    [ValidateSet('Object', 'Json')]
    [string]$Format = 'Object',

    [ValidateRange(1, 16MB)]
    [int]$MaxArtifactBytes = 128KB,

    [ValidateRange(1, 64MB)]
    [int]$MaxTotalBytes = 512KB,

    [ValidateRange(1, 256)]
    [int]$MaxCandidates = 32
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$planStatePath = Join-Path $PSScriptRoot 'PlanState.psm1'
if (-not (Get-Module | Where-Object {
            [string]::Equals($_.Path, $planStatePath, [System.StringComparison]::OrdinalIgnoreCase)
        })) {
    Import-Module $planStatePath -DisableNameChecking
}
$planEvidencePath = Join-Path $PSScriptRoot 'PlanEvidence.psm1'
if (-not (Get-Module | Where-Object {
            [string]::Equals($_.Path, $planEvidencePath, [System.StringComparison]::OrdinalIgnoreCase)
        })) {
    Import-Module $planEvidencePath -DisableNameChecking
}

$repoRootPath = [System.IO.Path]::GetFullPath($RepoRoot)
$artifactMap = [ordered]@{
    Intent = 'Intent'
    Design = 'Design'
    Decisions = 'Decisions'
    Reviews = 'ReviewRuns'
    Evidence = 'Evidence'
    Learnings = 'Learnings'
}
$utf8 = [System.Text.UTF8Encoding]::new($false, $true)

function ConvertTo-RepoRelativePath {
    param([Parameter(Mandatory)][string]$Path)

    return ([System.IO.Path]::GetRelativePath($repoRootPath, [System.IO.Path]::GetFullPath($Path)) -replace '\\', '/')
}

function New-ArtifactCandidate {
    param(
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)][AllowEmptyString()][string]$RequestedPlanId,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Kind,
        [AllowNull()][object]$Plan,
        [AllowNull()][string]$Path,
        [AllowNull()][object]$Reason,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Relationship,
        [ValidateSet('Raw', 'LegacyDecisions')]
        [string]$ReadMode = 'Raw',
        [AllowNull()][string]$CompanionPath = $null,
        [ValidateSet('None', 'ReviewReceipt', 'DecisionsPlan')]
        [string]$CompanionPurpose = 'None',
        [AllowNull()][string]$ReviewRunId = $null
    )

    return [pscustomobject][ordered]@{
        status = $Status
        planId = if ($Plan) { $Plan.Id } else { $RequestedPlanId }
        artifactKind = $Kind
        path = $Path
        relationship = $Relationship
        layout = if ($Plan) { $Plan.Layout } else { $null }
        isArchived = if ($Plan) { [bool]$Plan.IsArchived } else { $null }
        isUntrusted = $true
        authority = 'historical-context-only'
        byteCount = $null
        content = $null
        reason = $Reason
        planPath = if ($Plan) { $Plan.Path } else { $null }
        confinementContext = if ($Plan) { $Plan.ConfinementContext } else { $null }
        readMode = $ReadMode
        stream = $null
        companionPath = $CompanionPath
        companionStream = $null
        companionPurpose = $CompanionPurpose
        reviewRunId = $ReviewRunId
    }
}

function ConvertTo-PublicArtifactResult {
    param([Parameter(Mandatory)][object]$Candidate)

    return [pscustomobject][ordered]@{
        status = $Candidate.status
        planId = $Candidate.planId
        artifactKind = $Candidate.artifactKind
        path = $Candidate.path
        relationship = $Candidate.relationship
        layout = $Candidate.layout
        isArchived = $Candidate.isArchived
        isUntrusted = $Candidate.isUntrusted
        authority = $Candidate.authority
        byteCount = $Candidate.byteCount
        content = $Candidate.content
        reason = $Candidate.reason
    }
}

function Get-OrdinallySortedUnique {
    param([Parameter(Mandatory)][string[]]$Value)

    $values = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($item in $Value) {
        if ($seen.Add($item)) {
            $values.Add($item)
        }
    }
    $values.Sort([System.Comparison[string]] { param($left, $right) [string]::CompareOrdinal($left, $right) })
    return $values.ToArray()
}

function Read-BoundedUtf8Stream {
    param(
        [Parameter(Mandatory)][System.IO.FileStream]$Stream,
        [Parameter(Mandatory)][string]$Path
    )

    if ($Stream.Length -eq 0) {
        return [pscustomobject]@{ Status = 'refused'; ByteCount = 0; Content = $null; Bytes = $null }
    }
    if ($Stream.Length -gt $MaxArtifactBytes) {
        return [pscustomobject]@{ Status = 'oversized'; ByteCount = $Stream.Length; Content = $null; Bytes = $null }
    }

    $Stream.Position = 0
    $length = [int]$Stream.Length
    $bytes = [byte[]]::new($length)
    $offset = 0
    while ($offset -lt $length) {
        $read = $Stream.Read($bytes, $offset, $length - $offset)
        if ($read -eq 0) {
            throw "Artifact '$Path' changed while it was being read."
        }
        $offset += $read
    }
    if ($Stream.ReadByte() -ne -1) {
        return [pscustomobject]@{ Status = 'oversized'; ByteCount = $null; Content = $null; Bytes = $null }
    }

    $content = $utf8.GetString($bytes)
    if ([string]::IsNullOrWhiteSpace($content)) {
        return [pscustomobject]@{
            Status = 'refused'
            ByteCount = $length
            Content = $null
            Bytes = $null
        }
    }

    return [pscustomobject]@{
        Status = 'accepted'
        ByteCount = $length
        Content = $content
        Bytes = $bytes
    }
}

$relationshipValues = @(
    'reuses', 'extends', 'supersedes', 'conflicts', 'dependency', 'sibling', 'operator-selected'
)
$relationshipSet = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]$relationshipValues,
    [System.StringComparer]::Ordinal
)
$relationshipByPlan = [System.Collections.Generic.Dictionary[string, string]]::new(
    [System.StringComparer]::Ordinal
)
$relationshipError = $null
if ($Relationship.Count -ne 1 -and $Relationship.Count -ne $PlanId.Count) {
    $relationshipError = 'Relationship must contain one value for all plans or one value aligned with each PlanId.'
}
else {
    for ($index = 0; $index -lt $PlanId.Count; $index++) {
        $id = [string]$PlanId[$index]
        $mappedRelationship = [string]$(if ($Relationship.Count -eq 1) { $Relationship[0] } else { $Relationship[$index] })
        if (-not $relationshipSet.Contains($mappedRelationship)) {
            $relationshipError = "Relationship '$mappedRelationship' is not supported."
            break
        }
        if ($relationshipByPlan.ContainsKey($id) -and
            -not [string]::Equals($relationshipByPlan[$id], $mappedRelationship, [System.StringComparison]::Ordinal)) {
            $relationshipError = "Plan ID '$id' has conflicting relationship values."
            break
        }
        $relationshipByPlan[$id] = $mappedRelationship
    }
}

$ids = @(Get-OrdinallySortedUnique -Value $PlanId)
$kinds = @(Get-OrdinallySortedUnique -Value $ArtifactKind)
$combinationCount = [int64]$ids.Count * [int64]$kinds.Count
$inputError = $relationshipError
if (-not $inputError) {
    foreach ($inputSet in @(
            [pscustomobject]@{ Name = 'PlanId'; Values = @($PlanId) }
            [pscustomobject]@{ Name = 'ArtifactKind'; Values = @($ArtifactKind) }
            [pscustomobject]@{ Name = 'Relationship'; Values = @($Relationship) }
        )) {
        for ($index = 0; $index -lt $inputSet.Values.Count; $index++) {
            $value = [string]$inputSet.Values[$index]
            if ([string]::IsNullOrWhiteSpace($value)) {
                $inputError = "$($inputSet.Name)[$index] is empty."
                break
            }
            if ($value.Length -gt 64) {
                $inputError = "$($inputSet.Name)[$index] exceeds the 64-character limit."
                break
            }
        }
        if ($inputError) { break }
    }
}
if (-not $inputError -and ($ids.Count -eq 0 -or $kinds.Count -eq 0)) {
    $inputError = 'PlanId and ArtifactKind must each contain at least one value.'
}
if (-not $inputError -and $combinationCount -gt $MaxCandidates) {
    $inputError = "Selection expands to $combinationCount candidates, exceeding the $MaxCandidates-candidate limit."
}
if ($inputError) {
    $refusal = New-ArtifactCandidate `
        -Status 'refused' `
        -RequestedPlanId $(if ($ids.Count -eq 1 -and $ids[0].Length -le 64) { $ids[0] } else { '' }) `
        -Kind $(if ($kinds.Count -eq 1 -and $kinds[0].Length -le 64) { $kinds[0] } else { '' }) `
        -Relationship $(if ($Relationship.Count -eq 1 -and $Relationship[0].Length -le 64) { $Relationship[0] } else { '' }) `
        -Plan $null `
        -Path $null `
        -Reason $inputError
    $publicRefusal = ConvertTo-PublicArtifactResult -Candidate $refusal
    if ([string]::IsNullOrEmpty($publicRefusal.planId)) { $publicRefusal.planId = $null }
    if ([string]::IsNullOrEmpty($publicRefusal.artifactKind)) { $publicRefusal.artifactKind = $null }
    if ([string]::IsNullOrEmpty($publicRefusal.relationship)) { $publicRefusal.relationship = $null }
    if ($Format -eq 'Json') {
        ConvertTo-Json -InputObject @($publicRefusal) -Depth 5
    }
    else {
        $publicRefusal
    }
    return
}

$plansRoot = Join-Path $repoRootPath 'docs/implementation-plans'
if (-not (Test-Path -LiteralPath $repoRootPath -PathType Container)) {
    throw "RepoRoot '$repoRootPath' is not an existing directory."
}
if (-not (Test-Path -LiteralPath $plansRoot -PathType Container)) {
    throw "RepoRoot '$repoRootPath' does not contain the required plan corpus at '$plansRoot'."
}

$inventory = @(Get-PlanInventory -RepoRoot $repoRootPath)
$candidates = [System.Collections.Generic.List[object]]::new()
$selectionOverflow = $false
$selectionOverflowReason = $null
$attemptedCandidateCount = 0

function Add-ArtifactCandidate {
    param([Parameter(Mandatory)][object]$Candidate)

    $script:attemptedCandidateCount++
    if ($script:candidates.Count -eq $MaxCandidates) {
        $script:selectionOverflow = $true
        $script:selectionOverflowReason =
        "Selection produced at least $($script:attemptedCandidateCount) candidates, exceeding the $MaxCandidates-candidate limit."
        return
    }
    $script:candidates.Add($Candidate)
}

foreach ($id in $ids) {
    $planRelationship = $relationshipByPlan[$id]
    $plan = $null
    $planRefusal = $null
    if ($id -notmatch '^(?:[0-9a-f]{6}|\d{3})$') {
        $planRefusal = "Plan ID '$id' is not a canonical resolved plan ID."
    }
    else {
        $matches = @($inventory | Where-Object { $_.Id -ceq $id })
        if ($matches.Count -ne 1) {
            $planRefusal = "Plan ID '$id' is not a unique member of the plan inventory."
        }
        else {
            try {
                $entry = $matches[0]
                $planItem = Get-Item -LiteralPath $entry.Path -Force -ErrorAction Stop
                if (($planItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                    throw "Inventoried plan folder '$($entry.Path)' is a link or reparse point."
                }
                $planFile = Join-Path $entry.Path 'plan.md'
                $confinementContext = New-PlanConfinementContext -PlanDir $entry.Path
                $null = Resolve-ConfinedPlanPath `
                    -Context $confinementContext `
                    -Path $planFile `
                    -PathType Leaf
                $plan = [pscustomobject]@{
                    Id = $entry.Id
                    Path = $entry.Path
                    ConfinementContext = $confinementContext
                    IsArchived = [bool]$entry.IsArchived
                    Layout = Get-PlanLayout -PlanDir $entry.Path
                }
            }
            catch {
                $planRefusal = $_.Exception.Message
            }
        }
    }

    foreach ($kind in $kinds) {
        if ($planRefusal) {
            Add-ArtifactCandidate (New-ArtifactCandidate -Status 'refused' -RequestedPlanId $id -Kind $kind -Relationship $planRelationship -Plan $null -Path $null -Reason $planRefusal)
            continue
        }
        if ($artifactMap.Keys -cnotcontains $kind) {
            Add-ArtifactCandidate (New-ArtifactCandidate -Status 'refused' -RequestedPlanId $id -Kind $kind -Relationship $planRelationship -Plan $plan -Path $null -Reason "Artifact kind '$kind' is not supported.")
            continue
        }

        try {
            $resolvedPath = Resolve-PlanAssetPath `
                -PlanDir $plan.Path `
                -Kind $artifactMap[$kind] `
                -Layout $plan.Layout

            if ($kind -eq 'Reviews') {
                $relativeRoot = ConvertTo-RepoRelativePath $resolvedPath
                if (-not (Test-Path -LiteralPath $resolvedPath)) {
                    Add-ArtifactCandidate (New-ArtifactCandidate -Status 'missing' -RequestedPlanId $id -Kind $kind -Relationship $planRelationship -Plan $plan -Path $relativeRoot -Reason 'No finalized review artifact exists.')
                    continue
                }

                $null = Resolve-ConfinedPlanPath `
                    -Context $plan.ConfinementContext `
                    -Path $resolvedPath `
                    -PathType Container

                $reviewPaths = [System.Collections.Generic.List[object]]::new()
                $scannedEntries = 0
                $reviewOverflow = $false
                foreach ($reviewPath in [System.IO.Directory]::EnumerateFileSystemEntries(
                        $resolvedPath,
                        '*',
                        [System.IO.SearchOption]::TopDirectoryOnly
                    )) {
                    $scannedEntries++
                    if ($scannedEntries -gt $MaxCandidates) {
                        $reviewOverflow = $true
                        break
                    }
                    $reviewName = [System.IO.Path]::GetFileName($reviewPath)
                    if ($reviewName -cnotmatch '^(?<id>[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12})\.review\.md$') {
                        continue
                    }
                    $reviewPaths.Add([pscustomobject]@{
                            Path = $reviewPath
                            Name = $reviewName
                            RunId = [string]$Matches.id
                        })
                }
                if ($reviewOverflow) {
                    $selectionOverflow = $true
                    $selectionOverflowReason =
                    "Review scan inspected $scannedEntries entries, exceeding the $MaxCandidates-entry scan limit."
                    Add-ArtifactCandidate (New-ArtifactCandidate -Status 'refused' -RequestedPlanId $id -Kind $kind -Relationship $planRelationship -Plan $plan -Path $relativeRoot -Reason "Review directory exceeds the $MaxCandidates-entry scan limit.")
                    continue
                }
                $reviewPaths.Sort([System.Comparison[object]] {
                        param($left, $right)
                        [string]::CompareOrdinal([string]$left.Path, [string]$right.Path)
                    })
                $finalizedCount = 0
                foreach ($reviewEntry in $reviewPaths) {
                    $finalizedCount++
                    $reviewPath = [string]$reviewEntry.Path
                    $relativePath = ConvertTo-RepoRelativePath $reviewPath
                    $receiptPath = Join-Path $resolvedPath "$($reviewEntry.RunId).receipt.json"
                    if (-not (Test-Path -LiteralPath $receiptPath)) {
                        Add-ArtifactCandidate (New-ArtifactCandidate -Status 'refused' -RequestedPlanId $id -Kind $kind -Relationship $planRelationship -Plan $plan -Path $relativePath -Reason 'Finalized review artifact has no matching receipt.')
                        continue
                    }
                    try {
                        $reviewFile = Get-Item -LiteralPath $reviewPath -Force -ErrorAction Stop
                        if ($reviewFile -isnot [System.IO.FileInfo]) {
                            throw "Finalized review '$reviewPath' is not a regular file."
                        }
                        $receiptFile = Get-Item -LiteralPath $receiptPath -Force -ErrorAction Stop
                        if ($receiptFile -isnot [System.IO.FileInfo]) {
                            throw "Finalized review receipt '$receiptPath' is not a regular file."
                        }
                    }
                    catch {
                        Add-ArtifactCandidate (New-ArtifactCandidate -Status 'refused' -RequestedPlanId $id -Kind $kind -Relationship $planRelationship -Plan $plan -Path $relativePath -Reason "Finalized review pair was refused: $($_.Exception.Message)")
                        continue
                    }
                    Add-ArtifactCandidate (New-ArtifactCandidate -Status 'pending' -RequestedPlanId $id -Kind $kind -Relationship $planRelationship -Plan $plan -Path $relativePath -Reason $null -CompanionPath (ConvertTo-RepoRelativePath $receiptPath) -CompanionPurpose ReviewReceipt -ReviewRunId $reviewEntry.RunId)
                }
                if ($finalizedCount -eq 0) {
                    Add-ArtifactCandidate (New-ArtifactCandidate -Status 'missing' -RequestedPlanId $id -Kind $kind -Relationship $planRelationship -Plan $plan -Path $relativeRoot -Reason 'No finalized review artifact exists.')
                }
                continue
            }

            if ($kind -eq 'Decisions') {
                $planFile = Join-Path $plan.Path 'plan.md'
                if (-not (Test-Path -LiteralPath $resolvedPath)) {
                    Add-ArtifactCandidate (New-ArtifactCandidate -Status 'pending' -RequestedPlanId $id -Kind $kind -Relationship $planRelationship -Plan $plan -Path (ConvertTo-RepoRelativePath $planFile) -Reason $null -ReadMode LegacyDecisions)
                    continue
                }
                Add-ArtifactCandidate (New-ArtifactCandidate -Status 'pending' -RequestedPlanId $id -Kind $kind -Relationship $planRelationship -Plan $plan -Path (ConvertTo-RepoRelativePath $resolvedPath) -Reason $null -CompanionPath (ConvertTo-RepoRelativePath $planFile) -CompanionPurpose DecisionsPlan)
                continue
            }

            $relativePath = ConvertTo-RepoRelativePath $resolvedPath
            if (-not (Test-Path -LiteralPath $resolvedPath)) {
                Add-ArtifactCandidate (New-ArtifactCandidate -Status 'missing' -RequestedPlanId $id -Kind $kind -Relationship $planRelationship -Plan $plan -Path $relativePath -Reason 'Artifact file does not exist.')
                continue
            }

            Add-ArtifactCandidate (New-ArtifactCandidate -Status 'pending' -RequestedPlanId $id -Kind $kind -Relationship $planRelationship -Plan $plan -Path $relativePath -Reason $null)
        }
        catch {
            Add-ArtifactCandidate (New-ArtifactCandidate -Status 'refused' -RequestedPlanId $id -Kind $kind -Relationship $planRelationship -Plan $plan -Path $null -Reason $_.Exception.Message)
        }
    }
}

$eligibleBytes = [int64]0
try {
    $pendingCandidates = @($candidates | Where-Object status -eq 'pending')
    $requiredHandles = @($pendingCandidates | ForEach-Object {
            if (-not [string]::IsNullOrWhiteSpace($_.companionPath)) { 2 } else { 1 }
        } | Measure-Object -Sum).Sum
    if ($selectionOverflow -or $requiredHandles -gt $MaxCandidates) {
        $overflowReason = if ($selectionOverflow) {
            $selectionOverflowReason
        }
        else {
            "Selection requires $requiredHandles open handles, exceeding the $MaxCandidates-handle limit."
        }
        foreach ($candidate in @($candidates | Where-Object status -eq 'pending')) {
            $candidate.status = 'refused'
            $candidate.content = $null
            $candidate.reason = $overflowReason
        }
        $pendingCandidates = @()
    }

    foreach ($candidate in $pendingCandidates) {
        try {
            if (-not [string]::IsNullOrWhiteSpace($candidate.companionPath)) {
                $companionFullPath = Join-Path $repoRootPath $candidate.companionPath
                $candidate.companionStream = Open-ConfinedPlanFile `
                    -Context $candidate.confinementContext `
                    -Path $companionFullPath
                if ($candidate.companionStream.Length -eq 0) {
                    throw "$($candidate.companionPurpose) companion '$($candidate.companionPath)' is empty."
                }
                if ($candidate.companionStream.Length -gt $MaxArtifactBytes) {
                    $candidate.status = 'oversized'
                    $candidate.byteCount = [int64]$candidate.companionStream.Length
                    $candidate.reason = "$($candidate.companionPurpose) companion is $($candidate.companionStream.Length) bytes; the per-artifact limit is $MaxArtifactBytes bytes."
                    $candidate.companionStream.Dispose()
                    $candidate.companionStream = $null
                    continue
                }
            }

            $fullPath = Join-Path $repoRootPath $candidate.path
            $stream = Open-ConfinedPlanFile `
                -Context $candidate.confinementContext `
                -Path $fullPath
            $candidate.stream = $stream
            $candidate.byteCount = [int64]$stream.Length
            if ($stream.Length -eq 0) {
                $candidate.status = 'refused'
                $candidate.reason = 'Artifact file is empty.'
                $stream.Dispose()
                $candidate.stream = $null
                if ($null -ne $candidate.companionStream) {
                    $candidate.companionStream.Dispose()
                    $candidate.companionStream = $null
                }
            }
            elseif ($stream.Length -gt $MaxArtifactBytes) {
                $candidate.status = 'oversized'
                $candidate.reason = "Artifact is $($stream.Length) bytes; the per-artifact limit is $MaxArtifactBytes bytes."
                $stream.Dispose()
                $candidate.stream = $null
                if ($null -ne $candidate.companionStream) {
                    $candidate.companionStream.Dispose()
                    $candidate.companionStream = $null
                }
            }
            else {
                $eligibleBytes += $stream.Length
                if ($null -ne $candidate.companionStream) {
                    $eligibleBytes += $candidate.companionStream.Length
                }
            }
        }
        catch {
            if ($null -ne $candidate.stream) {
                $candidate.stream.Dispose()
                $candidate.stream = $null
            }
            if ($null -ne $candidate.companionStream) {
                $candidate.companionStream.Dispose()
                $candidate.companionStream = $null
            }
            $candidate.status = 'refused'
            $candidate.reason = $_.Exception.Message
        }
    }

    if ($eligibleBytes -gt $MaxTotalBytes) {
        foreach ($candidate in @($candidates | Where-Object status -eq 'pending')) {
            $candidate.status = 'oversized'
            $candidate.reason = "Selected artifacts total $eligibleBytes bytes; the aggregate limit is $MaxTotalBytes bytes."
        }
    }
    else {
        $actualBytes = [int64]0
        foreach ($candidate in @($candidates | Where-Object status -eq 'pending')) {
            try {
                $read = Read-BoundedUtf8Stream -Stream $candidate.stream -Path $candidate.path
                $candidate.byteCount = if ($null -eq $read.ByteCount) { $null } else { [int64]$read.ByteCount }
                if ($read.Status -eq 'refused') {
                    $candidate.status = 'refused'
                    $candidate.reason = if ($read.ByteCount -eq 0) {
                        'Artifact file is empty.'
                    }
                    else {
                        'Artifact file contains only whitespace.'
                    }
                    continue
                }
                if ($read.Status -eq 'oversized') {
                    $candidate.status = 'oversized'
                    $candidate.reason = "Artifact exceeded the per-artifact limit of $MaxArtifactBytes bytes while being read."
                    continue
                }

                $companionRead = $null
                if ($null -ne $candidate.companionStream) {
                    $companionRead = Read-BoundedUtf8Stream -Stream $candidate.companionStream -Path $candidate.companionPath
                    if ($companionRead.Status -ne 'accepted') {
                        $candidate.status = $companionRead.Status
                        $candidate.byteCount = if ($null -eq $companionRead.ByteCount) {
                            $null
                        }
                        else {
                            [int64]$companionRead.ByteCount
                        }
                        $candidate.reason = if ($companionRead.Status -eq 'oversized') {
                            "$($candidate.companionPurpose) companion exceeded the per-artifact limit of $MaxArtifactBytes bytes while being read."
                        }
                        elseif ($companionRead.ByteCount -gt 0) {
                            "$($candidate.companionPurpose) companion contains only whitespace."
                        }
                        else {
                            "$($candidate.companionPurpose) companion is empty."
                        }
                        continue
                    }
                }

                if ($candidate.companionPurpose -eq 'ReviewReceipt') {
                    $null = Assert-ReviewResultReceipt `
                        -ReviewRunId $candidate.reviewRunId `
                        -ReportName ([System.IO.Path]::GetFileName($candidate.path)) `
                        -ReportBytes $read.Bytes `
                        -ReceiptContent $companionRead.Content
                }

                $content = if ($candidate.artifactKind -eq 'Decisions') {
                    $decisionSection = if ($candidate.readMode -eq 'LegacyDecisions') {
                        Resolve-PlanSection `
                            -PlanDir $candidate.planPath `
                            -Section Decisions `
                            -LegacyContent $read.Content `
                            -AssetAbsent
                    }
                    else {
                        Resolve-PlanSection `
                            -PlanDir $candidate.planPath `
                            -Section Decisions `
                            -LegacyContent $companionRead.Content `
                            -AssetContent $read.Content `
                            -AssetPath (Join-Path $repoRootPath $candidate.path)
                    }
                    if ($decisionSection.Source -eq 'none') {
                        $null
                    }
                    elseif ($candidate.readMode -eq 'LegacyDecisions') {
                        $decisionLines = [string[]](
                            Get-PlanInlineSectionLine `
                                -Content $read.Content `
                                -Section Decisions `
                                -PreserveFencedContent
                        )
                        [string]::Join("`n", $decisionLines).Trim()
                    }
                    else {
                        $read.Content
                    }
                }
                else {
                    $read.Content
                }
                if ($null -eq $content) {
                    $candidate.status = 'missing'
                    $candidate.reason = 'No legacy Decisions section exists.'
                    continue
                }

                $candidate.status = 'accepted'
                $candidate.content = $content
                $candidate.byteCount = [int64]$utf8.GetByteCount($content)
                $actualBytes += [int64]$read.ByteCount
                if ($null -ne $companionRead) {
                    $actualBytes += [int64]$companionRead.ByteCount
                }
            }
            catch {
                $candidate.status = 'refused'
                $candidate.reason = $_.Exception.Message
            }
        }

        if ($actualBytes -gt $MaxTotalBytes) {
            foreach ($candidate in @($candidates | Where-Object status -eq 'accepted')) {
                $candidate.status = 'oversized'
                $candidate.content = $null
                $candidate.reason = "Selected artifacts exceeded the aggregate limit of $MaxTotalBytes bytes while being read."
            }
        }
    }
}
finally {
    foreach ($candidate in $candidates) {
        if ($null -ne $candidate.stream) {
            $candidate.stream.Dispose()
        }
        if ($null -ne $candidate.companionStream) {
            $candidate.companionStream.Dispose()
        }
    }
}

$output = [System.Collections.Generic.List[object]]::new()
foreach ($candidate in $candidates) {
    $output.Add((ConvertTo-PublicArtifactResult -Candidate $candidate))
}
if ($Format -eq 'Json') {
    ConvertTo-Json -InputObject $output.ToArray() -Depth 5
}
else {
    $output.ToArray()
}
