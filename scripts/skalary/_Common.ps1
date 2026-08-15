#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-RepoRoot {
    [CmdletBinding()]
    param(
        [string]$StartPath = $PSScriptRoot
    )

    $candidateStartPath = [System.IO.Path]::GetFullPath($StartPath)
    if (Test-Path -LiteralPath $candidateStartPath -PathType Leaf) {
        $candidateStartPath = Split-Path -Parent $candidateStartPath
    }

    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $repoRoot = git -C $candidateStartPath rev-parse --show-toplevel 2>$null
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $previous
    if ($exitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($repoRoot)) {
        return [System.IO.Path]::GetFullPath($repoRoot.Trim())
    }

    $current = $candidateStartPath
    while ($true) {
        if (Test-Path -LiteralPath (Join-Path $current '.git')) {
            return $current
        }

        $parent = Split-Path -Parent $current
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $current) {
            throw "Unable to resolve repository root from '$StartPath'."
        }
        $current = $parent
    }
}

function Resolve-RegistryPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [string]$RegistryPath
    )

    if (-not [string]::IsNullOrWhiteSpace($RegistryPath)) {
        $explicit = [System.IO.Path]::GetFullPath($RegistryPath)
        if (-not (Test-Path -LiteralPath $explicit -PathType Leaf)) {
            throw "registry.json not found at -RegistryPath '$RegistryPath'."
        }
        return $explicit
    }

    $rootRegistry = Join-Path $RepoRoot 'registry.json'
    if (Test-Path -LiteralPath $rootRegistry -PathType Leaf) {
        return $rootRegistry
    }

    # Bootstrapped repos have no root registry.json; bootstrap.ps1 writes it here.
    $bootstrapRegistry = Join-Path $RepoRoot 'scripts/skalary/registry.json'
    if (Test-Path -LiteralPath $bootstrapRegistry -PathType Leaf) {
        return $bootstrapRegistry
    }

    throw "No skalary registry found under '$RepoRoot' (looked for registry.json and scripts/skalary/registry.json). This is not a skalary-managed repo - run scripts/skalary/bootstrap.ps1 first, or pass -RegistryPath."
}

function Assert-PluginName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PluginName
    )

    if ($PluginName -notmatch '^[a-z0-9][a-z0-9-]*$') {
        throw 'Plugin name must contain only lowercase letters, digits, and hyphens, and must start with a letter or digit.'
    }
}

function Get-StringSha256 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    return [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

function ConvertTo-CanonicalGithubRepository {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Repository
    )

    $value = $Repository.Trim()
    $owner = $null
    $name = $null

    if ($value -match '^github\.com/(?<owner>[A-Za-z0-9](?:[A-Za-z0-9-]{0,38}))/(?<name>[A-Za-z0-9._-]+?)(?:\.git)?$') {
        $owner = $Matches.owner
        $name = $Matches.name
    }
    elseif ($value -match '^(?<owner>[A-Za-z0-9](?:[A-Za-z0-9-]{0,38}))/(?<name>[A-Za-z0-9._-]+?)(?:\.git)?$') {
        $owner = $Matches.owner
        $name = $Matches.name
    }
    elseif ($value -match '^(?:[^@\s]+@)?github\.com:(?<owner>[^/\s]+)/(?<name>[^/\s]+?)(?:\.git)?$') {
        $owner = $Matches.owner
        $name = $Matches.name
    }
    else {
        $uri = $null
        if (-not [System.Uri]::TryCreate($value, [System.UriKind]::Absolute, [ref]$uri) -or
            $uri.Host -ne 'github.com') {
            throw 'Repository source is not a supported GitHub repository identity.'
        }

        $validTransport = switch ($uri.Scheme.ToLowerInvariant()) {
            'https' { $uri.IsDefaultPort -or $uri.Port -eq 443 }
            'http' { $uri.IsDefaultPort -or $uri.Port -eq 80 }
            'ssh' { $uri.Port -eq -1 -or $uri.Port -eq 22 }
            'git' { $uri.Port -eq -1 -or $uri.Port -eq 9418 }
            default { $false }
        }
        if (-not $validTransport) {
            throw 'Repository source is not a supported GitHub repository identity.'
        }

        $segments = @($uri.AbsolutePath.Trim('/').Split('/', [System.StringSplitOptions]::RemoveEmptyEntries))
        if ($segments.Count -ne 2) {
            throw 'Repository source is not a supported GitHub repository identity.'
        }
        $owner = $segments[0]
        $name = $segments[1] -replace '\.git$', ''
    }

    if ($owner -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})$' -or
        $name -notmatch '^[A-Za-z0-9._-]+$') {
        throw 'Repository source is not a supported GitHub repository identity.'
    }

    return "github.com/$($owner.ToLowerInvariant())/$($name.ToLowerInvariant())"
}

function New-PluginSourceIdentity {
    [CmdletBinding(DefaultParameterSetName = 'Github')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Github')]
        [string]$Repository,

        [Parameter(Mandatory, ParameterSetName = 'Local')]
        [string]$LocalPath
    )

    if ($PSCmdlet.ParameterSetName -eq 'Local') {
        $canonicalPath = [System.IO.Path]::GetFullPath($LocalPath)
        return [pscustomobject][ordered]@{
            version = 1
            kind = 'local'
            identity = "sha256:$(Get-StringSha256 -Value $canonicalPath)"
        }
    }

    return [pscustomobject][ordered]@{
        version = 1
        kind = 'github'
        identity = ConvertTo-CanonicalGithubRepository -Repository $Repository
    }
}

function Assert-PluginSourceIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $SourceIdentity
    )

    $properties = @($SourceIdentity.PSObject.Properties.Name)
    $version = $SourceIdentity.version
    $isIntegerVersion = ($version -is [byte] -or
        $version -is [sbyte] -or
        $version -is [int16] -or
        $version -is [uint16] -or
        $version -is [int32] -or
        $version -is [uint32] -or
        $version -is [int64] -or
        $version -is [uint64])
    if ($properties.Count -ne 3 -or
        $properties -notcontains 'version' -or
        $properties -notcontains 'kind' -or
        $properties -notcontains 'identity' -or
        -not $isIntegerVersion -or
        $version -ne 1) {
        throw 'Plugin source identity has an unsupported or ambiguous shape.'
    }

    $kind = [string]$SourceIdentity.kind
    $identity = [string]$SourceIdentity.identity
    if ($kind -ceq 'github') {
        if ($identity -cne (ConvertTo-CanonicalGithubRepository -Repository $identity)) {
            throw 'GitHub plugin source identity is not canonical.'
        }
    }
    elseif ($kind -ceq 'local') {
        if ($identity -cnotmatch '^sha256:[a-f0-9]{64}$') {
            throw 'Local plugin source identity is invalid.'
        }
    }
    else {
        throw 'Plugin source identity kind is unsupported.'
    }
}

function Resolve-PluginReceiptSourceIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Receipt
    )

    if ($Receipt.PSObject.Properties.Name -contains 'sourceIdentity') {
        Assert-PluginSourceIdentity -SourceIdentity $Receipt.sourceIdentity
        return $Receipt.sourceIdentity
    }

    if ($Receipt.PSObject.Properties.Name -notcontains 'source' -or
        $Receipt.PSObject.Properties.Name -notcontains 'ref') {
        throw 'Legacy plugin receipt source identity is missing and cannot be reconciled safely.'
    }

    $legacy = [string]$Receipt.source
    $ref = [string]$Receipt.ref
    if ([string]::IsNullOrWhiteSpace($legacy) -or
        $ref -notmatch '^[a-f0-9]{40}([a-f0-9]{24})?$') {
        throw 'Legacy plugin receipt source identity is ambiguous and requires an explicit migration.'
    }

    $suffix = "@$ref"
    $label = if ($legacy.EndsWith($suffix, [System.StringComparison]::Ordinal) -and
        $legacy.Length -gt $suffix.Length) {
        $legacy.Substring(0, $legacy.Length - $suffix.Length)
    }
    else {
        $legacy
    }
    if ($label.StartsWith('remote:', [System.StringComparison]::Ordinal)) {
        return New-PluginSourceIdentity -Repository $label.Substring('remote:'.Length)
    }
    if ($label.StartsWith('local:', [System.StringComparison]::Ordinal)) {
        return New-PluginSourceIdentity -LocalPath $label.Substring('local:'.Length)
    }
    try {
        return New-PluginSourceIdentity -Repository $label
    }
    catch {
        throw 'Legacy plugin receipt source identity is ambiguous and requires an explicit migration.'
    }
}

