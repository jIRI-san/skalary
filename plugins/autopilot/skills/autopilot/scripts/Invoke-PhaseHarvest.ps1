#requires -Version 7.0
[CmdletBinding(DefaultParameterSetName = 'Phase')]
param(
    [Parameter(Mandatory)]
    [string]$PlanDir,

    [Parameter(Mandatory, ParameterSetName = 'Phase')]
    [Parameter(Mandatory, ParameterSetName = 'ValidateReceipt')]
    [Parameter(Mandatory, ParameterSetName = 'MigrateReceipt')]
    [ValidateRange(0, 999)]
    [int]$Phase,

    [Parameter(Mandatory, ParameterSetName = 'FinalSweep')]
    [switch]$FinalSweep,

    [Parameter(Mandatory, ParameterSetName = 'ValidateReceipt')]
    [switch]$ValidateReceipt,

    [Parameter(Mandatory, ParameterSetName = 'MigrateReceipt')]
    [switch]$MigrateLegacyReceipt,

    [Parameter(ParameterSetName = 'MigrateReceipt')]
    [ValidatePattern('^(?!-)[A-Za-z0-9][A-Za-z0-9._/@{}^~-]*$')]
    [string]$SourceRef = 'HEAD',

    [ValidateSet('ci', 'autopilot')]
    [string]$Src = 'ci',

    [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'LedgerStore.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AtomicStore.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'PlanState.psm1') -Force -DisableNameChecking

$receiptSchema = 'phase-harvest-receipt/v2'
$legacyReceiptSchema = 'phase-harvest-receipt/v1'
$migrationSchema = 'phase-harvest-receipt-migration/v1'
$migrationTool = 'skalary/Invoke-PhaseHarvest.ps1@phase-receipt-migration/v1'
$overflowSchema = 'workflow-learning-overflow/v1'
$maxCandidates = 64
$maxCandidateBytes = 512KB
$maxSourceRecordBytes = 16KB
$maxReceipts = 64
$maxReceiptBytes = 64KB
$placeholder = 'No entries for this phase.'
$kindConfig = [ordered]@{
    CrLog = [pscustomobject]@{ Header = '## CR Capture'; AssetKind = 'CrLog' }
    Learnings = [pscustomobject]@{ Header = '## Learnings Capture'; AssetKind = 'Learnings' }
    Capture = [pscustomobject]@{ Header = '## Capture'; AssetKind = 'Capture' }
}
$categoryMap = @{
    security = @{ cr = 'security'; dr = 'security' }
    'correctness-reliability' = @{ cr = 'error-handling'; dr = 'error-handling' }
    'architecture-patterns' = @{ cr = 'consistency'; dr = 'consistency' }
    performance = @{ cr = 'performance'; dr = 'performance' }
    'testing-evidence' = @{ cr = 'testing'; dr = 'plan-structure' }
    'maintainability-consistency' = @{ cr = 'consistency'; dr = 'consistency' }
    'operability-observability' = @{ cr = 'observability'; dr = 'observability' }
}

function Get-Sha256Hex {
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)

    return [Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData($Bytes)
    ).ToLowerInvariant()
}

function Get-DomainSeparatedId {
    param(
        [Parameter(Mandatory)][string]$Domain,
        [Parameter(Mandatory)][string[]]$Field
    )

    return Get-Sha256Hex -Bytes ([System.Text.Encoding]::UTF8.GetBytes(
            $Domain + [char]0 + ($Field -join [char]0)
        ))
}

function Get-RepoIdentity {
    param([Parameter(Mandatory)][string]$Root)

    $gitExitCode = 1
    $remote = try {
        $remoteOutput = & git -C $Root remote get-url origin 2>$null
        $gitExitCode = $LASTEXITCODE
        ([string]($remoteOutput | Select-Object -First 1)).Trim()
    }
    catch {
        ''
    }
    if ($gitExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($remote)) {
        $uri = $null
        if ([System.Uri]::TryCreate($remote, [System.UriKind]::Absolute, [ref]$uri) -and
            -not [string]::IsNullOrWhiteSpace($uri.Host)) {
            $repositoryPath = $uri.AbsolutePath.Trim('/').Replace('\', '/')
            if ($repositoryPath.EndsWith('.git', [System.StringComparison]::OrdinalIgnoreCase)) {
                $repositoryPath = $repositoryPath.Substring(0, $repositoryPath.Length - 4)
            }
            return 'origin:' + $uri.Host.ToLowerInvariant() + '/' + $repositoryPath
        }
        $scp = [regex]::Match($remote, '^(?:[^@]+@)?(?<host>[^:]+):(?<path>.+)$')
        if ($scp.Success) {
            $repositoryPath = $scp.Groups['path'].Value.Trim('/').Replace('\', '/')
            if ($repositoryPath.EndsWith('.git', [System.StringComparison]::OrdinalIgnoreCase)) {
                $repositoryPath = $repositoryPath.Substring(0, $repositoryPath.Length - 4)
            }
            return 'origin:' + $scp.Groups['host'].Value.ToLowerInvariant() + '/' + $repositoryPath
        }
        return 'origin-sha256:' + (Get-Sha256Hex -Bytes ([System.Text.Encoding]::UTF8.GetBytes($remote)))
    }
    $localPath = [System.IO.Path]::GetFullPath($Root).Replace('\', '/').TrimEnd('/')
    return 'path-sha256:' + (Get-Sha256Hex -Bytes ([System.Text.Encoding]::UTF8.GetBytes($localPath)))
}

function Get-RelativeSourcePath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Path
    )

    $relative = [System.IO.Path]::GetRelativePath($Root, [System.IO.Path]::GetFullPath($Path)).Replace('\', '/')
    if ($relative -eq '..' -or $relative.StartsWith('../', [System.StringComparison]::Ordinal)) {
        throw "Harvest source '$Path' escapes repository root."
    }
    return $relative
}

function Assert-PhysicalDescendant {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Path
    )

    $physicalRoot = Resolve-PhysicalRepoPath -Path $Root
    $physicalPath = Resolve-PhysicalRepoPath -Path $Path
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
        throw "Harvest file '$Path' escapes '$Root' through a link or reparse point."
    }
}

function Test-HarvestSourceSnapshot {
    param(
        [Parameter(Mandatory)][object[]]$Source,
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$OverflowRoot
    )

    foreach ($item in $Source) {
        $path = [System.IO.Path]::GetFullPath((Join-Path $Root ([string]$item.Path)))
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
        Assert-PhysicalDescendant -Root $Root -Path $path
        $bytes = [System.IO.File]::ReadAllBytes($path)
        if ($bytes.Length -ne [long]$item.Bytes -or
            (Get-Sha256Hex -Bytes $bytes) -ne [string]$item.Sha256) {
            return $false
        }
    }

    $expectedOverflow = [string[]]@(
        $Source | Where-Object Kind -eq 'LearningOverflow' | ForEach-Object { [string]$_.Path }
    )
    [Array]::Sort($expectedOverflow, [System.StringComparer]::Ordinal)
    $actualOverflow = [string[]]@(if (Test-Path -LiteralPath $OverflowRoot -PathType Container) {
            Get-ChildItem -LiteralPath $OverflowRoot -File -Filter '*.md' | ForEach-Object {
                Assert-PhysicalDescendant -Root $OverflowRoot -Path $_.FullName
                Get-RelativeSourcePath -Root $Root -Path $_.FullName
            }
        })
    [Array]::Sort($actualOverflow, [System.StringComparer]::Ordinal)
    return [string]::Equals(
        ($expectedOverflow -join "`n"),
        ($actualOverflow -join "`n"),
        [System.StringComparison]::Ordinal
    )
}

function Get-SortedRequirement {
    param([string]$Token)

    if ($Token -eq '-') { return , [string[]]@() }
    $requirements = [string[]]@($Token.Split(',', [System.StringSplitOptions]::RemoveEmptyEntries))
    if ($requirements.Count -eq 0) { throw 'Requirement provenance token is empty.' }
    foreach ($requirement in $requirements) {
        if ($requirement -notmatch '^REQ-[1-9][0-9]*$') {
            throw "Invalid requirement provenance '$requirement'."
        }
    }
    $unique = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($requirement in $requirements) {
        if (-not $unique.Add($requirement)) { throw "Duplicate requirement provenance '$requirement'." }
    }
    $sorted = [string[]]@($unique)
    [Array]::Sort($sorted, [System.StringComparer]::Ordinal)
    if (($sorted -join ',') -ne $Token) {
        throw "Requirement provenance '$Token' is not in canonical ordinal order."
    }
    return , $sorted
}

function ConvertFrom-WorkflowNote {
    param(
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][string]$Line,
        [Parameter(Mandatory)][int]$SourcePhase,
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][string]$RepoIdentity,
        [Parameter(Mandatory)][string]$PlanId,
        [Parameter(Mandatory)][string[]]$KnownRequirement
    )

    $common = '\[concern:(?<concern>security|correctness-reliability|architecture-patterns|performance|testing-evidence|maintainability-consistency|operability-observability)\] \[req:(?<req>-|REQ-[1-9][0-9]*(?:,REQ-[1-9][0-9]*)*)\] \[review:(?<review>cr|dr|none)\] \[source-record:(?<record>[0-9a-f]{64})\] (?<body>.+)$'
    $pattern = switch ($Kind) {
        'CrLog' { '^- \[(?<step>-|[0-9]+\.[0-9]+[a-z]?)\] \[src:(?<src>code-review|discovery|note)\] \[sev:(?<sev>Critical|High|Med|Low)\] ' + $common }
        'Learnings' { '^- \[(?<step>-|[0-9]+\.[0-9]+[a-z]?)\] \[trigger:(?<trigger>rework>1|plan-contradiction|reusable-pattern)\] ' + $common }
        'Capture' { '^- \[(?<step>-|[0-9]+\.[0-9]+[a-z]?)\](?: \[src:(?<src>code-review|discovery|note)\])?(?: \[sev:(?<sev>Critical|High|Med|Low)\])? ' + $common }
        default { throw "Unknown workflow-note kind '$Kind'." }
    }
    $match = [regex]::Match($Line, $pattern)
    if (-not $match.Success) {
        throw "Malformed typed $Kind record in '$RelativePath'."
    }

    $step = $match.Groups['step'].Value
    if ($step -ne '-' -and [int]($step.Split('.')[0]) -ne $SourcePhase) {
        throw "Workflow-note step '$step' disagrees with phase '$SourcePhase' in '$RelativePath'."
    }
    $requirements = Get-SortedRequirement -Token $match.Groups['req'].Value
    foreach ($requirement in $requirements) {
        if ($KnownRequirement -notcontains $requirement) {
            throw "Workflow-note requirement '$requirement' does not belong to plan '$PlanId'."
        }
    }

    $reviewType = $match.Groups['review'].Value
    if ($Kind -eq 'CrLog' -and $reviewType -eq 'none') {
        throw "CrLog record '$($match.Groups['record'].Value)' has no review provenance."
    }
    $source = if ($match.Groups['src'].Success) { $match.Groups['src'].Value } else { '-' }
    $severity = if ($match.Groups['sev'].Success) { $match.Groups['sev'].Value } else { '-' }
    $trigger = if ($match.Groups['trigger'].Success) { $match.Groups['trigger'].Value } else { '-' }
    $requirementToken = if ($requirements.Count -eq 0) { '-' } else { $requirements -join ',' }
    $expectedWorkflowId = Get-DomainSeparatedId `
        -Domain "workflow-note/$($Kind.ToLowerInvariant())/source-record/v1" `
        -Field @(
        $PlanId,
        [string]$SourcePhase,
        $step,
        $match.Groups['concern'].Value,
        $requirementToken,
        $reviewType,
        $source,
        $severity,
        $trigger,
        $match.Groups['body'].Value
    )
    if ($expectedWorkflowId -ne $match.Groups['record'].Value) {
        throw "Workflow-note source-record digest mismatch in '$RelativePath'."
    }

    $lineBytes = [System.Text.Encoding]::UTF8.GetBytes($Line)
    if ($lineBytes.Length -gt $maxSourceRecordBytes) {
        throw "capacity-blocked: source record in '$RelativePath' exceeds 16 KiB."
    }
    $harvestId = Get-DomainSeparatedId -Domain 'phase-harvest/source-record/v1' -Field @(
        $RepoIdentity,
        $PlanId,
        [string]$SourcePhase,
        $Kind.ToLowerInvariant(),
        $reviewType,
        $RelativePath,
        [Convert]::ToBase64String($lineBytes)
    )
    $mapReview = if ($reviewType -eq 'dr') { 'dr' } else { 'cr' }
    $concern = $match.Groups['concern'].Value
    $tags = [System.Collections.Generic.List[string]]::new()
    $tags.Add("phase-$SourcePhase")
    $tags.Add($concern)
    foreach ($requirement in $requirements) { $tags.Add($requirement.ToLowerInvariant()) }
    $sortedTags = [string[]]@($tags | Select-Object -Unique)
    [Array]::Sort($sortedTags, [System.StringComparer]::Ordinal)

    return [pscustomobject][ordered]@{
        SourceRecord = $Line
        SourceId = $harvestId
        WorkflowSourceRecordId = $match.Groups['record'].Value
        SourceKind = $Kind
        SourcePath = $RelativePath
        SourceBytesSha256 = Get-Sha256Hex -Bytes $lineBytes
        ReviewType = $reviewType
        Concern = $concern
        Requirements = $requirements
        Category = $categoryMap[$concern][$mapReview]
        Severity = if ($severity -eq '-') { 'Med' } else { $severity }
        Entry = ConvertTo-SafeLedgerText -Text $match.Groups['body'].Value -MaxLength 220
        Tags = $sortedTags
    }
}

