#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path,

    [string]$GenericStandardsPath,

    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:PathComparison = if ($IsWindows) {
    [System.StringComparison]::OrdinalIgnoreCase
}
else {
    [System.StringComparison]::Ordinal
}
$script:GenericByteLimit = 65536
$script:LocalByteLimit = 16384
$script:GenericEntryLimit = 64
$script:LocalEntryLimit = 32
$script:GuidanceLengthLimit = 512

function Resolve-RegularFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$DisplayPath,
        [switch]$Optional
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $rootPrefix = $Root.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    ) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $fullPath.StartsWith($rootPrefix, $script:PathComparison)) {
        throw "Review standards path escapes the repository: '$DisplayPath'."
    }
    if (-not (Test-Path -LiteralPath $fullPath)) {
        if ($Optional) {
            return $null
        }
        throw "Review standards file not found: '$DisplayPath'."
    }

    $relative = [System.IO.Path]::GetRelativePath($Root, $fullPath)
    $current = $Root
    foreach ($segment in $relative.Split(
            [char[]]@(
                [System.IO.Path]::DirectorySeparatorChar,
                [System.IO.Path]::AltDirectorySeparatorChar
            ),
            [System.StringSplitOptions]::RemoveEmptyEntries
        )) {
        $current = Join-Path $current $segment
        $item = Get-Item -LiteralPath $current -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Review standards path contains a reparse point: '$DisplayPath'."
        }
    }
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "Review standards path is not a regular file: '$DisplayPath'."
    }
    return (Resolve-Path -LiteralPath $fullPath).Path
}

function Read-BoundedUtf8File {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][int]$MaxBytes,
        [Parameter(Mandatory)][string]$DisplayPath
    )

    $item = Get-Item -LiteralPath $Path -Force
    if ($item.Length -gt $MaxBytes) {
        throw "Review standards file '$DisplayPath' exceeds the $MaxBytes-byte limit."
    }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $utf8 = [System.Text.UTF8Encoding]::new($false, $true)
    try {
        return $utf8.GetString($bytes)
    }
    catch {
        throw "Review standards file '$DisplayPath' is not valid UTF-8."
    }
}

function Assert-Guidance {
    param(
        [Parameter(Mandatory)][string]$Guidance,
        [Parameter(Mandatory)][string]$Source
    )

    if ([string]::IsNullOrWhiteSpace($Guidance) -or
        $Guidance.Length -gt $script:GuidanceLengthLimit -or
        $Guidance -match '[\r\n@{}]' -or
        $Guidance -match '^(?: {4,}| {0,3}\t| {0,3}(?:#{1,6}(?:[ \t]|$)|```|~~~|>|[-+*](?:[ \t]|$)|\d{1,9}[.)](?:[ \t]|$)|<|\[[^\]]+\]:))') {
        throw "Review standard guidance from '$Source' is malformed."
    }
}

$repoRootPath = [System.IO.Path]::GetFullPath($RepoRoot)
if (-not (Test-Path -LiteralPath $repoRootPath -PathType Container)) {
    throw "Repository root not found: '$RepoRoot'."
}
$repoRootPath = (Resolve-Path -LiteralPath $repoRootPath).Path

