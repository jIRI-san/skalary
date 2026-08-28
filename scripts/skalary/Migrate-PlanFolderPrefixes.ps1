#requires -Version 7.0
<#
.SYNOPSIS
    Inventories rollout-era hash-plan folders for optional prefix migration.
.DESCRIPTION
    The default path is a dry run: it inventories active and archived unprefixed hash-plan
    folders, validates every candidate before writing anything, and emits a deterministic
    old/new mapping. It never moves a plan folder.

    The mapping is the only accepted input to the explicit apply/resume path.
.EXAMPLE
    Migrate-PlanFolderPrefixes.ps1
.EXAMPLE
    Migrate-PlanFolderPrefixes.ps1 -MappingPath artifacts/plan-folder-prefix-migration.json
.EXAMPLE
    Migrate-PlanFolderPrefixes.ps1 -MappingPath artifacts/plan-folder-prefix-migration.json -Apply
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path,

    [string]$MappingPath,

    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'PlanState.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AtomicStore.psm1') -Force

$script:PathComparison = if ($IsWindows) {
    [System.StringComparison]::OrdinalIgnoreCase
}
else {
    [System.StringComparison]::Ordinal
}

function Test-PathWithinRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Root
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $fullRoot = [System.IO.Path]::GetFullPath($Root)
    $separator = [System.IO.Path]::DirectorySeparatorChar
    $prefix = $fullRoot.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    ) + $separator

    return $fullPath.StartsWith($prefix, $script:PathComparison)
}

function ConvertTo-RepoRelativePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$RepoRoot
    )

    return ([System.IO.Path]::GetRelativePath($RepoRoot, $Path) -replace '\\', '/')
}

function Resolve-ConfinedMappingPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$RepoRoot
    )

    $candidate = if ([System.IO.Path]::IsPathRooted($Path)) {
        [System.IO.Path]::GetFullPath($Path)
    }
    else {
        [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $Path))
    }

    if (-not (Test-PathWithinRoot -Path $candidate -Root $RepoRoot)) {
        throw "Mapping path '$candidate' must stay inside repository root '$RepoRoot'."
    }
    if ([System.IO.Path]::GetExtension($candidate) -ne '.json') {
        throw "Mapping path '$candidate' must use the .json extension."
    }

    $physicalRoot = Resolve-PhysicalRepoPath -Path $RepoRoot
    $physicalMapping = Resolve-PhysicalRepoPath -Path $candidate
    if (-not (Test-PathWithinRoot -Path $physicalMapping -Root $physicalRoot)) {
        throw "Mapping path '$candidate' escapes repository root '$RepoRoot' through a link or reparse point."
    }

    return $candidate
}

function Test-PhysicalDirectChild {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Parent
    )

    $physicalPath = Resolve-PhysicalRepoPath -Path $Path
    $physicalParent = Resolve-PhysicalRepoPath -Path $Parent
    return [string]::Equals(
        (Split-Path -Parent $physicalPath),
        $physicalParent,
        $script:PathComparison
    )
}

function Test-PhysicalPathWithinRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Root
    )

    $physicalPath = Resolve-PhysicalRepoPath -Path $Path
    $physicalRoot = Resolve-PhysicalRepoPath -Path $Root
    return Test-PathWithinRoot -Path $physicalPath -Root $physicalRoot
}

function Test-DirectoryEntryExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $parent = Split-Path -Parent $Path
    $name = Split-Path -Leaf $Path
    return @(
        Get-ChildItem -LiteralPath $parent -Force -ErrorAction Stop |
            Where-Object { [string]::Equals($_.Name, $name, $script:PathComparison) }
    ).Count -gt 0
}

function Get-MigrationTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Plan,

        [Parameter(Mandatory)]
        [string]$Prefix,

        [Parameter(Mandatory)]
        [string]$Parent
    )

    $folderName = "$Prefix-$($Plan.Date)-$($Plan.Id)-$($Plan.Slug)"
    return [System.IO.Path]::GetFullPath((Join-Path $Parent $folderName))
}