function ConvertFrom-PhaseSectionBytes {
    param(
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][byte[]]$Bytes,
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][int]$TargetPhase,
        [Parameter(Mandatory)][string]$RepoIdentity,
        [Parameter(Mandatory)][string]$PlanId,
        [Parameter(Mandatory)][string[]]$KnownRequirement
    )

    if ($Bytes.Length -gt 4MB) {
        throw "capacity-blocked: workflow log '$RelativePath' exceeds 4 MiB."
    }
    $text = [System.Text.UTF8Encoding]::new($false, $true).GetString($Bytes) -replace "`r`n", "`n"
    $lines = @($text.TrimEnd("`n").Split("`n"))
    $header = $kindConfig[$Kind].Header
    $ranges = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -ne $header) { continue }
        # Planning capture predates executable phases and legitimately uses Phase: 0.
        # Other logs may carry their generated empty Phase 0 placeholders, but not records.
        if (($i + 1) -ge $lines.Count -or $lines[$i + 1] -notmatch '^\s*Phase:\s*(?<phase>0|[1-9][0-9]*)\s*$') {
            throw "Malformed phase header after '$header' in '$RelativePath'."
        }
        $sectionPhase = [int]$Matches.phase
        $end = $lines.Count
        for ($j = $i + 2; $j -lt $lines.Count; $j++) {
            if ($lines[$j] -match '^##\s') { $end = $j; break }
        }
        if ($sectionPhase -eq 0 -and $Kind -ne 'Capture') {
            $phaseZeroContent = @(
                for ($j = $i + 2; $j -lt $end; $j++) {
                    if (-not [string]::IsNullOrWhiteSpace($lines[$j]) -and
                        $lines[$j].Trim() -ne $placeholder) {
                        $lines[$j]
                    }
                }
            )
            if ($phaseZeroContent.Count -gt 0) {
                throw "Phase 0 records are valid only for planning Capture in '$RelativePath'."
            }
        }
        if ($sectionPhase -eq $TargetPhase) { $ranges.Add([pscustomobject]@{ Start = $i + 2; End = $end }) }
    }
    if ($ranges.Count -ne 1) {
        throw "Expected exactly one '$header' section for phase $TargetPhase in '$RelativePath'; found $($ranges.Count)."
    }

    $records = [System.Collections.Generic.List[object]]::new()
    $sawPlaceholder = $false
    for ($i = $ranges[0].Start; $i -lt $ranges[0].End; $i++) {
        $line = $lines[$i]
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line.Trim() -eq $placeholder) {
            $sawPlaceholder = $true
            continue
        }
        if ($line -notmatch '^\s*-\s') {
            throw "Malformed content in phase $TargetPhase section of '$RelativePath'."
        }
        $records.Add((ConvertFrom-WorkflowNote -Kind $Kind -Line $line -SourcePhase $TargetPhase `
                -RelativePath $RelativePath -RepoIdentity $RepoIdentity -PlanId $PlanId `
                -KnownRequirement $KnownRequirement))
    }
    if ($sawPlaceholder -and $records.Count -gt 0) {
        throw "Phase $TargetPhase section in '$RelativePath' mixes the empty placeholder with records."
    }
    if (-not $sawPlaceholder -and $records.Count -eq 0) {
        throw "Phase $TargetPhase section in '$RelativePath' has neither records nor the empty placeholder."
    }
    if ($TargetPhase -eq 0 -and $Kind -ne 'Capture' -and $records.Count -gt 0) {
        throw "Phase 0 records are valid only for planning Capture in '$RelativePath'."
    }

    return [pscustomobject]@{
        Records = @($records)
        Source = [pscustomobject][ordered]@{
            Kind = $Kind
            Path = $RelativePath
            Sha256 = Get-Sha256Hex -Bytes $Bytes
            Bytes = $Bytes.Length
        }
    }
}

function Get-PhaseSectionRecords {
    param(
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][int]$TargetPhase,
        [Parameter(Mandatory)][string]$RepoIdentity,
        [Parameter(Mandatory)][string]$PlanId,
        [Parameter(Mandatory)][string[]]$KnownRequirement,
        [Parameter(Mandatory)][string]$Root
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing required workflow log '$Path'."
    }
    $relative = Get-RelativeSourcePath -Root $Root -Path $Path
    return ConvertFrom-PhaseSectionBytes -Kind $Kind `
        -Bytes ([System.IO.File]::ReadAllBytes($Path)) -RelativePath $relative `
        -TargetPhase $TargetPhase -RepoIdentity $RepoIdentity -PlanId $PlanId `
        -KnownRequirement $KnownRequirement
}

function ConvertFrom-OverflowBytes {
    param(
        [Parameter(Mandatory)][byte[]]$Bytes,
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][int]$TargetPhase,
        [Parameter(Mandatory)][string]$RepoIdentity,
        [Parameter(Mandatory)][string]$PlanId,
        [Parameter(Mandatory)][string[]]$KnownRequirement
    )

    if ($Bytes.Length -gt 512KB) {
        throw "capacity-blocked: overflow batch '$RelativePath' exceeds 512 KiB."
    }
    $content = [System.Text.UTF8Encoding]::new($false, $true).GetString($Bytes)
    $lines = @($content.TrimEnd("`r", "`n") -split "`r?`n")
    if ($lines.Count -lt 7 -or $lines[0] -ne '# Learning Overflow Batch' -or
        $lines[1] -ne "Schema: $overflowSchema" -or $lines[2] -ne "Plan: $PlanId" -or
        $lines[3] -notmatch '^Digest: (?<digest>[0-9a-f]{64})$' -or
        $lines[4] -notmatch '^Count: (?<count>\d+)$' -or $lines[5] -ne '') {
        throw "Malformed learning overflow batch '$RelativePath'."
    }
    $digest = [regex]::Match($lines[3], '^Digest: (?<value>[0-9a-f]{64})$').Groups['value'].Value
    $count = [int]([regex]::Match($lines[4], '^Count: (?<value>\d+)$').Groups['value'].Value)
    $recordLines = [string[]]@($lines[6..($lines.Count - 1)])
    $recordBytes = ($recordLines -join "`n") + "`n"
    $expectedDigest = Get-DomainSeparatedId -Domain $overflowSchema -Field @($PlanId, $recordBytes)
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($RelativePath)
    if ($count -ne $recordLines.Count -or $count -gt 64 -or
        $digest -ne $expectedDigest -or $baseName -ne $digest) {
        throw "Learning overflow count, digest, or filename mismatch in '$RelativePath'."
    }

    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($line in $recordLines) {
        if ($line -notmatch '^- \[(?<step>[0-9]+)\.') {
            if ($line -match '\[trigger:overflow-summary\]') {
                throw "legacy-loss: overflow batch '$RelativePath' contains a legacy summary."
            }
            throw "Overflow record in '$RelativePath' has no derivable phase."
        }
        $recordPhase = [int]$Matches.step
        if ($recordPhase -ne $TargetPhase) { continue }
        if ([System.Text.Encoding]::UTF8.GetByteCount($line) -gt $maxSourceRecordBytes) {
            throw "capacity-blocked: source record in '$RelativePath' exceeds 16 KiB."
        }
        $parsedKinds = [System.Collections.Generic.List[object]]::new()
        foreach ($candidateKind in @('CrLog', 'Learnings', 'Capture')) {
            try {
                $parsedKinds.Add((ConvertFrom-WorkflowNote -Kind $candidateKind -Line $line `
                        -SourcePhase $TargetPhase -RelativePath $RelativePath `
                        -RepoIdentity $RepoIdentity -PlanId $PlanId `
                        -KnownRequirement $KnownRequirement))
            }
            catch {
                # The source-record domain disambiguates grammars with overlapping visible tokens.
            }
        }
        if ($parsedKinds.Count -ne 1) {
            throw "Overflow record in '$RelativePath' does not resolve to exactly one typed workflow-note kind."
        }
        $records.Add($parsedKinds[0])
    }
    return [pscustomobject]@{
        Records = @($records)
        Source = [pscustomobject][ordered]@{
            Kind = 'LearningOverflow'
            Path = $RelativePath
            Sha256 = Get-Sha256Hex -Bytes $Bytes
            Bytes = $Bytes.Length
        }
    }
}