function Test-PluginSourceIdentityEqual {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Left,

        [Parameter(Mandatory)]
        $Right
    )

    Assert-PluginSourceIdentity -SourceIdentity $Left
    Assert-PluginSourceIdentity -SourceIdentity $Right
    return ([int]$Left.version -eq [int]$Right.version -and
        [string]$Left.kind -ceq [string]$Right.kind -and
        [string]$Left.identity -ceq [string]$Right.identity)
}

function Test-GithubRelativePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RelativePath
    )

    if ([string]::IsNullOrWhiteSpace($RelativePath)) {
        return $false
    }

    if ($RelativePath.StartsWith('/') -or $RelativePath.StartsWith('\')) {
        return $false
    }

    if ($RelativePath -match '^[A-Za-z]:') {
        return $false
    }

    if ($RelativePath -match '\\\\') {
        return $false
    }

    if ($RelativePath.Contains(':')) {
        return $false
    }

    $segments = ($RelativePath -replace '\\', '/').Split('/', [System.StringSplitOptions]::RemoveEmptyEntries)
    foreach ($segment in $segments) {
        if ($segment -eq '..') {
            return $false
        }
    }

    return $true
}

function Resolve-GithubConstrainedPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [Parameter(Mandatory)]
        [string]$RelativePath
    )

    if (-not (Test-GithubRelativePath -RelativePath $RelativePath)) {
        throw "Path '$RelativePath' is not a valid .github-relative destination."
    }

    $githubRoot = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot '.github'))
    $relativeSystemPath = ($RelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    $candidate = [System.IO.Path]::GetFullPath((Join-Path $githubRoot $relativeSystemPath))

    $separator = [System.IO.Path]::DirectorySeparatorChar
    $githubRootWithSeparator = $githubRoot.TrimEnd($separator) + $separator
    if (-not $candidate.StartsWith($githubRootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Resolved path '$candidate' escapes .github root '$githubRoot'."
    }

    return $candidate
}

function Resolve-PluginConstrainedPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PluginRoot,

        [Parameter(Mandatory)]
        [string]$RelativePath
    )

    if ([string]::IsNullOrWhiteSpace($RelativePath)) {
        throw 'Source path is empty.'
    }

    if ($RelativePath.StartsWith('/') -or $RelativePath.StartsWith('\')) {
        throw "Source path '$RelativePath' must be relative."
    }

    if ($RelativePath -match '^[A-Za-z]:') {
        throw "Source path '$RelativePath' cannot be drive-relative or absolute."
    }

    if ($RelativePath -match '\\\\') {
        throw "Source path '$RelativePath' cannot be UNC."
    }

    if ($RelativePath.Contains(':')) {
        throw "Source path '$RelativePath' cannot contain ':'."
    }

    $segments = ($RelativePath -replace '\\', '/').Split('/', [System.StringSplitOptions]::RemoveEmptyEntries)
    foreach ($segment in $segments) {
        if ($segment -eq '..') {
            throw "Source path '$RelativePath' cannot traverse parent directories."
        }
    }

    $normalizedRoot = [System.IO.Path]::GetFullPath($PluginRoot)
    $normalizedRelativePath = ($RelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    $candidate = [System.IO.Path]::GetFullPath((Join-Path $normalizedRoot $normalizedRelativePath))
    $separator = [System.IO.Path]::DirectorySeparatorChar
    $rootWithSeparator = $normalizedRoot.TrimEnd($separator) + $separator
    if (-not $candidate.StartsWith($rootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Source path '$RelativePath' resolves outside plugin root '$normalizedRoot'."
    }

    return $candidate
}

function Get-FileSha256 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "File not found: $Path"
    }

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function ConvertTo-SemVer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Version
    )

    $semverPattern = '^(?<major>0|[1-9]\d*)\.(?<minor>0|[1-9]\d*)\.(?<patch>0|[1-9]\d*)(?:-(?<pre>[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+(?<build>[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$'
    if ($Version -notmatch $semverPattern) {
        throw "Invalid semantic version '$Version'."
    }

    return [pscustomobject]@{
        Original = $Version
        Major = [int]$Matches.major
        Minor = [int]$Matches.minor
        Patch = [int]$Matches.patch
        PreRelease = if ($Matches.ContainsKey('pre')) { $Matches.pre } else { $null }
        Build = if ($Matches.ContainsKey('build')) { $Matches.build } else { $null }
    }
}

function Compare-PreRelease {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Left,

        [AllowNull()]
        [string]$Right
    )

    if ([string]::IsNullOrWhiteSpace($Left) -and [string]::IsNullOrWhiteSpace($Right)) {
        return 0
    }
    if ([string]::IsNullOrWhiteSpace($Left)) {
        return 1
    }
    if ([string]::IsNullOrWhiteSpace($Right)) {
        return -1
    }

    $leftParts = $Left.Split('.')
    $rightParts = $Right.Split('.')
    $max = [Math]::Max($leftParts.Count, $rightParts.Count)

    for ($index = 0; $index -lt $max; $index++) {
        if ($index -ge $leftParts.Count) { return -1 }
        if ($index -ge $rightParts.Count) { return 1 }

        $leftPart = $leftParts[$index]
        $rightPart = $rightParts[$index]

        $leftNumeric = $leftPart -match '^[0-9]+$'
        $rightNumeric = $rightPart -match '^[0-9]+$'

        if ($leftNumeric -and $rightNumeric) {
            $comparison = [int]$leftPart - [int]$rightPart
            if ($comparison -ne 0) {
                return [Math]::Sign($comparison)
            }
            continue
        }

        if ($leftNumeric -and -not $rightNumeric) { return -1 }
        if (-not $leftNumeric -and $rightNumeric) { return 1 }

        $stringComparison = [string]::CompareOrdinal($leftPart, $rightPart)
        if ($stringComparison -ne 0) {
            return [Math]::Sign($stringComparison)
        }
    }

    return 0
}

function Compare-SemVer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Left,

        [Parameter(Mandatory)]
        [string]$Right
    )

    $leftVersion = ConvertTo-SemVer -Version $Left
    $rightVersion = ConvertTo-SemVer -Version $Right

    foreach ($part in 'Major', 'Minor', 'Patch') {
        if ($leftVersion.$part -lt $rightVersion.$part) { return -1 }
        if ($leftVersion.$part -gt $rightVersion.$part) { return 1 }
    }

    return Compare-PreRelease -Left $leftVersion.PreRelease -Right $rightVersion.PreRelease
}

function Sort-Ordinal {
    <#
    .SYNOPSIS
        Sorts strings, or objects by string properties, with an explicit comparer.
    .DESCRIPTION
        `Sort-Object` compares strings through the current culture, so the order it
        produces is a property of the host rather than of the input: cs-CZ reads the
        digraph `ch` as one letter placed after `h`, and sorts accented letters apart
        from the base letter en-US folds them onto. Generated catalogs are compared
        byte-for-byte by the drift gates, so any list that reaches a generated file has
        to be ordered by a comparer the build carries with it (REQ-7, D8).
    .PARAMETER Property
        Property names to sort by, most significant first. Omit to sort the inputs
        themselves as strings.
    .PARAMETER Comparer
        Defaults to ordinal. Callers pass it explicitly where the choice is part of the
        contract the file documents.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$InputObject,

        [string[]]$Property,

        [switch]$Descending,

        [System.StringComparer]$Comparer = [System.StringComparer]::Ordinal
    )

    $items = @($InputObject | Where-Object { $null -ne $_ })
    if ($items.Count -le 1) {
        return $items
    }

    $decorated = [object[]]@(
        foreach ($item in $items) {
            # Assigned inside each branch rather than from the `if` statement's value:
            # statement output is enumerated, so a single-element key array would arrive
            # as a bare string and index by character.
            [string[]]$keys = @()
            if ($Property) {
                $keys = [string[]]@($Property | ForEach-Object { [string]$item.$_ })
            }
            else {
                $keys = [string[]]@([string]$item)
            }
            [pscustomobject]@{ Item = $item; Keys = $keys }
        }
    )

    $activeComparer = $Comparer
    $sign = if ($Descending) { -1 } else { 1 }
    # Sign-flipped rather than reversed: [array]::Sort with a Comparison is unstable, so
    # reversing its output would scramble entries whose keys compare equal.
    $comparison = [System.Comparison[object]] {
        param($left, $right)

        $leftKeys = $left.Keys
        $rightKeys = $right.Keys
        $sharedCount = [Math]::Min($leftKeys.Length, $rightKeys.Length)
        for ($index = 0; $index -lt $sharedCount; $index++) {
            $result = $activeComparer.Compare($leftKeys[$index], $rightKeys[$index])
            if ($result -ne 0) {
                return ($sign * [Math]::Sign($result))
            }
        }
        return ($sign * [Math]::Sign($leftKeys.Length - $rightKeys.Length))
    }

    [array]::Sort($decorated, $comparison)
    # Enumerated rather than returned as one array value: every call site wraps the result
    # in @(), which would otherwise nest the array inside a single-element array.
    return @($decorated | ForEach-Object { $_.Item })
}

