#requires -Version 7.0
<#
.SYNOPSIS
    Scaffolds an epic folder plus `epic.md` and stamps child plans into it.
.DESCRIPTION
    An epic is an index over ordinary sibling plan folders, never a container for them: child plans stay
    directly under `docs/implementation-plans/` so `Resolve-Plan`, `Get-PlanState`, and the validator keep
    resolving them unchanged, and each child stays independently executable.

    Membership lives in the child: `<!-- epic: <id> -->` in its `plan.md`. The child-plan table inside
    `epic.md` is a generated mirror of that marker set, rewritten on every run, so the two can never
    disagree. Ordering between children is expressed with the existing `<!-- depends-on: ... -->` marker.
.EXAMPLE
    New-Epic.ps1 -Title 'Payments rework' -Slug payments-rework
.EXAMPLE
    New-Epic.ps1 -Epic 9f2a1c -ChildPlan checkout-api -DependsOn payments-core
.EXAMPLE
    New-Epic.ps1 -Epic 9f2a1c -SetCoherencyVerdict -VerdictJson $json
#>
[CmdletBinding(DefaultParameterSetName = 'Scaffold')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Scaffold')]
    [string]$Title,

    [Parameter(Mandatory, ParameterSetName = 'Scaffold')]
    [string]$Slug,

    [Parameter(Mandatory, ParameterSetName = 'Attach')]
    [Parameter(Mandatory, ParameterSetName = 'Verdict')]
    [string]$Epic,

    [Parameter(Mandatory, ParameterSetName = 'Verdict')]
    [switch]$SetCoherencyVerdict,

    [Parameter(Mandatory, ParameterSetName = 'Verdict')]
    [ValidateLength(2, 65536)]
    [string]$VerdictJson,

    [Parameter(ParameterSetName = 'Attach')]
    [string[]]$ChildPlan = @(),

    [Parameter(ParameterSetName = 'Attach')]
    [string[]]$DependsOn = @(),

    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path,

    [Parameter(ParameterSetName = 'Scaffold')]
    [string]$Date = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd'),

    [Parameter(ParameterSetName = 'Scaffold')]
    [string]$EpicId,

    [Parameter(ParameterSetName = 'Scaffold')]
    [Parameter(ParameterSetName = 'Attach')]
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'PlanState.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AtomicStore.psm1') -Force -DisableNameChecking

function Write-PlanText {
    <#
    .SYNOPSIS
    Writes markdown back with exactly one trailing newline.

    .DESCRIPTION
    `Set-Content` appends a trailing newline of its own, so round-tripping raw content through
    split/join would grow the file by one blank line per rewrite and make repeat runs non-idempotent.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines
    )

    Set-Content -LiteralPath $Path -Value (($Lines -join "`n").TrimEnd("`n")) -Encoding utf8NoBOM
}

function Test-DirectoryEntryExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $comparison = if ($IsWindows) {
        [System.StringComparison]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparison]::Ordinal
    }
    $parent = Split-Path -Parent $Path
    $name = Split-Path -Leaf $Path
    return @(
        Get-ChildItem -LiteralPath $parent -Force -ErrorAction Stop |
            Where-Object { [string]::Equals($_.Name, $name, $comparison) }
    ).Count -gt 0
}

function Get-SanitizedSlug {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    $clean = $Value.ToLowerInvariant()
    $clean = $clean -replace '[^a-z0-9]+', '-'
    $clean = $clean.Trim('-')
    if ([string]::IsNullOrWhiteSpace($clean)) {
        throw "Slug '$Value' is empty after sanitization; supply alphanumeric characters."
    }

    return $clean
}

function Resolve-ConfinedFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Root,

        [Parameter(Mandatory)]
        [string]$FolderName
    )

    $resolvedRoot = [System.IO.Path]::GetFullPath($Root)
    $candidate = [System.IO.Path]::GetFullPath((Join-Path $resolvedRoot $FolderName))
    $separator = [System.IO.Path]::DirectorySeparatorChar
    $rootWithSeparator = $resolvedRoot.TrimEnd($separator) + $separator
    if (-not $candidate.StartsWith($rootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Resolved epic folder '$candidate' escapes epics root '$resolvedRoot'."
    }

    return $candidate
}

function Get-EpicScaffold {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Id,

        [Parameter(Mandatory)]
        [string]$EpicTitle
    )

    return @"
