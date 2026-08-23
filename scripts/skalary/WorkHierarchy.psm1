#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'PlanState.psm1') -Force -DisableNameChecking

$script:ProjectionSchema = 'skalary/work-hierarchy-projection@1'
$script:ProviderSchema = 'skalary/work-hierarchy-provider@1'
$script:MappingSchema = 'skalary/work-hierarchy-mapping@1'
$script:DryRunSchema = 'skalary/work-hierarchy-dry-run@1'
$script:IntentSectionOrder = @(
    'Goal',
    'Desired outcome',
    'Success signals',
    'Non-goals',
    'Definition of done'
)

function ConvertTo-WorkHierarchyLf {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Value
    )

    return (($Value ?? '') -replace "`r`n", "`n" -replace "`r", "`n")
}

function Get-WorkHierarchyTitle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(Mandatory)]
        [string]$LocalId,

        [Parameter(Mandatory)]
        [string]$SourcePath
    )

    $normalized = ConvertTo-WorkHierarchyLf -Value $Content
    foreach ($line in $normalized.Split("`n")) {
        if ($line -notmatch '^#\s+(?<title>.+?)\s*$') { continue }

        $title = $Matches.title.Trim()
        $prefix = "^$([regex]::Escape($LocalId))\s*:\s*"
        $title = [regex]::Replace($title, $prefix, '', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ([string]::IsNullOrWhiteSpace($title)) {
            break
        }
        return $title
    }

    throw "Markdown source '$SourcePath' has no non-empty level-one title for '$LocalId'."
}

function Get-WorkHierarchySections {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Content
    )

    $sections = [ordered]@{}
    $current = $null
    foreach ($line in (ConvertTo-WorkHierarchyLf -Value $Content).Split("`n")) {
        if ($line -match '^##\s+(?<heading>.+?)\s*$') {
            $current = $Matches.heading.Trim()
            if (-not $sections.Contains($current)) {
                $sections[$current] = [System.Collections.Generic.List[string]]::new()
            }
            continue
        }

        if ($null -ne $current) {
            $sections[$current].Add($line)
        }
    }

    $result = [ordered]@{}
    foreach ($heading in $sections.Keys) {
        $result[$heading] = (($sections[$heading] -join "`n").Trim())
    }
    return $result
}

function New-WorkHierarchySectionLines {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Heading,

        [AllowEmptyString()]
        [string]$Content
    )

    return [string[]]@(
        "## $Heading"
        ''
        $(if ([string]::IsNullOrWhiteSpace($Content)) { '_Not specified._' } else { $Content.Trim() })
        ''
    )
}

function New-WorkHierarchyManagedBody {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('epic', 'plan')]
        [string]$Kind,

        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9-]+$')]
        [string]$LocalId,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [System.Collections.Generic.List[string]]$ContentLines
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("<!-- skalary:work-hierarchy:${Kind}:${LocalId}:start -->")
    $lines.AddRange($ContentLines)
    while ($lines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($lines[$lines.Count - 1])) {
        $lines.RemoveAt($lines.Count - 1)
    }
    $lines.Add("<!-- skalary:work-hierarchy:${Kind}:${LocalId}:end -->")
    return ($lines -join "`n")
}

function Get-WorkHierarchyPhase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Steps
    )

    $phaseByName = [ordered]@{}
    foreach ($step in $Steps) {
        $phaseName = ([string]$step.Phase) -replace '^##\s+', ''
        if ([string]::IsNullOrWhiteSpace($phaseName)) { continue }
        if (-not $phaseByName.Contains($phaseName)) {
            $phaseByName[$phaseName] = [System.Collections.Generic.List[object]]::new()
        }

        $phaseByName[$phaseName].Add([pscustomobject][ordered]@{
            id = [string]$step.Id
            title = (([string]$step.Body) -replace '\s+`[SML]`\s*$', '').Trim()
            complete = ([string]$step.Status -eq 'x')
        })
    }

    $phases = [System.Collections.Generic.List[object]]::new()
    foreach ($phaseName in $phaseByName.Keys) {
        $phases.Add([pscustomobject][ordered]@{
            title = $phaseName
            steps = $phaseByName[$phaseName].ToArray()
        })
    }
    return $phases.ToArray()
}