function ConvertTo-SortedObject {
    [CmdletBinding()]
    param(
        [AllowNull()]
        $InputObject
    )

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $ordered = [ordered]@{}
        foreach ($key in (Sort-Ordinal -InputObject @($InputObject.Keys))) {
            $ordered[$key] = ConvertTo-SortedObject -InputObject $InputObject[$key]
        }
        return [pscustomobject]$ordered
    }

    if ($InputObject -is [pscustomobject] -and -not ($InputObject -is [string])) {
        $ordered = [ordered]@{}
        foreach ($property in (Sort-Ordinal -InputObject @($InputObject.PSObject.Properties.Name))) {
            $ordered[$property] = ConvertTo-SortedObject -InputObject $InputObject.$property
        }
        return [pscustomobject]$ordered
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        $items = @()
        foreach ($item in $InputObject) {
            $items += , (ConvertTo-SortedObject -InputObject $item)
        }
        return , ([object[]]$items)
    }

    return $InputObject
}

function Read-JsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "JSON file not found: $Path"
    }

    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 100
}

function Write-JsonFileStable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        $InputObject
    )

    $sorted = ConvertTo-SortedObject -InputObject $InputObject
    $json = $sorted | ConvertTo-Json -Depth 100
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $directory = Split-Path -Parent $fullPath
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        throw "JSON destination directory not found: $directory"
    }
    $tempPath = Join-Path $directory (".$([System.IO.Path]::GetFileName($fullPath)).$([guid]::NewGuid().ToString('N')).tmp")
    $stream = $null
    try {
        $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes("$json`n")
        $stream = [System.IO.File]::Open(
            $tempPath,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
        $stream.Dispose()
        $stream = $null
        [System.IO.File]::Move($tempPath, $fullPath, $true)
    }
    finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
        if (Test-Path -LiteralPath $tempPath -PathType Leaf) {
            Remove-Item -LiteralPath $tempPath -Force
        }
    }
}

function Get-PluginRetirementStateSchema {
    [CmdletBinding()]
    param()

    return @'
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "additionalProperties": false,
  "required": ["schemaVersion", "name", "status", "transactionId", "updatedAt", "tombstoneSha256", "prior", "affectedFiles", "remedy"],
  "properties": {
    "schemaVersion": { "const": 1 },
    "name": { "type": "string", "pattern": "^[a-z0-9][a-z0-9-]*$" },
    "status": { "enum": ["preview", "applying", "retired", "residue", "failed"] },
    "transactionId": { "type": "string", "pattern": "^[a-f0-9]{32}$" },
    "updatedAt": { "type": "string", "format": "date-time" },
    "tombstoneSha256": { "type": "string", "pattern": "^[a-f0-9]{64}$" },
    "prior": {
      "type": "object",
      "additionalProperties": false,
      "required": ["sourceIdentity", "ref", "version"],
      "properties": {
        "sourceIdentity": {
          "type": "object",
          "additionalProperties": false,
          "required": ["version", "kind", "identity"],
          "properties": {
            "version": { "const": 1 },
            "kind": { "enum": ["github", "local"] },
            "identity": {
              "type": "string",
              "pattern": "^(github\\.com/[a-z0-9-]+/[a-z0-9._-]+|sha256:[a-f0-9]{64})$"
            }
          }
        },
        "ref": { "type": "string", "pattern": "^[a-f0-9]{40}([a-f0-9]{24})?$" },
        "version": {
          "type": "string",
          "pattern": "^(0|[1-9]\\d*)\\.(0|[1-9]\\d*)\\.(0|[1-9]\\d*)(?:-[0-9A-Za-z-]+(?:\\.[0-9A-Za-z-]+)*)?(?:\\+[0-9A-Za-z-]+(?:\\.[0-9A-Za-z-]+)*)?$"
        }
      }
    },
    "affectedFiles": {
      "type": "array",
      "minItems": 1,
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["dest", "expectedSha256", "observedSha256", "outcome"],
        "properties": {
          "dest": { "type": "string", "minLength": 1 },
          "expectedSha256": { "type": "string", "pattern": "^[a-f0-9]{64}$" },
          "observedSha256": { "type": ["string", "null"], "pattern": "^[a-f0-9]{64}$" },
          "outcome": { "enum": ["pending", "removed", "residue"] }
        }
      }
    },
    "remedy": { "type": "string" },
    "error": { "type": "string" }
  }
}
'@
}

function Get-PluginRetirementStatePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [Parameter(Mandatory)]
        [string]$PluginName
    )

    Assert-PluginName -PluginName $PluginName
    return Resolve-GithubConstrainedPath -RepoRoot $RepoRoot -RelativePath ".skalary/retirements/$PluginName.json"
}

function Assert-GithubStatePathSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [Parameter(Mandatory)]
        [string]$Path
    )

    $githubRoot = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot '.github'))
    $candidate = [System.IO.Path]::GetFullPath($Path)
    $relative = [System.IO.Path]::GetRelativePath($githubRoot, $candidate)
    if ($relative.StartsWith('..') -or [System.IO.Path]::IsPathRooted($relative)) {
        throw 'Managed state path escapes the .github root.'
    }

    $current = $githubRoot
    foreach ($segment in @($relative.Split(
                [System.IO.Path]::DirectorySeparatorChar,
                [System.StringSplitOptions]::RemoveEmptyEntries))) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or
                -not [string]::IsNullOrWhiteSpace([string]$item.LinkType)) {
                throw "Managed state path traverses a link or reparse point at '$current'."
            }
        }
        $current = Join-Path $current $segment
    }

    if (Test-Path -LiteralPath $current) {
        $item = Get-Item -LiteralPath $current -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or
            -not [string]::IsNullOrWhiteSpace([string]$item.LinkType)) {
            throw "Managed state path resolves to a link or reparse point at '$current'."
        }
    }
}

function Assert-PluginRetirementStatePathSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [Parameter(Mandatory)]
        [string]$Path
    )

    Assert-GithubStatePathSafe -RepoRoot $RepoRoot -Path $Path
}

function Test-PluginRetirementState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $State
    )

    $json = ConvertTo-SortedObject -InputObject $State | ConvertTo-Json -Depth 100
    if (-not ($json | Test-Json -Schema (Get-PluginRetirementStateSchema) -ErrorAction SilentlyContinue)) {
        throw 'Plugin retirement state does not satisfy the version 1 schema.'
    }
    Assert-PluginName -PluginName ([string]$State.name)
    Assert-PluginSourceIdentity -SourceIdentity $State.prior.sourceIdentity

    foreach ($entry in @($State.affectedFiles)) {
        if (-not (Test-GithubRelativePath -RelativePath ([string]$entry.dest))) {
            throw 'Plugin retirement state contains an invalid affected destination.'
        }
    }
}

function Write-PluginRetirementState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [Parameter(Mandatory)]
        $State
    )

    Test-PluginRetirementState -State $State
    $statePath = Get-PluginRetirementStatePath -RepoRoot $RepoRoot -PluginName ([string]$State.name)
    Assert-PluginRetirementStatePathSafe -RepoRoot $RepoRoot -Path $statePath
    $stateRoot = Split-Path -Parent $statePath
    if (-not (Test-Path -LiteralPath $stateRoot -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $stateRoot -Force)
    }
    Assert-PluginRetirementStatePathSafe -RepoRoot $RepoRoot -Path $statePath
    Write-JsonFileStable -Path $statePath -InputObject $State
    return $statePath
}

function Read-PluginRetirementState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [Parameter(Mandatory)]
        [string]$PluginName
    )

    $statePath = Get-PluginRetirementStatePath -RepoRoot $RepoRoot -PluginName $PluginName
    Assert-PluginRetirementStatePathSafe -RepoRoot $RepoRoot -Path $statePath
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        return $null
    }

    Assert-PluginRetirementStatePathSafe -RepoRoot $RepoRoot -Path $statePath
    $state = Read-JsonFile -Path $statePath
    Test-PluginRetirementState -State $state
    if ([string]$state.name -cne $PluginName) {
        throw 'Plugin retirement state name does not match its confined file name.'
    }
    return $state
}