# ${Id}: $EpicTitle
<!-- epic-id: $Id -->
<!-- Folder naming: epics/<yyyy-mm-dd>-<6hex>-<slug> · epic-id is the canonical handle. New-Epic.ps1 fills these in. -->

## Goal

TBD

## Child plans

$script:ChildBlockStart
| Plan | Slug | Depends on |
|---|---|---|
| _(none yet)_ | | |
$script:ChildBlockEnd

Membership is the ``<!-- epic: $Id -->`` marker in each child ``plan.md``; the table above is a generated
mirror that ``New-Epic.ps1`` rewrites. Run ``Get-PlanState $Id`` for live rollup and the next unblocked
child plan.

## Decomposition notes

TBD
"@
}

function Set-PlanHeaderMarker {
    <#
    .SYNOPSIS
    Inserts or replaces a single `<!-- key: value -->` header marker in a plan file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines,

        [Parameter(Mandatory)]
        [string]$Key,

        [Parameter(Mandatory)]
        [string]$Value
    )

    $list = [System.Collections.Generic.List[string]]::new()
    $list.AddRange([string[]]$Lines)
    $pattern = "^\s*<!--\s*$([regex]::Escape($Key))\s*:\s*.*?-->\s*$"

    for ($i = 0; $i -lt $list.Count; $i++) {
        if ($list[$i] -match '^##\s') { break }
        if ($list[$i] -match $pattern) {
            $list[$i] = "<!-- ${Key}: $Value -->"
            return , $list.ToArray()
        }
    }

    # Anchor the new marker directly under `plan-id` so the header block stays in a stable order.
    $insertAt = -1
    for ($i = 0; $i -lt $list.Count; $i++) {
        if ($list[$i] -match '^##\s') { break }
        if ($list[$i] -match '^\s*<!--\s*plan-id\s*:') { $insertAt = $i + 1 }
    }
    if ($insertAt -lt 0) {
        for ($i = 0; $i -lt $list.Count; $i++) {
            if ($list[$i] -match '^#\s+') { $insertAt = $i + 1; break }
        }
    }
    if ($insertAt -lt 0) { $insertAt = 0 }

    $list.Insert($insertAt, "<!-- ${Key}: $Value -->")
    return , $list.ToArray()
}

function Get-EpicMember {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$EpicId,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Inventory
    )

    return @($Inventory |
            Where-Object { $_.EpicId -and $_.EpicId.ToLowerInvariant() -eq $EpicId.ToLowerInvariant() } |
            Sort-Object @{ Expression = { $_.Date } }, @{ Expression = { $_.Id } })
}

function Get-PrefixedChildTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Child,

        [Parameter(Mandatory)]
        [string]$TargetEpicId
    )

    # Legacy and rollout-era unprefixed hash plans keep their existing paths. Only a folder that
    # already participates in the prefix grammar must track later attachment or re-parenting.
    if ($Child.Scheme -ne 'new' -or [string]::IsNullOrWhiteSpace([string]$Child.FolderPrefix)) {
        return $null
    }

    $parent = Split-Path -Parent $Child.Path
    $folderName = "$TargetEpicId-$($Child.Date)-$($Child.Id)-$($Child.Slug)"
    return [pscustomobject]@{
        FolderName = $folderName
        Path       = Resolve-ConfinedFolder -Root $parent -FolderName $folderName
    }
}

function Get-EpicChildBlock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$EpicFile
    )

    $epicRaw = Get-Content -LiteralPath $EpicFile -Raw
    $epicLines = ($epicRaw -replace "`r`n", "`n").Split("`n")
    $startIndexes = @()
    $endIndexes = @()
    for ($i = 0; $i -lt $epicLines.Count; $i++) {
        $trimmedLine = $epicLines[$i].Trim()
        if ($trimmedLine -eq $script:ChildBlockStart) { $startIndexes += $i }
        if ($trimmedLine -eq $script:ChildBlockEnd) { $endIndexes += $i }
    }
    if ($startIndexes.Count -ne 1 -or $endIndexes.Count -ne 1 -or $endIndexes[0] -le $startIndexes[0]) {
        throw "Epic file '$EpicFile' must contain exactly one ordered '$script:ChildBlockStart' / '$script:ChildBlockEnd' block."
    }

    return [pscustomobject]@{
        Lines      = $epicLines
        StartIndex = $startIndexes[0]
        EndIndex   = $endIndexes[0]
    }
}