function Test-ReplaceableMapping {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Content
    )

    try {
        $existing = $Content | ConvertFrom-Json -Depth 20
    }
    catch {
        throw 'Existing mapping is not valid JSON; refusing to overwrite it.'
    }

    if ($null -eq $existing -or $existing -isnot [psobject]) {
        throw 'Existing mapping is not a migration mapping object; refusing to overwrite it.'
    }
    $propertyNames = @($existing.PSObject.Properties.Name)
    if ($propertyNames -notcontains 'schema' -or
        $propertyNames -notcontains 'mode' -or
        $propertyNames -notcontains 'entries') {
        throw 'Existing mapping is missing required schema, mode, or entries fields; refusing to overwrite it.'
    }
    if ([string]$existing.schema -ne 'skalary/plan-folder-prefix-migration@1') {
        throw "Existing mapping has unsupported schema '$($existing.schema)'; refusing to overwrite it."
    }
    if ([string]$existing.mode -eq 'apply') {
        throw 'Existing mapping records apply progress; refusing to overwrite resumable state.'
    }
    if ([string]$existing.mode -ne 'inventory') {
        throw "Existing mapping has unsupported mode '$($existing.mode)'; refusing to overwrite it."
    }
    $started = @($existing.entries | Where-Object { [string]$_.status -ne 'pending' })
    if ($started.Count -gt 0) {
        throw 'Existing mapping records apply progress; refusing to overwrite resumable state.'
    }

    return $true
}

function Get-RequiredMappingProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Context
    )

    if ($InputObject -isnot [psobject] -or
        @($InputObject.PSObject.Properties.Name) -notcontains $Name) {
        throw "$Context is missing required '$Name'."
    }

    return $InputObject.$Name
}

function Resolve-MappingEntryPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RelativePath,

        [Parameter(Mandatory)]
        [string]$ExpectedParent,

        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [Parameter(Mandatory)]
        [string]$Context
    )

    if ([string]::IsNullOrWhiteSpace($RelativePath) -or
        [System.IO.Path]::IsPathRooted($RelativePath) -or
        $RelativePath.Contains('\')) {
        throw "$Context path '$RelativePath' must be a normalized repository-relative path."
    }

    $fullPath = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $RelativePath))
    if (-not (Test-PathWithinRoot -Path $fullPath -Root $ExpectedParent) -or
        -not [string]::Equals(
            (Split-Path -Parent $fullPath),
            [System.IO.Path]::GetFullPath($ExpectedParent),
            $script:PathComparison
        ) -or
        -not [string]::Equals(
            (ConvertTo-RepoRelativePath -Path $fullPath -RepoRoot $RepoRoot),
            $RelativePath,
            [System.StringComparison]::Ordinal
        )) {
        throw "$Context path '$RelativePath' is outside its declared active/archive inventory root."
    }

    return $fullPath
}

function Read-ApplyMapping {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Migration mapping does not exist: '$Path'. Run inventory before -Apply."
    }

    try {
        $mapping = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 20
    }
    catch {
        throw "Migration mapping '$Path' is not valid JSON: $($_.Exception.Message)"
    }

    if ($null -eq $mapping -or $mapping -isnot [psobject]) {
        throw "Migration mapping '$Path' is not an object."
    }
    $schema = [string](Get-RequiredMappingProperty -InputObject $mapping -Name schema -Context 'Migration mapping')
    if ($schema -ne 'skalary/plan-folder-prefix-migration@1') {
        throw "Migration mapping has unsupported schema '$schema'."
    }
    $mode = [string](Get-RequiredMappingProperty -InputObject $mapping -Name mode -Context 'Migration mapping')
    if ($mode -notin @('inventory', 'apply')) {
        throw "Migration mapping has unsupported mode '$mode'."
    }
    $entries = Get-RequiredMappingProperty -InputObject $mapping -Name entries -Context 'Migration mapping'
    if ($null -eq $entries) {
        throw "Migration mapping field 'entries' must not be null."
    }

    return $mapping
}

function Write-ApplyMapping {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Mapping,

        [Parameter(Mandatory)]
        [string]$Path
    )

    $content = ($Mapping | ConvertTo-Json -Depth 8) + "`n"
    $write = Set-AtomicStoreContent -Path $Path -Content $content -Validate {
        param($candidatePath)

        $candidate = Get-Content -LiteralPath $candidatePath -Raw | ConvertFrom-Json -Depth 20
        if ([string]$candidate.schema -ne 'skalary/plan-folder-prefix-migration@1' -or
            [string]$candidate.mode -ne 'apply') {
            throw 'Updated migration mapping failed schema or mode validation.'
        }
    }
    if ($write.Status -ne 'complete') {
        throw "Migration progress write failed with status '$($write.Status)'."
    }
}