function Get-OverflowRecords {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][int]$TargetPhase,
        [Parameter(Mandatory)][string]$RepoIdentity,
        [Parameter(Mandatory)][string]$PlanId,
        [Parameter(Mandatory)][string[]]$KnownRequirement,
        [Parameter(Mandatory)][string]$RepoRootPath
    )

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        return [pscustomobject]@{ Records = @(); Sources = @() }
    }
    $records = [System.Collections.Generic.List[object]]::new()
    $sources = [System.Collections.Generic.List[object]]::new()
    foreach ($file in @(Get-ChildItem -LiteralPath $Root -File -Filter '*.md' | Sort-Object Name)) {
        Assert-PhysicalDescendant -Root $Root -Path $file.FullName
        $relative = Get-RelativeSourcePath -Root $RepoRootPath -Path $file.FullName
        $parsed = ConvertFrom-OverflowBytes -Bytes ([System.IO.File]::ReadAllBytes($file.FullName)) `
            -RelativePath $relative -TargetPhase $TargetPhase -RepoIdentity $RepoIdentity `
            -PlanId $PlanId -KnownRequirement $KnownRequirement
        $sources.Add($parsed.Source)
        foreach ($record in @($parsed.Records)) { $records.Add($record) }
    }
    return [pscustomobject]@{ Records = @($records); Sources = @($sources) }
}

function ConvertTo-CanonicalJson {
    param([Parameter(Mandatory)]$Value)

    return $Value | ConvertTo-Json -Depth 12 -Compress
}

function Assert-ExactPropertySet {
    param(
        [Parameter(Mandatory)][object]$Value,
        [Parameter(Mandatory)][string[]]$Name,
        [Parameter(Mandatory)][string]$Label
    )

    if ($null -eq $Value) { throw "$Label is missing." }
    $actual = @($Value.PSObject.Properties.Name)
    if ($actual.Count -ne $Name.Count -or
        @($Name | Where-Object { $actual -cnotcontains $_ }).Count -gt 0) {
        throw "$Label has an unexpected or incomplete property set."
    }
}

function Assert-HarvestRelativePath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][string]$Label
    )

    if ([string]::IsNullOrWhiteSpace($RelativePath) -or
        [System.IO.Path]::IsPathRooted($RelativePath) -or
        $RelativePath -match '[\x00-\x1f\\]' -or
        $RelativePath.Split('/') -contains '..') {
        throw "$Label '$RelativePath' is not a confined repository-relative path."
    }
    $fullPath = [System.IO.Path]::GetFullPath((Join-Path $Root $RelativePath))
    $rootPrefix = [System.IO.Path]::GetFullPath($Root).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    ) + [System.IO.Path]::DirectorySeparatorChar
    $comparison = if ($IsWindows) {
        [System.StringComparison]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparison]::Ordinal
    }
    if (-not $fullPath.StartsWith($rootPrefix, $comparison)) {
        throw "$Label '$RelativePath' escapes repository root."
    }
    return $fullPath
}

function Invoke-HarvestGit {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string[]]$Argument
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = 'git'
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true
    [void]$startInfo.ArgumentList.Add('-C')
    [void]$startInfo.ArgumentList.Add($Root)
    foreach ($item in $Argument) { [void]$startInfo.ArgumentList.Add($item) }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $output = [System.IO.MemoryStream]::new()
    try {
        if (-not $process.Start()) { throw 'git process did not start.' }
        $outputTask = $process.StandardOutput.BaseStream.CopyToAsync($output)
        $errorTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        [void]$outputTask.GetAwaiter().GetResult()
        $errorText = $errorTask.GetAwaiter().GetResult()
        return , [pscustomobject]@{
            ExitCode = $process.ExitCode
            Bytes = $output.ToArray()
            Error = $errorText.Trim()
        }
    }
    finally {
        $output.Dispose()
        $process.Dispose()
    }
}

function Get-HarvestGitText {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string[]]$Argument,
        [Parameter(Mandatory)][string]$Failure
    )

    $result = Invoke-HarvestGit -Root $Root -Argument $Argument
    if ($result.ExitCode -ne 0) {
        $detail = if ([string]::IsNullOrWhiteSpace($result.Error)) { '' } else { " $($result.Error)" }
        throw "$Failure$detail"
    }
    return ([System.Text.UTF8Encoding]::new($false, $true).GetString($result.Bytes)).TrimEnd(
        [char[]]@("`r", "`n")
    )
}

function Get-HarvestGitPathBlob {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Commit,
        [Parameter(Mandatory)][string]$RelativePath,
        [switch]$AllowMissing
    )

    [void](Assert-HarvestRelativePath -Root $Root -RelativePath $RelativePath -Label 'Git object path')
    $result = Invoke-HarvestGit -Root $Root -Argument @('rev-parse', '--verify', "$Commit`:$RelativePath")
    if ($result.ExitCode -ne 0) {
        if ($AllowMissing) { return $null }
        throw "Git commit '$Commit' does not contain '$RelativePath'."
    }
    return ([System.Text.UTF8Encoding]::new($false, $true).GetString($result.Bytes)).Trim()
}

function Get-HarvestGitBlobBytes {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Blob
    )

    $result = Invoke-HarvestGit -Root $Root -Argument @('cat-file', 'blob', $Blob)
    if ($result.ExitCode -ne 0) {
        throw "Git blob '$Blob' does not exist."
    }
    return , [byte[]]$result.Bytes
}

function Get-LegacyCandidateProjection {
    param([Parameter(Mandatory)]$Candidate)

    return [pscustomobject][ordered]@{
        SourceId = [string]$Candidate.SourceId
        WorkflowSourceRecordId = [string]$Candidate.WorkflowSourceRecordId
        SourceKind = [string]$Candidate.SourceKind
        SourcePath = [string]$Candidate.SourcePath
        SourceBytesSha256 = [string]$Candidate.SourceBytesSha256
        ReviewType = [string]$Candidate.ReviewType
        Concern = [string]$Candidate.Concern
        Requirements = [string[]]@($Candidate.Requirements)
        Category = [string]$Candidate.Category
        Severity = [string]$Candidate.Severity
        Entry = [string]$Candidate.Entry
        Tags = [string[]]@($Candidate.Tags)
    }
}

