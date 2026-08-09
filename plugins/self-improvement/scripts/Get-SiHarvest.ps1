#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$RepoRoot = (Get-Location).Path,

    [Parameter(Mandatory)]
    [string]$PlanReference,

    [Parameter(Mandatory)]
    [ValidatePattern('^(?:[0-9a-f]{40}|[0-9a-f]{64})$')]
    [string]$PinnedBaseOid,

    [ValidateRange(1, 64)]
    [int]$PageSize = 64,

    [string]$Cursor,

    [string[]]$ArchiveReference = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Installed shared closure: .github/skills/si/scripts/{AtomicStore,PlanState}.psm1
Import-Module (Join-Path $PSScriptRoot 'PlanState.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'SiStateStore.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'AtomicStore.psm1') -Force

$protocol = 'si-harvest-index-v1'
$cursorProtocol = 'si-harvest-cursor-v1'
$ledgerNames = @(
    'consistency.md',
    'error-handling.md',
    'observability.md',
    'performance.md',
    'plan-structure.md',
    'security.md',
    'testing.md'
)
$maxFiles = 256
$maxScanBytes = 160MB
$maxScanSeconds = 60
$maxSelectedRecords = 1024
$maxSelectedBytes = 4MB
$maxPageBytes = 256KB
$maxIndexBytes = 8MB
$utf8 = [System.Text.UTF8Encoding]::new($false, $true)
$newline = "`n"
$wrapperFence = [string]::new([char]0x60, 4)
$stateContract = Get-SiStateContract

function Get-SiHarvestDigest {
    param(
        [Parameter(Mandatory)][string]$Domain,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Field
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Domain + [char]0 + ($Field -join [char]0))
    return [Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData($bytes)
    ).ToLowerInvariant()
}

function ConvertTo-StableJson {
    param([Parameter(Mandatory)]$Value)
    return $Value | ConvertTo-Json -Depth 100 -Compress
}

function Invoke-GitText {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string[]]$Argument
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = 'git'
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($item in @('-C', $Root) + $Argument) { $startInfo.ArgumentList.Add($item) }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { throw 'Unable to start git.' }
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) {
            throw "git $($Argument[0]) failed: $($stderr.Trim())"
        }
        return $stdout
    }
    finally {
        $process.Dispose()
    }
}

function Read-PinnedBlob {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$BlobOid
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = 'git'
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($item in @('-C', $Root, 'cat-file', 'blob', $BlobOid)) {
        $startInfo.ArgumentList.Add($item)
    }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { throw 'Unable to start git cat-file.' }
        $memory = [System.IO.MemoryStream]::new()
        try {
            $process.StandardOutput.BaseStream.CopyTo($memory)
            $stderr = $process.StandardError.ReadToEnd()
            $process.WaitForExit()
            if ($process.ExitCode -ne 0) { throw "git cat-file failed: $($stderr.Trim())" }
            return $memory.ToArray()
        }
        finally {
            $memory.Dispose()
        }
    }
    finally {
        $process.Dispose()
    }
}

function ConvertFrom-TreeLine {
    param([Parameter(Mandatory)][string]$Line)

    if ($Line -notmatch '^(?<mode>\d{6}) blob (?<oid>[0-9a-f]{40}|[0-9a-f]{64})\t(?<path>.+)$' -or
        $Matches.mode -notin @('100644', '100755')) {
        throw "Pinned harvest tree contains a non-regular or malformed entry '$Line'."
    }
    return [pscustomobject]@{
        Mode = $Matches.mode
        Oid  = $Matches.oid
        Path = $Matches.path
    }
}

function Get-PinnedTreeEntry {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$CommitOid,
        [Parameter(Mandatory)][string]$Path
    )

    $text = Invoke-GitText -Root $Root -Argument @(
        '-c', 'core.quotePath=false', 'ls-tree', '--full-tree', $CommitOid, '--', $Path
    )
    $lines = @($text.TrimEnd("`r", "`n") -split "`r?`n" | Where-Object { $_ })
    if ($lines.Count -eq 0) { return $null }
    if ($lines.Count -ne 1) { throw "Pinned harvest path '$Path' did not resolve to one file." }
    $entry = ConvertFrom-TreeLine -Line $lines[0]
    if (-not [string]::Equals($entry.Path, $Path, [System.StringComparison]::Ordinal)) {
        throw "Pinned harvest path '$Path' resolved as '$($entry.Path)'."
    }
    return $entry
}