function Get-WorkHierarchyRequirement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Requirements
    )

    return @(
        $Requirements.Values |
            Sort-Object @{ Expression = { $_.Number } }, @{ Expression = { $_.Id } } |
            ForEach-Object {
                [pscustomobject][ordered]@{
                    id = [string]$_.Id
                    requirement = [string]$_.Text
                    acceptance = [string]$_.AcceptanceCriteria
                }
            }
    )
}

function New-WorkHierarchyPlanBody {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LocalId,

        [Parameter(Mandatory)]
        $IntentSections,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Dependencies,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Phases,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Requirements
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($heading in $script:IntentSectionOrder) {
        $remoteHeading = if ($heading -eq 'Goal') { 'Purpose' } else { $heading }
        $content = if ($IntentSections.Contains($heading)) { [string]$IntentSections[$heading] } else { '' }
        $lines.AddRange([string[]](New-WorkHierarchySectionLines -Heading $remoteHeading -Content $content))
    }

    $lines.Add('## Dependencies')
    $lines.Add('')
    if ($Dependencies.Count -eq 0) {
        $lines.Add('_None._')
    }
    else {
        foreach ($dependency in $Dependencies) {
            $lines.Add("- ``$dependency``")
        }
    }
    $lines.Add('')

    $lines.Add('## Phases')
    $lines.Add('')
    if ($Phases.Count -eq 0) {
        $lines.Add('_None._')
        $lines.Add('')
    }
    else {
        foreach ($phase in $Phases) {
            $lines.Add("### $($phase.title)")
            $lines.Add('')
            foreach ($step in $phase.steps) {
                $check = if ($step.complete) { 'x' } else { ' ' }
                $lines.Add("- [$check] ``$($step.id)`` $($step.title)")
            }
            $lines.Add('')
        }
    }

    $lines.Add('## Acceptance criteria')
    $lines.Add('')
    if ($Requirements.Count -eq 0) {
        $lines.Add('_None._')
        $lines.Add('')
    }
    else {
        foreach ($requirement in $Requirements) {
            $lines.Add("### $($requirement.id)")
            $lines.Add('')
            $lines.Add($requirement.requirement)
            $lines.Add('')
            $lines.Add("**Acceptance:** $($requirement.acceptance)")
            $lines.Add('')
        }
    }

    return New-WorkHierarchyManagedBody -Kind plan -LocalId $LocalId -ContentLines $lines
}

function New-WorkHierarchyEpicBody {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LocalId,

        [AllowEmptyString()]
        [string]$Purpose,

        [Parameter(Mandatory)]
        [object[]]$Children
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.AddRange([string[]](New-WorkHierarchySectionLines -Heading 'Purpose' -Content $Purpose))
    $lines.Add('## Child plans')
    $lines.Add('')
    foreach ($child in $Children) {
        $lines.Add("- ``$($child.localId)`` - $($child.title)")
    }
    $lines.Add('')
    return New-WorkHierarchyManagedBody -Kind epic -LocalId $LocalId -ContentLines $lines
}