$genericDisplayPath = $GenericStandardsPath
if ([string]::IsNullOrWhiteSpace($genericDisplayPath)) {
    $installedAsset = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../assets/review-standards.json'))
    $genericDisplayPath = [System.IO.Path]::GetRelativePath($repoRootPath, $installedAsset).Replace('\', '/')
}
$genericInput = if ([System.IO.Path]::IsPathRooted($genericDisplayPath)) {
    $genericDisplayPath
}
else {
    Join-Path $repoRootPath $genericDisplayPath
}
$genericPath = Resolve-RegularFile -Path $genericInput -Root $repoRootPath -DisplayPath $genericDisplayPath
$genericRaw = Read-BoundedUtf8File -Path $genericPath -MaxBytes $script:GenericByteLimit -DisplayPath $genericDisplayPath
try {
    $genericDocument = $genericRaw | ConvertFrom-Json -Depth 30
}
catch {
    throw "Generic review standards file '$genericDisplayPath' is not valid JSON."
}

$generic = [System.Collections.Generic.List[object]]::new()
$byId = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
$genericRecords = if ([string]$genericDocument.schema -ceq 'skalary/review-concerns@1' -and
    $genericDocument.PSObject.Properties.Name -contains 'concerns') {
    @(
        foreach ($concern in @($genericDocument.concerns)) {
            $concernStandards = if ($concern.PSObject.Properties.Name -contains 'standards') {
                @($concern.standards)
            }
            else {
                @()
            }
            foreach ($standard in $concernStandards) {
                [pscustomobject]@{
                    id = $standard.id
                    concern = $concern.id
                    guidance = $standard.guidance
                    localizable = $standard.localizable
                }
            }
        }
    )
}
elseif ([string]$genericDocument.schema -ceq 'skalary/review-standards@1' -and
    $genericDocument.PSObject.Properties.Name -contains 'standards') {
    @($genericDocument.standards)
}
else {
    throw "Generic review standards file '$genericDisplayPath' has an unsupported schema."
}

foreach ($standard in $genericRecords) {
    $id = [string]$standard.id
    $guidance = [string]$standard.guidance
    if ($id -notmatch '^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$' -or $id.Length -gt 64) {
        throw "Generic review standard id '$id' is malformed."
    }
    Assert-Guidance -Guidance $guidance -Source $id
    if ($byId.ContainsKey($id)) {
        throw "Generic review standard id '$id' is duplicated."
    }
    $entry = [pscustomobject][ordered]@{
        id = $id
        concern = [string]$standard.concern
        guidance = $guidance
        localizable = [bool]$standard.localizable
        source = 'generic'
    }
    $byId.Add($id, $entry)
    $generic.Add($entry)
    if ($generic.Count -gt $script:GenericEntryLimit) {
        throw "Generic review standards exceed the $($script:GenericEntryLimit)-entry limit."
    }
}

$localDisplayPath = 'docs/review-standards.md'
$localPath = Resolve-RegularFile -Path (Join-Path $repoRootPath $localDisplayPath) `
    -Root $repoRootPath -DisplayPath $localDisplayPath -Optional
$localCount = 0
if ($null -ne $localPath) {
    $localRaw = Read-BoundedUtf8File -Path $localPath -MaxBytes $script:LocalByteLimit -DisplayPath $localDisplayPath
    $lines = $localRaw -split '\r?\n'
    if ($lines.Count -eq 0 -or $lines[0] -cne '# Review standards') {
        throw "Local review standards must start with '# Review standards'."
    }
    $seenLocal = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($line in $lines | Select-Object -Skip 1) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        $match = [regex]::Match($line, '^- (?<mode>extend|replace) `(?<id>[a-z][a-z0-9]*(?:-[a-z0-9]+)*)`: (?<guidance>.+)$')
        if (-not $match.Success) {
            throw "Malformed local review standard line: '$line'."
        }
        $id = $match.Groups['id'].Value
        $mode = $match.Groups['mode'].Value
        $localGuidance = $match.Groups['guidance'].Value
        Assert-Guidance -Guidance $localGuidance -Source $localDisplayPath
        if (-not $seenLocal.Add($id)) {
            throw "Local review standard id '$id' is duplicated."
        }
        if (-not $byId.ContainsKey($id)) {
            throw "Local review standard '$id' does not match generic guidance."
        }
        $current = $byId[$id]
        if (-not [bool]$current.localizable) {
            throw "Generic review standard '$id' is not localizable."
        }
        $resolvedGuidance = if ($mode -ceq 'extend') {
            "$($current.guidance) $localGuidance"
        }
        else {
            $localGuidance
        }
        $replacement = [pscustomobject][ordered]@{
            id = $id
            concern = [string]$current.concern
            guidance = $resolvedGuidance
            localizable = $true
            source = "local-$mode"
        }
        $byId[$id] = $replacement
        $localCount++
        if ($localCount -gt $script:LocalEntryLimit) {
            throw "Local review standards exceed the $($script:LocalEntryLimit)-entry limit."
        }
    }
}

$resolved = @($generic | ForEach-Object { $byId[[string]$_.id] })
$result = [pscustomobject][ordered]@{
    schema = 'skalary/resolved-review-standards@1'
    localFile = if ($null -eq $localPath) { 'absent' } else { $localDisplayPath }
    standards = $resolved
}
if ($Json) {
    return ($result | ConvertTo-Json -Depth 8 -Compress)
}
return $result