function Get-PluginRetirementSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $State,

        [ValidateRange(0, 64)]
        [int]$MaxPaths = 8
    )

    Test-PluginRetirementState -State $State
    $allPaths = @($State.affectedFiles | ForEach-Object { [string]$_.dest })
    $shown = @($allPaths | Select-Object -First $MaxPaths)
    return [pscustomobject][ordered]@{
        name = [string]$State.name
        status = [string]$State.status
        totalPaths = $allPaths.Count
        paths = $shown
        omittedPaths = [Math]::Max(0, $allPaths.Count - $shown.Count)
        remedy = [string]$State.remedy
    }
}

function Get-StableJsonSha256 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $InputObject
    )

    $json = ConvertTo-SortedObject -InputObject $InputObject | ConvertTo-Json -Depth 100 -Compress
    return Get-StringSha256 -Value $json
}

function Invoke-ParentDirectoryPrune {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Directories,

        [Parameter(Mandatory)]
        [string]$GithubRoot
    )

    $separator = [System.IO.Path]::DirectorySeparatorChar
    $normalizedGithubRoot = [System.IO.Path]::GetFullPath($GithubRoot).TrimEnd($separator)
    $rootWithSeparator = $normalizedGithubRoot + $separator
    $queue = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($directory in $Directories) {
        if ([string]::IsNullOrWhiteSpace($directory)) {
            continue
        }
        $current = [System.IO.Path]::GetFullPath($directory)
        while (-not [string]::IsNullOrWhiteSpace($current) -and
            $current.StartsWith($rootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
            Assert-GithubStatePathSafe -RepoRoot (Split-Path -Parent $normalizedGithubRoot) -Path $current
            if (-not $queue.Add($current)) {
                break
            }
            $parent = Split-Path -Parent $current
            if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $current) {
                break
            }
            $current = $parent
        }
    }

    foreach ($directory in ($queue | Sort-Object Length -Descending)) {
        Assert-GithubStatePathSafe -RepoRoot (Split-Path -Parent $normalizedGithubRoot) -Path $directory
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
            continue
        }
        if (@(Get-ChildItem -LiteralPath $directory -Force).Count -eq 0) {
            Remove-Item -LiteralPath $directory -Force
        }
    }
}

function Invoke-WithPluginMutationLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [Parameter(Mandatory)]
        [scriptblock]$Body
    )

    $stream = Enter-PluginMutationLock -RepoRoot $RepoRoot
    try {
        return & $Body
    }
    finally {
        $stream.Dispose()
    }
}

function Enter-PluginMutationLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot
    )

    $lockPath = Resolve-GithubConstrainedPath -RepoRoot $RepoRoot -RelativePath '.skalary/mutation.lock'
    Assert-GithubStatePathSafe -RepoRoot $RepoRoot -Path $lockPath
    $lockRoot = Split-Path -Parent $lockPath
    if (-not (Test-Path -LiteralPath $lockRoot -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $lockRoot -Force)
    }
    Assert-GithubStatePathSafe -RepoRoot $RepoRoot -Path $lockPath

    return [System.IO.File]::Open(
        $lockPath,
        [System.IO.FileMode]::OpenOrCreate,
        [System.IO.FileAccess]::ReadWrite,
        [System.IO.FileShare]::None)
}

function Get-PluginRemovalJournalSchema {
    [CmdletBinding()]
    param()

    return @'
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "additionalProperties": false,
  "required": ["schemaVersion", "transactionId", "pluginName", "mode", "sourceIdentity", "operationRoot", "receiptBefore", "receiptBeforeSha256", "receiptAfter", "receiptAfterSha256", "entries", "updatedAt"],
  "properties": {
    "schemaVersion": { "const": 1 },
    "transactionId": { "type": "string", "pattern": "^[a-f0-9]{32}$" },
    "pluginName": { "type": "string", "pattern": "^[a-z0-9][a-z0-9-]*$" },
    "mode": { "enum": ["explicit", "retirement"] },
    "sourceIdentity": {
      "type": "object",
      "additionalProperties": false,
      "required": ["version", "kind", "identity"],
      "properties": {
        "version": { "const": 1 },
        "kind": { "enum": ["github", "local"] },
        "identity": { "type": "string", "pattern": "^(github\\.com/[a-z0-9-]+/[a-z0-9._-]+|sha256:[a-f0-9]{64})$" }
      }
    },
    "operationRoot": { "type": "string", "pattern": "^\\.skalary/tmp/removal-[a-f0-9]{32}$" },
    "receiptBefore": { "type": "object" },
    "receiptBeforeSha256": { "type": "string", "pattern": "^[a-f0-9]{64}$" },
    "receiptAfter": { "type": ["object", "null"] },
    "receiptAfterSha256": { "type": ["string", "null"], "pattern": "^[a-f0-9]{64}$" },
    "entries": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["dest", "expectedSha256", "originalSha256", "backupRelativePath", "backupSha256", "phase"],
        "properties": {
          "dest": { "type": "string", "minLength": 1 },
          "expectedSha256": { "type": "string", "pattern": "^[a-f0-9]{64}$" },
          "originalSha256": { "type": "string", "pattern": "^[a-f0-9]{64}$" },
          "backupRelativePath": { "type": "string", "minLength": 1 },
          "backupSha256": { "type": ["string", "null"], "pattern": "^[a-f0-9]{64}$" },
          "phase": { "enum": ["planned", "backed-up", "deleted"] }
        }
      }
    },
    "updatedAt": { "type": "string", "format": "date-time" }
  }
}
'@
}

function Get-PluginRemovalJournalPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [Parameter(Mandatory)]
        [string]$PluginName
    )

    Assert-PluginName -PluginName $PluginName
    return Resolve-GithubConstrainedPath -RepoRoot $RepoRoot -RelativePath ".skalary/journals/remove-$PluginName.json"
}

function Test-PluginReceiptShape {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Receipt,

        [string]$ExpectedPluginName,

        $ExpectedSourceIdentity
    )

    $allowed = @('name', 'version', 'source', 'sourceIdentity', 'ref', 'installedAt', 'degraded', 'evalStatus', 'files')
    $properties = @($Receipt.PSObject.Properties.Name)
    foreach ($property in $properties) {
        if ($property -notin $allowed) {
            throw "Plugin receipt contains unsupported property '$property'."
        }
    }
    foreach ($required in @('name', 'version', 'ref', 'installedAt', 'files')) {
        if ($properties -notcontains $required) {
            throw "Plugin receipt is missing required property '$required'."
        }
    }
    Assert-PluginName -PluginName ([string]$Receipt.name)
    if (-not [string]::IsNullOrWhiteSpace($ExpectedPluginName) -and
        [string]$Receipt.name -cne $ExpectedPluginName) {
        throw 'Plugin receipt identity does not match the requested plugin.'
    }
    [void](ConvertTo-SemVer -Version ([string]$Receipt.version))
    if ([string]$Receipt.ref -cnotmatch '^[a-f0-9]{40}([a-f0-9]{24})?$') {
        throw 'Plugin receipt immutable ref is invalid.'
    }
    $installedAt = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse(
            [string]$Receipt.installedAt,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::RoundtripKind,
            [ref]$installedAt)) {
        throw 'Plugin receipt installedAt timestamp is invalid.'
    }

    $sourceIdentity = Resolve-PluginReceiptSourceIdentity -Receipt $Receipt
    if ($null -ne $ExpectedSourceIdentity -and
        -not (Test-PluginSourceIdentityEqual -Left $sourceIdentity -Right $ExpectedSourceIdentity)) {
        throw 'Plugin receipt source identity does not match the expected recovery source.'
    }

    $files = @($Receipt.files)
    if ($files.Count -eq 0) {
        throw 'Plugin receipt must own at least one file.'
    }
    $destinations = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($entry in $files) {
        $entryProperties = @($entry.PSObject.Properties.Name)
        if ($entryProperties.Count -ne 3 -or
            $entryProperties -notcontains 'dest' -or
            $entryProperties -notcontains 'sha256' -or
            $entryProperties -notcontains 'outcome') {
            throw 'Plugin receipt file entry has an unsupported shape.'
        }
        $dest = [string]$entry.dest
        if (-not $destinations.Add($dest) -or -not (Test-GithubRelativePath -RelativePath $dest)) {
            throw "Plugin receipt contains an invalid or duplicate destination '$dest'."
        }
        if ([string]$entry.sha256 -cnotmatch '^[a-f0-9]{64}$') {
            throw "Plugin receipt contains an invalid hash for '$dest'."
        }
        if ([string]$entry.outcome -cnotin @('installed', 'updated', 'skipped-modified')) {
            throw "Plugin receipt contains an invalid outcome for '$dest'."
        }
    }
    return $sourceIdentity
}

