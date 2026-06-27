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

function Get-PlanMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$RepoRoot
    )

    $fullPath = (Resolve-Path -LiteralPath $Path).Path
    $repoRootPath = [System.IO.Path]::GetFullPath($RepoRoot)
    $content = Get-Content -LiteralPath $fullPath -Raw
    $normalized = $content -replace "`r`n", "`n"
    $allLines = $normalized.Split("`n")
    $lines = Remove-FencedCodeBlocks -Lines $allLines

    $inRequirements = $false
    $inRisks = $false
    $currentPhase = ''
    $phaseSteps = @{}
    $requirements = @{}
    $risks = @{}
    $steps = [System.Collections.Generic.List[object]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()

    foreach ($line in $lines) {
        if ($line -match '^\s*##\s+Requirements\b') {
            $inRequirements = $true
            $inRisks = $false
            continue
        }

        if ($line -match '^\s*##\s+Risks\b') {
            $inRequirements = $false
            $inRisks = $true
            continue
        }

        if ($line -match '^\s*##\s+') {
            $inRequirements = $false
            $inRisks = $false
            $currentPhase = $line.Trim()
            if ($currentPhase -match '^##\s+Phase\s+\d+:\s+') {
                $phaseSteps[$currentPhase] = [System.Collections.Generic.List[object]]::new()
            }
            continue
        }

        if ($inRequirements -and $line.Trim().StartsWith('|')) {
            $cells = Split-MarkdownTableCells -Row $line
            if ($cells.Count -lt 4 -or $cells[0] -eq 'ID' -or $cells[0] -eq '----') {
                continue
            }

            if ($cells[0] -match '^REQ-(?<id>\d+)$') {
                $requirements[$cells[0]] = [pscustomobject]@{
                    Id = $cells[0]
                    Number = [int]$Matches.id
                    AcceptanceCriteria = $cells[2]
                }
            }
            continue
        }

        if ($inRisks -and $line.Trim().StartsWith('|')) {
            $cells = Split-MarkdownTableCells -Row $line
            if ($cells.Count -lt 2 -or $cells[0] -eq 'ID' -or $cells[0] -eq '----') {
                continue
            }

            if ($cells[0] -match '^RISK-(?<id>\d+)$') {
                $risks[$cells[0]] = [int]$Matches.id
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
            }
            $steps.Add($step)
            if ($phaseSteps.ContainsKey($currentPhase)) {
                $phaseSteps[$currentPhase].Add($step)
            }
            continue
        }
    }

    $sizeBytes = [System.Text.Encoding]::UTF8.GetByteCount($content)
    if ($sizeBytes -ge 20480 -or $allLines.Length -ge 400) {
        $warnings.Add("Plan size warning: ${sizeBytes} bytes / $($allLines.Length) lines (warn threshold 20KB/400).")
    }
    if ($sizeBytes -ge 35840 -or $allLines.Length -ge 700) {
        $warnings.Add("Plan size warning: ${sizeBytes} bytes / $($allLines.Length) lines (block threshold 35KB/700 is advisory in this validator).")
    }

    return [pscustomobject]@{
        PlanPath = $fullPath
        RepoRoot = $repoRootPath
        Content = $content
        Lines = $lines
        AllLines = $allLines
        Requirements = $requirements
        Risks = $risks
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
        if (Test-Path -LiteralPath $planFile) {
            $raw = Get-Content -LiteralPath $planFile -Raw
            if ($raw -match '<!--\s*plan-id:\s*(?<id>[0-9a-fA-F]{3,})\s*-->') {
                $anchorId = $Matches.id.ToLowerInvariant()
            }
        }

        $canonicalId = if ($anchorId) { $anchorId } else { $folderId }

        $inventory.Add([pscustomobject]@{
            Id = $canonicalId
            FolderId = $folderId
            AnchorId = $anchorId
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

    return [pscustomobject]@{
        Step                  = $next
        Id                    = $next.Id
        Status                = $next.Status
        IsHuman               = ($next.Role -eq 'human')
        IsDiscovery           = [bool]$isDiscovery
        HasUncommittedChanges = [bool]$HasUncommittedChanges
        BlockedByAfter        = ($unmet.Count -gt 0)
        UnmetAfter            = $unmet
        IsComplete            = $false
    }
}

Export-ModuleMember -Function Get-PlanMetadata, Get-PlanInventory, New-PlanId, Resolve-Plan, Get-PlanProgress, Get-PlanHeaderMarkers, Get-NextStep
