#requires -Version 7.0

Set-StrictMode -Version Latest

function Remove-FencedCodeBlocks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines
    )

    $output = [System.Collections.Generic.List[string]]::new()
    $inFence = $false
    foreach ($line in $Lines) {
        if ($line -match '^\s*```') {
            $inFence = -not $inFence
            $output.Add('')
            continue
        }

        if ($inFence) {
            $output.Add('')
            continue
        }

        $output.Add($line)
    }

    return , $output.ToArray()
}

function Split-MarkdownTableCells {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Row
    )

    $trimmed = $Row.Trim()
    $withoutPipes = $trimmed.Trim('|')
    $rawCells = $withoutPipes.Split('|')
    $cells = @()
    foreach ($cell in $rawCells) {
        $cells += , $cell.Trim()
    }

    return , $cells
}

$script:PlanAssetMap = [ordered]@{
    Intent          = [pscustomobject]@{ Asset = 'intent.md'; Legacy = 'intent.md' }
    Requirements    = [pscustomobject]@{ Asset = 'requirements.md'; Legacy = $null }
    Risks           = [pscustomobject]@{ Asset = 'risks.md'; Legacy = $null }
    Decisions       = [pscustomobject]@{ Asset = 'decisions.md'; Legacy = $null }
    References      = [pscustomobject]@{ Asset = 'references.md'; Legacy = $null }
    Evidence        = [pscustomobject]@{ Asset = 'evidence.md'; Legacy = 'evidence.md' }
    EvolutionLog    = [pscustomobject]@{ Asset = 'evolution-log.md'; Legacy = 'evolution-log.md' }
    DecisionRecords = [pscustomobject]@{ Asset = 'decisions'; Legacy = 'decisions' }
    CrLog           = [pscustomobject]@{ Asset = 'logs/cr-log.md'; Legacy = 'cr-log.md' }
    Learnings       = [pscustomobject]@{ Asset = 'logs/learnings.md'; Legacy = 'learnings.md' }
    Capture         = [pscustomobject]@{ Asset = 'logs/capture.md'; Legacy = 'capture.md' }
}

function Get-PlanLayout {
    <#
    .SYNOPSIS
    Reports whether a plan folder uses the `plan.md` + `assets/` layout or the legacy flat layout.

    .DESCRIPTION
    The layout is anchored on `assets/requirements.md` — the one asset every plan has and that both
    `New-Plan` (scaffold) and migration write. Keying off mere `assets/` directory presence would flip a
    legacy plan the moment it grew any `assets/` subfolder, orphaning the logs and receipt already written
    at the plan root. An `assets/` folder that holds no recognized section file therefore stays `legacy`,
    which resolves per section rather than switching the whole plan into a broken mode.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PlanDir
    )

    $anchor = Join-Path (Join-Path $PlanDir 'assets') 'requirements.md'
    if (Test-Path -LiteralPath $anchor -PathType Leaf) {
        return 'assets'
    }

    return 'legacy'
}

function Resolve-PlanAssetPath {
    <#
    .SYNOPSIS
    Resolves the on-disk path of a plan asset for the plan folder's layout.

    .DESCRIPTION
    Single source of truth so writers (`Add-WorkflowNote`, `Build-EvidenceReceipt`, `/ci`) and readers
    (harvest, archival gate) never disagree about where logs and receipts live. Sections that only ever
    exist as assets (requirements/risks/decisions/references) always resolve under `assets/`; their legacy
    form lives inside `plan.md`, not in a sibling file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PlanDir,

        [Parameter(Mandatory)]
        [ValidateSet('Intent', 'Requirements', 'Risks', 'Decisions', 'References', 'Evidence', 'EvolutionLog', 'DecisionRecords', 'CrLog', 'Learnings', 'Capture')]
        [string]$Kind,

        [ValidateSet('assets', 'legacy')]
        [string]$Layout
    )

    $planDirFull = [System.IO.Path]::GetFullPath($PlanDir)
    if (-not $Layout) {
        $Layout = Get-PlanLayout -PlanDir $planDirFull
    }

    $entry = $script:PlanAssetMap[$Kind]
    if (-not $entry.Legacy) {
        # Section assets have no sibling-file legacy form — their legacy home is inside plan.md.
        return [System.IO.Path]::GetFullPath((Join-Path $planDirFull (Join-Path 'assets' $entry.Asset)))
    }

    $assetPath = [System.IO.Path]::GetFullPath((Join-Path $planDirFull (Join-Path 'assets' $entry.Asset)))
    $legacyPath = [System.IO.Path]::GetFullPath((Join-Path $planDirFull $entry.Legacy))

    # Fail loud on genuine split-brain: the same logical file existing at both locations means writers and
    # readers have already diverged, and silently preferring one would orphan real content.
    if ((Test-Path -LiteralPath $assetPath) -and (Test-Path -LiteralPath $legacyPath)) {
        throw "Plan folder '$planDirFull' holds '$Kind' at both '$assetPath' and '$legacyPath'. Move the legacy copy under assets/ so writers and readers cannot disagree."
    }

    if ($Layout -eq 'assets') {
        return $assetPath
    }

    return $legacyPath
}