function New-WorkHierarchyProjection {
    <#
    .SYNOPSIS
    Projects one resolved local epic and its child plan assets into a stable work hierarchy.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Epic,

        [Parameter(Mandatory)]
        [string]$RepoRoot
    )

    $repoRootPath = (Resolve-Path -LiteralPath $RepoRoot).Path
    $epicRecord = Resolve-Epic -Reference $Epic -RepoRoot $repoRootPath
    if (-not (Test-Path -LiteralPath $epicRecord.EpicFile -PathType Leaf)) {
        throw "Resolved epic '$($epicRecord.Id)' has no epic.md at '$($epicRecord.EpicFile)'."
    }

    $inventory = @(Get-PlanInventory -RepoRoot $repoRootPath)
    $members = @(
        $inventory |
            Where-Object { $_.EpicId -and $_.EpicId -eq $epicRecord.Id }
    )
    if ($members.Count -eq 0) {
        throw "Resolved epic '$($epicRecord.Id)' has no child plans."
    }

    $childIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $memberById = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($member in $members) {
        if ([string]::Equals($member.Id, $epicRecord.Id, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Epic '$($epicRecord.Id)' and child plan '$($member.FolderName)' have the same canonical id."
        }
        if (-not $childIds.Add([string]$member.Id)) {
            throw "Epic '$($epicRecord.Id)' has more than one child plan with canonical id '$($member.Id)'."
        }
        $memberById.Add([string]$member.Id, $member)
    }
    $orderedChildIds = [string[]]@($childIds)
    [array]::Sort($orderedChildIds, [System.StringComparer]::Ordinal)
    $members = @($orderedChildIds | ForEach-Object { $memberById[$_] })

    $children = [System.Collections.Generic.List[object]]::new()
    $relations = [System.Collections.Generic.List[object]]::new()
    foreach ($member in $members) {
        $planPath = Join-Path $member.Path 'plan.md'
        if (-not (Test-Path -LiteralPath $planPath -PathType Leaf)) {
            throw "Epic '$($epicRecord.Id)' child '$($member.Id)' has no plan.md."
        }

        $planContent = Get-Content -LiteralPath $planPath -Raw
        $metadata = Get-PlanMetadata -Path $planPath -RepoRoot $repoRootPath
        $markers = Get-PlanHeaderMarkers -Path $planPath
        $dependencySet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($dependencyReference in @($markers.DependsOn)) {
            $dependency = try {
                Resolve-Plan -Reference $dependencyReference -RepoRoot $repoRootPath -Inventory $inventory
            }
            catch {
                throw "Child plan '$($member.Id)' has unresolved dependency '$dependencyReference': $($_.Exception.Message)"
            }
            if ($dependency.Id -eq $member.Id) {
                throw "Child plan '$($member.Id)' cannot depend on itself."
            }
            [void]$dependencySet.Add([string]$dependency.Id)
        }
        $dependencies = [string[]]@($dependencySet)
        [array]::Sort($dependencies, [System.StringComparer]::Ordinal)

        $intentPath = Resolve-PlanAssetPath -PlanDir $member.Path -Kind Intent
        if (-not (Test-Path -LiteralPath $intentPath -PathType Leaf)) {
            throw "Child plan '$($member.Id)' has no intent asset at '$intentPath'."
        }

        $phases = @(Get-WorkHierarchyPhase -Steps @($metadata.Steps))
        $requirements = @(Get-WorkHierarchyRequirement -Requirements $metadata.Requirements)
        $child = [pscustomobject][ordered]@{
            localId = [string]$member.Id
            kind = 'plan'
            title = Get-WorkHierarchyTitle -Content $planContent -LocalId $member.Id -SourcePath $planPath
            managedBody = New-WorkHierarchyPlanBody `
                -LocalId $member.Id `
                -IntentSections (Get-WorkHierarchySections -Content (Get-Content -LiteralPath $intentPath -Raw)) `
                -Dependencies $dependencies `
                -Phases $phases `
                -Requirements $requirements
            dependencies = $dependencies
            phases = $phases
            acceptanceCriteria = $requirements
        }
        $children.Add($child)
        $relations.Add([pscustomobject][ordered]@{
            kind = 'parent-child'
            sourceId = [string]$epicRecord.Id
            targetId = [string]$member.Id
            targetInEpic = $true
        })
        foreach ($dependency in $dependencies) {
            $relations.Add([pscustomobject][ordered]@{
                kind = 'depends-on'
                sourceId = [string]$member.Id
                targetId = $dependency
                targetInEpic = $childIds.Contains($dependency)
            })
        }
    }

    $epicContent = Get-Content -LiteralPath $epicRecord.EpicFile -Raw
    $epicSections = Get-WorkHierarchySections -Content $epicContent
    $purpose = if ($epicSections.Contains('Goal')) { [string]$epicSections['Goal'] } else { '' }
    return [pscustomobject][ordered]@{
        schema = $script:ProjectionSchema
        epic = [pscustomobject][ordered]@{
            localId = [string]$epicRecord.Id
            kind = 'epic'
            title = Get-WorkHierarchyTitle -Content $epicContent -LocalId $epicRecord.Id -SourcePath $epicRecord.EpicFile
            managedBody = New-WorkHierarchyEpicBody -LocalId $epicRecord.Id -Purpose $purpose -Children $children.ToArray()
        }
        children = $children.ToArray()
        relations = $relations.ToArray()
    }
}

function ConvertTo-WorkHierarchyProjectionJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $Projection
    )

    process {
        if ([string]$Projection.schema -ne $script:ProjectionSchema) {
            throw "Projection schema must be '$script:ProjectionSchema'."
        }
        return (ConvertTo-Json -InputObject $Projection -Depth 30)
    }
}

function Get-WorkHierarchyDigest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Value
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    return ([System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes))).ToLowerInvariant()
}

function Get-WorkHierarchyObjectValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $InputObject,

        [Parameter(Mandatory)]
        [string]$Name,

        [switch]$Required
    )

    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) {
            return $InputObject[$Name]
        }
    }
    else {
        $property = $InputObject.PSObject.Properties[$Name]
        if ($null -ne $property) {
            return $property.Value
        }
    }

    if ($Required) {
        throw "Work hierarchy value is missing required property '$Name'."
    }
    return $null
}

function Get-WorkHierarchyMappingItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $MappingItems,

        [Parameter(Mandatory)]
        [string]$LocalId
    )

    return Get-WorkHierarchyObjectValue -InputObject $MappingItems -Name $LocalId
}

function Get-WorkHierarchyManagedRegion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Body,

        [Parameter(Mandatory)]
        [ValidateSet('epic', 'plan')]
        [string]$Kind,

        [Parameter(Mandatory)]
        [string]$LocalId
    )

    $markerPattern = '<!--\s*skalary:work-hierarchy:(?<kind>epic|plan):(?<id>[A-Za-z0-9-]+):(?<edge>start|end)\s*-->'
    $markerMatches = [regex]::Matches($Body, $markerPattern)
    $hasMarkerPrefix = [regex]::IsMatch($Body, '<!--\s*skalary:work-hierarchy:')
    if ($markerMatches.Count -eq 0) {
        return [pscustomobject][ordered]@{
            status = $(if ($hasMarkerPrefix) { 'conflict' } else { 'missing' })
            reason = $(if ($hasMarkerPrefix) { 'malformed-marker' } else { 'managed-region-missing' })
            prefix = ''
            managedBody = ''
            suffix = ''
        }
    }
    if ($markerMatches.Count -ne 2) {
        return [pscustomobject][ordered]@{
            status = 'conflict'
            reason = 'duplicate-or-nested-marker'
            prefix = ''
            managedBody = ''
            suffix = ''
        }
    }
    $unmatchedMarkerText = [regex]::Replace($Body, $markerPattern, '')
    if ([regex]::IsMatch($unmatchedMarkerText, '<!--\s*skalary:work-hierarchy:')) {
        return [pscustomobject][ordered]@{
            status = 'conflict'
            reason = 'malformed-marker'
            prefix = ''
            managedBody = ''
            suffix = ''
        }
    }

    $start = $markerMatches[0]
    $end = $markerMatches[1]
    if (
        $start.Groups['edge'].Value -ne 'start' -or
        $end.Groups['edge'].Value -ne 'end' -or
        $start.Groups['kind'].Value -ne $Kind -or
        $end.Groups['kind'].Value -ne $Kind -or
        $start.Groups['id'].Value -cne $LocalId -or
        $end.Groups['id'].Value -cne $LocalId
    ) {
        return [pscustomobject][ordered]@{
            status = 'conflict'
            reason = 'mismatched-marker'
            prefix = ''
            managedBody = ''
            suffix = ''
        }
    }

    $endIndex = $end.Index + $end.Length
    return [pscustomobject][ordered]@{
        status = 'present'
        reason = ''
        prefix = $Body.Substring(0, $start.Index)
        managedBody = $Body.Substring($start.Index, $endIndex - $start.Index)
        suffix = $Body.Substring($endIndex)
    }
}

function Get-WorkHierarchyFieldDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Field,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Desired,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Remote,

        [Parameter(Mandatory)]
        [string]$BaselineHash
    )

    if ($BaselineHash -notmatch '^[0-9a-f]{64}$') {
        return [pscustomobject]@{ state = 'refuse'; reason = "$Field-baseline-invalid" }
    }

    $desiredHash = Get-WorkHierarchyDigest -Value $Desired
    $remoteHash = Get-WorkHierarchyDigest -Value $Remote
    if ($desiredHash -eq $remoteHash) {
        return [pscustomobject]@{ state = 'same'; reason = '' }
    }
    if ($remoteHash -eq $BaselineHash) {
        return [pscustomobject]@{ state = 'update'; reason = "$Field-local-change" }
    }
    if ($desiredHash -eq $BaselineHash) {
        return [pscustomobject]@{ state = 'refuse'; reason = "$Field-remote-change" }
    }
    return [pscustomobject]@{ state = 'refuse'; reason = "$Field-concurrent-change" }
}

function New-WorkHierarchyAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('create', 'update', 'link', 'no-op', 'refuse')]
        [string]$Kind,

        [Parameter(Mandatory)]
        [string]$Subject,

        [Parameter(Mandatory)]
        [string]$Reason,

        $Detail
    )

    return [pscustomobject][ordered]@{
        kind = $Kind
        subject = $Subject
        reason = $Reason
        detail = $Detail
    }
}

function New-WorkHierarchyDryRun {
    <#
    .SYNOPSIS
    Reads mapped provider state and emits a deterministic mutation-free synchronization action set.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Projection,

        [Parameter(Mandatory)]
        [string]$Repository,

        [Parameter(Mandatory)]
        $Mapping,

        [Parameter(Mandatory)]
        $Provider
    )

    Assert-WorkHierarchyProvider -Provider $Provider
    if ([string](Get-WorkHierarchyObjectValue -InputObject $Projection -Name schema -Required) -ne $script:ProjectionSchema) {
        throw "Projection schema must be '$script:ProjectionSchema'."
    }
    if ([string](Get-WorkHierarchyObjectValue -InputObject $Mapping -Name schema -Required) -ne $script:MappingSchema) {
        throw "Mapping schema must be '$script:MappingSchema'."
    }
    $mappingRepository = [string](Get-WorkHierarchyObjectValue -InputObject $Mapping -Name repository -Required)
    if (-not [System.StringComparer]::OrdinalIgnoreCase.Equals($mappingRepository, $Repository)) {
        throw "Mapping repository does not match '$Repository'."
    }
    $mappingItems = Get-WorkHierarchyObjectValue -InputObject $Mapping -Name items -Required

    $desiredItems = @($Projection.epic) + @($Projection.children)
    $desiredById = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($item in $desiredItems) {
        $desiredById.Add([string]$item.localId, $item)
    }

    $requiredMappingIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($item in $desiredItems) {
        if ($null -ne (Get-WorkHierarchyMappingItem -MappingItems $mappingItems -LocalId $item.localId)) {
            [void]$requiredMappingIds.Add([string]$item.localId)
        }
    }
    foreach ($relation in @($Projection.relations | Where-Object kind -eq 'depends-on')) {
        if ($null -ne (Get-WorkHierarchyMappingItem -MappingItems $mappingItems -LocalId $relation.targetId)) {
            [void]$requiredMappingIds.Add([string]$relation.targetId)
        }
    }

    $mappingById = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    $remoteById = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    $providerIds = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    $ambiguousMappingIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $mappingRefusals = [System.Collections.Generic.List[object]]::new()
    $orderedRequiredIds = [string[]]@($requiredMappingIds)
    [array]::Sort($orderedRequiredIds, [System.StringComparer]::Ordinal)
    foreach ($localId in $orderedRequiredIds) {
        $entry = Get-WorkHierarchyMappingItem -MappingItems $mappingItems -LocalId $localId
        $number = [int](Get-WorkHierarchyObjectValue -InputObject $entry -Name number -Required)
        $providerId = [string](Get-WorkHierarchyObjectValue -InputObject $entry -Name providerId -Required)
        if ($number -le 0 -or $providerId -notmatch '^[1-9][0-9]*$') {
            $mappingRefusals.Add((New-WorkHierarchyAction -Kind refuse -Subject "item:$localId" -Reason 'mapping-identity-invalid' -Detail $null))
            continue
        }
        if ($providerIds.ContainsKey($providerId)) {
            [void]$ambiguousMappingIds.Add($providerIds[$providerId])
            [void]$ambiguousMappingIds.Add($localId)
            continue
        }
        $providerIds.Add($providerId, $localId)
        $mappingById.Add($localId, $entry)

        $remote = Invoke-WorkHierarchyProviderRead -Provider $Provider -Request ([pscustomobject][ordered]@{
            kind = 'issue'
            repository = $Repository
            number = $number
        })
        if ([string]$remote.providerId -cne $providerId -or [int]$remote.number -ne $number) {
            $mappingRefusals.Add((New-WorkHierarchyAction -Kind refuse -Subject "item:$localId" -Reason 'mapping-remote-identity-mismatch' -Detail ([pscustomobject]@{
                expectedProviderId = $providerId
                expectedNumber = $number
                actualProviderId = [string]$remote.providerId
                actualNumber = [int]$remote.number
            })))
            continue
        }
        $remoteById.Add($localId, $remote)
    }
    $orderedAmbiguousIds = [string[]]@($ambiguousMappingIds)
    [array]::Sort($orderedAmbiguousIds, [System.StringComparer]::Ordinal)
    foreach ($localId in $orderedAmbiguousIds) {
        $mappingRefusals.Add((New-WorkHierarchyAction -Kind refuse -Subject "item:$localId" -Reason 'mapping-identity-ambiguous' -Detail $null))
    }

    $actions = [System.Collections.Generic.List[object]]::new()
    $refusedItems = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $mappingRefusalById = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($refusal in $mappingRefusals) {
        $localId = ([string]$refusal.subject).Substring('item:'.Length)
        if (-not $mappingRefusalById.ContainsKey($localId)) {
            $mappingRefusalById.Add($localId, $refusal)
        }
        [void]$refusedItems.Add($localId)
    }

    foreach ($desired in $desiredItems) {
        $localId = [string]$desired.localId
        $subject = "item:$localId"
        if ($mappingRefusalById.ContainsKey($localId)) {
            $actions.Add($mappingRefusalById[$localId])
            continue
        }
        $mappingEntry = Get-WorkHierarchyMappingItem -MappingItems $mappingItems -LocalId $localId
        if ($null -eq $mappingEntry) {
            $actions.Add((New-WorkHierarchyAction -Kind create -Subject $subject -Reason 'mapping-missing' -Detail ([pscustomobject][ordered]@{
                itemKind = [string]$desired.kind
                title = [string]$desired.title
                managedBody = [string]$desired.managedBody
            })))
            continue
        }
        if ($refusedItems.Contains($localId) -or -not $remoteById.ContainsKey($localId)) {
            continue
        }

        $remote = $remoteById[$localId]
        $region = Get-WorkHierarchyManagedRegion -Body ([string]$remote.body) -Kind $desired.kind -LocalId $localId
        if ($region.status -ne 'present') {
            $actions.Add((New-WorkHierarchyAction -Kind refuse -Subject $subject -Reason $region.reason -Detail $null))
            [void]$refusedItems.Add($localId)
            continue
        }

        $titleDecision = Get-WorkHierarchyFieldDecision `
            -Field title `
            -Desired ([string]$desired.title) `
            -Remote ([string]$remote.title) `
            -BaselineHash ([string](Get-WorkHierarchyObjectValue -InputObject $mappingEntry -Name titleHash))
        $bodyDecision = Get-WorkHierarchyFieldDecision `
            -Field managed-body `
            -Desired ([string]$desired.managedBody) `
            -Remote ([string]$region.managedBody) `
            -BaselineHash ([string](Get-WorkHierarchyObjectValue -InputObject $mappingEntry -Name managedBodyHash))
        $refusalReasons = @(@($titleDecision, $bodyDecision) | Where-Object state -eq 'refuse' | ForEach-Object reason)
        if ($refusalReasons.Count -gt 0) {
            $actions.Add((New-WorkHierarchyAction -Kind refuse -Subject $subject -Reason ($refusalReasons -join ',') -Detail $null))
            [void]$refusedItems.Add($localId)
            continue
        }

        if ($titleDecision.state -eq 'update' -or $bodyDecision.state -eq 'update') {
            $actions.Add((New-WorkHierarchyAction -Kind update -Subject $subject -Reason 'local-projection-changed' -Detail ([pscustomobject][ordered]@{
                number = [int]$remote.number
                providerId = [string]$remote.providerId
                title = [string]$desired.title
                body = "$($region.prefix)$($desired.managedBody)$($region.suffix)"
                expectedTitleHash = Get-WorkHierarchyDigest -Value ([string]$remote.title)
                expectedManagedBodyHash = Get-WorkHierarchyDigest -Value ([string]$region.managedBody)
            })))
        }
        else {
            $actions.Add((New-WorkHierarchyAction -Kind no-op -Subject $subject -Reason 'item-current' -Detail $null))
        }
    }

    $externalRefusalIds = [string[]]@($mappingRefusalById.Keys | Where-Object { -not $desiredById.ContainsKey($_) })
    [array]::Sort($externalRefusalIds, [System.StringComparer]::Ordinal)
    foreach ($localId in $externalRefusalIds) {
        $actions.Add($mappingRefusalById[$localId])
    }

    $subIssueIds = $null
    if ($mappingById.ContainsKey([string]$Projection.epic.localId) -and -not $refusedItems.Contains([string]$Projection.epic.localId)) {
        $epicRemote = $remoteById[[string]$Projection.epic.localId]
        $subIssues = @(Invoke-WorkHierarchyProviderRead -Provider $Provider -Request ([pscustomobject][ordered]@{
            kind = 'sub-issues'
            repository = $Repository
            number = [int]$epicRemote.number
        }))
        $subIssueIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($subIssue in $subIssues) {
            [void]$subIssueIds.Add([string]$subIssue.providerId)
        }
    }

    $blockedByCache = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($relation in @($Projection.relations)) {
        $subject = "relation:$($relation.kind):$($relation.sourceId):$($relation.targetId)"
        if ($refusedItems.Contains([string]$relation.sourceId) -or $refusedItems.Contains([string]$relation.targetId)) {
            $actions.Add((New-WorkHierarchyAction -Kind refuse -Subject $subject -Reason 'related-item-refused' -Detail $null))
            continue
        }

        $sourceEntry = Get-WorkHierarchyMappingItem -MappingItems $mappingItems -LocalId $relation.sourceId
        $targetEntry = Get-WorkHierarchyMappingItem -MappingItems $mappingItems -LocalId $relation.targetId
        if ($relation.kind -eq 'depends-on' -and $null -eq $targetEntry -and -not [bool]$relation.targetInEpic) {
            $actions.Add((New-WorkHierarchyAction -Kind refuse -Subject $subject -Reason 'dependency-target-unmapped' -Detail $null))
            continue
        }

        if ($null -eq $sourceEntry -or $null -eq $targetEntry) {
            $actions.Add((New-WorkHierarchyAction -Kind link -Subject $subject -Reason 'relation-missing-after-create' -Detail ([pscustomobject][ordered]@{
                relationKind = [string]$relation.kind
                sourceId = [string]$relation.sourceId
                targetId = [string]$relation.targetId
            })))
            continue
        }

        $targetProviderId = [string](Get-WorkHierarchyObjectValue -InputObject $targetEntry -Name providerId -Required)
        if ($relation.kind -eq 'parent-child') {
            $linked = $null -ne $subIssueIds -and $subIssueIds.Contains($targetProviderId)
        }
        else {
            $sourceId = [string]$relation.sourceId
            if (-not $blockedByCache.ContainsKey($sourceId)) {
                $sourceRemote = $remoteById[$sourceId]
                $blockedBy = @(Invoke-WorkHierarchyProviderRead -Provider $Provider -Request ([pscustomobject][ordered]@{
                    kind = 'blocked-by'
                    repository = $Repository
                    number = [int]$sourceRemote.number
                }))
                $ids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
                foreach ($blockingIssue in $blockedBy) {
                    [void]$ids.Add([string]$blockingIssue.providerId)
                }
                $blockedByCache.Add($sourceId, $ids)
            }
            $linked = $blockedByCache[$sourceId].Contains($targetProviderId)
        }

        $actions.Add((New-WorkHierarchyAction `
            -Kind $(if ($linked) { 'no-op' } else { 'link' }) `
            -Subject $subject `
            -Reason $(if ($linked) { 'relation-current' } else { 'relation-missing' }) `
            -Detail $(if ($linked) { $null } else {
                [pscustomobject][ordered]@{
                    relationKind = [string]$relation.kind
                    sourceId = [string]$relation.sourceId
                    targetId = [string]$relation.targetId
                }
            })))
    }

    $projectionJson = ConvertTo-WorkHierarchyProjectionJson -Projection $Projection
    $actionsJson = ConvertTo-Json -InputObject $actions.ToArray() -Depth 30 -Compress
    return [pscustomobject][ordered]@{
        schema = $script:DryRunSchema
        repository = $Repository
        projectionDigest = Get-WorkHierarchyDigest -Value $projectionJson
        actionDigest = Get-WorkHierarchyDigest -Value $actionsJson
        hasChanges = @($actions | Where-Object kind -in @('create', 'update', 'link')).Count -gt 0
        hasRefusals = @($actions | Where-Object kind -eq 'refuse').Count -gt 0
        actions = $actions.ToArray()
    }
}

function ConvertTo-WorkHierarchyDryRunText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $DryRun
    )

    process {
        if ([string]$DryRun.schema -ne $script:DryRunSchema) {
            throw "Dry run schema must be '$script:DryRunSchema'."
        }
        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add("Work hierarchy dry run: $($DryRun.repository)")
        foreach ($action in @($DryRun.actions)) {
            $lines.Add(("[{0}] {1} - {2}" -f ([string]$action.kind).ToUpperInvariant(), $action.subject, $action.reason))
        }
        $lines.Add("Action digest: $($DryRun.actionDigest)")
        return ($lines -join "`n")
    }
}

function New-WorkHierarchyProvider {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[a-z][a-z0-9-]*$')]
        [string]$Name,

        [Parameter(Mandatory)]
        [scriptblock]$Read,

        [Parameter(Mandatory)]
        [scriptblock]$Write
    )

    return [pscustomobject][ordered]@{
        schema = $script:ProviderSchema
        name = $Name
        read = $Read
        write = $Write
    }
}