function Update-EpicChildTable {
    <#
    .SYNOPSIS
    Rewrites the generated child-plan block of one `epic.md` from the supplied member set.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$EpicFile,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Members
    )

    $rows = [System.Collections.Generic.List[string]]::new()
    $rows.Add('| Plan | Slug | Depends on |')
    $rows.Add('|---|---|---|')
    if ($Members.Count -eq 0) {
        $rows.Add('| _(none yet)_ | | |')
    }
    else {
        foreach ($member in $Members) {
            $memberMarkers = Get-PlanHeaderMarkers -Path (Join-Path $member.Path 'plan.md')
            $deps = @($memberMarkers.DependsOn)
            $depText = if ($deps.Count -gt 0) { ($deps | ForEach-Object { "``$_``" }) -join ', ' } else { '—' }
            $archivedNote = if ($member.IsArchived) { ' _(archived)_' } else { '' }
            $rows.Add("| ``$($member.Id)`` | $($member.Slug)$archivedNote | $depText |")
        }
    }

    $block = Get-EpicChildBlock -EpicFile $EpicFile
    $epicLines = $block.Lines
    $startIndex = $block.StartIndex
    $endIndex = $block.EndIndex

    $rebuilt = [System.Collections.Generic.List[string]]::new()
    $rebuilt.AddRange([string[]]($epicLines[0..$startIndex]))
    $rebuilt.AddRange([string[]]$rows.ToArray())
    $rebuilt.AddRange([string[]]($epicLines[$endIndex..($epicLines.Count - 1)]))
    Write-PlanText -Path $EpicFile -Lines $rebuilt.ToArray()
}

function Assert-CoherencyPropertySet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Node,
        [Parameter(Mandatory)][string[]]$Required,
        [string[]]$Optional = @(),
        [Parameter(Mandatory)][string]$Label
    )

    $actual = @($Node.Keys | ForEach-Object { [string]$_ } | Sort-Object)
    $allowed = @($Required + $Optional | Sort-Object)
    if (@($actual | Where-Object { $_ -cnotin $allowed }).Count -gt 0 -or
        @($Required | Where-Object { $_ -cnotin $actual }).Count -gt 0) {
        throw "$Label has an unexpected or incomplete property set."
    }
}

function ConvertTo-CoherencyMarkdownText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Value,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][ValidateRange(1, 2048)][int]$MaximumLength,
        [switch]$AllowEmpty
    )

    if ($Value.Length -gt $MaximumLength -or
        (-not $AllowEmpty -and [string]::IsNullOrWhiteSpace($Value)) -or
        $Value -match '[\x00-\x1f\x7f]' -or
        $Value -match '<!--|-->|epic-coherency-verdict') {
        throw "$Label contains unsupported or out-of-bounds content."
    }

    $escaped = $Value.Replace('&', '&amp;')
    $escaped = $escaped.Replace('|', '&#124;')
    $escaped = $escaped.Replace('<', '&lt;')
    $escaped = $escaped.Replace('>', '&gt;')
    return $escaped.Replace('`', '&#96;')
}

function Test-CoherencyPathContainsReparsePoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Boundary
    )

    $current = [System.IO.Path]::GetFullPath($Path)
    $stop = [System.IO.Path]::GetFullPath($Boundary).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar
    )
    $comparison = if ($IsWindows) {
        [System.StringComparison]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparison]::Ordinal
    }
    while (-not [string]::IsNullOrEmpty($current)) {
        $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or
            ($item.PSObject.Properties.Name -contains 'LinkType' -and
                -not [string]::IsNullOrWhiteSpace([string]$item.LinkType))) {
            return $true
        }
        if ([string]::Equals($current, $stop, $comparison)) {
            return $false
        }
        $parent = Split-Path -Parent $current
        if ([string]::IsNullOrEmpty($parent) -or $parent -eq $current) {
            throw "Coherency verdict path '$Path' does not descend from '$Boundary'."
        }
        $current = $parent
    }
    throw "Coherency verdict path '$Path' does not descend from '$Boundary'."
}