function Get-PinnedTreeEntries {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$CommitOid,
        [Parameter(Mandatory)][string]$Prefix,
        [Parameter(Mandatory)][int]$MaxCount
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = 'git'
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($item in @(
            '-C', $Root, '-c', 'core.quotePath=false', 'ls-tree', '-r', '--full-tree',
            $CommitOid, '--', $Prefix
        )) {
        $startInfo.ArgumentList.Add($item)
    }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $entries = [System.Collections.Generic.List[object]]::new()
    try {
        if (-not $process.Start()) { throw 'Unable to start git ls-tree.' }
        while (($line = $process.StandardOutput.ReadLine()) -ne $null) {
            $entries.Add((ConvertFrom-TreeLine -Line $line))
            if ($entries.Count -gt $MaxCount) {
                $process.Kill($true)
                throw "capacity-blocked: pinned harvest root '$Prefix' exceeds $MaxCount files."
            }
        }
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { throw "git ls-tree failed: $($stderr.Trim())" }
        return $entries.ToArray()
    }
    finally {
        $process.Dispose()
    }
}

function Resolve-PhysicalPath {
    param([Parameter(Mandatory)][string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $root = [System.IO.Path]::GetPathRoot($fullPath)
    $current = $root
    foreach ($segment in @($fullPath.Substring($root.Length) -split '[\\/]' | Where-Object { $_ })) {
        $candidate = Join-Path $current $segment
        if (Test-Path -LiteralPath $candidate) {
            $item = Get-Item -LiteralPath $candidate -Force
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                $target = $item.ResolveLinkTarget($true)
                if ($null -eq $target) { throw "Cannot resolve harvest link '$candidate'." }
                $current = [System.IO.Path]::GetFullPath($target.FullName)
                continue
            }
        }
        $current = [System.IO.Path]::GetFullPath($candidate)
    }
    return $current
}

function Assert-PhysicalDescendant {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Path
    )

    $physicalRoot = Resolve-PhysicalPath -Path $Root
    $physicalPath = Resolve-PhysicalPath -Path $Path
    $prefix = $physicalRoot.TrimEnd([char[]]@(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        )) + [System.IO.Path]::DirectorySeparatorChar
    $comparison = if ($IsWindows) {
        [System.StringComparison]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparison]::Ordinal
    }
    if (-not $physicalPath.StartsWith($prefix, $comparison)) {
        throw "Harvest path '$Path' escapes '$Root' through a link or reparse point."
    }
}

function Get-RelativeHarvestPath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Path
    )

    $relative = [System.IO.Path]::GetRelativePath($Root, [System.IO.Path]::GetFullPath($Path)).Replace('\', '/')
    if ($relative -eq '..' -or $relative.StartsWith('../', [System.StringComparison]::Ordinal)) {
        throw "Harvest path '$Path' escapes repository root."
    }
    return $relative
}

function New-HarvestRecord {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$SourceKind,
        [Parameter(Mandatory)][int]$Ordinal,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content
    )

    $contentBytes = [System.Text.Encoding]::UTF8.GetBytes($Content)
    if ($contentBytes.Length -gt $maxPageBytes) {
        throw "capacity-blocked: harvest record '$SourcePath#$Ordinal' exceeds the 256 KiB page ceiling."
    }
    $severity = if ($Content -match '(?i)(?:\[sev:|severity["'']?\s*[:=]\s*["'']?)(Critical|High|Med|Low)') {
        $Matches[1].Substring(0, 1).ToUpperInvariant() + $Matches[1].Substring(1).ToLowerInvariant()
    }
    else {
        'Low'
    }
    $severityScore = switch ($severity) {
        'Critical' { 4 }
        'High' { 3 }
        'Med' { 2 }
        default { 1 }
    }
    $recurrence = if ($Content -match '(?i)\[recurrence:\s*(\d+)\]') {
        [Math]::Max(1, [int]$Matches[1])
    }
    else {
        [Math]::Max(1, @([regex]::Matches($Content, '(?i)(?:plan-|plan:)[0-9a-f]{6}|(?:plan-|plan:)\d{3}') |
                    ForEach-Object { $_.Value.ToLowerInvariant() } | Select-Object -Unique).Count)
    }
    $blastRadius = switch ($SourceKind) {
        'ledger' { 3 }
        'active-run' { 3 }
        'feedback' { 2 }
        'plan-log' { 2 }
        'learning-overflow' { 2 }
        default { 1 }
    }
    $contentDigest = Get-SiHarvestDigest -Domain 'si-harvest-record-content-v1' -Field @($Content)
    return [pscustomobject][ordered]@{
        recordId      = Get-SiHarvestDigest -Domain 'si-harvest-record-v1' -Field @(
            $SourcePath, $SourceKind, [string]$Ordinal, $contentDigest
        )
        sourcePath    = $SourcePath
        sourceKind    = $SourceKind
        ordinal       = $Ordinal
        recurrence    = $recurrence
        severity      = $severity
        severityScore = $severityScore
        blastRadius   = $blastRadius
        byteCount     = $contentBytes.Length
        contentBase64 = [Convert]::ToBase64String($contentBytes)
    }
}