function Test-PluginRemovalJournal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [Parameter(Mandatory)]
        $Journal
    )

    $json = ConvertTo-SortedObject -InputObject $Journal | ConvertTo-Json -Depth 100
    if (-not ($json | Test-Json -Schema (Get-PluginRemovalJournalSchema) -ErrorAction SilentlyContinue)) {
        throw 'Plugin removal journal does not satisfy the version 1 schema.'
    }

    Assert-PluginName -PluginName ([string]$Journal.pluginName)
    Assert-PluginSourceIdentity -SourceIdentity $Journal.sourceIdentity
    [void](Test-PluginReceiptShape -Receipt $Journal.receiptBefore -ExpectedPluginName ([string]$Journal.pluginName) -ExpectedSourceIdentity $Journal.sourceIdentity)
    if ($null -ne $Journal.receiptAfter) {
        [void](Test-PluginReceiptShape -Receipt $Journal.receiptAfter -ExpectedPluginName ([string]$Journal.pluginName) -ExpectedSourceIdentity $Journal.sourceIdentity)
    }
    $expectedOperationRoot = ".skalary/tmp/removal-$([string]$Journal.transactionId)"
    if ([string]$Journal.operationRoot -cne $expectedOperationRoot) {
        throw 'Plugin removal journal operation root does not match its transaction identity.'
    }
    if ((Get-StableJsonSha256 -InputObject $Journal.receiptBefore) -cne [string]$Journal.receiptBeforeSha256) {
        throw 'Plugin removal journal pre-state receipt hash is invalid.'
    }
    if ($null -ne $Journal.receiptAfter) {
        if ([string]::IsNullOrWhiteSpace([string]$Journal.receiptAfterSha256) -or
            (Get-StableJsonSha256 -InputObject $Journal.receiptAfter) -cne [string]$Journal.receiptAfterSha256) {
            throw 'Plugin removal journal post-state receipt hash is invalid.'
        }
    }
    elseif ($null -ne $Journal.receiptAfterSha256) {
        throw 'Plugin removal journal has a post-state hash without a post-state receipt.'
    }

    $operationRoot = Resolve-GithubConstrainedPath -RepoRoot $RepoRoot -RelativePath ([string]$Journal.operationRoot)
    Assert-GithubStatePathSafe -RepoRoot $RepoRoot -Path $operationRoot
    $receiptBeforeByDest = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($receiptEntry in @($Journal.receiptBefore.files)) {
        $receiptBeforeByDest.Add([string]$receiptEntry.dest, $receiptEntry)
    }
    $index = 0
    $destinations = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($entry in @($Journal.entries)) {
        $dest = [string]$entry.dest
        if (-not $destinations.Add($dest)) {
            throw "Plugin removal journal contains duplicate destination '$dest'."
        }
        if (-not $receiptBeforeByDest.ContainsKey($dest) -or
            [string]$receiptBeforeByDest[$dest].sha256 -cne [string]$entry.expectedSha256) {
            throw "Plugin removal journal destination '$dest' is not owned by its receipt pre-state."
        }
        $targetPath = Resolve-GithubConstrainedPath -RepoRoot $RepoRoot -RelativePath $dest
        Assert-GithubStatePathSafe -RepoRoot $RepoRoot -Path $targetPath
        $expectedBackup = "$([string]$Journal.operationRoot)/backups/$('{0:d5}.bak' -f $index)"
        if ([string]$entry.backupRelativePath -cne $expectedBackup) {
            throw "Plugin removal journal backup path for '$dest' is not transaction-derived."
        }
        $backupPath = Resolve-GithubConstrainedPath -RepoRoot $RepoRoot -RelativePath $expectedBackup
        Assert-GithubStatePathSafe -RepoRoot $RepoRoot -Path $backupPath
        if ([string]$entry.phase -ne 'planned') {
            if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
                throw "Plugin removal journal backup is missing for '$dest'."
            }
            $actualBackupSha = Get-FileSha256 -Path $backupPath
            if ($actualBackupSha -cne [string]$entry.backupSha256 -or
                $actualBackupSha -cne [string]$entry.originalSha256) {
                throw "Plugin removal journal backup hash is invalid for '$dest'."
            }
        }
        $index++
    }

    if ($null -ne $Journal.receiptAfter) {
        $receiptAfterByDest = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
        foreach ($receiptEntry in @($Journal.receiptAfter.files)) {
            $receiptAfterByDest.Add([string]$receiptEntry.dest, $receiptEntry)
        }
        foreach ($dest in $receiptBeforeByDest.Keys) {
            if ($destinations.Contains($dest)) {
                if ($receiptAfterByDest.ContainsKey($dest)) {
                    throw "Plugin removal journal post-state still owns deleted destination '$dest'."
                }
                continue
            }
            if (-not $receiptAfterByDest.ContainsKey($dest) -or
                [string]$receiptAfterByDest[$dest].sha256 -cne [string]$receiptBeforeByDest[$dest].sha256) {
                throw "Plugin removal journal post-state changed unrelated destination '$dest'."
            }
        }
        if ($receiptAfterByDest.Count -ne ($receiptBeforeByDest.Count - $destinations.Count)) {
            throw 'Plugin removal journal post-state introduced unrelated receipt ownership.'
        }
    }
}

function Write-PluginRemovalJournal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [Parameter(Mandatory)]
        $Journal
    )

    $Journal.updatedAt = (Get-Date).ToUniversalTime().ToString('o')
    Test-PluginRemovalJournal -RepoRoot $RepoRoot -Journal $Journal
    $journalPath = Get-PluginRemovalJournalPath -RepoRoot $RepoRoot -PluginName ([string]$Journal.pluginName)
    Assert-GithubStatePathSafe -RepoRoot $RepoRoot -Path $journalPath
    $journalRoot = Split-Path -Parent $journalPath
    if (-not (Test-Path -LiteralPath $journalRoot -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $journalRoot -Force)
    }
    Assert-GithubStatePathSafe -RepoRoot $RepoRoot -Path $journalPath
    Write-JsonFileStable -Path $journalPath -InputObject $Journal
    return $journalPath
}

function Read-PluginRemovalJournal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [Parameter(Mandatory)]
        [string]$PluginName
    )

    $journalPath = Get-PluginRemovalJournalPath -RepoRoot $RepoRoot -PluginName $PluginName
    Assert-GithubStatePathSafe -RepoRoot $RepoRoot -Path $journalPath
    if (-not (Test-Path -LiteralPath $journalPath -PathType Leaf)) {
        return $null
    }
    Assert-GithubStatePathSafe -RepoRoot $RepoRoot -Path $journalPath
    $journal = Read-JsonFile -Path $journalPath
    Test-PluginRemovalJournal -RepoRoot $RepoRoot -Journal $journal
    if ([string]$journal.pluginName -cne $PluginName) {
        throw 'Plugin removal journal identity does not match its confined file name.'
    }
    return $journal
}

function Remove-PluginRemovalTransactionArtifacts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [Parameter(Mandatory)]
        $Journal
    )

    $journalPath = Get-PluginRemovalJournalPath -RepoRoot $RepoRoot -PluginName ([string]$Journal.pluginName)
    $operationRoot = Resolve-GithubConstrainedPath -RepoRoot $RepoRoot -RelativePath ([string]$Journal.operationRoot)
    Assert-GithubStatePathSafe -RepoRoot $RepoRoot -Path $journalPath
    Assert-GithubStatePathSafe -RepoRoot $RepoRoot -Path $operationRoot
    if (Test-Path -LiteralPath $journalPath -PathType Leaf) {
        Remove-Item -LiteralPath $journalPath -Force
    }
    if (Test-Path -LiteralPath $operationRoot -PathType Container) {
        Remove-Item -LiteralPath $operationRoot -Recurse -Force
    }
}

