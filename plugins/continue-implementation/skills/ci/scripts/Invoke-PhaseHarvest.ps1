#requires -Version 7.0
[CmdletBinding(DefaultParameterSetName = 'Phase')]
param(
    [Parameter(Mandatory)]
    [string]$PlanDir,

    [Parameter(Mandatory, ParameterSetName = 'Phase')]
    [ValidateRange(1, 999)]
    [int]$Phase,

    [Parameter(Mandatory, ParameterSetName = 'FinalSweep')]
    [switch]$FinalSweep,

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
    param([Parameter(Mandatory)][byte[]]$Bytes)

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
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -gt 4MB) { throw "capacity-blocked: workflow log '$Path' exceeds 4 MiB." }
    $text = [System.Text.UTF8Encoding]::new($false, $true).GetString($bytes) -replace "`r`n", "`n"
    $lines = @($text.TrimEnd("`n").Split("`n"))
    $header = $kindConfig[$Kind].Header
    $ranges = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -ne $header) { continue }
        # Planning capture predates executable phases and legitimately uses Phase: 0. Parse it so
        # later Capture sections remain reachable, but never select it because TargetPhase starts at 1.
        if (($i + 1) -ge $lines.Count -or $lines[$i + 1] -notmatch '^\s*Phase:\s*(?<phase>0|[1-9][0-9]*)\s*$') {
            throw "Malformed phase header after '$header' in '$Path'."
        }
        $sectionPhase = [int]$Matches.phase
        if ($sectionPhase -eq 0 -and $Kind -ne 'Capture') {
            throw "Phase 0 is valid only for planning Capture in '$Path'."
        }
        $end = $lines.Count
        for ($j = $i + 2; $j -lt $lines.Count; $j++) {
            if ($lines[$j] -match '^##\s') { $end = $j; break }
        }
        if ($sectionPhase -eq $TargetPhase) { $ranges.Add([pscustomobject]@{ Start = $i + 2; End = $end }) }
    }
    if ($ranges.Count -ne 1) {
        throw "Expected exactly one '$header' section for phase $TargetPhase in '$Path'; found $($ranges.Count)."
    }

    $relative = Get-RelativeSourcePath -Root $Root -Path $Path
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
            throw "Malformed content in phase $TargetPhase section of '$relative'."
        }
        $records.Add((ConvertFrom-WorkflowNote -Kind $Kind -Line $line -SourcePhase $TargetPhase `
                -RelativePath $relative -RepoIdentity $RepoIdentity -PlanId $PlanId `
                -KnownRequirement $KnownRequirement))
    }
    if ($sawPlaceholder -and $records.Count -gt 0) {
        throw "Phase $TargetPhase section in '$relative' mixes the empty placeholder with records."
    }
    if (-not $sawPlaceholder -and $records.Count -eq 0) {
        throw "Phase $TargetPhase section in '$relative' has neither records nor the empty placeholder."
    }

    return [pscustomobject]@{
        Records = @($records)
        Source = [pscustomobject][ordered]@{
            Kind = $Kind
            Path = $relative
            Sha256 = Get-Sha256Hex -Bytes $bytes
            Bytes = $bytes.Length
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
        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        if ($bytes.Length -gt 512KB) { throw "capacity-blocked: overflow batch '$($file.FullName)' exceeds 512 KiB." }
        $content = [System.Text.UTF8Encoding]::new($false, $true).GetString($bytes)
        $lines = @($content.TrimEnd("`r", "`n") -split "`r?`n")
        if ($lines.Count -lt 7 -or $lines[0] -ne '# Learning Overflow Batch' -or
            $lines[1] -ne "Schema: $overflowSchema" -or $lines[2] -ne "Plan: $PlanId" -or
            $lines[3] -notmatch '^Digest: (?<digest>[0-9a-f]{64})$' -or
            $lines[4] -notmatch '^Count: (?<count>\d+)$' -or $lines[5] -ne '') {
            throw "Malformed learning overflow batch '$($file.FullName)'."
        }
        $digest = [regex]::Match($lines[3], '^Digest: (?<value>[0-9a-f]{64})$').Groups['value'].Value
        $count = [int]([regex]::Match($lines[4], '^Count: (?<value>\d+)$').Groups['value'].Value)
        $recordLines = [string[]]@($lines[6..($lines.Count - 1)])
        $recordBytes = ($recordLines -join "`n") + "`n"
        $expectedDigest = Get-DomainSeparatedId -Domain $overflowSchema -Field @($PlanId, $recordBytes)
        if ($count -ne $recordLines.Count -or $count -gt 64 -or
            $digest -ne $expectedDigest -or $file.BaseName -ne $digest) {
            throw "Learning overflow count, digest, or filename mismatch in '$($file.FullName)'."
        }
        $relative = Get-RelativeSourcePath -Root $RepoRootPath -Path $file.FullName
        $sources.Add([pscustomobject][ordered]@{
                Kind = 'LearningOverflow'
                Path = $relative
                Sha256 = Get-Sha256Hex -Bytes $bytes
                Bytes = $bytes.Length
            })
        foreach ($line in $recordLines) {
            if ($line -notmatch '^- \[(?<step>[0-9]+)\.') {
                if ($line -match '\[trigger:overflow-summary\]') {
                    throw "legacy-loss: overflow batch '$relative' contains a legacy summary."
                }
                throw "Overflow record in '$relative' has no derivable phase."
            }
            $recordPhase = [int]$Matches.step
            if ($recordPhase -ne $TargetPhase) { continue }
            if ([System.Text.Encoding]::UTF8.GetByteCount($line) -gt $maxSourceRecordBytes) {
                throw "capacity-blocked: source record in '$relative' exceeds 16 KiB."
            }
            $parsedKinds = [System.Collections.Generic.List[object]]::new()
            foreach ($candidateKind in @('CrLog', 'Learnings', 'Capture')) {
                try {
                    $parsedKinds.Add((ConvertFrom-WorkflowNote -Kind $candidateKind -Line $line `
                            -SourcePhase $TargetPhase -RelativePath $relative `
                            -RepoIdentity $RepoIdentity -PlanId $PlanId `
                            -KnownRequirement $KnownRequirement))
                }
                catch {
                    # The source-record domain disambiguates grammars with overlapping visible tokens.
                }
            }
            if ($parsedKinds.Count -ne 1) {
                throw "Overflow record in '$relative' does not resolve to exactly one typed workflow-note kind."
            }
            $records.Add($parsedKinds[0])
        }
    }
    return [pscustomobject]@{ Records = @($records); Sources = @($sources) }
}

function ConvertTo-CanonicalJson {
    param([Parameter(Mandatory)]$Value)

    return $Value | ConvertTo-Json -Depth 12 -Compress
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
        [Parameter(Mandatory)][string]$RepoIdentity,
        [Parameter(Mandatory)][string]$PlanId,
        [Parameter(Mandatory)][string[]]$KnownRequirement
    )

    Assert-PhysicalDescendant -Root $ReceiptRoot -Path $Path
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -gt $maxReceiptBytes) { throw "Harvest receipt '$Path' exceeds 64 KiB." }
    $parsed = [System.Text.UTF8Encoding]::new($false, $true).GetString($bytes) | ConvertFrom-Json -Depth 12
    $envelopeProperties = @($parsed.PSObject.Properties.Name)
    if ($envelopeProperties.Count -ne 3 -or
        @('schema', 'receiptId', 'payload' | Where-Object { $envelopeProperties -notcontains $_ }).Count -gt 0 -or
        $parsed.schema -ne $receiptSchema -or $parsed.receiptId -notmatch '^[0-9a-f]{64}$') {
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
        $phaseNumber -lt 1 -or $phaseNumber -gt 999) {
        throw "Harvest receipt '$Path' has an invalid phase."
    }
    $sources = @($parsed.payload.sources)
    $candidates = @($parsed.payload.candidates)
    if ($sources.Count -lt 3 -or $candidates.Count -gt $maxCandidates) {
        throw "Harvest receipt '$Path' exceeds source or candidate bounds."
    }
    $sourcePaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
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

try {
    if ($FinalSweep) {
        $receiptFiles = @(if (Test-Path -LiteralPath $receiptRoot -PathType Container) {
                Get-ChildItem -LiteralPath $receiptRoot -File -Filter 'phase-*.json' | Sort-Object Name
            })
        if ($receiptFiles.Count -gt $maxReceipts) {
            throw 'capacity-blocked: active phase receipt ceiling exceeded.'
        }
        $receipts = @($receiptFiles | ForEach-Object {
                Read-HarvestReceipt -Path $_.FullName -ReceiptRoot $receiptRoot `
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
    $normalizedHarvestLock = Resolve-PhysicalRepoPath -Path $planDirFull
    if ($IsWindows) { $normalizedHarvestLock = $normalizedHarvestLock.ToLowerInvariant() }
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
            $receipt = Read-HarvestReceipt -Path $receiptPath -ReceiptRoot $receiptRoot `
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