function Get-ApplyPreflight {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Mapping,

        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [Parameter(Mandatory)]
        [string]$PlansRoot,

        [Parameter(Mandatory)]
        [string]$ArchivedRoot,

        [Parameter(Mandatory)]
        [string]$EpicsRoot,

        [Parameter(Mandatory)]
        [string]$MappingPath
    )

    $entries = @(Get-RequiredMappingProperty -InputObject $Mapping -Name entries -Context 'Migration mapping')
    $inventory = @(Get-PlanInventory -RepoRoot $RepoRoot)
    $epicInventory = @(Get-EpicInventory -RepoRoot $RepoRoot)
    $sourcePaths = [System.Collections.Generic.HashSet[string]]::new(
        $(if ($IsWindows) { [System.StringComparer]::OrdinalIgnoreCase } else { [System.StringComparer]::Ordinal })
    )
    $targetPaths = [System.Collections.Generic.HashSet[string]]::new(
        $(if ($IsWindows) { [System.StringComparer]::OrdinalIgnoreCase } else { [System.StringComparer]::Ordinal })
    )
    $planIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $actions = [System.Collections.Generic.List[object]]::new()
    $previousSource = $null

    for ($index = 0; $index -lt $entries.Count; $index++) {
        $entry = $entries[$index]
        $context = "Migration mapping entry $index"
        if ($null -eq $entry -or $entry -isnot [psobject]) {
            throw "$context is not an object."
        }

        $planId = [string](Get-RequiredMappingProperty -InputObject $entry -Name planId -Context $context)
        $sourceRelative = [string](Get-RequiredMappingProperty -InputObject $entry -Name source -Context $context)
        $targetRelative = [string](Get-RequiredMappingProperty -InputObject $entry -Name target -Context $context)
        $archived = Get-RequiredMappingProperty -InputObject $entry -Name archived -Context $context
        $status = [string](Get-RequiredMappingProperty -InputObject $entry -Name status -Context $context)

        if ($planId -notmatch '^[0-9a-f]{6}$') {
            throw "$context has invalid canonical plan id '$planId'."
        }
        if ($archived -isnot [bool]) {
            throw "$context field 'archived' must be a Boolean."
        }
        if ($status -notin @('pending', 'complete')) {
            throw "$context has unsupported status '$status'."
        }
        if ($null -ne $previousSource -and
            [string]::CompareOrdinal($previousSource, $sourceRelative) -ge 0) {
            throw 'Migration mapping entries must remain in unique ordinal source order.'
        }
        $previousSource = $sourceRelative
        if (-not $planIds.Add($planId)) {
            throw "$context duplicates canonical plan id '$planId'."
        }

        $expectedParent = if ($archived) { $ArchivedRoot } else { $PlansRoot }
        $sourcePath = Resolve-MappingEntryPath -RelativePath $sourceRelative `
            -ExpectedParent $expectedParent -RepoRoot $RepoRoot -Context "$context source"
        $targetPath = Resolve-MappingEntryPath -RelativePath $targetRelative `
            -ExpectedParent $expectedParent -RepoRoot $RepoRoot -Context "$context target"
        if (-not $sourcePaths.Add($sourcePath) -or -not $targetPaths.Add($targetPath)) {
            throw "$context duplicates a source or target path."
        }
        $physicalMappingPath = Resolve-PhysicalRepoPath -Path $MappingPath
        $physicalSourcePath = Resolve-PhysicalRepoPath -Path $sourcePath
        $physicalTargetPath = Resolve-PhysicalRepoPath -Path $targetPath
        if ((Test-PathWithinRoot -Path $MappingPath -Root $sourcePath) -or
            (Test-PathWithinRoot -Path $MappingPath -Root $targetPath) -or
            (Test-PathWithinRoot -Path $physicalMappingPath -Root $physicalSourcePath) -or
            (Test-PathWithinRoot -Path $physicalMappingPath -Root $physicalTargetPath)) {
            throw "$context contains the migration mapping beneath a folder that apply may move."
        }

        $sourceName = Split-Path -Leaf $sourcePath
        $targetName = Split-Path -Leaf $targetPath
        if ($sourceName -notmatch '^(?<date>\d{4}-\d{2}-\d{2})-(?<id>[0-9a-f]{6})-(?<slug>.+)$') {
            throw "$context source '$sourceRelative' is not an unprefixed hash-plan folder."
        }
        $sourceDate = $Matches.date
        $sourceId = $Matches.id
        $sourceSlug = $Matches.slug
        if ($targetName -notmatch '^(?<prefix>standalone|[0-9a-f]{6})-(?<date>\d{4}-\d{2}-\d{2})-(?<id>[0-9a-f]{6})-(?<slug>.+)$') {
            throw "$context target '$targetRelative' is not a prefixed hash-plan folder."
        }
        $targetPrefix = $Matches.prefix
        if ($sourceId -ne $planId -or $Matches.id -ne $planId -or
            $Matches.date -ne $sourceDate -or $Matches.slug -cne $sourceSlug) {
            throw "$context source, target, and canonical plan identity do not match."
        }

        $sourceEntryExists = Test-DirectoryEntryExists -Path $sourcePath
        $targetEntryExists = Test-DirectoryEntryExists -Path $targetPath
        $sourceExists = Test-Path -LiteralPath $sourcePath -PathType Container
        $targetExists = Test-Path -LiteralPath $targetPath -PathType Container
        if ($sourceEntryExists -ne $sourceExists) {
            throw "$context source '$sourceRelative' is not a resolvable directory."
        }
        if ($targetEntryExists -ne $targetExists) {
            throw "$context target '$targetRelative' is occupied by a non-directory or unresolved link."
        }
        if ($sourceExists -and $targetExists) {
            throw "$context has both source and target folders present."
        }
        if (-not $sourceExists -and -not $targetExists) {
            throw "$context has neither source nor target folder present."
        }

        $actualPath = if ($sourceExists) { $sourcePath } else { $targetPath }
        if (-not (Test-PhysicalDirectChild -Path $actualPath -Parent $expectedParent)) {
            throw "$context plan folder escapes its declared active/archive inventory root."
        }
        $planPath = Join-Path $actualPath 'plan.md'
        if (-not (Test-Path -LiteralPath $planPath -PathType Leaf) -or
            -not (Test-PhysicalDirectChild -Path $planPath -Parent $actualPath)) {
            throw "$context plan.md is missing or escapes its plan folder."
        }

        $inventoryMatches = @($inventory | Where-Object {
                $_.Id -and
                $_.Id.ToLowerInvariant() -eq $planId -and
                [string]::Equals(
                    [System.IO.Path]::GetFullPath($_.Path),
                    $actualPath,
                    $script:PathComparison
                )
            })
        $identityMatches = @($inventory | Where-Object {
                $_.Id -and $_.Id.ToLowerInvariant() -eq $planId
            })
        if ($inventoryMatches.Count -ne 1 -or $identityMatches.Count -ne 1) {
            throw "$context plan '$planId' is not a unique member of the current plan inventory."
        }

        $markers = Get-PlanHeaderMarkers -Path $planPath
        if (-not $markers.PlanId -or $markers.PlanId.Trim().ToLowerInvariant() -ne $planId) {
            throw "$context plan-id anchor does not match '$planId'."
        }
        $epicId = if ($markers.EpicId) { $markers.EpicId.Trim().ToLowerInvariant() } else { $null }
        if ($targetPrefix -eq 'standalone') {
            if ($epicId) {
                throw "$context target prefix is standalone but the plan belongs to epic '$epicId'."
            }
        }
        else {
            if ($epicId -ne $targetPrefix) {
                throw "$context target prefix '$targetPrefix' does not match epic membership '$epicId'."
            }
            $matchingEpics = @($epicInventory | Where-Object {
                    $_.Id -and $_.Id.ToLowerInvariant() -eq $epicId
                })
            if ($matchingEpics.Count -ne 1 -or
                -not (Test-Path -LiteralPath $matchingEpics[0].EpicFile -PathType Leaf) -or
                -not (Test-PhysicalDirectChild -Path $matchingEpics[0].Path -Parent $EpicsRoot) -or
                -not (Test-PhysicalDirectChild -Path $matchingEpics[0].EpicFile -Parent $matchingEpics[0].Path)) {
                throw "$context references unresolved or unconfined epic '$epicId'."
            }
        }

        $action = if ($status -eq 'complete') {
            if ($sourceExists -or -not $targetExists) {
                throw "$context is complete but its on-disk state is inconsistent."
            }
            'skip'
        }
        elseif ($sourceExists) {
            'move'
        }
        else {
            'recover'
        }

        $actions.Add([pscustomobject]@{
                Index = $index
                Entry = $entry
                SourcePath = $sourcePath
                TargetPath = $targetPath
                Action = $action
            })
    }

    $unmappedEligible = @($inventory | Where-Object {
            $_.Scheme -eq 'new' -and
            [string]::IsNullOrWhiteSpace([string]$_.FolderPrefix) -and
            -not $sourcePaths.Contains([System.IO.Path]::GetFullPath($_.Path))
        })
    if ($unmappedEligible.Count -gt 0) {
        $paths = @($unmappedEligible | ForEach-Object {
                ConvertTo-RepoRelativePath -Path $_.Path -RepoRoot $RepoRoot
            } | Sort-Object -CaseSensitive) -join ', '
        throw "Migration mapping does not cover eligible unprefixed plan folder(s): $paths."
    }

    return $actions.ToArray()
}