function Invoke-PluginRemovalRecovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [Parameter(Mandatory)]
        [string]$PluginName,

        $ExpectedSourceIdentity,

        [string]$ExpectedRef,

        [string]$ExpectedVersion
    )

    $journal = Read-PluginRemovalJournal -RepoRoot $RepoRoot -PluginName $PluginName
    if ($null -eq $journal) {
        return $false
    }
    if ($null -ne $ExpectedSourceIdentity -and
        -not (Test-PluginSourceIdentityEqual -Left $journal.sourceIdentity -Right $ExpectedSourceIdentity)) {
        throw "Plugin removal journal source identity does not match recovery scope for '$PluginName'."
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedRef) -and
        [string]$journal.receiptBefore.ref -cne $ExpectedRef) {
        throw "Plugin removal journal immutable ref does not match recovery scope for '$PluginName'."
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedVersion) -and
        [string]$journal.receiptBefore.version -cne $ExpectedVersion) {
        throw "Plugin removal journal version does not match recovery scope for '$PluginName'."
    }

    $receiptPath = Get-PluginReceiptPath -RepoRoot $RepoRoot -PluginName $PluginName
    Assert-GithubStatePathSafe -RepoRoot $RepoRoot -Path $receiptPath
    if (Test-Path -LiteralPath $receiptPath -PathType Leaf) {
        $currentReceipt = Read-JsonFile -Path $receiptPath
        $currentSha = Get-StableJsonSha256 -InputObject $currentReceipt
        $allowed = $currentSha -ceq [string]$journal.receiptBeforeSha256
        if (-not $allowed -and $null -ne $journal.receiptAfterSha256) {
            $allowed = $currentSha -ceq [string]$journal.receiptAfterSha256
        }
        if (-not $allowed) {
            throw "Plugin '$PluginName' receipt changed across removal recovery; refusing mixed-version rollback."
        }
    }
    elseif ($null -ne $journal.receiptAfter) {
        throw "Plugin '$PluginName' receipt is missing across a partial removal transaction."
    }
    elseif (@($journal.entries).Count -ne @($journal.receiptBefore.files).Count) {
        throw "Plugin '$PluginName' journal has no post-state receipt and does not cover every pre-state destination."
    }

    foreach ($entry in @($journal.entries)) {
        if ([string]$entry.phase -eq 'planned') {
            continue
        }
        $targetPath = Resolve-GithubConstrainedPath -RepoRoot $RepoRoot -RelativePath ([string]$entry.dest)
        $backupPath = Resolve-GithubConstrainedPath -RepoRoot $RepoRoot -RelativePath ([string]$entry.backupRelativePath)
        Assert-GithubStatePathSafe -RepoRoot $RepoRoot -Path $targetPath
        Assert-GithubStatePathSafe -RepoRoot $RepoRoot -Path $backupPath
        if (Test-Path -LiteralPath $targetPath -PathType Leaf) {
            if ((Get-FileSha256 -Path $targetPath) -cne [string]$entry.originalSha256) {
                throw "Plugin removal recovery found unexpected content at '$([string]$entry.dest)'."
            }
            continue
        }
        $targetRoot = Split-Path -Parent $targetPath
        if (-not (Test-Path -LiteralPath $targetRoot -PathType Container)) {
            [void](New-Item -ItemType Directory -Path $targetRoot -Force)
        }
        Assert-GithubStatePathSafe -RepoRoot $RepoRoot -Path $targetPath
        Copy-Item -LiteralPath $backupPath -Destination $targetPath -Force
        if ((Get-FileSha256 -Path $targetPath) -cne [string]$entry.originalSha256) {
            throw "Plugin removal recovery failed to restore '$([string]$entry.dest)'."
        }
    }

    $receiptRoot = Split-Path -Parent $receiptPath
    if (-not (Test-Path -LiteralPath $receiptRoot -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $receiptRoot -Force)
    }
    Assert-GithubStatePathSafe -RepoRoot $RepoRoot -Path $receiptPath
    Write-JsonFileStable -Path $receiptPath -InputObject $journal.receiptBefore
    if ((Get-StableJsonSha256 -InputObject (Read-JsonFile -Path $receiptPath)) -cne [string]$journal.receiptBeforeSha256) {
        throw "Plugin '$PluginName' receipt recovery verification failed."
    }

    Remove-PluginRemovalTransactionArtifacts -RepoRoot $RepoRoot -Journal $journal
    return $true
}

function Reset-FailedPluginRetirementState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [Parameter(Mandatory)]
        [string]$PluginName
    )

    return Invoke-WithPluginMutationLock -RepoRoot $RepoRoot -Body {
        $statePath = Get-PluginRetirementStatePath -RepoRoot $RepoRoot -PluginName $PluginName
        $receiptPath = Get-PluginReceiptPath -RepoRoot $RepoRoot -PluginName $PluginName
        $journalPath = Get-PluginRemovalJournalPath -RepoRoot $RepoRoot -PluginName $PluginName
        foreach ($path in @($statePath, $receiptPath, $journalPath)) {
            Assert-GithubStatePathSafe -RepoRoot $RepoRoot -Path $path
        }

        $state = Read-PluginRetirementState -RepoRoot $RepoRoot -PluginName $PluginName
        if ($null -eq $state -or [string]$state.status -cne 'failed') {
            throw "Plugin '$PluginName' has no failed retirement state to recover."
        }
        $expectedSource = $state.prior.sourceIdentity
        if (Test-Path -LiteralPath $journalPath -PathType Leaf) {
            [void](Invoke-PluginRemovalRecovery -RepoRoot $RepoRoot -PluginName $PluginName -ExpectedSourceIdentity $expectedSource -ExpectedRef ([string]$state.prior.ref) -ExpectedVersion ([string]$state.prior.version))
        }

        $receipt = Read-PluginReceipt -RepoRoot $RepoRoot -PluginName $PluginName
        if ($null -eq $receipt -or
            -not (Test-PluginSourceIdentityEqual -Left (Resolve-PluginReceiptSourceIdentity -Receipt $receipt) -Right $expectedSource) -or
            [string]$receipt.ref -cne [string]$state.prior.ref -or
            [string]$receipt.version -cne [string]$state.prior.version) {
            throw "Plugin '$PluginName' recovery pre-state does not match the failed retirement authority."
        }

        $receiptByDest = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
        foreach ($entry in @($receipt.files)) {
            $receiptByDest.Add([string]$entry.dest, $entry)
        }
        foreach ($entry in @($state.affectedFiles)) {
            $dest = [string]$entry.dest
            $targetPath = Resolve-GithubConstrainedPath -RepoRoot $RepoRoot -RelativePath $dest
            Assert-GithubStatePathSafe -RepoRoot $RepoRoot -Path $targetPath
            if (-not $receiptByDest.ContainsKey($dest) -or
                [string]$receiptByDest[$dest].sha256 -cne [string]$entry.expectedSha256) {
                throw "Plugin '$PluginName' recovery receipt does not own expected destination '$dest'."
            }
            $observed = [string]$entry.observedSha256
            if ([string]::IsNullOrWhiteSpace($observed)) {
                if (Test-Path -LiteralPath $targetPath -PathType Leaf) {
                    throw "Plugin '$PluginName' recovery expected '$dest' to be absent."
                }
            }
            elseif (-not (Test-Path -LiteralPath $targetPath -PathType Leaf) -or
                (Get-FileSha256 -Path $targetPath) -cne $observed) {
                throw "Plugin '$PluginName' recovery content does not match the recorded pre-state for '$dest'."
            }
        }

        $state.status = 'preview'
        $state.transactionId = [guid]::NewGuid().ToString('N')
        $state.updatedAt = (Get-Date).ToUniversalTime().ToString('o')
        if ($state.PSObject.Properties.Name -contains 'error') {
            $state.PSObject.Properties.Remove('error')
        }
        [void](Write-PluginRetirementState -RepoRoot $RepoRoot -State $state)
        return $state
    }
}

function Get-RetirementRemovalAuthority {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Receipt,

        [Parameter(Mandatory)]
        $PayloadSet
    )

    $payloadSource = [pscustomobject][ordered]@{
        version = 1
        kind = [string]$PayloadSet.sourceKind
        identity = [string]$PayloadSet.sourceIdentity
    }
    Assert-PluginSourceIdentity -SourceIdentity $payloadSource
    $receiptSource = Resolve-PluginReceiptSourceIdentity -Receipt $Receipt
    if (-not (Test-PluginSourceIdentityEqual -Left $receiptSource -Right $payloadSource)) {
        throw 'Retirement payload source does not match the installed receipt source.'
    }
    if ([string]$Receipt.ref -cne [string]$PayloadSet.ref -or
        [string]$Receipt.version -cne [string]$PayloadSet.version) {
        throw 'Retirement payload ref/version does not match the installed receipt pre-state.'
    }

    $receiptByDest = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($entry in @($Receipt.files)) {
        $dest = [string]$entry.dest
        if ($receiptByDest.ContainsKey($dest)) {
            throw "Installed receipt contains duplicate destination '$dest'."
        }
        $receiptByDest.Add($dest, $entry)
    }

    $authority = @()
    $payloadDestinations = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($file in @($PayloadSet.files)) {
        $dest = [string]$file.dest
        if (-not $payloadDestinations.Add($dest)) {
            throw "Retirement payload contains duplicate destination '$dest'."
        }
        if ($receiptByDest.ContainsKey($dest) -and
            [string]$receiptByDest[$dest].sha256 -ceq [string]$file.sha256) {
            $authority += , $receiptByDest[$dest]
        }
    }

    return [pscustomobject]@{
        Entries = $authority
        SourceIdentity = $payloadSource
    }
}