function ConvertTo-CoherencyVerdictBlock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Verdict
    )

    Assert-CoherencyPropertySet -Node $Verdict -Label 'Coherency verdict' -Required @(
        'action', 'blocking', 'decision', 'findings', 'reviewRunId', 'schema', 'sourceDigest'
    )
    if ($Verdict['schema'] -cne 'skalary/epic-coherency-verdict@1' -or
        $Verdict['sourceDigest'] -isnot [string] -or
        [string]$Verdict['sourceDigest'] -cnotmatch '^sha256:[0-9a-f]{64}$' -or
        $Verdict['blocking'] -isnot [bool] -or
        $Verdict['decision'] -isnot [string] -or
        [string]$Verdict['decision'] -cnotin @('keep', 'simplify', 'split', 'defer') -or
        $Verdict['action'] -isnot [string] -or
        $Verdict['findings'] -isnot [System.Collections.IList]) {
        throw 'Coherency verdict has invalid identity, source, or decision metadata.'
    }

    $reviewRunId = $Verdict['reviewRunId']
    if ($null -ne $reviewRunId -and
        ($reviewRunId -isnot [string] -or
            [string]$reviewRunId -cnotmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')) {
        throw 'Coherency verdict reviewRunId must be null or a lowercase UUID.'
    }

    $findings = @($Verdict['findings'])
    if ($findings.Count -gt 64) {
        throw 'Coherency verdict exceeds the 64-finding limit.'
    }
    if ($findings.Count -gt 0 -and $null -eq $reviewRunId) {
        throw 'Finding resolutions require the verified design-review run id.'
    }

    $seenFindings = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $rows = [System.Collections.Generic.List[string]]::new()
    foreach ($finding in $findings) {
        if ($finding -isnot [System.Collections.IDictionary]) {
            throw 'Each coherency finding resolution must be an object.'
        }
        Assert-CoherencyPropertySet -Node $finding -Label 'Coherency finding resolution' -Required @(
            'action', 'blocking', 'operatorDecision', 'proportionalityClass', 'taskId', 'title'
        )

        $taskId = [string]$finding['taskId']
        $title = [string]$finding['title']
        $class = [string]$finding['proportionalityClass']
        $operatorDecision = [string]$finding['operatorDecision']
        $findingAction = [string]$finding['action']
        if ($finding['blocking'] -isnot [bool] -or
            $finding['taskId'] -isnot [string] -or
            $finding['title'] -isnot [string] -or
            $finding['proportionalityClass'] -isnot [string] -or
            $finding['operatorDecision'] -isnot [string] -or
            $finding['action'] -isnot [string] -or
            $taskId -cnotmatch '^[a-z0-9][a-z0-9-]{0,62}-m(?:[1-9]|1[0-6])$' -or
            $class -cnotin @('speculative platform', 'required shared contract', 'local fix') -or
            $operatorDecision -cnotin @('keep', 'simplify', 'split', 'defer') -or
            -not $seenFindings.Add("$taskId`0$title")) {
            throw "Coherency finding resolution '$taskId' is invalid, duplicated, or conflicting."
        }

        $safeTaskId = ConvertTo-CoherencyMarkdownText -Value $taskId -Label 'Finding task id' -MaximumLength 80
        $safeTitle = ConvertTo-CoherencyMarkdownText -Value $title -Label "Finding '$taskId' title" -MaximumLength 240
        $safeAction = ConvertTo-CoherencyMarkdownText -Value $findingAction -Label "Finding '$taskId' action" -MaximumLength 1024
        $rows.Add("| ``$safeTaskId`` | $safeTitle | $class | $(if ($finding['blocking']) { 'yes' } else { 'no' }) | $operatorDecision | $safeAction |")
    }
    $hasBlockingFinding = @($findings | Where-Object { [bool]$_['blocking'] }).Count -gt 0
    if ([bool]$Verdict['blocking'] -ne $hasBlockingFinding) {
        throw 'Coherency verdict blocking state conflicts with its finding resolutions.'
    }

    $safeAction = ConvertTo-CoherencyMarkdownText -Value ([string]$Verdict['action']) `
        -Label 'Coherency verdict action' -MaximumLength 1024
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add($script:CoherencyBlockStart)
    $lines.Add('Schema: `skalary/epic-coherency-verdict@1`')
    $lines.Add("Prior source digest: ``$([string]$Verdict['sourceDigest'])``")
    $reviewRunDisplay = if ($null -eq $reviewRunId) { '_not yet reviewed_' } else { "``$reviewRunId``" }
    $lines.Add("Review run: $reviewRunDisplay")
    $lines.Add("Operator decision: **$([string]$Verdict['decision'])**")
    $lines.Add("Blocking: **$(if ($Verdict['blocking']) { 'yes' } else { 'no' })**")
    $lines.Add("Action: $safeAction")
    $lines.Add('')
    $lines.Add('| Task ID | Finding title | Proportionality class | Blocking | Operator decision | Concrete action |')
    $lines.Add('|---|---|---|---|---|---|')
    if ($rows.Count -eq 0) {
        $lines.Add('| _(none)_ | | | | | |')
    }
    else {
        $lines.AddRange([string[]]$rows.ToArray())
    }
    $lines.Add($script:CoherencyBlockEnd)
    return $lines.ToArray()
}

function Set-EpicCoherencyVerdict {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EpicFile,
        [Parameter(Mandatory)][string]$Boundary,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Verdict
    )

    $fullPath = [System.IO.Path]::GetFullPath($EpicFile)
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf) -or
        (Test-CoherencyPathContainsReparsePoint -Path $fullPath -Boundary $Boundary)) {
        throw "Epic coherency verdict target must be one regular, confined epic.md: $fullPath"
    }

    $expectedDigest = [string]$Verdict['sourceDigest']
    $blockLines = ConvertTo-CoherencyVerdictBlock -Verdict $Verdict
    $result = Invoke-AtomicStoreUpdate -Path $fullPath -MaxAttempts 1 -Transform {
        param($current, $generation)

        if ($null -eq $current) {
            throw "Epic coherency verdict target disappeared: $fullPath"
        }
        $actualDigest = "sha256:$generation"
        if ($actualDigest -cne $expectedDigest) {
            throw "Epic source is stale: expected '$expectedDigest', found '$actualDigest'."
        }

        $normalized = $current -replace "`r`n", "`n"
        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.AddRange([string[]]$normalized.Split("`n"))
        $markerLines = @(
            for ($index = 0; $index -lt $lines.Count; $index++) {
                if ($lines[$index] -match '<!--.*epic-coherency-verdict') {
                    [pscustomobject]@{ Index = $index; Text = $lines[$index].Trim() }
                }
            }
        )
        $starts = @($markerLines | Where-Object { $_.Text -ceq $script:CoherencyBlockStart })
        $ends = @($markerLines | Where-Object { $_.Text -ceq $script:CoherencyBlockEnd })
        $headings = @(
            for ($index = 0; $index -lt $lines.Count; $index++) {
                if ($lines[$index].Trim() -ceq '## Epic coherency verdict') { $index }
            }
        )
        if ($markerLines.Count -ne ($starts.Count + $ends.Count) -or
            $starts.Count -ne $ends.Count -or
            $starts.Count -gt 1 -or
            ($starts.Count -eq 0 -and $headings.Count -ne 0) -or
            ($starts.Count -eq 1 -and (
                $ends[0].Index -le $starts[0].Index -or
                $headings.Count -ne 1 -or
                $headings[0] -ge $starts[0].Index
            ))) {
            throw "Epic file '$fullPath' has malformed or duplicate coherency verdict markers."
        }

        $rebuilt = [System.Collections.Generic.List[string]]::new()
        if ($starts.Count -eq 0) {
            while ($lines.Count -gt 0 -and [string]::IsNullOrEmpty($lines[$lines.Count - 1])) {
                $lines.RemoveAt($lines.Count - 1)
            }
            $rebuilt.AddRange([string[]]$lines.ToArray())
            $rebuilt.Add('')
            $rebuilt.Add('## Epic coherency verdict')
            $rebuilt.Add('')
            $rebuilt.AddRange([string[]]$blockLines)
        }
        else {
            if ($starts[0].Index -gt 0) {
                $rebuilt.AddRange([string[]]$lines.GetRange(0, $starts[0].Index).ToArray())
            }
            $rebuilt.AddRange([string[]]$blockLines)
            if ($ends[0].Index + 1 -lt $lines.Count) {
                $rebuilt.AddRange([string[]]$lines.GetRange(
                        $ends[0].Index + 1,
                        $lines.Count - $ends[0].Index - 1
                    ).ToArray())
            }
        }

        return (($rebuilt -join "`n").TrimEnd("`n") + "`n")
    }

    if ($result.Status -ne 'complete') {
        throw "Epic coherency verdict write failed with atomic-store status '$($result.Status)'."
    }
    return $result
}

