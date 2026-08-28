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
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path,

    [string]$MappingPath
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
    if ($propertyNames -notcontains 'schema' -or $propertyNames -notcontains 'entries') {
        throw 'Existing mapping is missing required schema or entries fields; refusing to overwrite it.'
    }
    if ([string]$existing.schema -ne 'skalary/plan-folder-prefix-migration@1') {
        throw "Existing mapping has unsupported schema '$($existing.schema)'; refusing to overwrite it."
    }
    $started = @($existing.entries | Where-Object { [string]$_.status -ne 'pending' })
    if ($started.Count -gt 0) {
        throw 'Existing mapping records apply progress; refusing to overwrite resumable state.'
    }

    return $true
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
    $write = Invoke-AtomicStoreUpdate -Path $mappingPathResolved -LockScope $repoRootPath -Transform {
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