function Invoke-PluginRemovalPrimitive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [Parameter(Mandatory)]
        [string]$PluginName,

        [ValidateSet('explicit', 'retirement')]
        [string]$Mode = 'explicit',

        [switch]$Force,

        $PayloadSet,

        [switch]$LockHeld,

        [ValidateSet('', 'after-journal', 'after-backup', 'after-delete', 'after-receipt')]
        [string]$FaultAt = ''
    )

    Assert-PluginName -PluginName $PluginName
    if ($Mode -eq 'retirement' -and $null -eq $PayloadSet) {
        throw 'Retirement removal requires a tombstone payload set.'
    }
    if ($Mode -eq 'retirement' -and $Force) {
        throw 'Automatic retirement cannot use force removal.'
    }

    $operation = {
        $receiptPath = Get-PluginReceiptPath -RepoRoot $RepoRoot -PluginName $PluginName
        $journalPath = Get-PluginRemovalJournalPath -RepoRoot $RepoRoot -PluginName $PluginName
        $statePath = Get-PluginRetirementStatePath -RepoRoot $RepoRoot -PluginName $PluginName
        foreach ($stateFile in @($receiptPath, $journalPath, $statePath)) {
            Assert-GithubStatePathSafe -RepoRoot $RepoRoot -Path $stateFile
        }

        $existingJournal = Read-PluginRemovalJournal -RepoRoot $RepoRoot -PluginName $PluginName
        if ($null -ne $existingJournal) {
            $expectedRecoverySource = if ($Mode -eq 'retirement') {
                [pscustomobject][ordered]@{
                    version = 1
                    kind = [string]$PayloadSet.sourceKind
                    identity = [string]$PayloadSet.sourceIdentity
                }
            }
            else {
                $null
            }
            $expectedRecoveryRef = if ($Mode -eq 'retirement') { [string]$PayloadSet.ref } else { $null }
            $expectedRecoveryVersion = if ($Mode -eq 'retirement') { [string]$PayloadSet.version } else { $null }
            [void](Invoke-PluginRemovalRecovery -RepoRoot $RepoRoot -PluginName $PluginName -ExpectedSourceIdentity $expectedRecoverySource -ExpectedRef $expectedRecoveryRef -ExpectedVersion $expectedRecoveryVersion)
        }

        $receipt = Read-PluginReceipt -RepoRoot $RepoRoot -PluginName $PluginName
        if ($null -eq $receipt) {
            throw "Plugin '$PluginName' is not installed (receipt missing)."
        }
        $sourceIdentity = Test-PluginReceiptShape -Receipt $receipt -ExpectedPluginName $PluginName
        $authorityEntries = @($receipt.files)
        if ($Mode -eq 'retirement') {
            $authority = Get-RetirementRemovalAuthority -Receipt $receipt -PayloadSet $PayloadSet
            $sourceIdentity = $authority.SourceIdentity
            $authorityEntries = @($authority.Entries)
            if ($authorityEntries.Count -eq 0) {
                return [pscustomobject]@{
                    PluginName = $PluginName
                    Mode = $Mode
                    RemovedCount = 0
                    ModifiedCount = 0
                    MissingCount = 0
                    RemainingCount = @($receipt.files).Count
                    SourceIdentity = $sourceIdentity
                }
            }
        }

        $authorityByDest = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
        foreach ($entry in $authorityEntries) {
            $dest = [string]$entry.dest
            if ($authorityByDest.ContainsKey($dest)) {
                throw "Removal authority contains duplicate destination '$dest'."
            }
            $targetPath = Resolve-GithubConstrainedPath -RepoRoot $RepoRoot -RelativePath $dest
            Assert-GithubStatePathSafe -RepoRoot $RepoRoot -Path $targetPath
            $authorityByDest.Add($dest, $entry)
        }
        foreach ($entry in @($receipt.files)) {
            $targetPath = Resolve-GithubConstrainedPath -RepoRoot $RepoRoot -RelativePath ([string]$entry.dest)
            Assert-GithubStatePathSafe -RepoRoot $RepoRoot -Path $targetPath
        }

        $removedDestinations = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        $modifiedDestinations = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        $missingDestinations = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        $deleteCandidates = @()
        foreach ($dest in (Sort-Ordinal -InputObject @($authorityByDest.Keys))) {
            $entry = $authorityByDest[$dest]
            $targetPath = Resolve-GithubConstrainedPath -RepoRoot $RepoRoot -RelativePath $dest
            if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
                [void]$missingDestinations.Add($dest)
                continue
            }
            $actualSha = Get-FileSha256 -Path $targetPath
            if (-not $Force -and
                ([string]$entry.outcome -ceq 'skipped-modified' -or
                $actualSha -cne [string]$entry.sha256)) {
                [void]$modifiedDestinations.Add($dest)
                continue
            }
            $deleteCandidates += , [pscustomobject]@{
                Dest = $dest
                ExpectedSha256 = [string]$entry.sha256
                OriginalSha256 = $actualSha
                TargetPath = $targetPath
            }
        }

        $transactionId = [guid]::NewGuid().ToString('N')
        $operationRelativeRoot = ".skalary/tmp/removal-$transactionId"
        $operationRoot = Resolve-GithubConstrainedPath -RepoRoot $RepoRoot -RelativePath $operationRelativeRoot
        Assert-GithubStatePathSafe -RepoRoot $RepoRoot -Path $operationRoot

        $journalEntries = @()
        $index = 0
        foreach ($candidate in $deleteCandidates) {
            $backupRelativePath = "$operationRelativeRoot/backups/$('{0:d5}.bak' -f $index)"
            $backupPath = Resolve-GithubConstrainedPath -RepoRoot $RepoRoot -RelativePath $backupRelativePath
            Assert-GithubStatePathSafe -RepoRoot $RepoRoot -Path $backupPath
            $journalEntries += , [pscustomobject][ordered]@{
                dest = [string]$candidate.Dest
                expectedSha256 = [string]$candidate.ExpectedSha256
                originalSha256 = [string]$candidate.OriginalSha256
                backupRelativePath = $backupRelativePath
                backupSha256 = $null
                phase = 'planned'
            }
            $index++
        }
        foreach ($dest in (Sort-Ordinal -InputObject @($missingDestinations))) {
            $backupRelativePath = "$operationRelativeRoot/backups/$('{0:d5}.bak' -f $index)"
            $journalEntries += , [pscustomobject][ordered]@{
                dest = $dest
                expectedSha256 = [string]$authorityByDest[$dest].sha256
                originalSha256 = [string]$authorityByDest[$dest].sha256
                backupRelativePath = $backupRelativePath
                backupSha256 = $null
                phase = 'planned'
            }
            $index++
        }

        $journal = [pscustomobject][ordered]@{
            schemaVersion = 1
            transactionId = $transactionId
            pluginName = $PluginName
            mode = $Mode
            sourceIdentity = $sourceIdentity
            operationRoot = $operationRelativeRoot
            receiptBefore = $receipt
            receiptBeforeSha256 = Get-StableJsonSha256 -InputObject $receipt
            receiptAfter = $null
            receiptAfterSha256 = $null
            entries = $journalEntries
            updatedAt = (Get-Date).ToUniversalTime().ToString('o')
        }

        try {
            [void](Write-PluginRemovalJournal -RepoRoot $RepoRoot -Journal $journal)
            if ($FaultAt -eq 'after-journal') { throw 'Injected plugin removal fault after journal.' }
            [void](New-Item -ItemType Directory -Path (Join-Path $operationRoot 'backups') -Force)
            Assert-GithubStatePathSafe -RepoRoot $RepoRoot -Path $operationRoot

            for ($entryIndex = 0; $entryIndex -lt $deleteCandidates.Count; $entryIndex++) {
                $candidate = $deleteCandidates[$entryIndex]
                $journalEntry = $journal.entries[$entryIndex]
                $backupPath = Resolve-GithubConstrainedPath -RepoRoot $RepoRoot -RelativePath ([string]$journalEntry.backupRelativePath)
                Assert-GithubStatePathSafe -RepoRoot $RepoRoot -Path $backupPath
                Copy-Item -LiteralPath $candidate.TargetPath -Destination $backupPath -Force
                $backupSha = Get-FileSha256 -Path $backupPath
                if ($backupSha -cne [string]$candidate.OriginalSha256) {
                    throw "Plugin removal backup verification failed for '$([string]$candidate.Dest)'."
                }
                $journalEntry.backupSha256 = $backupSha
                $journalEntry.phase = 'backed-up'
                [void](Write-PluginRemovalJournal -RepoRoot $RepoRoot -Journal $journal)
                if ($FaultAt -eq 'after-backup') { throw 'Injected plugin removal fault after backup.' }

                Assert-GithubStatePathSafe -RepoRoot $RepoRoot -Path $candidate.TargetPath
                if ((Get-FileSha256 -Path $candidate.TargetPath) -cne [string]$candidate.OriginalSha256) {
                    throw "Plugin removal pre-state changed for '$([string]$candidate.Dest)'."
                }
                Remove-Item -LiteralPath $candidate.TargetPath -Force
                [void]$removedDestinations.Add([string]$candidate.Dest)
                $journalEntry.phase = 'deleted'
                [void](Write-PluginRemovalJournal -RepoRoot $RepoRoot -Journal $journal)
                if ($FaultAt -eq 'after-delete') { throw 'Injected plugin removal fault after delete.' }
            }

            $nextFiles = @()
            foreach ($entry in @($receipt.files)) {
                $dest = [string]$entry.dest
                if ($removedDestinations.Contains($dest) -or $missingDestinations.Contains($dest)) {
                    continue
                }
                $nextOutcome = if ($modifiedDestinations.Contains($dest)) { 'skipped-modified' } else { [string]$entry.outcome }
                $nextFiles += , [pscustomobject][ordered]@{
                    dest = $dest
                    sha256 = [string]$entry.sha256
                    outcome = $nextOutcome
                }
            }

            $nextReceipt = $null
            if ($nextFiles.Count -gt 0) {
                $nextReceipt = [ordered]@{}
                foreach ($property in $receipt.PSObject.Properties) {
                    if ($property.Name -notin @('files', 'degraded')) {
                        $nextReceipt[$property.Name] = $property.Value
                    }
                }
                $nextReceipt.files = $nextFiles
                $nextReceipt.degraded = $true
                $nextReceipt = [pscustomobject]$nextReceipt
            }
            $journal.receiptAfter = $nextReceipt
            $journal.receiptAfterSha256 = if ($null -ne $nextReceipt) { Get-StableJsonSha256 -InputObject $nextReceipt } else { $null }
            [void](Write-PluginRemovalJournal -RepoRoot $RepoRoot -Journal $journal)

            Assert-GithubStatePathSafe -RepoRoot $RepoRoot -Path $receiptPath
            if ($null -eq $nextReceipt) {
                if (Test-Path -LiteralPath $receiptPath -PathType Leaf) {
                    Remove-Item -LiteralPath $receiptPath -Force
                }
            }
            else {
                Write-JsonFileStable -Path $receiptPath -InputObject $nextReceipt
            }
            if ($FaultAt -eq 'after-receipt') { throw 'Injected plugin removal fault after receipt.' }

            $deletedParentDirs = @($deleteCandidates | ForEach-Object { Split-Path -Parent $_.TargetPath })
            Invoke-ParentDirectoryPrune -Directories $deletedParentDirs -GithubRoot (Join-Path $RepoRoot '.github')
            Remove-PluginRemovalTransactionArtifacts -RepoRoot $RepoRoot -Journal $journal

            return [pscustomobject]@{
                PluginName = $PluginName
                Mode = $Mode
                RemovedCount = $removedDestinations.Count
                ModifiedCount = $modifiedDestinations.Count
                MissingCount = $missingDestinations.Count
                RemainingCount = $nextFiles.Count
                SourceIdentity = $sourceIdentity
            }
        }
        catch {
            $failure = $_
            try {
                [void](Invoke-PluginRemovalRecovery -RepoRoot $RepoRoot -PluginName $PluginName -ExpectedSourceIdentity $sourceIdentity -ExpectedRef ([string]$receipt.ref) -ExpectedVersion ([string]$receipt.version))
            }
            catch {
                throw "Plugin removal failed and exact recovery was refused: $($failure.Exception.Message) Recovery error: $($_.Exception.Message)"
            }
            throw $failure
        }
    }
    if ($LockHeld) {
        return & $operation
    }
    return Invoke-WithPluginMutationLock -RepoRoot $RepoRoot -Body $operation
}