$repoRootPath = [System.IO.Path]::GetFullPath($RepoRoot)
$plansRoot = Join-Path $repoRootPath 'docs/implementation-plans'
$archivedRoot = Join-Path $plansRoot 'archived'
$epicsRoot = Join-Path $plansRoot 'epics'

if (-not (Test-Path -LiteralPath $plansRoot -PathType Container)) {
    throw "Plans root does not exist: '$plansRoot'."
}
if (-not (Test-PhysicalPathWithinRoot -Path $plansRoot -Root $repoRootPath)) {
    throw "Plans root '$plansRoot' escapes repository root '$repoRootPath' through a link or reparse point."
}
$repositoryLockScope = Resolve-PhysicalRepoPath -Path $repoRootPath
if ($IsWindows) {
    $repositoryLockScope = $repositoryLockScope.ToLowerInvariant()
}
foreach ($optionalRoot in @($archivedRoot, $epicsRoot)) {
    if ((Test-Path -LiteralPath $optionalRoot -PathType Container) -and
        -not (Test-PhysicalPathWithinRoot -Path $optionalRoot -Root $plansRoot)) {
        throw "Plan inventory root '$optionalRoot' escapes plans root '$plansRoot' through a link or reparse point."
    }
}

if (-not $MappingPath) {
    $MappingPath = Join-Path $repoRootPath 'artifacts/plan-folder-prefix-migration.json'
}
$mappingPathResolved = Resolve-ConfinedMappingPath -Path $MappingPath -RepoRoot $repoRootPath