function Read-LegacyHarvestReceipt {
    param(
        [Parameter(Mandatory)][byte[]]$Bytes,
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$RepoIdentity,
        [Parameter(Mandatory)][string]$PlanId,
        [Parameter(Mandatory)][int]$TargetPhase
    )

    if ($Bytes.Length -gt $maxReceiptBytes) {
        throw "Legacy harvest receipt '$SourcePath' exceeds 64 KiB."
    }
    try {
        $parsed = [System.Text.UTF8Encoding]::new($false, $true).GetString($Bytes) |
            ConvertFrom-Json -Depth 12
    }
    catch {
        throw "Malformed legacy harvest receipt '$SourcePath': $($_.Exception.Message)"
    }
    Assert-ExactPropertySet -Value $parsed -Name @('schema', 'receiptId', 'payload') `
        -Label "Legacy harvest receipt '$SourcePath'"
    Assert-ExactPropertySet -Value $parsed.payload -Name @(
        'repo', 'plan', 'phase', 'status', 'ledgerSource', 'sources', 'candidates'
    ) -Label "Legacy harvest receipt payload '$SourcePath'"
    if ($parsed.schema -cne $legacyReceiptSchema -or
        [string]$parsed.receiptId -cnotmatch '^[0-9a-f]{64}$') {
        throw "Legacy harvest receipt '$SourcePath' has an unsupported schema or receipt id."
    }
    $payloadJson = ConvertTo-CanonicalJson -Value $parsed.payload
    $expectedId = Get-DomainSeparatedId -Domain $legacyReceiptSchema -Field @($payloadJson)
    if ($expectedId -cne [string]$parsed.receiptId) {
        throw "Legacy harvest receipt '$SourcePath' failed its content-address check."
    }
    if ([string]$parsed.payload.repo -cne $RepoIdentity -or
        [string]$parsed.payload.plan -cne $PlanId -or
        [string]$parsed.payload.status -cnotin @('complete', 'empty') -or
        [string]$parsed.payload.ledgerSource -cnotin @('ci', 'autopilot')) {
        throw "Legacy harvest receipt '$SourcePath' has an identity or unsupported outcome mismatch."
    }
    $legacyPhase = 0
    if (-not [int]::TryParse([string]$parsed.payload.phase, [ref]$legacyPhase) -or
        $legacyPhase -ne $TargetPhase) {
        throw "Legacy harvest receipt '$SourcePath' does not match requested phase $TargetPhase."
    }

    $sources = @($parsed.payload.sources)
    $candidates = @($parsed.payload.candidates)
    if ($sources.Count -lt 3 -or $candidates.Count -gt $maxCandidates) {
        throw "Legacy harvest receipt '$SourcePath' exceeds source or candidate bounds."
    }
    $sourcePaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $sourceKinds = @{}
    foreach ($source in $sources) {
        Assert-ExactPropertySet -Value $source -Name @('Kind', 'Path', 'Sha256', 'Bytes') `
            -Label "Legacy harvest receipt source in '$SourcePath'"
        [void](Assert-HarvestRelativePath -Root $repoRootFull -RelativePath ([string]$source.Path) `
                -Label 'Legacy harvest source')
        if ([string]$source.Kind -cnotin @('CrLog', 'Learnings', 'Capture', 'LearningOverflow') -or
            [string]$source.Sha256 -cnotmatch '^[0-9a-f]{64}$' -or [long]$source.Bytes -lt 0) {
            throw "Malformed legacy harvest receipt source in '$SourcePath'."
        }
        if (-not $sourcePaths.Add([string]$source.Path)) {
            throw "Duplicate legacy harvest receipt source '$($source.Path)' in '$SourcePath'."
        }
        $kind = [string]$source.Kind
        $sourceKinds[$kind] = 1 + [int]($sourceKinds[$kind] ?? 0)
    }
    foreach ($requiredKind in @('CrLog', 'Learnings', 'Capture')) {
        if ([int]($sourceKinds[$requiredKind] ?? 0) -ne 1) {
            throw "Legacy harvest receipt '$SourcePath' must contain exactly one $requiredKind source."
        }
    }

    $candidateIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($candidate in $candidates) {
        Assert-ExactPropertySet -Value $candidate -Name @(
            'SourceId', 'WorkflowSourceRecordId', 'SourceKind', 'SourcePath',
            'SourceBytesSha256', 'ReviewType', 'Concern', 'Requirements', 'Category',
            'Severity', 'Entry', 'Tags'
        ) -Label "Legacy harvest receipt candidate in '$SourcePath'"
        if (-not $sourcePaths.Contains([string]$candidate.SourcePath) -or
            [string]$candidate.SourceId -cnotmatch '^[0-9a-f]{64}$' -or
            [string]$candidate.WorkflowSourceRecordId -cnotmatch '^[0-9a-f]{64}$' -or
            [string]$candidate.SourceBytesSha256 -cnotmatch '^[0-9a-f]{64}$' -or
            -not $candidateIds.Add([string]$candidate.SourceId)) {
            throw "Malformed or duplicate legacy harvest receipt candidate in '$SourcePath'."
        }
    }
    if (($parsed.payload.status -ceq 'empty') -ne ($candidates.Count -eq 0)) {
        throw "Legacy harvest receipt '$SourcePath' has inconsistent candidate state."
    }
    return $parsed
}

function Get-LegacyMigrationMaterial {
    param(
        [Parameter(Mandatory)]$LegacyReceipt,
        [Parameter(Mandatory)][string]$Commit,
        [Parameter(Mandatory)][string]$ReceiptPath,
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$RepoIdentity,
        [Parameter(Mandatory)][string]$PlanId,
        [Parameter(Mandatory)][int]$TargetPhase,
        [Parameter(Mandatory)][string[]]$KnownRequirement
    )

    $pathMatch = [regex]::Match(
        $ReceiptPath,
        '^(?<plan>docs/implementation-plans/[^/]+)/(?<assets>assets/)?harvest-receipts/phase-(?<phase>[0-9]{3})\.json$'
    )
    if (-not $pathMatch.Success -or
        [int]$pathMatch.Groups['phase'].Value -ne $TargetPhase) {
        throw "Legacy harvest receipt path '$ReceiptPath' does not identify its plan and phase."
    }
    $planRoot = $pathMatch.Groups['plan'].Value
    $usesAssets = $pathMatch.Groups['assets'].Success
    $logRoot = if ($usesAssets) { "$planRoot/assets/logs" } else { $planRoot }
    $overflowRoot = if ($usesAssets) {
        "$planRoot/assets/logs/learning-overflow"
    }
    else {
        "$planRoot/learning-overflow"
    }

    $derivedSources = [System.Collections.Generic.List[object]]::new()
    $migratedCandidates = [System.Collections.Generic.List[object]]::new()
    foreach ($kind in $kindConfig.Keys) {
        $fileName = switch ($kind) {
            'CrLog' { 'cr-log.md' }
            'Learnings' { 'learnings.md' }
            'Capture' { 'capture.md' }
        }
        $sourcePath = "$logRoot/$fileName"
        $blob = Get-HarvestGitPathBlob -Root $Root -Commit $Commit -RelativePath $sourcePath
        $parsed = ConvertFrom-PhaseSectionBytes -Kind $kind `
            -Bytes (Get-HarvestGitBlobBytes -Root $Root -Blob $blob) `
            -RelativePath $sourcePath -TargetPhase $TargetPhase -RepoIdentity $RepoIdentity `
            -PlanId $PlanId -KnownRequirement $KnownRequirement
        $derivedSources.Add($parsed.Source)
        foreach ($record in @($parsed.Records)) { $migratedCandidates.Add($record) }
    }

    $overflowText = Get-HarvestGitText -Root $Root `
        -Argument @('ls-tree', '-r', '--name-only', $Commit, '--', $overflowRoot) `
        -Failure "Unable to enumerate legacy overflow sources at '$overflowRoot'."
    $overflowPaths = [string[]]@($overflowText -split '\r?\n' | Where-Object {
            if (-not $_.StartsWith("$overflowRoot/", [System.StringComparison]::Ordinal)) {
                return $false
            }
            $tail = $_.Substring($overflowRoot.Length + 1)
            return -not $tail.Contains('/') -and
                $tail.EndsWith('.md', [System.StringComparison]::OrdinalIgnoreCase)
        })
    [Array]::Sort($overflowPaths, [System.StringComparer]::Ordinal)
    foreach ($sourcePath in $overflowPaths) {
        $blob = Get-HarvestGitPathBlob -Root $Root -Commit $Commit -RelativePath $sourcePath
        $parsed = ConvertFrom-OverflowBytes `
            -Bytes (Get-HarvestGitBlobBytes -Root $Root -Blob $blob) `
            -RelativePath $sourcePath -TargetPhase $TargetPhase -RepoIdentity $RepoIdentity `
            -PlanId $PlanId -KnownRequirement $KnownRequirement
        $derivedSources.Add($parsed.Source)
        foreach ($record in @($parsed.Records)) { $migratedCandidates.Add($record) }
    }

    $duplicateIds = @($migratedCandidates | Group-Object WorkflowSourceRecordId |
        Where-Object Count -gt 1)
    if ($duplicateIds.Count -gt 0) {
        throw "Duplicate workflow source-record id '$($duplicateIds[0].Name)' across legacy sources."
    }
    if ($migratedCandidates.Count -gt $maxCandidates) {
        throw 'capacity-blocked: legacy phase harvest exceeds 64 candidates.'
    }
    $candidateBytes = [long]0
    foreach ($record in $migratedCandidates) {
        $candidateBytes += [System.Text.Encoding]::UTF8.GetByteCount([string]$record.Entry)
    }
    if ($candidateBytes -gt $maxCandidateBytes) {
        throw 'capacity-blocked: legacy phase harvest exceeds 512 KiB.'
    }

    $orderedSources = @($derivedSources | Sort-Object Path)
    $orderedCandidates = @($migratedCandidates | Sort-Object SourceId)
    $legacyCandidates = @($LegacyReceipt.payload.candidates | ForEach-Object {
            Get-LegacyCandidateProjection -Candidate $_
        })
    $derivedCandidates = @($orderedCandidates | ForEach-Object {
            Get-LegacyCandidateProjection -Candidate $_
        })
    $derivedStatus = if ($orderedCandidates.Count -eq 0) { 'empty' } else { 'complete' }
    if ($derivedStatus -cne [string]$LegacyReceipt.payload.status -or
        -not [string]::Equals(
            (ConvertTo-CanonicalJson -Value $orderedSources),
            (ConvertTo-CanonicalJson -Value @($LegacyReceipt.payload.sources)),
            [System.StringComparison]::Ordinal
        ) -or
        -not [string]::Equals(
            (ConvertTo-CanonicalJson -Value $derivedCandidates),
            (ConvertTo-CanonicalJson -Value $legacyCandidates),
            [System.StringComparison]::Ordinal
        )) {
        throw 'Legacy harvest receipt does not equal the complete immutable source re-derivation.'
    }
    foreach ($source in $orderedSources) {
        $legacySource = @($LegacyReceipt.payload.sources | Where-Object {
                [string]$_.Path -ceq [string]$source.Path
            })
        if ($legacySource.Count -ne 1 -or
            [long]$legacySource[0].Bytes -ne [long]$source.Bytes -or
            [string]$legacySource[0].Sha256 -cne [string]$source.Sha256) {
            throw "Legacy harvest source '$($source.Path)' is stale or tampered at commit '$Commit'."
        }
    }
    return , $orderedCandidates
}

function Get-LegacyReceiptIntroduction {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$ReachableFrom,
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][string]$Blob
    )

    $historyText = Get-HarvestGitText -Root $Root `
        -Argument @('rev-list', $ReachableFrom, '--', $RelativePath) `
        -Failure "Unable to inspect receipt history for '$RelativePath'."
    $introductions = [System.Collections.Generic.List[string]]::new()
    foreach ($commit in @($historyText -split '\r?\n' | Where-Object { $_ })) {
        $commitBlob = Get-HarvestGitPathBlob -Root $Root -Commit $commit `
            -RelativePath $RelativePath -AllowMissing
        if ($commitBlob -cne $Blob) { continue }
        $line = Get-HarvestGitText -Root $Root -Argument @('rev-list', '--parents', '-n', '1', $commit) `
            -Failure "Unable to inspect parents for '$commit'."
        $parents = @($line.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries) | Select-Object -Skip 1)
        $parentHasBlob = $false
        foreach ($parent in $parents) {
            if ((Get-HarvestGitPathBlob -Root $Root -Commit $parent -RelativePath $RelativePath `
                        -AllowMissing) -ceq $Blob) {
                $parentHasBlob = $true
                break
            }
        }
        if (-not $parentHasBlob) { $introductions.Add($commit) }
    }
    if ($introductions.Count -ne 1) {
        throw "Legacy receipt blob '$Blob' has ambiguous introduction history at '$RelativePath'."
    }
    return $introductions[0]
}

function Assert-LegacyReceiptReplacement {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$ReceiptPath,
        [Parameter(Mandatory)][string]$ActiveReceiptPath,
        [Parameter(Mandatory)][string]$SourceBlob,
        [Parameter(Mandatory)][string]$ExpectedText,
        [switch]$PendingWrite,
        [switch]$AllowPendingMigration
    )

    $head = Get-HarvestGitText -Root $Root -Argument @('rev-parse', '--verify', 'HEAD^{commit}') `
        -Failure 'Unable to resolve repository HEAD while validating receipt replacement.'
    $headSourceBlob = Get-HarvestGitPathBlob -Root $Root -Commit $head `
        -RelativePath $ActiveReceiptPath -AllowMissing
    if ($PendingWrite) {
        if ($headSourceBlob -cne $SourceBlob) {
            throw 'Legacy receipt changed before the migrated replacement could be written.'
        }
        return
    }

    $currentBytes = [System.IO.File]::ReadAllBytes($ReceiptPath)
    $expectedBytes = [System.Text.UTF8Encoding]::new($false).GetBytes($ExpectedText)
    if ($currentBytes.Length -ne $expectedBytes.Length -or
        [Convert]::ToBase64String($currentBytes) -cne [Convert]::ToBase64String($expectedBytes)) {
        throw "Migrated receipt '$ReceiptPath' is not the canonical tool-produced envelope."
    }

    $relativeReceiptPath = Get-RelativeSourcePath -Root $Root -Path $ReceiptPath
    $headReceiptBlob = Get-HarvestGitPathBlob -Root $Root -Commit $head `
        -RelativePath $relativeReceiptPath -AllowMissing
    if ($AllowPendingMigration -and $relativeReceiptPath -ceq $ActiveReceiptPath -and
        $headReceiptBlob -ceq $SourceBlob) {
        $status = Get-HarvestGitText -Root $Root `
            -Argument @('status', '--porcelain=v1', '--untracked-files=all', '--', $relativeReceiptPath) `
            -Failure "Unable to inspect pending migrated receipt '$relativeReceiptPath'."
        if ([string]::IsNullOrWhiteSpace($status)) {
            throw 'Pending migrated receipt is not distinguishable from its committed v1 source.'
        }
        return
    }
    if ($null -eq $headReceiptBlob) {
        throw "Migrated receipt '$relativeReceiptPath' is absent from repository HEAD."
    }
    $headReceiptBytes = Get-HarvestGitBlobBytes -Root $Root -Blob $headReceiptBlob
    if ($headReceiptBytes.Length -ne $expectedBytes.Length -or
        [Convert]::ToBase64String($headReceiptBytes) -cne [Convert]::ToBase64String($expectedBytes)) {
        throw "Migrated receipt '$relativeReceiptPath' does not match repository HEAD."
    }

    $historyPaths = [System.Collections.Generic.List[string]]::new()
    $historyPaths.Add($ActiveReceiptPath)
    if ($relativeReceiptPath -cne $ActiveReceiptPath) {
        $historyPaths.Add($relativeReceiptPath)
    }
    $arguments = [System.Collections.Generic.List[string]]::new()
    foreach ($item in @('rev-list', $head, '--')) { $arguments.Add($item) }
    foreach ($item in $historyPaths) { $arguments.Add($item) }
    $historyText = Get-HarvestGitText -Root $Root -Argument $arguments.ToArray() `
        -Failure "Unable to inspect migrated receipt history for '$relativeReceiptPath'."
    foreach ($commit in @($historyText -split '\r?\n' | Where-Object { $_ })) {
        $containsMigratedBlob = $false
        foreach ($path in $historyPaths) {
            if ((Get-HarvestGitPathBlob -Root $Root -Commit $commit -RelativePath $path `
                        -AllowMissing) -ceq $headReceiptBlob) {
                $containsMigratedBlob = $true
                break
            }
        }
        if (-not $containsMigratedBlob) {
            throw 'Migrated receipt history contains an intervening conflicting receipt.'
        }

        $line = Get-HarvestGitText -Root $Root `
            -Argument @('rev-list', '--parents', '-n', '1', $commit) `
            -Failure "Unable to inspect migrated receipt parents for '$commit'."
        $parents = @($line.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries) |
            Select-Object -Skip 1)
        if ($parents.Count -eq 1 -and
            (Get-HarvestGitPathBlob -Root $Root -Commit $parents[0] `
                -RelativePath $ActiveReceiptPath -AllowMissing) -ceq $SourceBlob) {
            return
        }
    }
    throw 'Migrated receipt is not an immediate, auditable replacement of its declared v1 source.'
}