$script:ChildBlockStart = '<!-- child-plans:start -->'
$script:ChildBlockEnd = '<!-- child-plans:end -->'
$script:CoherencyBlockStart = '<!-- epic-coherency-verdict:start -->'
$script:CoherencyBlockEnd = '<!-- epic-coherency-verdict:end -->'

$repoRootPath = [System.IO.Path]::GetFullPath($RepoRoot)
$plansRoot = Join-Path $repoRootPath 'docs/implementation-plans'
$epicsRoot = Join-Path $plansRoot 'epics'

if ($DependsOn.Count -gt 0 -and $ChildPlan.Count -ne 1) {
    throw '-DependsOn applies to exactly one -ChildPlan; run New-Epic once per child so each dependency edge is explicit.'
}

$planInventory = @(Get-PlanInventory -RepoRoot $repoRootPath)
$epicInventory = @(Get-EpicInventory -RepoRoot $repoRootPath)

if ($PSCmdlet.ParameterSetName -eq 'Verdict') {
    try {
        $verdict = $VerdictJson | ConvertFrom-Json -AsHashtable -Depth 10
    }
    catch {
        throw "Coherency verdict is invalid JSON: $($_.Exception.Message)"
    }
    if ($verdict -isnot [System.Collections.IDictionary]) {
        throw 'Coherency verdict must be one JSON object.'
    }

    $resolvedEpic = Resolve-Epic -Reference $Epic -RepoRoot $repoRootPath -Inventory $epicInventory
    $epicFile = [System.IO.Path]::GetFullPath([string]$resolvedEpic.EpicFile)
    $expectedEpicRoot = [System.IO.Path]::GetFullPath([string]$resolvedEpic.Path)
    $pathComparison = if ($IsWindows) {
        [System.StringComparison]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparison]::Ordinal
    }
    if (-not $expectedEpicRoot.StartsWith(
            [System.IO.Path]::GetFullPath($epicsRoot).TrimEnd(
                [System.IO.Path]::DirectorySeparatorChar
            ) + [System.IO.Path]::DirectorySeparatorChar,
            $pathComparison
        ) -or -not $epicFile.StartsWith(
            $expectedEpicRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) +
                [System.IO.Path]::DirectorySeparatorChar,
            $pathComparison
        ) -or [System.IO.Path]::GetFileName($epicFile) -cne 'epic.md') {
        throw "Resolved coherency verdict target is outside epic '$($resolvedEpic.Id)'."
    }

    $write = Set-EpicCoherencyVerdict -EpicFile $epicFile -Boundary $epicsRoot -Verdict $verdict
    return [pscustomobject]@{
        EpicId      = $resolvedEpic.Id
        EpicFile    = $epicFile
        SourceDigest = [string]$verdict['sourceDigest']
        NewDigest   = "sha256:$($write.Generation)"
        Decision    = [string]$verdict['decision']
        Findings    = @($verdict['findings']).Count
    }
}