function Get-PlanSectionRecord {
    <#
    .SYNOPSIS
    Normalizes a plan section's lines into a comparable record set (not raw text), so divergence checks
    ignore cosmetic drift such as column padding, heading prose, blank lines, and row order.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [AllowNull()]
        [string[]]$Lines,

        [Parameter(Mandatory)]
        [ValidateSet('Table', 'List')]
        [string]$Kind,

        [string]$IdPattern,

        [int]$MinCell = 2
    )

    $records = [System.Collections.Generic.List[string]]::new()
    foreach ($line in @($Lines)) {
        if ($null -eq $line) { continue }
        $trimmed = $line.Trim()

        if ($Kind -eq 'Table') {
            if (-not $trimmed.StartsWith('|')) { continue }
            $cells = Split-MarkdownTableCells -Row $trimmed
            # Match the consumer parsers' minimum column count exactly: a row they would discard must not
            # count as a well-formed record here, or a short-columned asset resolves to zero requirements.
            if ($cells.Count -lt $MinCell) { continue }
            if ($IdPattern -and $cells[0] -notmatch $IdPattern) { continue }
            $normalizedCells = @($cells | ForEach-Object { ($_ -replace '\s+', ' ').Trim() })
            $records.Add(($normalizedCells -join ' | '))
            continue
        }

        if ($trimmed -notmatch '^[-*]\s+') { continue }
        $body = (($trimmed -replace '^[-*]\s+', '') -replace '\s+', ' ').Trim()
        if (-not [string]::IsNullOrWhiteSpace($body)) {
            $records.Add($body)
        }
    }

    return , $records.ToArray()
}

function Resolve-PlanSection {
    <#
    .SYNOPSIS
    Resolves one plan section (Requirements / Risks / Decisions) from either `assets/<section>.md` or the
    legacy in-`plan.md` table, per the documented state table.

    .DESCRIPTION
    | Asset absent                          | fall back to the in-plan.md section |
    | Asset present, non-empty, well-formed | asset wins |
    | Asset present but empty or malformed  | fail loud (never silently resolve to zero records) |
    | Both present                          | asset wins; divergence over the normalized record set errors |

    Fenced code blocks are stripped from asset files exactly as they are from `plan.md`.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PlanDir,

        [Parameter(Mandatory)]
        [ValidateSet('Requirements', 'Risks', 'Decisions')]
        [string]$Section,

        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [AllowNull()]
        [string[]]$LegacyLine
    )

    $kind = if ($Section -eq 'Decisions') { 'List' } else { 'Table' }
    $idPattern = switch ($Section) {
        'Requirements' { '^REQ-\d+$' }
        'Risks' { '^RISK-\d+$' }
        default { $null }
    }
    # Mirror the consumer parsers' column requirements so "well-formed" here means "parseable there".
    $minCell = switch ($Section) {
        'Requirements' { 4 }
        default { 2 }
    }

    $legacyLines = @($LegacyLine)
    $legacyRecords = Get-PlanSectionRecord -Lines $legacyLines -Kind $kind -IdPattern $idPattern -MinCell $minCell

    $assetPath = Resolve-PlanAssetPath -PlanDir $PlanDir -Kind $Section
    if (-not (Test-Path -LiteralPath $assetPath -PathType Leaf)) {
        $source = if ($legacyRecords.Count -gt 0) { 'legacy' } else { 'none' }
        return [pscustomobject]@{
            Section = $Section
            Source  = $source
            Path    = $null
            Lines   = $legacyLines
            Records = $legacyRecords
        }
    }

    $raw = Get-Content -LiteralPath $assetPath -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "Plan asset '$assetPath' is present but empty; $Section must never silently resolve to zero records. Author the file or delete it to fall back to plan.md."
    }

    $assetLines = Remove-FencedCodeBlocks -Lines (($raw -replace "`r`n", "`n").Split("`n"))
    $assetRecords = Get-PlanSectionRecord -Lines $assetLines -Kind $kind -IdPattern $idPattern -MinCell $minCell
    if ($assetRecords.Count -eq 0) {
        $expected = if ($kind -eq 'Table') { "table rows with at least $minCell columns whose first cell matches $idPattern" } else { 'bullet list entries' }
        throw "Plan asset '$assetPath' is malformed: no $Section records found (expected $expected)."
    }

    if ($legacyRecords.Count -gt 0) {
        $assetKey = (@($assetRecords) | Sort-Object) -join "`n"
        $legacyKey = (@($legacyRecords) | Sort-Object) -join "`n"
        if ($assetKey -cne $legacyKey) {
            throw "Plan asset '$assetPath' diverges from the legacy '## $Section' section in plan.md. Remove the legacy table (the asset is authoritative) or reconcile the two."
        }
    }

    return [pscustomobject]@{
        Section = $Section
        Source  = 'asset'
        Path    = $assetPath
        Lines   = $assetLines
        Records = $assetRecords
    }
}

function ConvertFrom-PlanRequirementLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [AllowNull()]
        [string[]]$Lines
    )

    $requirements = @{}
    foreach ($line in @($Lines)) {
        if ($null -eq $line -or -not $line.Trim().StartsWith('|')) { continue }
        $cells = Split-MarkdownTableCells -Row $line
        if ($cells.Count -lt 4 -or $cells[0] -eq 'ID' -or $cells[0] -eq '----') {
            continue
        }

        if ($cells[0] -match '^REQ-(?<id>\d+)$') {
            $requirements[$cells[0]] = [pscustomobject]@{
                Id = $cells[0]
                Number = [int]$Matches.id
                Text = $cells[1]
                AcceptanceCriteria = $cells[2]
                Steps = $cells[3]
            }
        }
    }

    return $requirements
}

function ConvertFrom-PlanRiskLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [AllowNull()]
        [string[]]$Lines
    )

    $risks = @{}
    foreach ($line in @($Lines)) {
        if ($null -eq $line -or -not $line.Trim().StartsWith('|')) { continue }
        $cells = Split-MarkdownTableCells -Row $line
        if ($cells.Count -lt 2 -or $cells[0] -eq 'ID' -or $cells[0] -eq '----') {
            continue
        }

        if ($cells[0] -match '^RISK-(?<id>\d+)$') {
            $risks[$cells[0]] = [int]$Matches.id
        }
    }

    return $risks
}