function Get-PluginReceiptPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [Parameter(Mandatory)]
        [string]$PluginName
    )

    Assert-PluginName -PluginName $PluginName
    return Resolve-GithubConstrainedPath -RepoRoot $RepoRoot -RelativePath ".skalary/receipts/$PluginName.json"
}

function Read-PluginReceipt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [Parameter(Mandatory)]
        [string]$PluginName
    )

    $receiptPath = Get-PluginReceiptPath -RepoRoot $RepoRoot -PluginName $PluginName
    if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) {
        return $null
    }

    return Read-JsonFile -Path $receiptPath
}

function Test-PluginReceiptUpToDate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [Parameter(Mandatory)]
        $Plugin
    )

    $receipt = Read-PluginReceipt -RepoRoot $RepoRoot -PluginName ([string]$Plugin.name)
    if ($null -eq $receipt) {
        return $false
    }

    if ([string]$receipt.version -ne [string]$Plugin.version) {
        return $false
    }

    $receiptFiles = @($receipt.files)
    if ($receiptFiles.Count -eq 0) {
        return $false
    }

    $receiptByDest = @{}
    foreach ($receiptFile in $receiptFiles) {
        $dest = [string]$receiptFile.dest
        if (-not [string]::IsNullOrWhiteSpace($dest)) {
            $receiptByDest[$dest] = $receiptFile
        }
    }

    foreach ($pluginFile in @($Plugin.files)) {
        $src = [string]$pluginFile.src
        if ($src -match '^evals(?:/|$)') {
            continue
        }

        $dest = [string]$pluginFile.dest
        if (-not $receiptByDest.ContainsKey($dest)) {
            return $false
        }

        if ([string]$receiptByDest[$dest].sha256 -ne [string]$pluginFile.sha256) {
            return $false
        }

        $targetPath = Resolve-GithubConstrainedPath -RepoRoot $RepoRoot -RelativePath $dest
        if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
            return $false
        }
        if ((Get-FileSha256 -Path $targetPath) -ne [string]$pluginFile.sha256) {
            return $false
        }
    }

    return $true
}

function Resolve-PluginDependencyOrder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$PluginsByName,

        [Parameter(Mandatory)]
        [string]$RootPluginName,

        [Parameter(Mandatory)]
        [string]$RepoRoot
    )

    if (-not $PluginsByName.ContainsKey($RootPluginName)) {
        throw "Plugin '$RootPluginName' is not present in registry.json."
    }

    $stateByName = @{}
    $topologicalNames = [System.Collections.Generic.List[string]]::new()

    function Search-DependencyNode {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$Name,

            [string[]]$Stack
        )

        if (-not $PluginsByName.ContainsKey($Name)) {
            $parentName = if ($Stack.Count -gt 0) { $Stack[$Stack.Count - 1] } else { $RootPluginName }
            throw "Plugin '$parentName' depends on missing plugin '$Name'."
        }

        $state = if ($stateByName.ContainsKey($Name)) { [int]$stateByName[$Name] } else { 0 }
        if ($state -eq 1) {
            $cycle = @($Stack + $Name) -join ' -> '
            throw "Dependency cycle detected: $cycle"
        }
        if ($state -eq 2) {
            return
        }

        $stateByName[$Name] = 1
        $plugin = $PluginsByName[$Name]
        $dependencies = @($plugin.dependencies | ForEach-Object { [string]$_ } | Sort-Object)
        foreach ($dependencyName in $dependencies) {
            Search-DependencyNode -Name $dependencyName -Stack ($Stack + $Name)
        }

        $stateByName[$Name] = 2
        $topologicalNames.Add($Name)
    }

    Search-DependencyNode -Name $RootPluginName -Stack @()

    $ordered = @()
    $pending = @()
    foreach ($name in $topologicalNames) {
        $plugin = $PluginsByName[$name]
        $ordered += , $plugin
        if (-not (Test-PluginReceiptUpToDate -RepoRoot $RepoRoot -Plugin $plugin)) {
            $pending += , $plugin
        }
    }

    return [pscustomobject]@{
        Ordered = $ordered
        Pending = $pending
    }
}