function Get-MigrationBody {
    param([Parameter(Mandatory)]$Migration)

    $migratedAt = if ($Migration.migratedAt -is [datetime]) {
        ([datetime]$Migration.migratedAt).ToUniversalTime().ToString('o')
    }
    elseif ($Migration.migratedAt -is [datetimeoffset]) {
        ([datetimeoffset]$Migration.migratedAt).UtcDateTime.ToString('o')
    }
    else {
        [string]$Migration.migratedAt
    }
    return [pscustomobject][ordered]@{
        schema = [string]$Migration.schema
        migratedAt = $migratedAt
        tool = [string]$Migration.tool
        source = $Migration.source
        validation = $Migration.validation
    }
}

function Assert-HarvestMigration {
    param(
        [Parameter(Mandatory)]$Migration,
        [Parameter(Mandatory)]$Payload,
        [Parameter(Mandatory)][string]$ReceiptPath,
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$RepoIdentity,
        [Parameter(Mandatory)][string]$PlanId,
        [Parameter(Mandatory)][string[]]$KnownRequirement,
        [switch]$PendingWrite,
        [switch]$AllowPendingMigration
    )

    Assert-ExactPropertySet -Value $Migration -Name @(
        'schema', 'migrationId', 'migratedAt', 'tool', 'source', 'validation'
    ) -Label "Harvest receipt migration in '$ReceiptPath'"
    Assert-ExactPropertySet -Value $Migration.source -Name @(
        'schema', 'receiptId', 'sha256', 'payloadSha256', 'blob', 'commit', 'tree', 'ref', 'path'
    ) -Label "Harvest receipt migration source in '$ReceiptPath'"
    Assert-ExactPropertySet -Value $Migration.validation -Name @(
        'sourceReceipt', 'sourceCommit', 'sourceSnapshots', 'candidates', 'identity'
    ) -Label "Harvest receipt migration validation in '$ReceiptPath'"

    $migrationBody = Get-MigrationBody -Migration $Migration
    $parsedTimestamp = [datetimeoffset]::MinValue
    if ($Migration.schema -cne $migrationSchema -or
        [string]$Migration.migrationId -cnotmatch '^[0-9a-f]{64}$' -or
        -not [datetimeoffset]::TryParseExact(
            [string]$migrationBody.migratedAt,
            'o',
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::RoundtripKind,
            [ref]$parsedTimestamp
        ) -or
        $Migration.tool -cne $migrationTool) {
        throw "Harvest receipt migration in '$ReceiptPath' has invalid identity metadata."
    }
    $expectedMigrationId = Get-DomainSeparatedId -Domain $migrationSchema `
        -Field @((ConvertTo-CanonicalJson -Value $migrationBody))
    if ($expectedMigrationId -cne [string]$Migration.migrationId) {
        throw "Harvest receipt migration in '$ReceiptPath' failed its content-address check."
    }
    $expectedValidation = [ordered]@{
        sourceReceipt = 'digest-verified'
        sourceCommit = 'reachable-and-matched'
        sourceSnapshots = 'blob-verified'
        candidates = 'rederived'
        identity = 'repo-plan-phase-matched'
    }
    if ((ConvertTo-CanonicalJson -Value $Migration.validation) -cne
        (ConvertTo-CanonicalJson -Value $expectedValidation)) {
        throw "Harvest receipt migration in '$ReceiptPath' has unsupported validation results."
    }

    $relativeReceiptPath = Get-RelativeSourcePath -Root $Root -Path $ReceiptPath
    [void](Assert-HarvestRelativePath -Root $Root -RelativePath $relativeReceiptPath `
            -Label 'Migrated receipt path')
    $activeReceiptPath = if ($relativeReceiptPath.StartsWith(
            'docs/implementation-plans/archived/',
            [System.StringComparison]::Ordinal
        )) {
        'docs/implementation-plans/' + $relativeReceiptPath.Substring(
            'docs/implementation-plans/archived/'.Length
        )
    }
    else {
        $relativeReceiptPath
    }
    $source = $Migration.source
    if ($source.schema -cne $legacyReceiptSchema -or
        [string]$source.receiptId -cnotmatch '^[0-9a-f]{64}$' -or
        [string]$source.sha256 -cnotmatch '^[0-9a-f]{64}$' -or
        [string]$source.payloadSha256 -cnotmatch '^[0-9a-f]{64}$' -or
        [string]$source.blob -cnotmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$' -or
        [string]$source.commit -cnotmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$' -or
        [string]$source.tree -cnotmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$' -or
        [string]$source.ref -cnotmatch '^(?!-)[A-Za-z0-9][A-Za-z0-9._/@{}^~-]*$' -or
        [string]$source.path -cne $activeReceiptPath) {
        throw "Harvest receipt migration in '$ReceiptPath' has invalid source provenance."
    }

    $commit = Get-HarvestGitText -Root $Root `
        -Argument @('rev-parse', '--verify', "$($source.commit)^{commit}") `
        -Failure "Migrated receipt source commit '$($source.commit)' does not exist."
    if ($commit -cne [string]$source.commit) {
        throw "Migrated receipt source commit '$($source.commit)' is not canonical."
    }
    $ancestor = Invoke-HarvestGit -Root $Root -Argument @(
        'merge-base', '--is-ancestor', [string]$source.commit, 'HEAD'
    )
    if ($ancestor.ExitCode -ne 0) {
        throw "Migrated receipt source commit '$($source.commit)' is not reachable from HEAD."
    }
    $tree = Get-HarvestGitText -Root $Root -Argument @(
        'rev-parse', '--verify', "$($source.commit)^{tree}"
    ) -Failure "Migrated receipt source tree '$($source.tree)' does not exist."
    if ($tree -cne [string]$source.tree) {
        throw "Migrated receipt source tree does not match commit '$($source.commit)'."
    }
    $blob = Get-HarvestGitPathBlob -Root $Root -Commit ([string]$source.commit) `
        -RelativePath $activeReceiptPath
    if ($blob -cne [string]$source.blob) {
        throw "Migrated receipt source blob does not match '$activeReceiptPath'."
    }
    $introduction = Get-LegacyReceiptIntroduction -Root $Root -ReachableFrom 'HEAD' `
        -RelativePath $activeReceiptPath -Blob $blob
    if ($introduction -cne [string]$source.commit) {
        throw "Migrated receipt source commit is not the unique receipt-blob introduction."
    }

    $legacyBytes = Get-HarvestGitBlobBytes -Root $Root -Blob $blob
    if ((Get-Sha256Hex -Bytes $legacyBytes) -cne [string]$source.sha256) {
        throw "Migrated receipt source bytes do not match their SHA-256 binding."
    }
    $targetPhase = [int]$Payload.phase
    $legacy = Read-LegacyHarvestReceipt -Bytes $legacyBytes -SourcePath $activeReceiptPath `
        -RepoIdentity $RepoIdentity -PlanId $PlanId -TargetPhase $targetPhase
    $legacyPayloadSha = Get-Sha256Hex -Bytes ([System.Text.Encoding]::UTF8.GetBytes(
            (ConvertTo-CanonicalJson -Value $legacy.payload)
        ))
    if ($legacy.receiptId -cne [string]$source.receiptId -or
        $legacyPayloadSha -cne [string]$source.payloadSha256) {
        throw "Migrated receipt source payload does not match its provenance."
    }
    $migratedCandidates = Get-LegacyMigrationMaterial -LegacyReceipt $legacy `
        -Commit ([string]$source.commit) -ReceiptPath $activeReceiptPath `
        -Root $Root -RepoIdentity $RepoIdentity `
        -PlanId $PlanId -TargetPhase $targetPhase -KnownRequirement $KnownRequirement
    $expectedPayload = [pscustomobject][ordered]@{
        repo = [string]$legacy.payload.repo
        plan = [string]$legacy.payload.plan
        phase = [int]$legacy.payload.phase
        status = [string]$legacy.payload.status
        ledgerSource = [string]$legacy.payload.ledgerSource
        candidateFormat = 'typed-source-record/v1'
        sources = @($legacy.payload.sources)
        candidates = @($migratedCandidates)
    }
    if ((ConvertTo-CanonicalJson -Value $expectedPayload) -cne
        (ConvertTo-CanonicalJson -Value $Payload)) {
        throw "Migrated receipt payload does not equal immutable v1 re-derivation."
    }
    $normalizedMigration = [pscustomobject][ordered]@{
        schema = [string]$Migration.schema
        migrationId = [string]$Migration.migrationId
        migratedAt = [string]$migrationBody.migratedAt
        tool = [string]$Migration.tool
        source = $Migration.source
        validation = $Migration.validation
    }
    $expectedEnvelope = [pscustomobject][ordered]@{
        schema = $receiptSchema
        receiptId = Get-DomainSeparatedId -Domain $receiptSchema `
            -Field @((ConvertTo-CanonicalJson -Value $Payload))
        payload = $Payload
        migration = $normalizedMigration
    }
    Assert-LegacyReceiptReplacement -Root $Root -ReceiptPath $ReceiptPath `
        -ActiveReceiptPath $activeReceiptPath -SourceBlob $blob `
        -ExpectedText ((ConvertTo-CanonicalJson -Value $expectedEnvelope) + "`n") `
        -PendingWrite:$PendingWrite -AllowPendingMigration:$AllowPendingMigration
}

function Assert-CommittedMigrationPath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Label
    )

    $relativePath = Get-RelativeSourcePath -Root $Root -Path $Path
    [void](Assert-HarvestRelativePath -Root $Root -RelativePath $relativePath -Label $Label)
    $tracked = Invoke-HarvestGit -Root $Root -Argument @(
        'ls-files', '--full-name', '--error-unmatch', '--', $relativePath
    )
    if ($tracked.ExitCode -ne 0) {
        throw "$Label '$relativePath' is not committed."
    }
    $status = Get-HarvestGitText -Root $Root `
        -Argument @('status', '--porcelain=v1', '--untracked-files=all', '--', $relativePath) `
        -Failure "Unable to inspect $Label '$relativePath'."
    if (-not [string]::IsNullOrWhiteSpace($status)) {
        throw "$Label '$relativePath' has uncommitted changes."
    }
    return $relativePath
}