function Get-PlanMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$RepoRoot
    )

    $fullPath = (Resolve-Path -LiteralPath $Path).Path
    $planDir = Split-Path -Parent $fullPath
    $repoRootPath = [System.IO.Path]::GetFullPath($RepoRoot)
    $content = Get-Content -LiteralPath $fullPath -Raw
    $normalized = $content -replace "`r`n", "`n"
    $allLines = $normalized.Split("`n")
    $lines = Remove-FencedCodeBlocks -Lines $allLines

    $currentPhase = ''
    $currentSection = $null
    $phaseSteps = @{}
    $sectionLines = @{
        Requirements = [System.Collections.Generic.List[string]]::new()
        Risks        = [System.Collections.Generic.List[string]]::new()
        Decisions    = [System.Collections.Generic.List[string]]::new()
    }
    $steps = [System.Collections.Generic.List[object]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()

    # `<details>` blocks under a step (the `@human` handoff detail) are captured here rather than
    # re-parsed by consumers, so the validator gate and the /ci handoff read the same text. Detail text
    # is taken from $allLines, not the fence-stripped $lines, because handoffs routinely contain fenced
    # operator commands and a stripped block would silently lose exactly the part a human needs.
    # Every `<details>` block under a step is collected: plans also carry Result/evidence blocks, and
    # keying on the first block (or on its <summary> text) would misread those as the handoff.
    $currentStep = $null
    $detailBlocks = $null
    $detailLines = $null
    $detailDepth = 0

    $flushDetail = {
        if ($currentStep) {
            if ($null -ne $detailLines -and $detailLines.Count -gt 0 -and $null -ne $detailBlocks) {
                # An unterminated block still carries the operator's text; keep it so the gate reports the
                # missing sections instead of a misleading "no details block at all".
                $detailBlocks.Add(($detailLines -join "`n"))
            }
            if ($null -ne $detailBlocks -and $detailBlocks.Count -gt 0) {
                $currentStep.Detail = ($detailBlocks -join "`n`n")
            }
        }
        $currentStep = $null
        $detailBlocks = $null
        $detailLines = $null
        $detailDepth = 0
    }

    for ($lineIndex = 0; $lineIndex -lt $lines.Length; $lineIndex++) {
        $line = $lines[$lineIndex]
        $rawLine = if ($lineIndex -lt $allLines.Length) { $allLines[$lineIndex] } else { $line }

        if ($line -match '^\s*##\s+(?<section>Requirements|Risks|Decisions)\b') {
            $currentSection = [string]$Matches.section
            . $flushDetail
            continue
        }

        if ($line -match '^\s*##\s+') {
            $currentSection = $null
            $currentPhase = $line.Trim()
            if ($currentPhase -match '^##\s+Phase\s+\d+:\s+') {
                $phaseSteps[$currentPhase] = [System.Collections.Generic.List[object]]::new()
            }
            . $flushDetail
            continue
        }

        if ($currentSection) {
            $sectionLines[$currentSection].Add($line)
            if ($line.Trim().StartsWith('|')) { continue }
        }

        # Inside an open block every line belongs to it, including step-shaped lines in example markup —
        # except an unindented step line, which is structural: an unterminated block must not silently
        # swallow the rest of the plan's steps. Depth is counted on the fence-stripped line so a fenced
        # example cannot close the real block, while the captured text comes from the raw line so fenced
        # operator commands survive.
        if ($currentStep -and $detailDepth -gt 0 -and $line -notmatch '^-\s\[[ x~]\]\s+\d+\.\d+[a-z]?\s') {
            $detailLines.Add($rawLine)
            $detailDepth += ([regex]::Matches($line, '<details\b')).Count
            $detailDepth -= ([regex]::Matches($line, '</details>')).Count
            if ($detailDepth -le 0) {
                $detailBlocks.Add(($detailLines -join "`n"))
                $detailLines = $null
                $detailDepth = 0
            }
            continue
        }

        if ($line -match '^\s*-\s\[(?<status>[ x~])\]\s+(?<step>\d+\.\d+[a-z]?)\s+(?<body>.+)$') {
            $stepId = $Matches.step
            $status = $Matches.status
            $body = $Matches.body
            $size = ''
            if ($body -match '`(?<size>[SML])`') {
                $size = [string]$Matches.size
            }

            $role = 'ai-agent'
            if ($body -match '\s@(?<role>human|ai-agent)\b') {
                $role = [string]$Matches.role
            }

            $afterIds = @()
            if ($body -match '\[after:\s*(?<after>[^\]]+)\]') {
                $afterList = $Matches.after.Split(',')
                foreach ($after in $afterList) {
                    $candidate = $after.Trim()
                    if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                        $afterIds += , $candidate
                    }
                }
            }

            $refs = @()
            $parenMatches = [regex]::Matches($body, '\((?<refs>[^)]*)\)')
            foreach ($parenMatch in $parenMatches) {
                $candidateRefs = @($parenMatch.Groups['refs'].Value.Split(',') | ForEach-Object { $_.Trim() })
                if ($candidateRefs -match '^REQ-\d+$' -or $candidateRefs -match '^RISK-\d+$') {
                    $refs = @($candidateRefs | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                }
            }

            $step = [pscustomobject]@{
                Id = $stepId
                Status = $status
                Body = $body
                Role = $role
                Size = $size
                After = $afterIds
                Refs = $refs
                Phase = $currentPhase
                Detail = ''
            }

            . $flushDetail
            $steps.Add($step)
            if ($phaseSteps.ContainsKey($currentPhase)) {
                $phaseSteps[$currentPhase].Add($step)
            }
            $currentStep = $step
            $detailBlocks = [System.Collections.Generic.List[string]]::new()
            continue
        }

        if ($currentStep -and $line -match '<details\b') {
            $detailLines = [System.Collections.Generic.List[string]]::new()
            $detailLines.Add($rawLine)
            $detailDepth = ([regex]::Matches($line, '<details\b')).Count - ([regex]::Matches($line, '</details>')).Count
            if ($detailDepth -le 0) {
                $detailBlocks.Add(($detailLines -join "`n"))
                $detailLines = $null
                $detailDepth = 0
            }
        }
    }

    . $flushDetail

    $resolvedSections = [ordered]@{}
    foreach ($section in @('Requirements', 'Risks', 'Decisions')) {
        $resolvedSections[$section] = Resolve-PlanSection -PlanDir $planDir -Section $section -LegacyLine $sectionLines[$section].ToArray()
    }

    $requirements = ConvertFrom-PlanRequirementLine -Lines $resolvedSections['Requirements'].Lines
    $risks = ConvertFrom-PlanRiskLine -Lines $resolvedSections['Risks'].Lines

    $sectionSources = [ordered]@{}
    foreach ($section in $resolvedSections.Keys) {
        $sectionSources[$section] = $resolvedSections[$section].Source
    }

    $sizeBytes = [System.Text.Encoding]::UTF8.GetByteCount($content)
    if ($sizeBytes -ge 20480 -or $allLines.Length -ge 400) {
        $warnings.Add("Plan size warning: ${sizeBytes} bytes / $($allLines.Length) lines (warn threshold 20KB/400).")
    }
    if ($sizeBytes -ge 35840 -or $allLines.Length -ge 700) {
        $warnings.Add("Plan size warning: ${sizeBytes} bytes / $($allLines.Length) lines (block threshold 35KB/700 is advisory in this validator).")
    }

    # Archived plans are immutable historical records: they are still parsed and validated, but drafting
    # gates introduced after they were written must not retroactively fail them. Derived from the plan's
    # own resolved path (an `archived` folder directly under `implementation-plans`) rather than from
    # $RepoRoot, which may be relative and would then resolve against the wrong base.
    $isArchived = $false
    $ancestor = $planDir
    while ($ancestor) {
        if ([System.IO.Path]::GetFileName($ancestor) -eq 'archived') {
            $parentName = [System.IO.Path]::GetFileName((Split-Path -Parent $ancestor))
            if ($parentName -eq 'implementation-plans') {
                $isArchived = $true
                break
            }
        }
        $ancestor = Split-Path -Parent $ancestor
    }

    return [pscustomobject]@{
        PlanPath = $fullPath
        PlanDir = $planDir
        Layout = (Get-PlanLayout -PlanDir $planDir)
        IsArchived = $isArchived
        RepoRoot = $repoRootPath
        Content = $content
        Lines = $lines
        AllLines = $allLines
        Requirements = $requirements
        Risks = $risks
        Decisions = @($resolvedSections['Decisions'].Records)
        # The resolved section objects themselves (Source/Path/Lines/Records) so cross-plan readers such as
        # Get-PlanIndex see exactly what the resolver saw, instead of re-deciding layout for themselves.
        Sections = $resolvedSections
        SectionSources = $sectionSources
        Steps = @($steps)
        PhaseSteps = $phaseSteps
        Warnings = $warnings
    }
}

