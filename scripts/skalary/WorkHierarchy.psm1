#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'PlanState.psm1') -Force -DisableNameChecking

$script:ProjectionSchema = 'skalary/work-hierarchy-projection@1'
$script:ProviderSchema = 'skalary/work-hierarchy-provider@1'
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
    New-WorkHierarchyProvider, Assert-WorkHierarchyProvider, `
    Invoke-WorkHierarchyProviderRead, Invoke-WorkHierarchyProviderWrite