function New-LegacyReceiptMigration {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ReceiptRoot,
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$RepoIdentity,
        [Parameter(Mandatory)][string]$PlanId,
        [Parameter(Mandatory)][int]$TargetPhase,
        [Parameter(Mandatory)][string[]]$KnownRequirement,
        [Parameter(Mandatory)][string]$Ref,
        [Parameter(Mandatory)][string]$PlanPath
    )

    Assert-PhysicalDescendant -Root $ReceiptRoot -Path $Path
    $currentBytes = [System.IO.File]::ReadAllBytes($Path)
    try {
        $currentDocument = [System.Text.UTF8Encoding]::new($false, $true).GetString($currentBytes) |
            ConvertFrom-Json -Depth 12
    }
    catch {
        $currentDocument = $null
    }
    if ($null -ne $currentDocument -and
        $currentDocument.PSObject.Properties.Name -ccontains 'schema' -and
        [string]$currentDocument.schema -ceq $receiptSchema) {
        $validated = Read-HarvestReceipt -Path $Path -ReceiptRoot $ReceiptRoot -Root $Root `
            -RepoIdentity $RepoIdentity -PlanId $PlanId -KnownRequirement $KnownRequirement `
            -AllowPendingMigration
        if ([int]$validated.payload.phase -ne $TargetPhase) {
            throw "Existing migrated receipt '$Path' does not match requested phase $TargetPhase."
        }
        if ($validated.PSObject.Properties.Name -cnotcontains 'migration') {
            throw "Refusing to replace an existing native v2 receipt '$Path'."
        }
        return [pscustomobject]@{
            Text = [System.Text.UTF8Encoding]::new($false, $true).GetString($currentBytes)
            AlreadyMigrated = $true
            Receipt = $validated
        }
    }

    $relativeReceiptPath = Assert-CommittedMigrationPath -Root $Root -Path $Path `
        -Label 'Legacy harvest receipt'
    [void](Assert-CommittedMigrationPath -Root $Root -Path $PlanPath -Label 'Plan file')
    $head = Get-HarvestGitText -Root $Root -Argument @('rev-parse', '--verify', 'HEAD^{commit}') `
        -Failure 'Unable to resolve repository HEAD.'
    $resolvedRef = Get-HarvestGitText -Root $Root `
        -Argument @('rev-parse', '--verify', "$Ref^{commit}") `
        -Failure "Legacy receipt source ref '$Ref' does not resolve to a commit."
    if ($resolvedRef -cne $head) {
        throw "Legacy receipt source ref '$Ref' must resolve to current HEAD '$head'."
    }
    $headBlob = Get-HarvestGitPathBlob -Root $Root -Commit $resolvedRef `
        -RelativePath $relativeReceiptPath
    $headBytes = Get-HarvestGitBlobBytes -Root $Root -Blob $headBlob
    if ($currentBytes.Length -ne $headBytes.Length -or
        (Get-Sha256Hex -Bytes $currentBytes) -cne (Get-Sha256Hex -Bytes $headBytes)) {
        throw "Legacy harvest receipt '$relativeReceiptPath' does not match committed source ref '$Ref'."
    }

    $sourceCommit = Get-LegacyReceiptIntroduction -Root $Root -ReachableFrom $resolvedRef `
        -RelativePath $relativeReceiptPath -Blob $headBlob
    $sourceBytes = Get-HarvestGitBlobBytes -Root $Root -Blob $headBlob
    $legacy = Read-LegacyHarvestReceipt -Bytes $sourceBytes -SourcePath $relativeReceiptPath `
        -RepoIdentity $RepoIdentity -PlanId $PlanId -TargetPhase $TargetPhase
    foreach ($source in @($legacy.payload.sources)) {
        $sourceFullPath = Assert-HarvestRelativePath -Root $Root `
            -RelativePath ([string]$source.Path) -Label 'Legacy harvest source'
        [void](Assert-CommittedMigrationPath -Root $Root -Path $sourceFullPath `
                -Label 'Legacy harvest source')
    }
    $migratedCandidates = Get-LegacyMigrationMaterial -LegacyReceipt $legacy `
        -Commit $sourceCommit -ReceiptPath $relativeReceiptPath -Root $Root `
        -RepoIdentity $RepoIdentity -PlanId $PlanId `
        -TargetPhase $TargetPhase -KnownRequirement $KnownRequirement
    $v2 = New-HarvestReceipt -RepoIdentity $RepoIdentity -PlanId $PlanId `
        -TargetPhase $TargetPhase -Status ([string]$legacy.payload.status) `
        -Sources @($legacy.payload.sources) -Candidates @($migratedCandidates) `
        -LedgerSource ([string]$legacy.payload.ledgerSource)
    $tree = Get-HarvestGitText -Root $Root `
        -Argument @('rev-parse', '--verify', "$sourceCommit^{tree}") `
        -Failure "Unable to resolve tree for legacy receipt source commit '$sourceCommit'."
    $migrationBody = [pscustomobject][ordered]@{
        schema = $migrationSchema
        migratedAt = [DateTime]::UtcNow.ToString('o')
        tool = $migrationTool
        source = [pscustomobject][ordered]@{
            schema = $legacyReceiptSchema
            receiptId = [string]$legacy.receiptId
            sha256 = Get-Sha256Hex -Bytes $sourceBytes
            payloadSha256 = Get-Sha256Hex -Bytes ([System.Text.Encoding]::UTF8.GetBytes(
                    (ConvertTo-CanonicalJson -Value $legacy.payload)
                ))
            blob = $headBlob
            commit = $sourceCommit
            tree = $tree
            ref = $Ref
            path = $relativeReceiptPath
        }
        validation = [pscustomobject][ordered]@{
            sourceReceipt = 'digest-verified'
            sourceCommit = 'reachable-and-matched'
            sourceSnapshots = 'blob-verified'
            candidates = 'rederived'
            identity = 'repo-plan-phase-matched'
        }
    }
    $migration = [pscustomobject][ordered]@{
        schema = $migrationBody.schema
        migrationId = Get-DomainSeparatedId -Domain $migrationSchema `
            -Field @((ConvertTo-CanonicalJson -Value $migrationBody))
        migratedAt = $migrationBody.migratedAt
        tool = $migrationBody.tool
        source = $migrationBody.source
        validation = $migrationBody.validation
    }
    $envelope = [pscustomobject][ordered]@{
        schema = $receiptSchema
        receiptId = $v2.Id
        payload = $v2.Payload
        migration = $migration
    }
    Assert-HarvestMigration -Migration $migration -Payload $v2.Payload -ReceiptPath $Path `
        -Root $Root -RepoIdentity $RepoIdentity -PlanId $PlanId `
        -KnownRequirement $KnownRequirement -PendingWrite
    return [pscustomobject]@{
        Text = (ConvertTo-CanonicalJson -Value $envelope) + "`n"
        AlreadyMigrated = $false
        Receipt = $envelope
    }
}

function New-HarvestReceipt {
    param(
        [Parameter(Mandatory)][string]$RepoIdentity,
        [Parameter(Mandatory)][string]$PlanId,
        [Parameter(Mandatory)][int]$TargetPhase,
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)][object[]]$Sources,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Candidates,
        [Parameter(Mandatory)][string]$LedgerSource
    )

    $payload = [pscustomobject][ordered]@{
        repo = $RepoIdentity
        plan = $PlanId
        phase = $TargetPhase
        status = $Status
        ledgerSource = $LedgerSource
        candidateFormat = 'typed-source-record/v1'
        sources = $Sources
        candidates = $Candidates
    }
    $payloadJson = ConvertTo-CanonicalJson -Value $payload
    $receiptId = Get-DomainSeparatedId -Domain $receiptSchema -Field @($payloadJson)
    $envelope = [pscustomobject][ordered]@{
        schema = $receiptSchema
        receiptId = $receiptId
        payload = $payload
    }
    return [pscustomobject]@{
        Id = $receiptId
        Payload = $payload
        Text = (ConvertTo-CanonicalJson -Value $envelope) + "`n"
    }
}

