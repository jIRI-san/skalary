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
    $suffix = "@$ref"
    if ([string]::IsNullOrWhiteSpace($legacy) -or
        $ref -notmatch '^[a-f0-9]{40}([a-f0-9]{24})?$' -or
        -not $legacy.EndsWith($suffix, [System.StringComparison]::Ordinal) -or
        $legacy.Length -le $suffix.Length) {
        throw 'Legacy plugin receipt source identity is ambiguous and requires an explicit migration.'
    }

    $label = $legacy.Substring(0, $legacy.Length - $suffix.Length)
    if ($label.StartsWith('remote:', [System.StringComparison]::Ordinal)) {
        return New-PluginSourceIdentity -Repository $label.Substring('remote:'.Length)
    }
    if ($label.StartsWith('local:', [System.StringComparison]::Ordinal)) {
        return New-PluginSourceIdentity -LocalPath $label.Substring('local:'.Length)
    }

    throw 'Legacy plugin receipt source identity is ambiguous and requires an explicit migration.'
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
    Set-Content -LiteralPath $Path -Value "$json`n" -Encoding utf8
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

function Assert-PluginRetirementStatePathSafe {
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
        throw 'Plugin retirement state path escapes the .github root.'
    }

    $current = $githubRoot
    foreach ($segment in @($relative.Split(
                [System.IO.Path]::DirectorySeparatorChar,
                [System.StringSplitOptions]::RemoveEmptyEntries))) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or
                -not [string]::IsNullOrWhiteSpace([string]$item.LinkType)) {
                throw "Plugin retirement state path traverses a link or reparse point at '$current'."
            }
        }
        $current = Join-Path $current $segment
    }

    if (Test-Path -LiteralPath $current) {
        $item = Get-Item -LiteralPath $current -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or
            -not [string]::IsNullOrWhiteSpace([string]$item.LinkType)) {
            throw "Plugin retirement state path resolves to a link or reparse point at '$current'."
        }
    }
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