if ($Apply) {
    $applyResult = Invoke-WithAtomicStoreLock -Scope $repositoryLockScope -Action {
        $mapping = Read-ApplyMapping -Path $mappingPathResolved
        $actions = @(Get-ApplyPreflight -Mapping $mapping -RepoRoot $repoRootPath `
                -PlansRoot $plansRoot -ArchivedRoot $archivedRoot -EpicsRoot $epicsRoot `
                -MappingPath $mappingPathResolved)
        $completedBefore = @($actions | Where-Object { $_.Action -eq 'skip' }).Count

        if (-not $PSCmdlet.ShouldProcess(
                $repoRootPath,
                "Apply $($actions.Count) plan-folder prefix migration mapping entries"
            )) {
            return [pscustomobject]@{
                Mode = 'Apply'
                MappingPath = $mappingPathResolved
                MappingWritten = $false
                Count = $actions.Count
                Moved = 0
                Recovered = 0
                Completed = $completedBefore
            }
        }

        $moved = 0
        $recovered = 0
        $mappingWritten = $false
        if ([string]$mapping.mode -ne 'apply') {
            $mapping.mode = 'apply'
            Write-ApplyMapping -Mapping $mapping -Path $mappingPathResolved
            $mappingWritten = $true
        }

        foreach ($action in $actions) {
            if ($action.Action -eq 'skip') {
                continue
            }
            if ($action.Action -eq 'move') {
                Move-Item -LiteralPath $action.SourcePath -Destination $action.TargetPath
                $moved++
            }
            else {
                $recovered++
            }

            $mapping.mode = 'apply'
            $action.Entry.status = 'complete'
            Write-ApplyMapping -Mapping $mapping -Path $mappingPathResolved
            $mappingWritten = $true
        }

        return [pscustomobject]@{
            Mode = 'Apply'
            MappingPath = $mappingPathResolved
            MappingWritten = $mappingWritten
            Count = $actions.Count
            Moved = $moved
            Recovered = $recovered
            Completed = @($actions | Where-Object { $_.Entry.status -eq 'complete' }).Count
        }
    }
    return $applyResult
}

