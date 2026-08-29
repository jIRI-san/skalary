#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'PlanState.psm1') -DisableNameChecking

$script:PlanEvidenceOutcomes = @('passed', 'failed', 'skipped', 'unrun', 'stale', 'degraded', 'waived')

function Get-PlanEvidenceField {
    param(
        [Parameter(Mandatory)][object]$InputObject,
        [Parameter(Mandatory)][string]$Name
    )

    if ($InputObject.PSObject.Properties.Name -contains $Name) {
        return $InputObject.$Name
    }
    return $null
}

function ConvertTo-PlanEvidenceResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$InputObject
    )

    process {
        $req = [string](Get-PlanEvidenceField -InputObject $InputObject -Name 'Req')
        $marker = [string](Get-PlanEvidenceField -InputObject $InputObject -Name 'Marker')
        if ([string]::IsNullOrWhiteSpace($req) -or $req -notmatch '^REQ-\d+$') {
            throw "Evidence result has invalid requirement '$req'."
        }
        if ([string]::IsNullOrWhiteSpace($marker)) {
            throw 'Evidence result requires a non-empty Marker.'
        }

        $hasStatus = $InputObject.PSObject.Properties.Name -contains 'Status'
        $hasSuccess = $InputObject.PSObject.Properties.Name -contains 'Success'
        $status = if ($hasStatus) {
            [string]$InputObject.Status
        }
        elseif ($hasSuccess) {
            if ($InputObject.Success -eq $true) { 'passed' }
            elseif ($InputObject.Success -eq $false) { 'failed' }
            else { 'unrun' }
        }
        else {
            'unrun'
        }
        if ($status -cnotin $script:PlanEvidenceOutcomes) {
            throw "Evidence result for '$marker' has invalid status '$status'."
        }

        if ($hasStatus -and $hasSuccess) {
            $expectedSuccess = $status -in @('passed', 'waived')
            if ($null -ne $InputObject.Success -and [bool]$InputObject.Success -ne $expectedSuccess) {
                throw "Evidence result for '$marker' has conflicting Status and Success fields."
            }
        }

        $note = [string](Get-PlanEvidenceField -InputObject $InputObject -Name 'Note')
        if ([string]::IsNullOrWhiteSpace($note)) {
            $note = [string](Get-PlanEvidenceField -InputObject $InputObject -Name 'Message')
        }
        foreach ($value in @($req, $marker, $note)) {
            if ($value -match "[`r`n]" -or $value.Contains(" $([char]0x2014) ")) {
                throw "Evidence result for '$marker' contains a receipt delimiter or line break."
            }
        }

        return [pscustomobject]@{
            Req = $req
            Marker = $marker
            Status = $status
            Success = ($status -in @('passed', 'waived'))
            Note = $note.Trim()
        }
    }
}

function Resolve-PlanEvidenceAssetPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$PlanMetadata,
        [Parameter(Mandatory)]
        [ValidateSet('Evidence', 'EvidenceWaivers')]
        [string]$Kind
    )

    $repoRoot = [System.IO.Path]::GetFullPath($PlanMetadata.RepoRoot)
    $plansRoot = [System.IO.Path]::GetFullPath((Join-Path $repoRoot 'docs/implementation-plans'))
    $plansPrefix = $plansRoot.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    ) + [System.IO.Path]::DirectorySeparatorChar
    $planDir = [System.IO.Path]::GetFullPath($PlanMetadata.PlanDir)
    $comparison = if ($IsWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    if ($planDir.StartsWith($plansPrefix, $comparison)) {
        return Resolve-PlanAssetPath -PlanDir $planDir -Kind $Kind -RepoRoot $repoRoot
    }

    # Unit fixtures may exercise the pure parser outside the repository inventory.
    return Resolve-PlanAssetPath -PlanDir $planDir -Kind $Kind
}