if ($PSCmdlet.ParameterSetName -eq 'Scaffold') {
    if ($Date -notmatch '^\d{4}-\d{2}-\d{2}$') {
        throw "Date '$Date' must be in yyyy-MM-dd format."
    }

    $slugClean = Get-SanitizedSlug -Value $Slug

    if ($EpicId) {
        $EpicId = $EpicId.Trim().ToLowerInvariant()
        if ($EpicId -notmatch '^[0-9a-f]{6}$') {
            throw "EpicId '$EpicId' must be exactly 6 hex chars."
        }
    }
    else {
        # Epic ids share the plan id space: `/ci` accepts either handle, so a collision would make the
        # reference ambiguous rather than merely ugly.
        $taken = @($planInventory | ForEach-Object { $_.Id }) + @($epicInventory | ForEach-Object { $_.Id })
        $EpicId = New-PlanId -ExistingId $taken
    }

    foreach ($existing in ($planInventory + $epicInventory)) {
        if ($existing.Id -and $existing.Id.ToLowerInvariant() -eq $EpicId) {
            throw "Epic id '$EpicId' is already taken by '$($existing.FolderName)'."
        }
    }

    if (-not (Test-Path -LiteralPath $epicsRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $epicsRoot -Force | Out-Null
    }

    $folderName = "$Date-$EpicId-$slugClean"
    $epicDir = Resolve-ConfinedFolder -Root $epicsRoot -FolderName $folderName
    $epicFile = Join-Path $epicDir 'epic.md'

    if ((Test-Path -LiteralPath $epicFile -PathType Leaf) -and -not $Force) {
        throw "Epic already exists: $epicFile (use -Force to rewrite epic.md)."
    }

    New-Item -ItemType Directory -Path $epicDir -Force | Out-Null
    Set-Content -LiteralPath $epicFile -Value (Get-EpicScaffold -Id $EpicId -EpicTitle $Title) -Encoding utf8NoBOM
    $epicInventory = @(Get-EpicInventory -RepoRoot $repoRootPath)
}
else {
    $resolvedEpic = Resolve-Epic -Reference $Epic -RepoRoot $repoRootPath -Inventory $epicInventory
    $EpicId = $resolvedEpic.Id
    $epicDir = $resolvedEpic.Path
    $epicFile = $resolvedEpic.EpicFile
    $folderName = $resolvedEpic.FolderName
    if (-not (Test-Path -LiteralPath $epicFile -PathType Leaf)) {
        throw "Epic '$EpicId' has no epic.md at $epicFile."
    }
}

$pathComparer = if ($IsWindows) {
    [System.StringComparer]::OrdinalIgnoreCase
}
else {
    [System.StringComparer]::Ordinal
}
$validatedEpicFiles = [System.Collections.Generic.HashSet[string]]::new($pathComparer)
$resolvedEpicFile = [System.IO.Path]::GetFullPath($epicFile)
if ($validatedEpicFiles.Add($resolvedEpicFile)) {
    Get-EpicChildBlock -EpicFile $resolvedEpicFile | Out-Null
}

$attachments = [System.Collections.Generic.List[object]]::new()
$targetPaths = [System.Collections.Generic.HashSet[string]]::new($pathComparer)
foreach ($reference in $ChildPlan) {
    $child = Resolve-Plan -Reference $reference -RepoRoot $repoRootPath -Inventory $planInventory
    $childPlanFile = Join-Path $child.Path 'plan.md'
    if (-not (Test-Path -LiteralPath $childPlanFile -PathType Leaf)) {
        throw "Child plan '$($child.Id)' has no plan.md at $childPlanFile."
    }
    if ($child.IsArchived) {
        Write-Warning "Child plan '$($child.Id)' is archived; stamping it into epic '$EpicId' anyway."
    }

    $raw = Get-Content -LiteralPath $childPlanFile -Raw
    $lines = ($raw -replace "`r`n", "`n").Split("`n")
    $markers = Get-PlanHeaderMarkers -Content ($raw)

    if ($markers.EpicId -and $markers.EpicId.ToLowerInvariant() -ne $EpicId) {
        if (-not $Force) {
            throw "Child plan '$($child.Id)' already belongs to epic '$($markers.EpicId)'. Re-parenting is a deliberate call — re-run with -Force."
        }

        $previousEpicId = $markers.EpicId.ToLowerInvariant()
        $previousEpic = @($epicInventory | Where-Object {
                $_.Id -and $_.Id.ToLowerInvariant() -eq $previousEpicId
            })
        if ($previousEpic.Count -ne 1 -or -not (Test-Path -LiteralPath $previousEpic[0].EpicFile -PathType Leaf)) {
            throw "Cannot re-parent child plan '$($child.Id)': previous epic '$previousEpicId' has no unique epic.md."
        }
        $previousEpicFile = [System.IO.Path]::GetFullPath([string]$previousEpic[0].EpicFile)
        if ($validatedEpicFiles.Add($previousEpicFile)) {
            Get-EpicChildBlock -EpicFile $previousEpicFile | Out-Null
        }
    }

    $mergedDeps = [System.Collections.Generic.List[string]]::new()
    foreach ($existingDep in @($markers.DependsOn)) {
        $token = $existingDep.Trim().ToLowerInvariant()
        if ($token -and -not $mergedDeps.Contains($token)) { $mergedDeps.Add($token) }
    }
    foreach ($dep in $DependsOn) {
        $resolvedDep = Resolve-Plan -Reference $dep -RepoRoot $repoRootPath -Inventory $planInventory
        if ($resolvedDep.Id.ToLowerInvariant() -eq $child.Id.ToLowerInvariant()) {
            throw "Child plan '$($child.Id)' cannot depend on itself."
        }
        $token = $resolvedDep.Id.ToLowerInvariant()
        if (-not $mergedDeps.Contains($token)) { $mergedDeps.Add($token) }
    }

    $target = Get-PrefixedChildTarget -Child $child -TargetEpicId $EpicId
    if ($target -and -not $pathComparer.Equals($target.Path, $child.Path)) {
        if ((Test-DirectoryEntryExists -Path $target.Path) -or -not $targetPaths.Add($target.Path)) {
            throw "Cannot attach child plan '$($child.Id)': target folder '$($target.Path)' already exists or is selected by another child."
        }
    }

    $attachments.Add([pscustomobject]@{
            Child     = $child
            PlanFile  = $childPlanFile
            Lines     = $lines
            Markers   = $markers
            DependsOn = $mergedDeps
            Target    = $target
        })
}

$stamped = [System.Collections.Generic.List[object]]::new()
$reparentedFrom = [System.Collections.Generic.List[string]]::new()
foreach ($attachment in $attachments) {
    $child = $attachment.Child
    $requiresMove = $attachment.Target -and
    -not $pathComparer.Equals($attachment.Target.Path, $child.Path)
    if ($requiresMove -and (Test-DirectoryEntryExists -Path $attachment.Target.Path)) {
        throw "Cannot attach child plan '$($child.Id)': target folder '$($attachment.Target.Path)' already exists."
    }

    $lines = Set-PlanHeaderMarker -Lines $attachment.Lines -Key 'epic' -Value $EpicId
    if ($attachment.Markers.EpicId -and $attachment.Markers.EpicId.ToLowerInvariant() -ne $EpicId) {
        $reparentedFrom.Add($attachment.Markers.EpicId.ToLowerInvariant())
    }

    $mergedDeps = $attachment.DependsOn
    if ($mergedDeps.Count -gt 0) {
        $lines = Set-PlanHeaderMarker -Lines $lines -Key 'depends-on' -Value ($mergedDeps -join ', ')
    }

    Write-PlanText -Path $attachment.PlanFile -Lines $lines
    $childPath = $child.Path
    $childPlanFile = $attachment.PlanFile
    if ($requiresMove) {
        try {
            [System.IO.Directory]::Move($child.Path, $attachment.Target.Path)
        }
        catch {
            $moveError = $_
            try {
                Write-PlanText -Path $attachment.PlanFile -Lines $attachment.Lines
            }
            catch {
                throw "Moving child plan '$($child.Id)' failed: $($moveError.Exception.Message). Restoring its original plan header also failed: $($_.Exception.Message)"
            }
            throw $moveError
        }
        $childPath = $attachment.Target.Path
        $childPlanFile = Join-Path $childPath 'plan.md'
    }

    $stamped.Add([pscustomobject]@{
            Id        = $child.Id
            Slug      = $child.Slug
            Path      = $childPath
            PlanFile  = $childPlanFile
            DependsOn = $mergedDeps.ToArray()
        })
}

# Rebuild the mirror from the markers on disk (including children stamped by earlier runs) so the table
# is derived state, never a second source of truth that can drift from the plans themselves. A -Force
# re-parent rebuilds the losing epic too, otherwise its table would keep listing a child it no longer owns.
$currentInventory = @(Get-PlanInventory -RepoRoot $repoRootPath)
$members = @(Get-EpicMember -EpicId $EpicId -Inventory $currentInventory)
Update-EpicChildTable -EpicFile $epicFile -Members $members

$currentEpicInventory = @(Get-EpicInventory -RepoRoot $repoRootPath)
foreach ($orphanedEpicId in ($reparentedFrom | Sort-Object -Unique)) {
    $orphanedEpic = @($currentEpicInventory | Where-Object { $_.Id -and $_.Id.ToLowerInvariant() -eq $orphanedEpicId })
    if ($orphanedEpic.Count -ne 1 -or -not (Test-Path -LiteralPath $orphanedEpic[0].EpicFile -PathType Leaf)) {
        Write-Warning "Previous epic '$orphanedEpicId' has no resolvable epic.md; its child table was not refreshed."
        continue
    }
    Update-EpicChildTable -EpicFile $orphanedEpic[0].EpicFile -Members @(Get-EpicMember -EpicId $orphanedEpicId -Inventory $currentInventory)
}

$result = [pscustomobject]@{
    EpicId     = $EpicId
    FolderName = $folderName
    Path       = $epicDir
    EpicFile   = $epicFile
    Stamped    = $stamped.ToArray()
    Children   = @($members | ForEach-Object { $_.Id })
}

Write-Host "Epic '$folderName' (epic-id $EpicId) has $($members.Count) child plan(s) at $epicFile" -ForegroundColor Green
return $result