function ConvertTo-HarvestRecords {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$SourceKind,
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$PlanId
    )

    $contents = [System.Collections.Generic.List[string]]::new()
    $lines = @($Text -split "`r?`n")
    switch ($SourceKind) {
        'manifest' {
            $schemaPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../schemas/manifest.schema.json'))
            $errors = @()
            if (-not ($Text | Test-Json -SchemaFile $schemaPath -ErrorVariable errors)) {
                throw "Manifest source '$SourcePath' failed schema validation."
            }
        }
        'phase-receipt' {
            try { $receipt = $Text | ConvertFrom-Json -Depth 100 }
            catch { throw "Malformed phase receipt '$SourcePath': $($_.Exception.Message)" }
            $names = @($receipt.PSObject.Properties.Name)
            $payloadNames = @($receipt.payload.PSObject.Properties.Name)
            if ($names.Count -ne 3 -or
                @('schema', 'receiptId', 'payload' | Where-Object { $names -notcontains $_ }).Count -gt 0 -or
                $receipt.schema -ne 'phase-harvest-receipt/v1' -or
                $receipt.receiptId -notmatch '^[0-9a-f]{64}$' -or
                $payloadNames.Count -ne 7 -or
                @('repo', 'plan', 'phase', 'status', 'ledgerSource', 'sources', 'candidates' |
                        Where-Object { $payloadNames -notcontains $_ }).Count -gt 0 -or
                $receipt.payload.plan -ne $PlanId -or
                $receipt.payload.status -notin @('complete', 'empty') -or
                $receipt.payload.ledgerSource -notin @('ci', 'autopilot') -or
                [int]$receipt.payload.phase -ne
                [int]([regex]::Match($SourcePath, 'phase-(\d{3})\.json$').Groups[1].Value)) {
                throw "Phase receipt '$SourcePath' failed closed payload validation."
            }
            $expected = Get-SiHarvestDigest -Domain 'phase-harvest-receipt/v1' -Field @(
                ConvertTo-StableJson -Value $receipt.payload
            )
            if ($expected -ne [string]$receipt.receiptId) {
                throw "Phase receipt '$SourcePath' failed its content-address check."
            }
        }
        'ledger' {
            foreach ($line in $lines) {
                if ($line -match '^- \[\d{4}-\d{2}-\d{2}\] ') { $contents.Add($line) }
            }
        }
        'feedback' {
            $recorded = [Array]::IndexOf($lines, '## Recorded')
            if ($recorded -lt 0) { throw "Feedback source '$SourcePath' is missing its ## Recorded section." }
            for ($index = $recorded + 1; $index -lt $lines.Count; $index++) {
                if ($lines[$index] -match '^## ') { break }
                if ($lines[$index] -match '^- \[') { $contents.Add($lines[$index]) }
            }
        }
        'plan-log' {
            if ($Text -notmatch '(?m)^## (?:CR Capture|Learnings Capture|Capture)\s*$' -or
                $Text -notmatch '(?m)^Phase: \d+\s*$') {
                throw "Plan log '$SourcePath' is missing its expected header or phase section."
            }
            foreach ($line in $lines) {
                if ($line -match '^- \[') { $contents.Add($line) }
            }
        }
        'learning-overflow' {
            if ($lines.Count -lt 7 -or $lines[0] -ne '# Learning Overflow Batch' -or
                $lines[1] -ne 'Schema: workflow-learning-overflow/v1' -or
                $lines[2] -ne "Plan: $PlanId" -or $lines[3] -notmatch '^Digest: [0-9a-f]{64}$' -or
                $lines[4] -notmatch '^Count: \d+$' -or $lines[5] -ne '') {
                throw "Malformed learning overflow source '$SourcePath'."
            }
            $records = @($lines[6..($lines.Count - 1)] | Where-Object {
                    -not [string]::IsNullOrEmpty($_)
                })
            $recordBytes = ($records -join "`n") + "`n"
            $expected = Get-SiHarvestDigest -Domain 'workflow-learning-overflow/v1' -Field @($PlanId, $recordBytes)
            $declared = $lines[3].Substring('Digest: '.Length)
            if ($records.Count -ne [int]$lines[4].Substring('Count: '.Length) -or
                $declared -ne $expected -or
                [System.IO.Path]::GetFileNameWithoutExtension($SourcePath) -ne $declared) {
                throw "Learning overflow source '$SourcePath' failed its count or digest check."
            }
            foreach ($record in $records) { $contents.Add($record) }
        }
        'active-run' {
            try { $run = $Text | ConvertFrom-Json -Depth 100 }
            catch { throw "Malformed active SI run '$SourcePath': $($_.Exception.Message)" }
            $schemaPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../schemas/run.schema.json'))
            $errors = @()
            if (-not ($Text | Test-Json -SchemaFile $schemaPath -ErrorVariable errors)) {
                throw "Active SI run '$SourcePath' failed schema validation."
            }
            Assert-SiRunIntegrity -Run $run
            foreach ($candidate in @($run.rankedSet.candidates)) {
                $contents.Add((ConvertTo-StableJson -Value $candidate))
            }
        }
        'archive-reference' {
            if ($SourcePath.EndsWith('.json', [System.StringComparison]::OrdinalIgnoreCase)) {
                try {
                    $document = $Text | ConvertFrom-Json -Depth 100
                    if ($document.PSObject.Properties.Name -contains 'rankedSet' -and
                        $document.rankedSet.PSObject.Properties.Name -contains 'candidates') {
                        foreach ($candidate in @($document.rankedSet.candidates)) {
                            $contents.Add((ConvertTo-StableJson -Value $candidate))
                        }
                    }
                    else {
                        $contents.Add((ConvertTo-StableJson -Value $document))
                    }
                }
                catch { throw "Malformed archive JSON '$SourcePath': $($_.Exception.Message)" }
            }
            else {
                foreach ($line in $lines) {
                    if ($line -match '^- \[') { $contents.Add($line) }
                }
            }
        }
        default { throw "Unknown SI harvest source kind '$SourceKind'." }
    }

    if (($SourceKind -eq 'ledger' -and $contents.Count -gt 10000) -or
        ($SourceKind -eq 'feedback' -and $contents.Count -gt 2048) -or
        ($SourceKind -eq 'learning-overflow' -and $contents.Count -gt 64)) {
        throw "capacity-blocked: harvest source '$SourcePath' exceeds its record-count ceiling."
    }

    $result = [System.Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $contents.Count; $index++) {
        $result.Add((New-HarvestRecord -SourcePath $SourcePath -SourceKind $SourceKind `
                    -Ordinal ($index + 1) -Content $contents[$index]))
    }
    return $result.ToArray()
}

function New-HarvestCursor {
    param(
        [Parameter(Mandatory)][string]$PlanId,
        [Parameter(Mandatory)][string]$PinnedOid,
        [Parameter(Mandatory)][string]$SnapshotDigest,
        [Parameter(Mandatory)][string]$SelectedDigest,
        [Parameter(Mandatory)][int]$Offset
    )

    $payload = [ordered]@{
        protocol       = $cursorProtocol
        planId         = $PlanId
        pinnedBaseOid  = $PinnedOid
        snapshotDigest = $SnapshotDigest
        selectedDigest = $SelectedDigest
        offset         = $Offset
    }
    $payload.cursorId = Get-SiHarvestDigest -Domain $cursorProtocol -Field @(
        $PlanId, $PinnedOid, $SnapshotDigest, $SelectedDigest, [string]$Offset
    )
    $bytes = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-StableJson -Value $payload))
    return [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function Read-HarvestCursor {
    param([Parameter(Mandatory)][string]$Value)

    if ([System.Text.Encoding]::UTF8.GetByteCount($Value) -gt 16KB -or $Value -notmatch '^[A-Za-z0-9_-]+$') {
        throw 'Harvest cursor is malformed or exceeds 16 KiB.'
    }
    $base64 = $Value.Replace('-', '+').Replace('_', '/')
    $base64 += '=' * ((4 - ($base64.Length % 4)) % 4)
    try {
        $cursorDocument = $utf8.GetString([Convert]::FromBase64String($base64)) | ConvertFrom-Json -Depth 10
    }
    catch {
        throw "Harvest cursor is malformed: $($_.Exception.Message)"
    }
    $names = @($cursorDocument.PSObject.Properties.Name)
    if ($names.Count -ne 7 -or
        @('protocol', 'planId', 'pinnedBaseOid', 'snapshotDigest', 'selectedDigest', 'offset', 'cursorId' |
                Where-Object { $names -notcontains $_ }).Count -gt 0 -or
        $cursorDocument.protocol -ne $cursorProtocol -or [int64]$cursorDocument.offset -lt 0) {
        throw 'Harvest cursor has an invalid closed payload.'
    }
    $expected = Get-SiHarvestDigest -Domain $cursorProtocol -Field @(
        [string]$cursorDocument.planId,
        [string]$cursorDocument.pinnedBaseOid,
        [string]$cursorDocument.snapshotDigest,
        [string]$cursorDocument.selectedDigest,
        [string][int64]$cursorDocument.offset
    )
    if ($expected -ne [string]$cursorDocument.cursorId) {
        throw 'Harvest cursor digest mismatch.'
    }
    return $cursorDocument
}

$repoRootFull = [System.IO.Path]::GetFullPath($RepoRoot)
if (-not (Test-Path -LiteralPath $repoRootFull -PathType Container)) {
    throw "Repository root not found: $repoRootFull"
}

$PinnedBaseOid = $PinnedBaseOid.ToLowerInvariant()
$null = Invoke-GitText -Root $repoRootFull -Argument @('cat-file', '-e', "$PinnedBaseOid`^{commit}")
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

$inventory = @(Get-PlanInventory -RepoRoot $repoRootFull)
if ($stopwatch.Elapsed.TotalSeconds -gt $maxScanSeconds) {
    throw 'capacity-blocked: SI plan discovery exceeded 60 seconds.'
}
$plan = Resolve-Plan -Reference $PlanReference -RepoRoot $repoRootFull -Inventory $inventory
$planId = [string]$plan.Id
$planDir = [System.IO.Path]::GetFullPath([string]$plan.Path)
$planRelative = Get-RelativeHarvestPath -Root $repoRootFull -Path (Join-Path $planDir 'plan.md')
$pinnedPlan = Get-PinnedTreeEntry -Root $repoRootFull -CommitOid $PinnedBaseOid -Path $planRelative
if ($null -eq $pinnedPlan) { throw "Resolved plan '$planId' is absent from pinned commit '$PinnedBaseOid'." }
$pinnedPlanBytes = Read-PinnedBlob -Root $repoRootFull -BlobOid $pinnedPlan.Oid
if ($pinnedPlanBytes.Length -gt 1MB) { throw "Resolved plan '$planId' exceeds the discovery ceiling." }
$pinnedPlanText = $utf8.GetString($pinnedPlanBytes)
if ($pinnedPlanText -notmatch "(?m)^<!-- plan-id: $([regex]::Escape($planId)) -->\s*$") {
    throw "Resolved plan '$planId' does not match its pinned plan-id anchor."
}

$sourceSpecs = [System.Collections.Generic.List[object]]::new()
$sourcePaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
function Add-SourceSpec {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][long]$MaxBytes,
        $Entry
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $relative = Get-RelativeHarvestPath -Root $repoRootFull -Path $fullPath
    if (-not $sourcePaths.Add($relative)) { throw "Duplicate SI harvest source '$relative'." }
    $sourceSpecs.Add([pscustomobject]@{
            Path         = $fullPath
            RelativePath = $relative
            Kind         = $Kind
            MaxBytes     = $MaxBytes
            Entry        = $Entry
        })
}

$manifestPath = Resolve-SiStatePath -RepoRoot $repoRootFull -Segments @(
    [string]$stateContract.Topology.ManifestName
)
Add-SourceSpec -Path $manifestPath -Kind manifest -MaxBytes 256KB
foreach ($ledgerName in $ledgerNames) {
    Add-SourceSpec -Path (Join-Path $repoRootFull "docs/review-ledger/$ledgerName") -Kind ledger -MaxBytes 4MB
}
foreach ($kind in @('CrLog', 'Learnings', 'Capture')) {
    Add-SourceSpec -Path (Resolve-PlanAssetPath -PlanDir $planDir -Kind $kind `
            -RepoRoot $repoRootFull -Inventory $inventory) -Kind plan-log -MaxBytes 4MB
}
Add-SourceSpec -Path (Join-Path $repoRootFull 'docs/feedback/queue.md') -Kind feedback -MaxBytes 4MB

$overflowRoot = Resolve-PlanAssetPath -PlanDir $planDir -Kind LearningOverflowRoot `
    -RepoRoot $repoRootFull -Inventory $inventory
$overflowRelative = Get-RelativeHarvestPath -Root $repoRootFull -Path $overflowRoot
$overflowEntries = @(Get-PinnedTreeEntries -Root $repoRootFull -CommitOid $PinnedBaseOid `
        -Prefix $overflowRelative -MaxCount 64)
foreach ($entry in $overflowEntries) {
    if ($entry.Path -notmatch ('^' + [regex]::Escape($overflowRelative.TrimEnd('/') + '/') +
            '[0-9a-f]{64}\.md$')) {
        throw "Unexpected active learning overflow file '$($entry.Path)'."
    }
    Add-SourceSpec -Path (Join-Path $repoRootFull $entry.Path) -Kind learning-overflow `
        -MaxBytes 512KB -Entry $entry
}

$receiptRoot = Resolve-PlanAssetPath -PlanDir $planDir -Kind HarvestReceiptRoot `
    -RepoRoot $repoRootFull -Inventory $inventory
$receiptRelative = Get-RelativeHarvestPath -Root $repoRootFull -Path $receiptRoot
$receiptEntries = @(Get-PinnedTreeEntries -Root $repoRootFull -CommitOid $PinnedBaseOid `
        -Prefix $receiptRelative -MaxCount 64)
foreach ($entry in $receiptEntries) {
    if ($entry.Path -notmatch ('^' + [regex]::Escape($receiptRelative.TrimEnd('/') + '/') +
            'phase-\d{3}\.json$')) {
        throw "Unexpected active phase receipt '$($entry.Path)'."
    }
    Add-SourceSpec -Path (Join-Path $repoRootFull $entry.Path) -Kind phase-receipt `
        -MaxBytes 64KB -Entry $entry
}

$runsRoot = Resolve-SiStatePath -RepoRoot $repoRootFull `
    -Segments @([string]$stateContract.Topology.ActiveRunsSegments[0])
$stateRootRelative = (
    Get-RelativeHarvestPath -Root $repoRootFull -Path (Split-Path -Parent $manifestPath)
).TrimEnd('/') + '/'
$activeRunsRelative = $stateRootRelative + [string]$stateContract.Topology.ActiveRunsSegments[0] + '/'
$runEntries = @(Get-PinnedTreeEntries -Root $repoRootFull -CommitOid $PinnedBaseOid `
        -Prefix $activeRunsRelative.TrimEnd('/') -MaxCount 48)
foreach ($entry in $runEntries) {
    if ($entry.Path -notmatch ('^' + [regex]::Escape($activeRunsRelative) +
            '\d{4}/\d{2}/[0-9a-f]{64}\.json$')) {
        throw "Unexpected active SI run path '$($entry.Path)'."
    }
    Add-SourceSpec -Path (Join-Path $repoRootFull $entry.Path) -Kind active-run `
        -MaxBytes 1MB -Entry $entry
}

$archivePrefixes = @(
    'docs/review-ledger/.archive/'
    $stateRootRelative + [string]$stateContract.Topology.ArchiveSegments[0] + '/'
    $stateRootRelative + [string]$stateContract.Topology.BackupSegments[0] + '/'
    $stateRootRelative + [string]$stateContract.Topology.QuarantineSegments[0] + '/'
    $stateRootRelative + [string]$stateContract.Topology.ObservationSegments[0] + '/'
    $stateRootRelative + [string]$stateContract.Topology.ReceiptSegments[0] + '/'
    $stateRootRelative + [string]$stateContract.Topology.ResolverReceiptSegments[0] + '/'
)
foreach ($reference in @($ArchiveReference)) {
    $normalized = $reference.Replace('\', '/').TrimStart('/')
    if ($normalized -notmatch '^[A-Za-z0-9._/-]+$' -or $normalized -match '(^|/)\.\.?(/|$)' -or
        @($archivePrefixes | Where-Object {
                $normalized.StartsWith($_, [System.StringComparison]::Ordinal)
            }).Count -ne 1) {
        throw "Archive reference '$reference' is outside the closed auxiliary/archive roots."
    }
    $archivePath = [System.IO.Path]::GetFullPath((Join-Path $repoRootFull $normalized))
    $entry = Get-PinnedTreeEntry -Root $repoRootFull -CommitOid $PinnedBaseOid -Path $normalized
    if ($null -eq $entry) { throw "Archive reference '$reference' is absent from the pinned commit." }
    Add-SourceSpec -Path $archivePath -Kind archive-reference -MaxBytes 1MB -Entry $entry
}

$sources = [System.Collections.Generic.List[object]]::new()
$records = [System.Collections.Generic.List[object]]::new()
$fileCount = 0
$scanBytes = [long]0
$completedRuns = 0
$inFlightRuns = 0
foreach ($spec in @($sourceSpecs | Sort-Object RelativePath)) {
    if ($stopwatch.Elapsed.TotalSeconds -gt $maxScanSeconds) {
        throw 'capacity-blocked: SI active scan exceeded 60 seconds.'
    }
    $entry = if ($null -ne $spec.Entry) {
        $spec.Entry
    }
    else {
        Get-PinnedTreeEntry -Root $repoRootFull -CommitOid $PinnedBaseOid -Path $spec.RelativePath
    }
    if ($null -eq $entry) {
        $sources.Add([pscustomobject][ordered]@{
                path      = $spec.RelativePath
                kind      = $spec.Kind
                status    = 'absent'
                byteCount = 0
                sha256    = $null
            })
        continue
    }
    $bytes = Read-PinnedBlob -Root $repoRootFull -BlobOid $entry.Oid
    $fileCount++
    $scanBytes += $bytes.Length
    if ($fileCount -gt $maxFiles -or $scanBytes -gt $maxScanBytes) {
        throw 'capacity-blocked: SI active scan exceeds 256 files or 160 MiB.'
    }
    if ($bytes.Length -gt [long]$spec.MaxBytes) {
        throw "capacity-blocked: harvest source '$($spec.RelativePath)' exceeds its byte ceiling."
    }
    try { $text = $utf8.GetString($bytes) }
    catch { throw "Harvest source '$($spec.RelativePath)' is not valid UTF-8." }
    $sha256 = [Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData($bytes)
    ).ToLowerInvariant()
    $sources.Add([pscustomobject][ordered]@{
            path      = $spec.RelativePath
            kind      = $spec.Kind
            status    = 'present'
            byteCount = $bytes.Length
            sha256    = $sha256
        })
    if ($spec.Kind -eq 'active-run') {
        $run = $text | ConvertFrom-Json -Depth 100
        $runRecords = @(ConvertTo-HarvestRecords -SourcePath $spec.RelativePath `
                -SourceKind $spec.Kind -Text $text -PlanId $planId)
        if ([string]$run.status -in @('declined-before-ranking', 'no-candidates', 'completed')) {
            $completedRuns++
        }
        else {
            $inFlightRuns++
        }
        if ($completedRuns -gt 32 -or $inFlightRuns -gt 16) {
            throw 'capacity-blocked: active SI run status ceilings exceeded.'
        }
        foreach ($record in $runRecords) { $records.Add($record) }
        continue
    }
    foreach ($record in @(ConvertTo-HarvestRecords -SourcePath $spec.RelativePath `
                -SourceKind $spec.Kind -Text $text -PlanId $planId)) {
        $records.Add($record)
    }
}
if ($stopwatch.Elapsed.TotalSeconds -gt $maxScanSeconds) {
    throw 'capacity-blocked: SI active scan exceeded 60 seconds.'
}

$sourceDigestJson = ConvertTo-StableJson -Value @($sources)
$snapshotDigest = Get-SiHarvestDigest -Domain 'si-harvest-snapshot-v1' -Field @(
    $PinnedBaseOid, $planId, $sourceDigestJson
)
$orderedRecords = @($records | Sort-Object `
    @{ Expression = 'recurrence'; Descending = $true },
    @{ Expression = 'severityScore'; Descending = $true },
    @{ Expression = 'blastRadius'; Descending = $true },
    @{ Expression = 'byteCount'; Descending = $false },
    @{ Expression = 'recordId'; Descending = $false })
$selected = [System.Collections.Generic.List[object]]::new()
$selectedBytes = [long]0
foreach ($record in $orderedRecords) {
    if ($selected.Count -ge $maxSelectedRecords) { break }
    if ($selectedBytes + [long]$record.byteCount -gt $maxSelectedBytes) { continue }
    $raw = $utf8.GetString([Convert]::FromBase64String([string]$record.contentBase64))
    $neutralized = [regex]::Replace($raw, '(?i)UNTRUSTED_INPUT', 'UNTRUSTED-INPUT[neutralized]')
    $safeSource = [regex]::Replace([string]$record.sourcePath, '[\r\n"]', '_')
    $safeSource = [regex]::Replace($safeSource, '(?i)UNTRUSTED_INPUT', 'UNTRUSTED-INPUT[neutralized]')
    $capacityProbe = "<<<UNTRUSTED_INPUT_START id=$('0' * 24) source=`"$safeSource`">>>" +
    $newline + $wrapperFence + $newline + $neutralized + $newline + $wrapperFence + $newline +
    "<<<UNTRUSTED_INPUT_END id=$('0' * 24)>>>"
    if ([System.Text.Encoding]::UTF8.GetByteCount($capacityProbe) -gt $maxPageBytes) {
        throw "capacity-blocked: wrapped harvest record '$($record.recordId)' exceeds the page ceiling."
    }
    $selected.Add($record)
    $selectedBytes += [long]$record.byteCount
}
$selectedDigest = Get-SiHarvestDigest -Domain 'si-harvest-selected-window-v1' -Field @(
    $snapshotDigest,
    (ConvertTo-StableJson -Value @($selected | ForEach-Object {
            [ordered]@{ recordId = $_.recordId; contentBase64 = $_.contentBase64 }
        }))
)

$cursorDocument = if ($Cursor) { Read-HarvestCursor -Value $Cursor } else { $null }
$offset = if ($null -eq $cursorDocument) { 0 } else { [int64]$cursorDocument.offset }
if ($null -ne $cursorDocument -and (
        $cursorDocument.planId -ne $planId -or
        $cursorDocument.pinnedBaseOid -ne $PinnedBaseOid -or
        $cursorDocument.snapshotDigest -ne $snapshotDigest -or
        $cursorDocument.selectedDigest -ne $selectedDigest
    )) {
    throw 'Harvest cursor is stale for the current pinned snapshot or selected evidence window.'
}
if ($offset -gt $selected.Count) { throw 'Harvest cursor offset exceeds the selected evidence window.' }

$page = [System.Collections.Generic.List[object]]::new()
$pageBytes = [long]0
for ($indexOffset = [int]$offset; $indexOffset -lt $selected.Count -and $page.Count -lt $PageSize; $indexOffset++) {
    $record = $selected[$indexOffset]
    $raw = $utf8.GetString([Convert]::FromBase64String([string]$record.contentBase64))
    $injection = $raw -match '(?i)UNTRUSTED_INPUT'
    $neutralized = [regex]::Replace($raw, '(?i)UNTRUSTED_INPUT', 'UNTRUSTED-INPUT[neutralized]')
    $wrapperId = [Convert]::ToHexString(
        [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(12)
    ).ToLowerInvariant()
    $safeSource = [regex]::Replace([string]$record.sourcePath, '[\r\n"]', '_')
    $safeSource = [regex]::Replace($safeSource, '(?i)UNTRUSTED_INPUT', 'UNTRUSTED-INPUT[neutralized]')
    $wrapped = "<<<UNTRUSTED_INPUT_START id=$wrapperId source=`"$safeSource`">>>" +
    $newline + $wrapperFence + $newline + $neutralized + $newline + $wrapperFence + $newline +
    "<<<UNTRUSTED_INPUT_END id=$wrapperId>>>"
    $wrappedBytes = [System.Text.Encoding]::UTF8.GetByteCount($wrapped)
    if ($pageBytes + $wrappedBytes -gt $maxPageBytes) {
        if ($page.Count -eq 0) {
            throw "capacity-blocked: wrapped harvest record '$($record.recordId)' exceeds the page ceiling."
        }
        break
    }
    $page.Add([pscustomobject][ordered]@{
            recordId          = $record.recordId
            sourcePath        = $record.sourcePath
            sourceKind        = $record.sourceKind
            recurrence        = $record.recurrence
            severity          = $record.severity
            blastRadius       = $record.blastRadius
            injectionDetected = $injection
            wrappedContent    = $wrapped
        })
    $pageBytes += $wrappedBytes
}

$index = [ordered]@{
    schemaVersion     = 1
    protocol          = $protocol
    planId            = $planId
    planPath          = Get-RelativeHarvestPath -Root $repoRootFull -Path $planDir
    pinnedBaseOid     = $PinnedBaseOid
    snapshotDigest    = $snapshotDigest
    selectedDigest    = $selectedDigest
    fileCount         = $fileCount
    scannedByteCount  = $scanBytes
    sourceCount       = $sources.Count
    recordCount       = $records.Count
    selectedByteCount = $selectedBytes
    sources           = @($sources)
    selectedRecords   = @($selected)
}
$indexJson = (ConvertTo-StableJson -Value $index) + "`n"
if ([System.Text.Encoding]::UTF8.GetByteCount($indexJson) -gt $maxIndexBytes) {
    throw 'capacity-blocked: SI harvest index exceeds 8 MiB.'
}
$indexPath = Resolve-SiStatePath -RepoRoot $repoRootFull -Segments @('harvest-index.json')
Assert-PhysicalDescendant -Root $repoRootFull -Path $indexPath
$indexWrite = Invoke-AtomicStoreUpdate -Path $indexPath -Transform { $indexJson } -Validate {
    param($tempPath)
    $candidate = [System.IO.File]::ReadAllText($tempPath) | ConvertFrom-Json -Depth 100
    $names = @($candidate.PSObject.Properties.Name)
    if ($names.Count -ne 14 -or
        @('schemaVersion', 'protocol', 'planId', 'planPath', 'pinnedBaseOid', 'snapshotDigest',
            'selectedDigest', 'fileCount', 'scannedByteCount', 'sourceCount', 'recordCount',
            'selectedByteCount', 'sources', 'selectedRecords' |
                Where-Object { $names -notcontains $_ }).Count -gt 0 -or
        $candidate.schemaVersion -ne 1 -or $candidate.protocol -ne $protocol) {
        throw 'SI harvest index failed closed-shape validation.'
    }
}
if ($indexWrite.Status -ne 'complete') {
    throw "SI harvest index write failed with status '$($indexWrite.Status)'."
}

$nextOffset = [int]$offset + $page.Count
return [pscustomobject][ordered]@{
    Status            = if ($selected.Count -eq 0) { 'empty' } else { 'complete' }
    PlanId            = $planId
    PinnedBaseOid     = $PinnedBaseOid
    SnapshotDigest    = $snapshotDigest
    SelectedDigest    = $selectedDigest
    FileCount         = $fileCount
    ScannedByteCount  = $scanBytes
    SourceCount       = $sources.Count
    RecordCount       = $records.Count
    SelectedCount     = $selected.Count
    SelectedByteCount = $selectedBytes
    InjectionCount    = @($page | Where-Object injectionDetected).Count
    IndexPath         = $indexPath
    Items             = $page.ToArray()
    NextCursor        = if ($nextOffset -lt $selected.Count) {
        New-HarvestCursor -PlanId $planId -PinnedOid $PinnedBaseOid -SnapshotDigest $snapshotDigest `
            -SelectedDigest $selectedDigest -Offset $nextOffset
    }
    else {
        $null
    }
}