$inventory = @(Get-PlanInventory -RepoRoot $repoRootPath)
$epicInventory = @(Get-EpicInventory -RepoRoot $repoRootPath)
$candidatesByPath = [System.Collections.Generic.SortedDictionary[string, object]]::new(
    [System.StringComparer]::Ordinal
)
foreach ($plan in $inventory) {
    if ($plan.Scheme -eq 'new' -and [string]::IsNullOrWhiteSpace([string]$plan.FolderPrefix)) {
        $relativePath = ConvertTo-RepoRelativePath -Path $plan.Path -RepoRoot $repoRootPath
        $candidatesByPath.Add($relativePath, $plan)
    }
}
$candidates = @($candidatesByPath.Values)

$errors = [System.Collections.Generic.List[string]]::new()
$entries = [System.Collections.Generic.List[object]]::new()
$pathComparer = if ($IsWindows) {
    [System.StringComparer]::OrdinalIgnoreCase
}
else {
    [System.StringComparer]::Ordinal
}
$targetPaths = [System.Collections.Generic.HashSet[string]]::new($pathComparer)

foreach ($candidate in $candidates) {
    $expectedParent = if ($candidate.IsArchived) { $archivedRoot } else { $plansRoot }
    $sourcePath = [System.IO.Path]::GetFullPath($candidate.Path)
    $sourceRelative = ConvertTo-RepoRelativePath -Path $sourcePath -RepoRoot $repoRootPath
    $planPath = Join-Path $sourcePath 'plan.md'

    if (-not [string]::Equals(
            (Split-Path -Parent $sourcePath),
            [System.IO.Path]::GetFullPath($expectedParent),
            $script:PathComparison
        )) {
        $errors.Add("$sourceRelative is outside its inventoried active/archive root.")
        continue
    }

    try {
        $sourceIsConfined = Test-PhysicalDirectChild -Path $sourcePath -Parent $expectedParent
    }
    catch {
        $errors.Add("$sourceRelative cannot be physically resolved: $($_.Exception.Message)")
        continue
    }
    if (-not $sourceIsConfined) {
        $errors.Add("$sourceRelative escapes its inventoried active/archive root through a link or reparse point.")
        continue
    }

    if (-not (Test-Path -LiteralPath $planPath -PathType Leaf)) {
        $errors.Add("$sourceRelative has no plan.md.")
        continue
    }
    try {
        $planFileIsConfined = Test-PhysicalDirectChild -Path $planPath -Parent $sourcePath
    }
    catch {
        $errors.Add("$sourceRelative/plan.md cannot be physically resolved: $($_.Exception.Message)")
        continue
    }
    if (-not $planFileIsConfined) {
        $errors.Add("$sourceRelative/plan.md escapes its inventoried plan folder through a link or reparse point.")
        continue
    }

    $identityMatches = @($inventory | Where-Object {
            $_.Id -and $_.Id.ToLowerInvariant() -eq $candidate.Id.ToLowerInvariant()
        })
    if ($identityMatches.Count -ne 1) {
        $errors.Add("$sourceRelative does not have a unique canonical plan identity '$($candidate.Id)'.")
        continue
    }

    try {
        $markers = Get-PlanHeaderMarkers -Path $planPath
    }
    catch {
        $errors.Add("$sourceRelative/plan.md cannot be read: $($_.Exception.Message)")
        continue
    }
    $anchorId = if ($markers.PlanId) { $markers.PlanId.Trim().ToLowerInvariant() } else { '' }
    if ($anchorId -notmatch '^[0-9a-f]{6}$') {
        $errors.Add("$sourceRelative has a missing or invalid six-hex plan-id anchor.")
        continue
    }
    if ($anchorId -ne $candidate.FolderId -or $candidate.Id -ne $candidate.FolderId) {
        $errors.Add(
            "$sourceRelative has mismatched identity: folder '$($candidate.FolderId)', anchor '$anchorId', inventory '$($candidate.Id)'."
        )
        continue
    }

    $prefix = 'standalone'
    if (-not [string]::IsNullOrWhiteSpace([string]$markers.EpicId)) {
        $epicId = $markers.EpicId.Trim().ToLowerInvariant()
        if ($epicId -notmatch '^[0-9a-f]{6}$') {
            $errors.Add("$sourceRelative has invalid epic membership '$($markers.EpicId)'.")
            continue
        }

        $matchingEpics = @($epicInventory | Where-Object {
                $_.Id -and $_.Id.ToLowerInvariant() -eq $epicId
            })
        if ($matchingEpics.Count -ne 1 -or
            -not (Test-Path -LiteralPath $matchingEpics[0].EpicFile -PathType Leaf)) {
            $errors.Add("$sourceRelative references unresolved epic '$epicId'.")
            continue
        }
        try {
            $epicFolderIsConfined = Test-PhysicalDirectChild `
                -Path $matchingEpics[0].Path `
                -Parent $epicsRoot
            $epicFileIsConfined = Test-PhysicalDirectChild `
                -Path $matchingEpics[0].EpicFile `
                -Parent $matchingEpics[0].Path
        }
        catch {
            $errors.Add("$sourceRelative references epic '$epicId' whose epic.md cannot be physically resolved.")
            continue
        }
        if (-not $epicFolderIsConfined -or -not $epicFileIsConfined) {
            $errors.Add("$sourceRelative references epic '$epicId' whose epic.md escapes its inventoried epic folder.")
            continue
        }
        $prefix = $epicId
    }

    $target = Get-MigrationTarget -Plan $candidate -Prefix $prefix -Parent $expectedParent
    $targetRelative = ConvertTo-RepoRelativePath -Path $target -RepoRoot $repoRootPath
    if (-not (Test-PathWithinRoot -Path $target -Root $expectedParent) -or
        -not [string]::Equals(
            (Split-Path -Parent $target),
            [System.IO.Path]::GetFullPath($expectedParent),
            $script:PathComparison
        )) {
        $errors.Add("$sourceRelative resolves to target '$targetRelative' outside its inventoried root.")
        continue
    }
    if ((Test-DirectoryEntryExists -Path $target) -or -not $targetPaths.Add($target)) {
        $errors.Add("$sourceRelative collides with migration target '$targetRelative'.")
        continue
    }

    $entries.Add([ordered]@{
            planId = $candidate.Id
            source = $sourceRelative
            target = $targetRelative
            archived = [bool]$candidate.IsArchived
            status = 'pending'
        })
}