function Get-PlanEvidenceWaiver {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$PlanMetadata,
        [Parameter(Mandatory)][string]$PlanDirectory
    )

    if (-not [string]::Equals(
            [System.IO.Path]::GetFullPath($PlanMetadata.PlanDir),
            [System.IO.Path]::GetFullPath($PlanDirectory),
            $(if ($IsWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal })
        )) {
        throw "Evidence waiver plan directory '$PlanDirectory' does not match the parsed plan."
    }
    $path = Resolve-PlanEvidenceAssetPath -PlanMetadata $PlanMetadata -Kind EvidenceWaivers
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return @()
    }
    if ((Get-Item -LiteralPath $path -Force).Length -gt 65536) {
        throw "Evidence waiver file '$path' exceeds 65536 bytes."
    }

    try {
        $policy = Get-Content -LiteralPath $path -Raw -Force |
            ConvertFrom-Json -AsHashtable -Depth 20
    }
    catch {
        throw "Evidence waiver file '$path' is malformed JSON: $($_.Exception.Message)"
    }

    if ($policy -isnot [System.Collections.IDictionary]) {
        throw "Evidence waiver file '$path' must contain a JSON object."
    }
    $topProperties = @($policy.Keys | Sort-Object)
    $waiverEntries = $policy['waivers']
    if (($topProperties -join ',') -cne 'schema,waivers' -or
        $policy['schema'] -isnot [string] -or
        [string]$policy['schema'] -cne 'skalary/evidence-waivers@1' -or
        $waiverEntries -isnot [System.Collections.IList] -or
        $waiverEntries -is [string]) {
        throw "Evidence waiver file '$path' must contain only schema 'skalary/evidence-waivers@1' and a waivers array."
    }

    $header = Get-PlanHeaderMarkers -Content $PlanMetadata.Content
    $planId = [string]$header.All['plan-id']
    if ([string]::IsNullOrWhiteSpace($planId) -and
        $PlanMetadata.Content -match '(?m)^#\s+(?<id>\d{3}|[0-9a-f]{6}):') {
        $planId = $Matches.id
    }
    if ([string]::IsNullOrWhiteSpace($planId)) {
        throw 'Evidence waiver validation could not resolve the canonical plan id.'
    }
    $platform = if ($IsWindows) { 'Windows' } elseif ($IsMacOS) { 'MacOS' } else { 'Linux' }
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $waivers = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in @($waiverEntries)) {
        if ($entry -isnot [System.Collections.IDictionary]) {
            throw "Evidence waiver file '$path' contains a non-object entry."
        }
        $properties = @($entry.Keys | Sort-Object)
        $required = @('marker', 'outcome', 'plan', 'reason', 'requirement')
        $allowed = @($required + 'platform' | Sort-Object)
        if (@($required | Where-Object { $_ -cnotin $properties }).Count -gt 0 -or
            @($properties | Where-Object { $_ -cnotin $allowed }).Count -gt 0) {
            throw "Evidence waiver file '$path' contains an entry with missing or unknown fields."
        }
        foreach ($field in $required) {
            if ($entry[$field] -isnot [string]) {
                throw "Evidence waiver file '$path' entry field '$field' must be a string."
            }
        }
        if ($properties -contains 'platform' -and $entry['platform'] -isnot [string]) {
            throw "Evidence waiver file '$path' entry field 'platform' must be a string when present."
        }

        $entryPlan = [string]$entry['plan']
        $requirement = [string]$entry['requirement']
        $marker = [string]$entry['marker']
        $outcome = [string]$entry['outcome']
        $reason = [string]$entry['reason']
        $entryPlatform = if ($properties -contains 'platform') { [string]$entry['platform'] } else { $null }
        if ($entryPlan -cne $planId) {
            throw "Evidence waiver targets plan '$entryPlan', expected '$planId'."
        }
        if ($requirement -notmatch '^REQ-\d+$' -or
            @($PlanMetadata.Requirements.Keys | Where-Object { [string]$_ -ceq $requirement }).Count -ne 1) {
            throw "Evidence waiver targets unknown requirement '$requirement'."
        }
        $declaredMarkers = @(
            Get-TypedEvidenceMarkers -AcceptanceCriteria $PlanMetadata.Requirements[$requirement].AcceptanceCriteria |
                ForEach-Object { $_ }
        )
        if ([string]::IsNullOrWhiteSpace($marker) -or $marker.Contains('*') -or $declaredMarkers -cnotcontains $marker) {
            throw "Evidence waiver targets undeclared or wildcard marker '$marker' for '$requirement' (declared: $($declaredMarkers -join ', '))."
        }
        if ($outcome -cnotin @('skipped', 'degraded')) {
            throw "Evidence waiver for '$marker' may target only skipped or degraded, not '$outcome'."
        }
        if ([string]::IsNullOrWhiteSpace($reason) -or $reason.Length -gt 500 -or
            $reason -match "[`r`n\x00-\x1f]" -or $reason.Contains(" $([char]0x2014) ")) {
            throw "Evidence waiver for '$marker' has an invalid reason."
        }
        if ($entryPlatform -and $entryPlatform -cnotin @('Windows', 'Linux', 'MacOS')) {
            throw "Evidence waiver for '$marker' has invalid platform '$entryPlatform'."
        }

        $key = "$requirement|$marker|$outcome|$entryPlatform"
        if (-not $seen.Add($key)) {
            throw "Evidence waiver file '$path' contains duplicate binding '$key'."
        }
        $waivers.Add([pscustomobject]@{
                Requirement = $requirement
                Marker = $marker
                Outcome = $outcome
                Reason = $reason.Trim()
                Platform = $entryPlatform
                Applies = (-not $entryPlatform -or $entryPlatform -ceq $platform)
            })
    }

    return , $waivers.ToArray()
}