function Get-PlanInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot
    )

    $root = [System.IO.Path]::GetFullPath($RepoRoot)
    $plansRoot = Join-Path $root 'docs/implementation-plans'
    $inventory = [System.Collections.Generic.List[object]]::new()
    if (-not (Test-Path -LiteralPath $plansRoot)) {
        return $inventory.ToArray()
    }

    $archivedRoot = Join-Path $plansRoot 'archived'
    $folders = @()
    $folders += Get-ChildItem -LiteralPath $plansRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne 'archived' } |
        ForEach-Object { [pscustomobject]@{ Dir = $_; IsArchived = $false } }
    if (Test-Path -LiteralPath $archivedRoot) {
        $folders += Get-ChildItem -LiteralPath $archivedRoot -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { [pscustomobject]@{ Dir = $_; IsArchived = $true } }
    }

    foreach ($entry in $folders) {
        $name = $entry.Dir.Name
        $scheme = $null
        $folderId = $null
        $slug = $null
        $date = $null

        if ($name -match '^(?<date>\d{4}-\d{2}-\d{2})-(?<hash>[0-9a-f]{6})-(?<slug>.+)$') {
            $scheme = 'new'
            $folderId = $Matches.hash
            $slug = $Matches.slug
            $date = $Matches.date
        }
        elseif ($name -match '^(?<num>\d{3})-(?<slug>.+)$') {
            $scheme = 'legacy'
            $folderId = $Matches.num
            $slug = $Matches.slug
        }
        else {
            continue
        }

        $planFile = Join-Path $entry.Dir.FullName 'plan.md'
        $anchorId = $null
        $epicId = $null
        if (Test-Path -LiteralPath $planFile) {
            $raw = Get-Content -LiteralPath $planFile -Raw
            if ($raw -match '<!--\s*plan-id:\s*(?<id>[0-9a-fA-F]{3,})\s*-->') {
                $anchorId = $Matches.id.ToLowerInvariant()
            }
            # Epic membership is carried by the child plan, never by the epic's own table: the marker
            # travels with the plan folder (including into archived/), so a rollup cannot go stale.
            # It is read through the same header-scoped view every other marker uses, so a plan that
            # merely documents the marker in its body is not silently enrolled in that epic.
            $headerEpicId = (Get-PlanHeaderMarkers -Content $raw).EpicId
            if ($headerEpicId -and $headerEpicId -match '^[0-9a-fA-F]{3,}$') {
                $epicId = $headerEpicId.ToLowerInvariant()
            }
        }

        $canonicalId = if ($anchorId) { $anchorId } else { $folderId }

        $inventory.Add([pscustomobject]@{
            Id = $canonicalId
            FolderId = $folderId
            AnchorId = $anchorId
            EpicId = $epicId
            Scheme = $scheme
            Slug = $slug
            Date = $date
            FolderName = $name
            Path = $entry.Dir.FullName
            IsArchived = $entry.IsArchived
        })
    }

    return $inventory.ToArray()
}