function Read-HarvestReceipt {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ReceiptRoot,
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$RepoIdentity,
        [Parameter(Mandatory)][string]$PlanId,
        [Parameter(Mandatory)][string[]]$KnownRequirement,
        [switch]$AllowPendingMigration
    )

    Assert-PhysicalDescendant -Root $ReceiptRoot -Path $Path
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -gt $maxReceiptBytes) { throw "Harvest receipt '$Path' exceeds 64 KiB." }
    $parsed = [System.Text.UTF8Encoding]::new($false, $true).GetString($bytes) | ConvertFrom-Json -Depth 12
    $envelopeProperties = @($parsed.PSObject.Properties.Name)
    $hasMigration = $envelopeProperties -ccontains 'migration'
    $expectedEnvelopeProperties = if ($hasMigration) {
        @('schema', 'receiptId', 'payload', 'migration')
    }
    else {
        @('schema', 'receiptId', 'payload')
    }
    if ($envelopeProperties.Count -ne $expectedEnvelopeProperties.Count -or
        @($expectedEnvelopeProperties |
                Where-Object { $envelopeProperties -cnotcontains $_ }).Count -gt 0 -or
        $parsed.schema -cne $receiptSchema -or $parsed.receiptId -cnotmatch '^[0-9a-f]{64}$') {
        throw "Malformed harvest receipt '$Path'."
    }
    $payloadProperties = @($parsed.payload.PSObject.Properties.Name)
    if ($payloadProperties.Count -ne 8 -or
        @('repo', 'plan', 'phase', 'status', 'ledgerSource', 'candidateFormat', 'sources', 'candidates' |
            Where-Object { $payloadProperties -notcontains $_ }).Count -gt 0) {
        throw "Malformed harvest receipt payload '$Path'."
    }
    $payloadJson = ConvertTo-CanonicalJson -Value $parsed.payload
    $expectedId = Get-DomainSeparatedId -Domain $receiptSchema -Field @($payloadJson)
    if ($expectedId -ne $parsed.receiptId -or $parsed.payload.repo -ne $RepoIdentity -or
        $parsed.payload.plan -ne $PlanId -or $parsed.payload.status -notin @('complete', 'empty') -or
        $parsed.payload.candidateFormat -ne 'typed-source-record/v1' -or
        $parsed.payload.ledgerSource -notin @('ci', 'autopilot')) {
        throw "Harvest receipt identity or digest mismatch '$Path'."
    }

    $phaseNumber = 0
    if (-not [int]::TryParse([string]$parsed.payload.phase, [ref]$phaseNumber) -or
        $phaseNumber -lt 0 -or $phaseNumber -gt 999) {
        throw "Harvest receipt '$Path' has an invalid phase."
    }
    $sources = @($parsed.payload.sources)
    $candidates = @($parsed.payload.candidates)
    if ($sources.Count -lt 3 -or $candidates.Count -gt $maxCandidates) {
        throw "Harvest receipt '$Path' exceeds source or candidate bounds."
    }
    $sourcePaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $sourceKinds = @{}
    foreach ($source in $sources) {
        $sourceProperties = @($source.PSObject.Properties.Name)
        if ($sourceProperties.Count -ne 4 -or
            @('Kind', 'Path', 'Sha256', 'Bytes' | Where-Object { $sourceProperties -notcontains $_ }).Count -gt 0 -or
            $source.Kind -notin @('CrLog', 'Learnings', 'Capture', 'LearningOverflow') -or
            [string]::IsNullOrWhiteSpace([string]$source.Path) -or
            [System.IO.Path]::IsPathRooted([string]$source.Path) -or
            ([string]$source.Path).Split('/') -contains '..' -or
            $source.Sha256 -notmatch '^[0-9a-f]{64}$' -or [long]$source.Bytes -lt 0) {
            throw "Malformed harvest receipt source in '$Path'."
        }
        if (-not $sourcePaths.Add([string]$source.Path)) {
            throw "Duplicate harvest receipt source '$($source.Path)' in '$Path'."
        }
        $sourceKind = [string]$source.Kind
        $sourceKinds[$sourceKind] = 1 + [int]($sourceKinds[$sourceKind] ?? 0)
    }
    foreach ($requiredKind in @('CrLog', 'Learnings', 'Capture')) {
        if ([int]($sourceKinds[$requiredKind] ?? 0) -ne 1) {
            throw "Harvest receipt '$Path' must contain exactly one $requiredKind source."
        }
    }

    $candidateBytes = [long]0
    foreach ($candidate in $candidates) {
        $candidateProperties = @($candidate.PSObject.Properties.Name)
        $requiredCandidateProperties = @(
            'SourceRecord', 'SourceId', 'WorkflowSourceRecordId', 'SourceKind', 'SourcePath',
            'SourceBytesSha256', 'ReviewType', 'Concern', 'Requirements', 'Category',
            'Severity', 'Entry', 'Tags'
        )
        if ($candidateProperties.Count -ne $requiredCandidateProperties.Count -or
            @($requiredCandidateProperties | Where-Object { $candidateProperties -notcontains $_ }).Count -gt 0 -or
            -not $sourcePaths.Contains([string]$candidate.SourcePath)) {
            throw "Malformed harvest receipt candidate in '$Path'."
        }
        $derived = ConvertFrom-WorkflowNote -Kind ([string]$candidate.SourceKind) `
            -Line ([string]$candidate.SourceRecord) -SourcePhase $phaseNumber `
            -RelativePath ([string]$candidate.SourcePath) -RepoIdentity $RepoIdentity `
            -PlanId $PlanId -KnownRequirement $KnownRequirement
        if (-not [string]::Equals(
                (ConvertTo-CanonicalJson -Value $derived),
                (ConvertTo-CanonicalJson -Value $candidate),
                [System.StringComparison]::Ordinal
            )) {
            throw "Harvest receipt candidate derivation mismatch in '$Path'."
        }
        $candidateBytes += [System.Text.Encoding]::UTF8.GetByteCount([string]$candidate.Entry)
    }
    if ($candidateBytes -gt $maxCandidateBytes -or
        ($parsed.payload.status -eq 'empty') -ne ($candidates.Count -eq 0)) {
        throw "Harvest receipt '$Path' has inconsistent candidate state."
    }
    if ($hasMigration) {
        Assert-HarvestMigration -Migration $parsed.migration -Payload $parsed.payload `
            -ReceiptPath $Path -Root $Root -RepoIdentity $RepoIdentity -PlanId $PlanId `
            -KnownRequirement $KnownRequirement -AllowPendingMigration:$AllowPendingMigration
    }
    return $parsed
}

function ConvertTo-LedgerInputs {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Candidate,
        [Parameter(Mandatory)][string]$PlanId,
        [Parameter(Mandatory)][string]$LedgerSource
    )

    return , @($Candidate | ForEach-Object {
            [pscustomobject]@{
                Category = [string]$_.Category
                Plan = $PlanId
                Src = $LedgerSource
                Severity = [string]$_.Severity
                Entry = [string]$_.Entry
                Tags = [string[]]@($_.Tags)
                SourceId = [string]$_.SourceId
            }
        })
}

function Invoke-ReceiptReplay {
    param(
        [Parameter(Mandatory)][object[]]$Receipt,
        [Parameter(Mandatory)][string]$PlanId,
        [Parameter(Mandatory)][string]$Root
    )

    $inputs = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $Receipt) {
        foreach ($candidate in @($item.payload.candidates)) {
            $inputs.Add([pscustomobject]@{
                    Category = [string]$candidate.Category
                    Plan = $PlanId
                    Src = [string]$item.payload.ledgerSource
                    Severity = [string]$candidate.Severity
                    Entry = [string]$candidate.Entry
                    Tags = [string[]]@($candidate.Tags)
                    SourceId = [string]$candidate.SourceId
                })
        }
    }
    return Invoke-LedgerBatch -Entry @($inputs) -RepoRoot $Root
}

function Write-HarvestResult {
    param(
        [Parameter(Mandatory)][string]$Status,
        [int]$TargetPhase,
        [int]$CandidateCount,
        [int]$ReceiptCount,
        [int]$Added,
        [int]$Duplicate,
        [string]$ReceiptPath,
        [string]$Note
    )

    Write-Output ([pscustomobject][ordered]@{
            Status = $Status
            Plan = $planId
            Phase = if ($TargetPhase -gt 0) { $TargetPhase } else { $null }
            Candidates = $CandidateCount
            Receipts = $ReceiptCount
            Added = $Added
            Duplicate = $Duplicate
            ReceiptPath = $ReceiptPath
            Note = $Note
        })
}

$planDirFull = [System.IO.Path]::GetFullPath($PlanDir)
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $cursor = [System.IO.DirectoryInfo]::new($planDirFull)
    while ($null -ne $cursor) {
        if ($cursor.Name -eq 'implementation-plans' -and $null -ne $cursor.Parent -and
            $cursor.Parent.Name -eq 'docs' -and $null -ne $cursor.Parent.Parent) {
            $RepoRoot = $cursor.Parent.Parent.FullName
            break
        }
        $cursor = $cursor.Parent
    }
    if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
        throw "Cannot derive repository root from plan folder '$planDirFull'; pass -RepoRoot."
    }
}
$repoRootFull = [System.IO.Path]::GetFullPath($RepoRoot)
$inventory = @(Get-PlanInventory -RepoRoot $repoRootFull)
$planRecord = @($inventory | Where-Object {
        $_.Path -and [string]::Equals(
            [System.IO.Path]::GetFullPath([string]$_.Path),
            $planDirFull,
            [System.StringComparison]::OrdinalIgnoreCase
        )
    })
if ($planRecord.Count -ne 1) {
    throw "Plan folder '$planDirFull' is not a unique member of the repository plan inventory."
}
$planId = [string]$planRecord[0].Id
$repoIdentity = Get-RepoIdentity -Root $repoRootFull
$receiptRoot = Resolve-PlanAssetPath -PlanDir $planDirFull -Kind HarvestReceiptRoot `
    -RepoRoot $repoRootFull -Inventory $inventory
$metadata = Get-PlanMetadata -Path (Join-Path $planDirFull 'plan.md') -RepoRoot $repoRootFull
$knownRequirements = [string[]]@($metadata.Requirements.Values | ForEach-Object { [string]$_.Id })
$normalizedHarvestLock = Resolve-PhysicalRepoPath -Path $planDirFull
if ($IsWindows) { $normalizedHarvestLock = $normalizedHarvestLock.ToLowerInvariant() }

try {
    if ([string]::IsNullOrWhiteSpace($planId)) {
        throw "Plan '$($metadata.PlanPath)' has no canonical plan-id marker."
    }
    if ($MigrateLegacyReceipt) {
        $receiptPath = Join-Path $receiptRoot ('phase-{0:D3}.json' -f $Phase)
        if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) {
            throw "Legacy harvest receipt '$receiptPath' does not exist."
        }
        $migration = Invoke-WithAtomicStoreLock -Scope $normalizedHarvestLock `
            -TimeoutSeconds 30 -Action {
            $generation = Get-AtomicStoreGeneration -Path $receiptPath
            $result = New-LegacyReceiptMigration -Path $receiptPath -ReceiptRoot $receiptRoot `
                -Root $repoRootFull -RepoIdentity $repoIdentity -PlanId $planId `
                -TargetPhase $Phase -KnownRequirement $knownRequirements -Ref $SourceRef `
                -PlanPath $metadata.PlanPath
            if (-not $result.AlreadyMigrated) {
                if ([System.Text.Encoding]::UTF8.GetByteCount($result.Text) -gt $maxReceiptBytes) {
                    throw 'capacity-blocked: migrated phase harvest receipt exceeds 64 KiB.'
                }
                $write = Set-AtomicStoreContent -Path $receiptPath -Content $result.Text `
                    -ExpectedGeneration $generation
                if ($write.Status -ne 'complete') {
                    throw "Phase receipt migration failed with status '$($write.Status)'."
                }
            }
            return $result
        }
        Write-HarvestResult -Status migrated -TargetPhase $Phase `
            -CandidateCount @($migration.Receipt.payload.candidates).Count -ReceiptCount 1 `
            -ReceiptPath $receiptPath -Note $(if ($migration.AlreadyMigrated) {
                'Validated identical existing migrated legacy receipt; content unchanged.'
            }
            else {
                'Migrated committed legacy receipt without phase replay.'
            })
        exit 0
    }
    if ($ValidateReceipt) {
        $receiptPath = Join-Path $receiptRoot ('phase-{0:D3}.json' -f $Phase)
        if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) {
            throw "Harvest receipt '$receiptPath' does not exist."
        }
        $receipt = Read-HarvestReceipt -Path $receiptPath -ReceiptRoot $receiptRoot -Root $repoRootFull `
            -RepoIdentity $repoIdentity -PlanId $planId -KnownRequirement $knownRequirements
        if ([int]$receipt.payload.phase -ne $Phase) {
            throw "Harvest receipt '$receiptPath' phase does not match requested phase $Phase."
        }
        Write-HarvestResult -Status $receipt.payload.status -TargetPhase $Phase `
            -CandidateCount @($receipt.payload.candidates).Count -ReceiptCount 1 `
            -ReceiptPath $receiptPath -Note 'Validated immutable phase receipt.'
        exit 0
    }

    if ($FinalSweep) {
        $receiptFiles = @(if (Test-Path -LiteralPath $receiptRoot -PathType Container) {
                Get-ChildItem -LiteralPath $receiptRoot -File -Filter 'phase-*.json' | Sort-Object Name
            })
        if ($receiptFiles.Count -gt $maxReceipts) {
            throw 'capacity-blocked: active phase receipt ceiling exceeded.'
        }
        $receipts = @($receiptFiles | ForEach-Object {
                Read-HarvestReceipt -Path $_.FullName -ReceiptRoot $receiptRoot -Root $repoRootFull `
                    -RepoIdentity $repoIdentity -PlanId $planId -KnownRequirement $knownRequirements
            })
        if ($receipts.Count -eq 0) {
            Write-HarvestResult -Status empty -ReceiptCount 0 -Note 'No active phase receipts to replay.'
            exit 0
        }
        $ledger = Invoke-ReceiptReplay -Receipt $receipts -PlanId $planId -Root $repoRootFull
        if ($ledger.Status -eq 'capacity-blocked') {
            Write-HarvestResult -Status capacity-blocked -ReceiptCount $receipts.Count -Note $ledger.Reason
            exit 4
        }
        if ($ledger.Status -ne 'complete') {
            Write-HarvestResult -Status degraded -ReceiptCount $receipts.Count -Note "Ledger replay failed with status '$($ledger.Status)'."
            exit 3
        }
        $candidateCount = @($receipts | ForEach-Object { $_.payload.candidates }).Count
        Write-HarvestResult -Status complete -CandidateCount $candidateCount -ReceiptCount $receipts.Count `
            -Added $ledger.Added -Duplicate $ledger.Duplicate
        exit 0
    }

    $receiptPath = Join-Path $receiptRoot ('phase-{0:D3}.json' -f $Phase)
    $existingReceipts = @(if (Test-Path -LiteralPath $receiptRoot -PathType Container) {
            Get-ChildItem -LiteralPath $receiptRoot -File -Filter 'phase-*.json'
        })
    if (Test-Path -LiteralPath $receiptPath -PathType Leaf) {
        $replay = Invoke-WithAtomicStoreLock -Scope $normalizedHarvestLock -TimeoutSeconds 30 -Action {
            $receiptCount = @(Get-ChildItem -LiteralPath $receiptRoot -File -Filter 'phase-*.json').Count
            if ($receiptCount -gt $maxReceipts) {
                return [pscustomobject]@{
                    Status = 'capacity-blocked'
                    ReceiptCount = $receiptCount
                    Reason = 'Active phase receipt ceiling exceeded before ledger mutation.'
                }
            }
            $receipt = Read-HarvestReceipt -Path $receiptPath -ReceiptRoot $receiptRoot -Root $repoRootFull `
                -RepoIdentity $repoIdentity -PlanId $planId -KnownRequirement $knownRequirements
            if ([int]$receipt.payload.phase -ne $Phase) {
                throw "Harvest receipt '$receiptPath' phase does not match requested phase $Phase."
            }
            $ledgerResult = Invoke-ReceiptReplay -Receipt @($receipt) -PlanId $planId -Root $repoRootFull
            return [pscustomobject]@{
                Status = $ledgerResult.Status
                ReceiptCount = $receiptCount
                Receipt = $receipt
                Ledger = $ledgerResult
                Reason = if ($ledgerResult.PSObject.Properties.Name -contains 'Reason') { $ledgerResult.Reason } else { '' }
            }
        }
        if ($replay.Status -eq 'capacity-blocked') {
            Write-HarvestResult -Status capacity-blocked -TargetPhase $Phase `
                -ReceiptCount $replay.ReceiptCount -ReceiptPath $receiptPath -Note $replay.Reason
            exit 4
        }
        $receipt = $replay.Receipt
        $ledger = $replay.Ledger
        if ($ledger.Status -eq 'capacity-blocked') {
            Write-HarvestResult -Status capacity-blocked -TargetPhase $Phase `
                -CandidateCount @($receipt.payload.candidates).Count -ReceiptCount 1 `
                -ReceiptPath $receiptPath -Note $ledger.Reason
            exit 4
        }
        if ($ledger.Status -ne 'complete') {
            Write-HarvestResult -Status degraded -TargetPhase $Phase `
                -CandidateCount @($receipt.payload.candidates).Count -ReceiptCount 1 `
                -ReceiptPath $receiptPath -Note "Ledger replay failed with status '$($ledger.Status)'."
            exit 3
        }
        Write-HarvestResult -Status $receipt.payload.status -TargetPhase $Phase `
            -CandidateCount @($receipt.payload.candidates).Count -ReceiptCount 1 `
            -Added $ledger.Added -Duplicate $ledger.Duplicate -ReceiptPath $receiptPath `
            -Note 'Replayed immutable phase receipt.'
        exit 0
    }

    if ($existingReceipts.Count -ge $maxReceipts) {
        Write-HarvestResult -Status capacity-blocked -TargetPhase $Phase -ReceiptCount $existingReceipts.Count `
            -Note 'Active phase receipt ceiling of 64 reached before ledger mutation.'
        exit 4
    }

    $allRecords = [System.Collections.Generic.List[object]]::new()
    $allSources = [System.Collections.Generic.List[object]]::new()
    foreach ($kind in $kindConfig.Keys) {
        $path = Resolve-PlanAssetPath -PlanDir $planDirFull -Kind $kindConfig[$kind].AssetKind `
            -RepoRoot $repoRootFull -Inventory $inventory
        $source = Get-PhaseSectionRecords -Kind $kind -Path $path -TargetPhase $Phase `
            -RepoIdentity $repoIdentity -PlanId $planId -KnownRequirement $knownRequirements `
            -Root $repoRootFull
        foreach ($record in $source.Records) { $allRecords.Add($record) }
        $allSources.Add($source.Source)
    }
    $overflowRoot = Resolve-PlanAssetPath -PlanDir $planDirFull -Kind LearningOverflowRoot `
        -RepoRoot $repoRootFull -Inventory $inventory
    $overflow = Get-OverflowRecords -Root $overflowRoot -TargetPhase $Phase `
        -RepoIdentity $repoIdentity -PlanId $planId -KnownRequirement $knownRequirements `
        -RepoRootPath $repoRootFull
    foreach ($record in $overflow.Records) { $allRecords.Add($record) }
    foreach ($source in $overflow.Sources) { $allSources.Add($source) }

    $duplicateIds = @($allRecords | Group-Object WorkflowSourceRecordId | Where-Object Count -gt 1)
    if ($duplicateIds.Count -gt 0) {
        throw "Duplicate workflow source-record id '$($duplicateIds[0].Name)' across harvest sources."
    }
    if ($allRecords.Count -gt $maxCandidates) {
        throw 'capacity-blocked: phase harvest exceeds 64 candidates.'
    }
    $candidateBytes = [long]0
    foreach ($record in $allRecords) {
        $candidateBytes += [System.Text.Encoding]::UTF8.GetByteCount([string]$record.Entry)
    }
    if ($candidateBytes -gt $maxCandidateBytes) {
        throw 'capacity-blocked: phase harvest exceeds 512 KiB.'
    }

    $orderedRecords = @($allRecords | Sort-Object SourceId)
    $receiptStatus = if ($orderedRecords.Count -eq 0) { 'empty' } else { 'complete' }
    $receipt = New-HarvestReceipt -RepoIdentity $repoIdentity -PlanId $planId -TargetPhase $Phase `
        -Status $receiptStatus -Sources @($allSources | Sort-Object Path) -Candidates $orderedRecords `
        -LedgerSource $Src
    $receiptBytes = [System.Text.Encoding]::UTF8.GetByteCount($receipt.Text)
    if ($receiptBytes -gt $maxReceiptBytes) {
        throw 'capacity-blocked: phase harvest receipt exceeds 64 KiB.'
    }

    $ledgerInputs = ConvertTo-LedgerInputs -Candidate $orderedRecords -PlanId $planId -LedgerSource $Src
    $publish = try {
        Invoke-WithAtomicStoreLock -Scope $normalizedHarvestLock -TimeoutSeconds 30 -Action {
            if (-not (Test-HarvestSourceSnapshot -Source @($allSources) -Root $repoRootFull `
                        -OverflowRoot $overflowRoot)) {
                return [pscustomobject]@{
                    Status = 'cas-conflict'
                    ReceiptCount = $existingReceipts.Count
                }
            }
            $receiptCount = @(if (Test-Path -LiteralPath $receiptRoot -PathType Container) {
                    Get-ChildItem -LiteralPath $receiptRoot -File -Filter 'phase-*.json'
                }).Count
            if ($receiptCount -gt $maxReceipts) {
                return [pscustomobject]@{
                    Status = 'capacity-blocked'
                    Reason = 'Active phase receipt ceiling exceeded before ledger mutation.'
                    ReceiptCount = $receiptCount
                }
            }
            if (Test-Path -LiteralPath $receiptPath -PathType Leaf) {
                Assert-PhysicalDescendant -Root $receiptRoot -Path $receiptPath
                $existingReceipt = [System.IO.File]::ReadAllText($receiptPath)
                if (-not [string]::Equals($existingReceipt, $receipt.Text, [System.StringComparison]::Ordinal)) {
                    return [pscustomobject]@{
                        Status = 'invalid'
                        ReceiptCount = $receiptCount
                    }
                }
                $replayedLedger = Invoke-LedgerBatch -Entry $ledgerInputs -RepoRoot $repoRootFull
                return [pscustomobject]@{
                    Status = $replayedLedger.Status
                    Ledger = $replayedLedger
                    ReceiptCount = $receiptCount
                    AddedReceipt = $false
                }
            }
            if ($receiptCount -ge $maxReceipts) {
                return [pscustomobject]@{
                    Status = 'capacity-blocked'
                    Reason = 'Active phase receipt ceiling of 64 reached before ledger mutation.'
                    ReceiptCount = $receiptCount
                }
            }
            $ledgerResult = Invoke-LedgerBatch -Entry $ledgerInputs -RepoRoot $repoRootFull
            if ($ledgerResult.Status -ne 'complete') {
                return [pscustomobject]@{
                    Status = $ledgerResult.Status
                    Reason = if ($ledgerResult.PSObject.Properties.Name -contains 'Reason') { $ledgerResult.Reason } else { '' }
                    Ledger = $ledgerResult
                    ReceiptCount = $receiptCount
                }
            }
            $receiptWrite = Set-AtomicStoreContent -Path $receiptPath -Content $receipt.Text -ExpectedGeneration 'absent'
            return [pscustomobject]@{
                Status = $receiptWrite.Status
                Ledger = $ledgerResult
                ReceiptCount = $receiptCount
                AddedReceipt = $true
            }
        }
    }
    catch [System.TimeoutException] {
        [pscustomobject]@{ Status = 'lock-timeout'; ReceiptCount = $existingReceipts.Count }
    }
    if ($publish.Status -eq 'capacity-blocked') {
        Write-HarvestResult -Status capacity-blocked -TargetPhase $Phase `
            -CandidateCount $orderedRecords.Count -ReceiptCount $publish.ReceiptCount `
            -ReceiptPath $receiptPath -Note $publish.Reason
        exit 4
    }
    if ($publish.Status -ne 'complete') {
        Write-HarvestResult -Status degraded -TargetPhase $Phase `
            -CandidateCount $orderedRecords.Count -ReceiptCount $publish.ReceiptCount `
            -ReceiptPath $receiptPath -Note "Phase harvest publication failed with status '$($publish.Status)'."
        exit 3
    }

    $ledger = $publish.Ledger
    $receiptIncrement = if ($publish.AddedReceipt) { 1 } else { 0 }
    Write-HarvestResult -Status $receiptStatus -TargetPhase $Phase `
        -CandidateCount $orderedRecords.Count -ReceiptCount ($publish.ReceiptCount + $receiptIncrement) `
        -Added $ledger.Added -Duplicate $ledger.Duplicate -ReceiptPath $receiptPath
    exit 0
}
catch {
    $message = $_.Exception.Message
    Write-Verbose $_.ScriptStackTrace
    if ($message.StartsWith('capacity-blocked:', [System.StringComparison]::Ordinal)) {
        Write-HarvestResult -Status capacity-blocked -TargetPhase $(if ($FinalSweep) { 0 } else { $Phase }) `
            -Note $message
        exit 4
    }
    Write-HarvestResult -Status degraded -TargetPhase $(if ($FinalSweep) { 0 } else { $Phase }) `
        -Note $message
    exit 3
}