function ConvertFrom-StructuredTestEvidenceResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        $PlanMetadata
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Structured test evidence is missing: '$Path'."
    }
    if ((Get-Item -LiteralPath $Path -Force).Length -gt 1048576) {
        throw "Structured test evidence '$Path' exceeds 1048576 bytes."
    }
    try {
        $payload = Get-Content -LiteralPath $Path -Raw -Force |
            ConvertFrom-Json -AsHashtable -Depth 20
    }
    catch {
        throw "Structured test evidence '$Path' is malformed JSON: $($_.Exception.Message)"
    }
    if ($payload -isnot [System.Collections.IDictionary]) {
        throw "Structured test evidence '$Path' must contain a JSON object."
    }

    $expectedTop = 'executedCount,results,schema,selectedCount'
    if ((@($payload.Keys | Sort-Object) -join ',') -cne $expectedTop -or
        $payload['schema'] -isnot [string] -or
        [string]$payload['schema'] -cne 'skalary/evidence-test-results@1' -or
        $payload['results'] -isnot [System.Collections.IList] -or
        $payload['results'] -is [string]) {
        throw "Structured test evidence '$Path' has an invalid top-level shape."
    }
    foreach ($field in @('selectedCount', 'executedCount')) {
        if ($payload[$field] -isnot [ValueType] -or
            [long]$payload[$field] -lt 0 -or
            [decimal]$payload[$field] -ne [long]$payload[$field]) {
            throw "Structured test evidence '$Path' field '$field' must be a non-negative integer."
        }
    }

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $results = [System.Collections.Generic.List[object]]::new()
    $selectedTotal = 0L
    $executedTotal = 0L
    foreach ($record in @($payload['results'])) {
        if ($record -isnot [System.Collections.IDictionary] -or
            (@($record.Keys | Sort-Object) -join ',') -cne 'executedCount,marker,message,outcomes,selectedCount,status') {
            throw "Structured test evidence '$Path' contains a result with an invalid shape."
        }
        foreach ($field in @('marker', 'status', 'message')) {
            if ($record[$field] -isnot [string]) {
                throw "Structured test evidence '$Path' result field '$field' must be a string."
            }
        }
        foreach ($field in @('selectedCount', 'executedCount')) {
            if ($record[$field] -isnot [ValueType] -or
                [long]$record[$field] -lt 0 -or
                [decimal]$record[$field] -ne [long]$record[$field]) {
                throw "Structured test evidence '$Path' result field '$field' must be a non-negative integer."
            }
        }
        if ($record['outcomes'] -isnot [System.Collections.IList] -or
            $record['outcomes'] -is [string] -or
            @($record['outcomes'] | Where-Object { $_ -isnot [string] }).Count -gt 0) {
            throw "Structured test evidence '$Path' result outcomes must be an array of strings."
        }

        $marker = [string]$record['marker']
        $status = [string]$record['status']
        if ($marker -notmatch '^test:[A-Za-z0-9._-]+$' -or -not $seen.Add($marker)) {
            throw "Structured test evidence '$Path' contains an invalid or duplicate marker '$marker'."
        }
        if ($status -cnotin @('passed', 'failed', 'skipped', 'unrun', 'degraded')) {
            throw "Structured test evidence '$Path' marker '$marker' has invalid status '$status'."
        }
        if ([long]$record['executedCount'] -gt [long]$record['selectedCount']) {
            throw "Structured test evidence '$Path' marker '$marker' executed more tests than it selected."
        }

        $matchingRequirements = @(
            foreach ($requirement in @($PlanMetadata.Requirements.Values | Sort-Object Number)) {
                $declaredMarkers = @(
                    Get-TypedEvidenceMarkers -AcceptanceCriteria ([string]$requirement.AcceptanceCriteria) |
                        ForEach-Object { $_ }
                )
                if ($declaredMarkers -ccontains $marker) {
                    $requirement
                }
            }
        )
        if ($matchingRequirements.Count -eq 0) {
            throw "Structured test evidence '$Path' marker '$marker' is not declared by the plan."
        }

        $selectedTotal += [long]$record['selectedCount']
        $executedTotal += [long]$record['executedCount']
        $outcomes = @($record['outcomes'])
        $note = "selected=$($record['selectedCount']) executed=$($record['executedCount']) outcomes=$($outcomes -join ',')"
        if (-not [string]::IsNullOrWhiteSpace([string]$record['message'])) {
            $note += "; $([string]$record['message'])"
        }
        foreach ($requirement in $matchingRequirements) {
            $results.Add([pscustomobject]@{
                    Req = [string]$requirement.Id
                    Marker = $marker
                    Status = $status
                    Note = $note
                })
        }
    }
    if ($selectedTotal -ne [long]$payload['selectedCount'] -or
        $executedTotal -ne [long]$payload['executedCount']) {
        throw "Structured test evidence '$Path' aggregate counts do not match its results."
    }

    return $results.ToArray()
}