function New-PlanHexId {
    [CmdletBinding()]
    param()

    $bytes = [byte[]]::new(3)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    return (($bytes | ForEach-Object { $_.ToString('x2') }) -join '')
}

function New-PlanId {
    [CmdletBinding()]
    param(
        [string]$RepoRoot,

        [string[]]$ExistingId,

        [scriptblock]$HexProvider = { New-PlanHexId },

        [int]$MaxAttempts = 1000
    )

    if (-not $PSBoundParameters.ContainsKey('ExistingId')) {
        if (-not $RepoRoot) {
            throw 'New-PlanId requires -RepoRoot when -ExistingId is not supplied.'
        }
        $ExistingId = @(Get-PlanInventory -RepoRoot $RepoRoot | ForEach-Object { $_.Id })
    }

    $existingSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($id in $ExistingId) {
        if (-not [string]::IsNullOrWhiteSpace($id)) {
            [void]$existingSet.Add($id.Trim().ToLowerInvariant())
        }
    }

    $candidate = $null
    for ($attempt = 0; $attempt -lt $MaxAttempts; $attempt++) {
        $generated = (& $HexProvider)
        if ($generated -isnot [string]) { $generated = [string]$generated }
        $generated = $generated.Trim().ToLowerInvariant()
        if ($generated -notmatch '^[0-9a-f]{6}$') {
            throw "New-PlanId generated an invalid id '$generated' (expected 6 hex chars)."
        }
        if (-not $existingSet.Contains($generated)) {
            $candidate = $generated
            break
        }
    }

    if (-not $candidate) {
        throw "New-PlanId could not generate a unique id after $MaxAttempts attempts."
    }

    $prefix = $candidate.Substring(0, 4)
    foreach ($existing in $existingSet) {
        if ($existing.Length -ge 4 -and $existing.Substring(0, 4) -eq $prefix) {
            Write-Warning "Plan id '$candidate' is not uniquely addressable at the 4-char prefix '$prefix' (collides with existing '$existing')."
            break
        }
    }

    return $candidate
}

function Resolve-Plan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Reference,

        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [object[]]$Inventory
    )

    if ([string]::IsNullOrWhiteSpace($Reference)) {
        throw 'Resolve-Plan requires a non-empty -Reference.'
    }

    if (-not $PSBoundParameters.ContainsKey('Inventory')) {
        $Inventory = @(Get-PlanInventory -RepoRoot $RepoRoot)
    }

    $ref = $Reference.Trim()
    $refLower = $ref.ToLowerInvariant()
    $matches = @()
    $kind = $null

    if ($ref -match '^\d{4}-\d{2}-\d{2}$') {
        $kind = "date '$ref'"
        $matches = @($Inventory | Where-Object { $_.Date -eq $ref })
    }
    elseif ($ref -match '^\d{3}$') {
        $kind = "legacy number '$ref'"
        $matches = @($Inventory | Where-Object { $_.Scheme -eq 'legacy' -and $_.Id -eq $ref })
    }
    elseif ($refLower -match '^[0-9a-f]{4,6}$') {
        $kind = "hash prefix '$ref'"
        $matches = @($Inventory | Where-Object { $_.Id -and $_.Id.ToLowerInvariant().StartsWith($refLower) })
        if ($matches.Count -eq 0) {
            $kind = "slug '$ref'"
            $matches = @($Inventory | Where-Object { $_.Slug -eq $ref })
        }
    }
    else {
        $kind = "slug '$ref'"
        $matches = @($Inventory | Where-Object { $_.Slug -eq $ref })
        if ($matches.Count -eq 0) {
            $matches = @($Inventory | Where-Object { $_.Slug -and $_.Slug.ToLowerInvariant().Contains($refLower) })
        }
    }

    if ($matches.Count -eq 0) {
        throw "No plan matches $kind."
    }

    if ($matches.Count -gt 1) {
        $detail = ($matches | ForEach-Object { "$($_.Id) ($($_.FolderName))" }) -join ', '
        throw "Ambiguous plan reference: $kind matches multiple plans: $detail. Use a longer prefix or the full id."
    }

    return $matches[0]
}