if ($errors.Count -gt 0) {
    $errors.Sort([System.StringComparer]::Ordinal)
    $details = $errors -join [Environment]::NewLine
    throw "Plan-folder prefix migration preflight failed before mapping write:$([Environment]::NewLine)$details"
}

$mapping = [ordered]@{
    schema = 'skalary/plan-folder-prefix-migration@1'
    mode = 'inventory'
    entries = $entries.ToArray()
}

$json = ($mapping | ConvertTo-Json -Depth 8) + "`n"
$mappingWritten = $false
if ($PSCmdlet.ShouldProcess($mappingPathResolved, 'Write deterministic plan-folder prefix migration mapping')) {
    $write = Invoke-AtomicStoreUpdate -Path $mappingPathResolved -LockScope $repositoryLockScope -Transform {
        param($current)

        if ($null -ne $current) {
            [void](Test-ReplaceableMapping -Content $current)
        }
        return $json
    } -Validate {
        param($path)

        $written = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -Depth 20
        if ([string]$written.schema -ne 'skalary/plan-folder-prefix-migration@1') {
            throw 'Written plan-folder prefix migration mapping failed schema validation.'
        }
    }
    if ($write.Status -ne 'complete') {
        throw "Migration mapping write failed with status '$($write.Status)'."
    }
    $mappingWritten = $true
}

return [pscustomobject]@{
    Mode = 'Inventory'
    MappingPath = $mappingPathResolved
    MappingWritten = $mappingWritten
    Count = $entries.Count
    Entries = $entries.ToArray()
}