function Read-PlanEvidenceReceipt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Evidence receipt is missing: '$Path'."
    }
    if ((Get-Item -LiteralPath $Path -Force).Length -gt 262144) {
        throw "Evidence receipt '$Path' exceeds 262144 bytes."
    }

    $entries = [System.Collections.Generic.List[object]]::new()
    $lineNumber = 0
    foreach ($line in @(Get-Content -LiteralPath $Path -Force)) {
        $lineNumber++
        if ([string]::IsNullOrWhiteSpace($line) -or $line -match '^Phase \d+ Crosscheck:$') {
            continue
        }
        if ($line -notmatch '^(?<glyph>[✓✗⊘]) (?<req>REQ-\d+) — (?<marker>.+?) — (?<status>passed|failed|skipped|unrun|stale|degraded|waived)(?:: (?<note>.*))? — (?<commit>[0-9a-fA-F]{7,40})$') {
            throw "Malformed evidence receipt line $lineNumber in '$Path'."
        }

        $status = $Matches.status
        $expectedGlyph = if ($status -eq 'passed') { '✓' } elseif ($status -eq 'waived') { '⊘' } else { '✗' }
        if ($Matches.glyph -ne $expectedGlyph) {
            throw "Evidence receipt line $lineNumber uses glyph '$($Matches.glyph)' for status '$status'."
        }
        $entries.Add([pscustomobject]@{
                Req = $Matches.req
                Marker = $Matches.marker
                Status = $status
                Note = if ($Matches.ContainsKey('note')) { $Matches.note } else { '' }
                Commit = $Matches.commit.ToLowerInvariant()
                LineNumber = $lineNumber
            })
    }

    return , $entries.ToArray()
}