function Get-EpicInventory {
    <#
    .SYNOPSIS
    Enumerates the epic folders under `docs/implementation-plans/epics/`.

    .DESCRIPTION
    An epic is an index, not a plan: it holds `epic.md` and no `plan.md`, and its children stay ordinary
    sibling plan folders so every existing consumer keeps resolving them unchanged. The folder name
    follows the plan scheme (`<yyyy-mm-dd>-<6hex>-<slug>`); the `<!-- epic-id: ... -->` anchor in
    `epic.md` is canonical when present, exactly as `plan-id` is for plans.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot
    )

    $root = [System.IO.Path]::GetFullPath($RepoRoot)
    $epicsRoot = Join-Path $root 'docs/implementation-plans/epics'
    $inventory = [System.Collections.Generic.List[object]]::new()
    if (-not (Test-Path -LiteralPath $epicsRoot -PathType Container)) {
        return $inventory.ToArray()
    }

    foreach ($dir in (Get-ChildItem -LiteralPath $epicsRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name)) {
        if ($dir.Name -notmatch '^(?<date>\d{4}-\d{2}-\d{2})-(?<hash>[0-9a-f]{6})-(?<slug>.+)$') {
            continue
        }

        $folderId = $Matches.hash
        $slug = $Matches.slug
        $date = $Matches.date

        $epicFile = Join-Path $dir.FullName 'epic.md'
        $anchorId = $null
        $title = $null
        if (Test-Path -LiteralPath $epicFile -PathType Leaf) {
            $raw = Get-Content -LiteralPath $epicFile -Raw
            if ($raw -match '<!--\s*epic-id:\s*(?<id>[0-9a-fA-F]{3,})\s*-->') {
                $anchorId = $Matches.id.ToLowerInvariant()
            }
            if ($raw -match '(?m)^#\s+(?<title>.+?)\s*$') {
                $title = $Matches.title.Trim()
            }
        }

        $inventory.Add([pscustomobject]@{
            Id         = if ($anchorId) { $anchorId } else { $folderId }
            FolderId   = $folderId
            AnchorId   = $anchorId
            Slug       = $slug
            Date       = $date
            Title      = $title
            FolderName = $dir.Name
            Path       = $dir.FullName
            EpicFile   = $epicFile
        })
    }

    return $inventory.ToArray()
}

function Resolve-Epic {
    <#
    .SYNOPSIS
    Resolves an epic reference (hash prefix, slug, or date) to exactly one epic record.

    .DESCRIPTION
    Same contract as `Resolve-Plan`: ambiguity is an error, never a silent first-match pick.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Reference,

        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [object[]]$Inventory
    )

    if ([string]::IsNullOrWhiteSpace($Reference)) {
        throw 'Resolve-Epic requires a non-empty -Reference.'
    }

    if (-not $PSBoundParameters.ContainsKey('Inventory')) {
        $Inventory = @(Get-EpicInventory -RepoRoot $RepoRoot)
    }

    $ref = $Reference.Trim()
    $refLower = $ref.ToLowerInvariant()
    $epicMatches = @()
    $kind = $null

    if ($ref -match '^\d{4}-\d{2}-\d{2}$') {
        $kind = "date '$ref'"
        $epicMatches = @($Inventory | Where-Object { $_.Date -eq $ref })
    }
    elseif ($refLower -match '^[0-9a-f]{4,6}$') {
        $kind = "hash prefix '$ref'"
        $epicMatches = @($Inventory | Where-Object { $_.Id -and $_.Id.ToLowerInvariant().StartsWith($refLower) })
        if ($epicMatches.Count -eq 0) {
            $kind = "slug '$ref'"
            $epicMatches = @($Inventory | Where-Object { $_.Slug -eq $ref })
        }
    }
    else {
        $kind = "slug '$ref'"
        $epicMatches = @($Inventory | Where-Object { $_.Slug -eq $ref })
        if ($epicMatches.Count -eq 0) {
            $epicMatches = @($Inventory | Where-Object { $_.Slug -and $_.Slug.ToLowerInvariant().Contains($refLower) })
        }
    }

    if ($epicMatches.Count -eq 0) {
        throw "No epic matches $kind."
    }

    if ($epicMatches.Count -gt 1) {
        $detail = ($epicMatches | ForEach-Object { "$($_.Id) ($($_.FolderName))" }) -join ', '
        throw "Ambiguous epic reference: $kind matches multiple epics: $detail. Use a longer prefix or the full id."
    }

    return $epicMatches[0]
}

function Get-PlanHeaderMarkers {
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [string]$Path,

        [Parameter(Mandatory, ParameterSetName = 'Content')]
        [AllowEmptyString()]
        [string]$Content
    )

    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        $Content = Get-Content -LiteralPath (Resolve-Path -LiteralPath $Path).Path -Raw
    }

    $normalized = ($Content ?? '') -replace "`r`n", "`n"
    $lines = $normalized.Split("`n")
    $headerLines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $lines) {
        if ($line -match '^##\s') { break }
        $headerLines.Add($line)
    }
    $header = $headerLines -join "`n"

    $all = [ordered]@{}
    foreach ($match in [regex]::Matches($header, '<!--\s*(?<key>[A-Za-z][\w-]*)\s*:\s*(?<value>.*?)\s*-->')) {
        $key = $match.Groups['key'].Value.ToLowerInvariant()
        if (-not $all.Contains($key)) {
            $all[$key] = $match.Groups['value'].Value.Trim()
        }
    }

    $getValue = { param($k) if ($all.Contains($k)) { $all[$k] } else { $null } }

    $dependsOn = @()
    $dependsRaw = & $getValue 'depends-on'
    if ($dependsRaw) {
        $dependsOn = @($dependsRaw.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }

    return [pscustomobject]@{
        PlanId        = & $getValue 'plan-id'
        EpicId        = & $getValue 'epic'
        ExecutionMode = & $getValue 'execution-mode'
        Scope         = & $getValue 'scope'
        CipStage      = & $getValue 'cip-stage'
        DependsOn     = $dependsOn
        All           = $all
    }
}