function Assert-WorkHierarchyProvider {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Provider
    )

    if (
        [string]$Provider.schema -ne $script:ProviderSchema -or
        $Provider.read -isnot [scriptblock] -or
        $Provider.write -isnot [scriptblock]
    ) {
        throw "Provider must implement '$script:ProviderSchema' with read and write handlers."
    }
}

function Invoke-WorkHierarchyProviderRead {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Provider,

        [Parameter(Mandatory)]
        $Request
    )

    Assert-WorkHierarchyProvider -Provider $Provider
    return & $Provider.read $Request
}

function Invoke-WorkHierarchyProviderWrite {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Provider,

        [Parameter(Mandatory)]
        $Operation
    )

    Assert-WorkHierarchyProvider -Provider $Provider
    return & $Provider.write $Operation
}

Export-ModuleMember -Function `
    New-WorkHierarchyProjection, ConvertTo-WorkHierarchyProjectionJson, `
    Get-WorkHierarchyDigest, Get-WorkHierarchyManagedRegion, `
    New-WorkHierarchyDryRun, ConvertTo-WorkHierarchyDryRunText, `
    New-WorkHierarchyProvider, Assert-WorkHierarchyProvider, `
    Invoke-WorkHierarchyProviderRead, Invoke-WorkHierarchyProviderWrite