function Resolve-PlanEvidencePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [Parameter(Mandatory)]
        [string]$RelativePath
    )

    if ([string]::IsNullOrWhiteSpace($RelativePath)) {
        throw 'Evidence path is empty.'
    }

    if ($RelativePath.StartsWith('/') -or $RelativePath.StartsWith('\')) {
        throw "Evidence path '$RelativePath' must be relative."
    }

    if ($RelativePath -match '^[A-Za-z]:') {
        throw "Evidence path '$RelativePath' cannot be absolute."
    }

    if ($RelativePath -match '\\\\') {
        throw "Evidence path '$RelativePath' cannot be UNC."
    }

    $separator = [System.IO.Path]::DirectorySeparatorChar
    $repoRootFullPath = [System.IO.Path]::GetFullPath($RepoRoot)
    $candidatePath = [System.IO.Path]::GetFullPath((Join-Path $repoRootFullPath ($RelativePath -replace '/', $separator)))
    $repoRootPrefix = $repoRootFullPath.TrimEnd($separator) + $separator
    $pathComparison = if ($IsWindows) {
        [System.StringComparison]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparison]::Ordinal
    }
    if (-not $candidatePath.StartsWith($repoRootPrefix, $pathComparison)) {
        throw "Evidence path '$RelativePath' resolves outside repository root."
    }

    $physicalRepoRoot = Resolve-PhysicalRepoPath -Path $repoRootFullPath
    $physicalCandidate = Resolve-PhysicalRepoPath -Path $candidatePath
    $physicalPrefix = $physicalRepoRoot.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    ) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $physicalCandidate.StartsWith($physicalPrefix, [System.StringComparison]::Ordinal)) {
        throw "Evidence path '$RelativePath' escapes repository root via symlink."
    }

    return $physicalCandidate
}

function Parse-PlanFileEvidenceMarker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Marker
    )

    if ($Marker -notmatch '^file:(?<path>[^#]+)#(?<assertion>.+)$') {
        throw "Invalid file evidence marker '$Marker'. Expected file:<path>#<assertion>."
    }

    $relativePath = $Matches.path.Trim()
    $assertion = $Matches.assertion.Trim()
    if ($assertion -eq 'exists') {
        return [pscustomobject]@{
            Marker = $Marker
            RelativePath = $relativePath
            Assertion = 'exists'
            Threshold = $null
            Regex = $null
        }
    }

    if ($assertion -like 'contains:*') {
        $pattern = $assertion.Substring('contains:'.Length)
        if ([string]::IsNullOrWhiteSpace($pattern)) {
            throw "Invalid contains assertion in '$Marker'."
        }
        return [pscustomobject]@{
            Marker = $Marker
            RelativePath = $relativePath
            Assertion = 'contains'
            Threshold = $null
            Regex = $pattern
        }
    }

    if ($assertion -match '^count>=(?<count>\d+)$') {
        return [pscustomobject]@{
            Marker = $Marker
            RelativePath = $relativePath
            Assertion = 'count'
            Threshold = [int]$Matches.count
            Regex = $null
        }
    }

    if ($assertion -match '^dircount>=(?<count>\d+)$') {
        return [pscustomobject]@{
            Marker = $Marker
            RelativePath = $relativePath
            Assertion = 'dircount'
            Threshold = [int]$Matches.count
            Regex = $null
        }
    }

    throw "Invalid file evidence assertion '$assertion' in '$Marker'. Allowed: exists, contains:, count>=N, dircount>=N."
}

function Get-FileRegexMatchCount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Pattern,

        [int]$PerMatchTimeoutMs = 100
    )

    $content = Get-Content -LiteralPath $Path -Raw -Force
    $regex = [regex]::new(
        $Pattern,
        [System.Text.RegularExpressions.RegexOptions]::None,
        [TimeSpan]::FromMilliseconds($PerMatchTimeoutMs)
    )
    return [int]$regex.IsMatch($content)
}