function Get-PlanProgress {
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Metadata')]
        [object]$Metadata,

        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [string]$Path,

        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [string]$RepoRoot
    )

    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        $Metadata = Get-PlanMetadata -Path $Path -RepoRoot $RepoRoot
    }

    $steps = @($Metadata.Steps)
    $total = $steps.Count
    $completed = @($steps | Where-Object { $_.Status -eq 'x' }).Count
    $inProgress = @($steps | Where-Object { $_.Status -eq '~' }).Count
    $pending = @($steps | Where-Object { $_.Status -eq ' ' }).Count

    $lastCompleted = $null
    foreach ($step in $steps) {
        if ($step.Status -eq 'x') { $lastCompleted = $step.Id }
    }

    $currentPhase = $null
    foreach ($step in $steps) {
        if ($step.Status -ne 'x') { $currentPhase = $step.Phase; break }
    }
    if (-not $currentPhase -and $total -gt 0) {
        $currentPhase = $steps[$total - 1].Phase
    }

    $percent = if ($total -gt 0) { [math]::Round(($completed / $total) * 100, 1) } else { 0 }

    return [pscustomobject]@{
        Total         = $total
        Completed     = $completed
        InProgress    = $inProgress
        Pending       = $pending
        Percent       = $percent
        CurrentPhase  = $currentPhase
        LastCompleted = $lastCompleted
        IsComplete    = ($total -gt 0 -and $completed -eq $total)
    }
}

function Get-NextStep {
    [CmdletBinding(DefaultParameterSetName = 'Metadata')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Metadata')]
        [object]$Metadata,

        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [string]$Path,

        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [string]$RepoRoot,

        [switch]$HasUncommittedChanges
    )

    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        $Metadata = Get-PlanMetadata -Path $Path -RepoRoot $RepoRoot
    }

    $steps = @($Metadata.Steps)
    $completed = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($step in $steps) {
        if ($step.Status -eq 'x') { [void]$completed.Add($step.Id) }
    }

    $next = $null
    foreach ($step in $steps) {
        if ($step.Status -ne 'x') { $next = $step; break }
    }

    if (-not $next) {
        return [pscustomobject]@{
            Step                  = $null
            Id                    = $null
            Status                = $null
            IsHuman               = $false
            IsDiscovery           = $false
            Detail                = ''
            HasUncommittedChanges = [bool]$HasUncommittedChanges
            BlockedByAfter        = $false
            UnmetAfter            = @()
            IsComplete            = $true
        }
    }

    $unmet = @()
    foreach ($afterId in @($next.After)) {
        if (-not $completed.Contains($afterId)) { $unmet += , $afterId }
    }

    $isDiscovery = ($next.Body -match '\[discovery\]')
    $detail = if ($next.PSObject.Properties['Detail']) { [string]$next.Detail } else { '' }

    return [pscustomobject]@{
        Step                  = $next
        Id                    = $next.Id
        Status                = $next.Status
        IsHuman               = ($next.Role -eq 'human')
        IsDiscovery           = [bool]$isDiscovery
        Detail                = $detail
        HasUncommittedChanges = [bool]$HasUncommittedChanges
        BlockedByAfter        = ($unmet.Count -gt 0)
        UnmetAfter            = $unmet
        IsComplete            = $false
    }
}