function Invoke-PlanFileEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [Parameter(Mandatory)]
        [string]$Marker,

        [ValidateSet('Draft', 'PhaseCrosscheck', 'PlanCrosscheck')]
        [string]$Stage = 'Draft',

        [long]$MaxFileBytes = 1048576,

        [int]$PerMatchTimeoutMs = 100
    )

    $parsed = Parse-PlanFileEvidenceMarker -Marker $Marker
    $resolvedPath = Resolve-PlanEvidencePath -RepoRoot $RepoRoot -RelativePath $parsed.RelativePath
    $isBlockingStage = $Stage -ne 'Draft'
    if (-not (Test-Path -LiteralPath $resolvedPath)) {
        return [pscustomobject]@{
            Marker = $Marker
            Status = 'failed'
            Success = $false
            Blocking = $isBlockingStage
            Message = "Missing target '$($parsed.RelativePath)'."
        }
    }

    if ($parsed.Assertion -eq 'dircount') {
        if (-not (Test-Path -LiteralPath $resolvedPath -PathType Container)) {
            return [pscustomobject]@{
                Marker = $Marker
                Status = 'failed'
                Success = $false
                Blocking = $isBlockingStage
                Message = "Target '$($parsed.RelativePath)' is not a directory."
            }
        }

        $physicalRoot = Resolve-PhysicalRepoPath -Path $RepoRoot
        $rootPrefix = $physicalRoot.TrimEnd(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        ) + [System.IO.Path]::DirectorySeparatorChar
        $seenDirectories = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        $queue = [System.Collections.Generic.Queue[string]]::new()
        $queue.Enqueue($resolvedPath)
        $count = 0
        while ($queue.Count -gt 0) {
            $current = $queue.Dequeue()
            $items = Get-ChildItem -LiteralPath $current -Force
            foreach ($item in $items) {
                if ($item.LinkType) {
                    continue
                }

                if ($item.PSIsContainer) {
                    $childPath = [System.IO.Path]::GetFullPath($item.FullName)
                    if (-not $childPath.StartsWith($rootPrefix, [System.StringComparison]::Ordinal)) {
                        throw "Directory walk escaped repository root through '$childPath'."
                    }
                    if ($seenDirectories.Add($childPath)) {
                        $queue.Enqueue($childPath)
                        $count++
                        if ($count -ge $parsed.Threshold) {
                            return [pscustomobject]@{
                                Marker = $Marker; Status = 'passed'; Success = $true; Blocking = $isBlockingStage
                                Message = "Counted at least $count item(s), required >= $($parsed.Threshold)."
                            }
                        }
                    }
                    continue
                }

                $count++
                if ($count -ge $parsed.Threshold) {
                    return [pscustomobject]@{
                        Marker = $Marker; Status = 'passed'; Success = $true; Blocking = $isBlockingStage
                        Message = "Counted at least $count item(s), required >= $($parsed.Threshold)."
                    }
                }
            }
        }

        return [pscustomobject]@{
            Marker = $Marker
            Status = if ($count -ge $parsed.Threshold) { 'passed' } else { 'failed' }
            Success = $count -ge $parsed.Threshold
            Blocking = $isBlockingStage
            Message = "Counted $count item(s), required >= $($parsed.Threshold)."
        }
    }

    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
        return [pscustomobject]@{
            Marker = $Marker
            Status = 'failed'
            Success = $false
            Blocking = $isBlockingStage
            Message = "Target '$($parsed.RelativePath)' is not a file."
        }
    }

    $length = (Get-Item -LiteralPath $resolvedPath -Force).Length
    if ($length -gt $MaxFileBytes) {
        throw "File '$($parsed.RelativePath)' exceeds max size (${MaxFileBytes} bytes)."
    }

    if ($parsed.Assertion -eq 'exists') {
        return [pscustomobject]@{
            Marker = $Marker
            Status = 'passed'
            Success = $true
            Blocking = $isBlockingStage
            Message = "File '$($parsed.RelativePath)' exists."
        }
    }

    if ($parsed.Assertion -eq 'count') {
        $lineCount = @((Get-Content -LiteralPath $resolvedPath -Force)).Count
        return [pscustomobject]@{
            Marker = $Marker
            Status = if ($lineCount -ge $parsed.Threshold) { 'passed' } else { 'failed' }
            Success = $lineCount -ge $parsed.Threshold
            Blocking = $isBlockingStage
            Message = "File has $lineCount line(s), required >= $($parsed.Threshold)."
        }
    }

    $matchCount = Get-FileRegexMatchCount -Path $resolvedPath -Pattern $parsed.Regex -PerMatchTimeoutMs $PerMatchTimeoutMs
    return [pscustomobject]@{
        Marker = $Marker
        Status = if ($matchCount -gt 0) { 'passed' } else { 'failed' }
        Success = $matchCount -gt 0
        Blocking = $isBlockingStage
        Message = if ($matchCount -gt 0) { 'Regex matched.' } else { 'Regex did not match.' }
    }
}

Export-ModuleMember -Function ConvertTo-PlanEvidenceResult, ConvertFrom-StructuredTestEvidenceResult, Resolve-PlanEvidenceAssetPath, Get-PlanEvidenceWaiver, Read-PlanEvidenceReceipt, Parse-PlanFileEvidenceMarker, Invoke-PlanFileEvidence