function Get-EpicRollup {
    <#
    .SYNOPSIS
    Rolls child-plan progress up to the epic and selects the next unblocked child.

    .DESCRIPTION
    Membership comes from the `<!-- epic: <id> -->` header marker in each child plan (active and
    archived), ordering from each child's `<!-- depends-on: ... -->` marker. A child counts as complete
    when every step is `[x]` or the plan has been archived — archival is the terminal state of the
    workflow, so a dependent must not stay blocked behind it.

    Dependency resolution is fail-closed: a `depends-on` token that resolves to no plan, or to more than
    one, blocks the child and is reported rather than silently ignored.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$EpicId,

        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [object[]]$Inventory
    )

    $repoRootPath = [System.IO.Path]::GetFullPath($RepoRoot)
    if (-not $PSBoundParameters.ContainsKey('Inventory')) {
        $Inventory = @(Get-PlanInventory -RepoRoot $repoRootPath)
    }

    $epicIdLower = $EpicId.Trim().ToLowerInvariant()
    $members = @($Inventory |
        Where-Object { $_.EpicId -and $_.EpicId.ToLowerInvariant() -eq $epicIdLower } |
        Sort-Object @{ Expression = { $_.Date } }, @{ Expression = { $_.Id } })

    $records = [System.Collections.Generic.List[object]]::new()
    # Completion is cached per plan id because a `depends-on` may point at a plan outside the epic; the
    # dependency's own state decides, never its membership.
    $completionCache = @{}

    foreach ($member in $members) {
        $planFile = Join-Path $member.Path 'plan.md'
        $metadata = Get-PlanMetadata -Path $planFile -RepoRoot $repoRootPath
        $progress = Get-PlanProgress -Metadata $metadata
        $markers = Get-PlanHeaderMarkers -Path $planFile
        $next = Get-NextStep -Metadata $metadata
        $isComplete = ($progress.IsComplete -or $member.IsArchived)
        $completionCache[$member.Id.ToLowerInvariant()] = $isComplete

        $records.Add([pscustomobject]@{
            Id            = $member.Id
            Slug          = $member.Slug
            FolderName    = $member.FolderName
            Path          = $member.Path
            PlanFile      = $planFile
            IsArchived    = $member.IsArchived
            IsComplete    = $isComplete
            DependsOn     = @($markers.DependsOn)
            Progress      = $progress
            NextStepId    = $next.Id
            NextStepHuman = $next.IsHuman
        })
    }

    $resolved = [System.Collections.Generic.List[object]]::new()
    foreach ($record in $records) {
        $unmet = [System.Collections.Generic.List[string]]::new()
        $unknown = [System.Collections.Generic.List[string]]::new()
        foreach ($token in $record.DependsOn) {
            $dependency = $null
            try {
                $dependency = Resolve-Plan -Reference $token -RepoRoot $repoRootPath -Inventory $Inventory
            }
            catch {
                $unknown.Add($token)
                continue
            }
            $dependencyKey = $dependency.Id.ToLowerInvariant()
            if (-not $completionCache.ContainsKey($dependencyKey)) {
                $dependencyPlanFile = Join-Path $dependency.Path 'plan.md'
                if (-not (Test-Path -LiteralPath $dependencyPlanFile -PathType Leaf)) {
                    $unknown.Add($token)
                    continue
                }
                $dependencyProgress = Get-PlanProgress -Metadata (Get-PlanMetadata -Path $dependencyPlanFile -RepoRoot $repoRootPath)
                $completionCache[$dependencyKey] = ($dependencyProgress.IsComplete -or $dependency.IsArchived)
            }
            if (-not $completionCache[$dependencyKey]) {
                $unmet.Add($dependency.Id)
            }
        }

        $resolved.Add([pscustomobject]@{
            Id             = $record.Id
            Slug           = $record.Slug
            FolderName     = $record.FolderName
            Path           = $record.Path
            PlanFile       = $record.PlanFile
            IsArchived     = $record.IsArchived
            IsComplete     = $record.IsComplete
            DependsOn      = @($record.DependsOn)
            UnmetDependsOn = $unmet.ToArray()
            UnknownDependsOn = $unknown.ToArray()
            IsBlocked      = (-not $record.IsComplete -and ($unmet.Count -gt 0 -or $unknown.Count -gt 0))
            Progress       = $record.Progress
            NextStepId     = $record.NextStepId
            NextStepHuman  = $record.NextStepHuman
        })
    }

    $nextChild = $null
    foreach ($record in $resolved) {
        if (-not $record.IsComplete -and -not $record.IsBlocked) { $nextChild = $record; break }
    }

    $totalSteps = 0
    $completedSteps = 0
    foreach ($record in $resolved) {
        $totalSteps += $record.Progress.Total
        $completedSteps += $record.Progress.Completed
    }

    return [pscustomobject]@{
        EpicId          = $epicIdLower
        Children        = $resolved.ToArray()
        ChildCount      = $resolved.Count
        CompleteCount   = @($resolved | Where-Object { $_.IsComplete }).Count
        BlockedCount    = @($resolved | Where-Object { $_.IsBlocked }).Count
        TotalSteps      = $totalSteps
        CompletedSteps  = $completedSteps
        Percent         = if ($totalSteps -gt 0) { [math]::Round(($completedSteps / $totalSteps) * 100, 1) } else { 0 }
        NextChild       = $nextChild
        IsComplete      = ($resolved.Count -gt 0 -and @($resolved | Where-Object { $_.IsComplete }).Count -eq $resolved.Count)
    }
}

function Get-TypedEvidenceMarkers {
    <#
    .SYNOPSIS
    Extracts the closed-vocabulary typed evidence markers from an acceptance-criteria cell.

    .DESCRIPTION
    The closed vocabulary is `test:<TestId>`, `file:<path>#<assertion>`, `review:cr|dr`, and
    `arch:<ContractId>`. Pure string parsing (no execution). A `·`-separated segment that is marker-SHAPED
    (`<prefix>:<value>`) but whose prefix is NOT in the closed set is surfaced VERBATIM so the evaluator
    fails loud on it — a stale installed bundle that does not recognize `arch:` must BLOCK rather than
    silently drop the marker and false-green (RISK-12).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AcceptanceCriteria
    )

    $markers = [System.Collections.Generic.List[string]]::new()
    $segments = $AcceptanceCriteria.Split('·')
    foreach ($segment in $segments) {
        $trimmed = $segment.Trim().Trim('`').Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            continue
        }

        $matched = $false

        foreach ($testMatch in [regex]::Matches($trimmed, 'test:[^\s`|·]+')) {
            $markers.Add($testMatch.Value.Trim())
            $matched = $true
        }

        foreach ($reviewMatch in [regex]::Matches($trimmed, 'review:(?:cr|dr)')) {
            $markers.Add($reviewMatch.Value.Trim())
            $matched = $true
        }

        foreach ($archMatch in [regex]::Matches($trimmed, 'arch:[^\s`|·#]+')) {
            $markers.Add($archMatch.Value.Trim())
            $matched = $true
        }

        foreach ($fileMatch in [regex]::Matches($trimmed, 'file:[^#\s`|·]+#.+$')) {
            $value = $fileMatch.Value.Trim().Trim('`').Trim()
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                $markers.Add($value)
                $matched = $true
            }
        }

        # Fail-loud on an unrecognized typed-marker prefix: a marker-shaped token (`<prefix>:<value>`) that no
        # known extractor matched is surfaced verbatim so the evaluator flags it as unknown. Unanchored (like the
        # known extractors) so an unknown marker with surrounding text is still caught, never silently dropped.
        if (-not $matched) {
            foreach ($unknownMatch in [regex]::Matches($trimmed, '[a-z][a-z-]*:[^\s`|·]+')) {
                $markers.Add($unknownMatch.Value.Trim())
            }
        }
    }

    return , $markers.ToArray()
}

Export-ModuleMember -Function Get-PlanMetadata, Get-PlanInventory, Get-EpicInventory, Resolve-Epic, Get-EpicRollup, New-PlanId, Resolve-Plan, Get-PlanProgress, Get-PlanHeaderMarkers, Get-NextStep, Get-TypedEvidenceMarkers, Get-PlanLayout, Resolve-PlanAssetPath, Resolve-PlanSection, Get-PlanSectionRecord, Remove-FencedCodeBlocks, Split-MarkdownTableCells
