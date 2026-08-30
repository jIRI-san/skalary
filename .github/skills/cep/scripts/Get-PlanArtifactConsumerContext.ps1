#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string[]]$PlanId,

    [Parameter(Mandatory)]
    [string[]]$ArtifactKind,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string[]]$Relationship,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$RepoRoot,

    [ValidateRange(1, 16MB)]
    [int]$MaxArtifactBytes = 128KB,

    [ValidateRange(1, 64MB)]
    [int]$MaxTotalBytes = 512KB,

    [ValidateRange(1, 256)]
    [int]$MaxCandidates = 32,

    [ValidateRange(1, 120)]
    [int]$ResolverTimeoutSeconds = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRootPath = [System.IO.Path]::GetFullPath($RepoRoot)
$resolverPath = Join-Path $PSScriptRoot 'Get-PlanArtifactContext.ps1'
if (-not (Test-Path -LiteralPath $resolverPath -PathType Leaf)) {
    throw "Installed plan-artifact resolver is missing: '$resolverPath'."
}
$secretGuardPath = Join-Path $PSScriptRoot 'SecretGuard.psm1'
if (-not (Test-Path -LiteralPath $secretGuardPath -PathType Leaf)) {
    throw "Installed secret guard is missing: '$secretGuardPath'."
}
Import-Module $secretGuardPath -DisableNameChecking

function Get-BoundedResolverDiagnostic {
    param(
        [AllowEmptyString()][AllowNull()][string]$Value,
        [int]$Limit = 512
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return 'no diagnostic was emitted'
    }
    $secretTypes = @(Find-HighConfidenceSecret -Value $Value)
    if ($secretTypes.Count -gt 0) {
        return "redacted high-confidence credential type(s): $($secretTypes -join ', ')"
    }
    $singleLine = ($Value -replace '[\r\n\t]+', ' ').Trim()
    if ($singleLine.Length -le $Limit) {
        return $singleLine
    }
    return $singleLine.Substring(0, $Limit) + '…'
}

function Test-JsonInteger {
    param([AllowNull()][object]$Value)

    return $Value -is [byte] -or
    $Value -is [sbyte] -or
    $Value -is [int16] -or
    $Value -is [uint16] -or
    $Value -is [int32] -or
    $Value -is [uint32] -or
    $Value -is [int64] -or
    $Value -is [uint64]
}

$request = [ordered]@{
    PlanId = @($PlanId)
    ArtifactKind = @($ArtifactKind)
    Relationship = @($Relationship)
    RepoRoot = $repoRootPath
    MaxArtifactBytes = $MaxArtifactBytes
    MaxTotalBytes = $MaxTotalBytes
    MaxCandidates = $MaxCandidates
}
$childScript = @'
$ErrorActionPreference = 'Stop'
try {
    $request = $env:SKALARY_PLAN_ARTIFACT_REQUEST | ConvertFrom-Json -AsHashtable -Depth 10
    & $env:SKALARY_PLAN_ARTIFACT_RESOLVER @request -Format Json
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
'@
$encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childScript))
$start = [System.Diagnostics.ProcessStartInfo]::new()
$start.FileName = (Get-Process -Id $PID).Path
$start.UseShellExecute = $false
$start.RedirectStandardOutput = $true
$start.RedirectStandardError = $true
$start.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
$start.StandardErrorEncoding = [System.Text.UTF8Encoding]::new($false)
$start.Environment['SKALARY_PLAN_ARTIFACT_REQUEST'] = $request | ConvertTo-Json -Depth 10 -Compress
$start.Environment['SKALARY_PLAN_ARTIFACT_RESOLVER'] = $resolverPath
[void]$start.ArgumentList.Add('-NoProfile')
[void]$start.ArgumentList.Add('-EncodedCommand')
[void]$start.ArgumentList.Add($encodedCommand)

$process = [System.Diagnostics.Process]::new()
$process.StartInfo = $start
$stdout = ''
$stderr = ''
$exitCode = $null
try {
    [void]$process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($ResolverTimeoutSeconds * 1000)) {
        try {
            $process.Kill($true)
        }
        catch {
            throw "Plan-artifact resolver timed out after $ResolverTimeoutSeconds seconds and process-tree termination failed: $($_.Exception.Message)"
        }
        if (-not $process.WaitForExit(5000)) {
            throw "Plan-artifact resolver timed out after $ResolverTimeoutSeconds seconds and did not terminate within 5 seconds."
        }
        [void][System.Threading.Tasks.Task]::WaitAll(
            [System.Threading.Tasks.Task[]]@($stdoutTask, $stderrTask),
            5000
        )
        throw "Plan-artifact resolver '$resolverPath' timed out after $ResolverTimeoutSeconds seconds; its process tree was terminated."
    }
    if (-not [System.Threading.Tasks.Task]::WaitAll(
            [System.Threading.Tasks.Task[]]@($stdoutTask, $stderrTask),
            5000
        )) {
        throw "Plan-artifact resolver '$resolverPath' exited but redirected output did not drain within 5 seconds."
    }
    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult().Trim()
    $exitCode = $process.ExitCode
}
finally {
    $process.Dispose()
}
if ($exitCode -ne 0) {
    $diagnostic = Get-BoundedResolverDiagnostic -Value $stderr
    throw "Plan-artifact resolver '$resolverPath' exited $exitCode`: $diagnostic"
}
if (-not [string]::IsNullOrWhiteSpace($stderr)) {
    $diagnostic = Get-BoundedResolverDiagnostic -Value $stderr
    Write-Warning "Plan-artifact resolver '$resolverPath' wrote stderr after a successful exit: $diagnostic"
}
if ([string]::IsNullOrWhiteSpace($stdout)) {
    throw "Plan-artifact resolver '$resolverPath' returned whitespace-only output; expected a top-level JSON array."
}

try {
    $document = [System.Text.Json.JsonDocument]::Parse($stdout)
}
catch {
    $excerpt = Get-BoundedResolverDiagnostic -Value $stdout -Limit 240
    throw "Plan-artifact resolver '$resolverPath' returned malformed JSON: $($_.Exception.Message) Output excerpt: $excerpt"
}
try {
    if ($document.RootElement.ValueKind -ne [System.Text.Json.JsonValueKind]::Array) {
        throw "Plan-artifact resolver '$resolverPath' JSON must have a top-level array; received $($document.RootElement.ValueKind)."
    }
}
finally {
    $document.Dispose()
}

$results = @($stdout | ConvertFrom-Json -AsHashtable -Depth 20)
$expectedKeys = @(
    'artifactKind', 'authority', 'byteCount', 'content', 'isArchived', 'isUntrusted',
    'layout', 'path', 'planId', 'reason', 'relationship', 'status'
)
$resultIndex = 0
foreach ($result in $results) {
    $identity = "result[$resultIndex]"
    if ($result -isnot [System.Collections.IDictionary]) {
        $entryType = if ($null -eq $result) { 'null' } else { $result.GetType().FullName }
        throw "Plan-artifact resolver $identity must be an object; received $entryType."
    }
    if ($result.Contains('planId') -and -not [string]::IsNullOrWhiteSpace([string]$result['planId'])) {
        $identity += " planId='$($result['planId'])'"
    }
    if ($result.Contains('artifactKind') -and -not [string]::IsNullOrWhiteSpace([string]$result['artifactKind'])) {
        $identity += " artifactKind='$($result['artifactKind'])'"
    }
    if ($result.Contains('path') -and -not [string]::IsNullOrWhiteSpace([string]$result['path'])) {
        $identity += " path='$($result['path'])'"
    }
    $actualKeys = @($result.Keys | ForEach-Object { [string]$_ } | Sort-Object)
    $missingKeys = @($expectedKeys | Where-Object { $actualKeys -cnotcontains $_ } | Sort-Object)
    $unexpectedKeys = @($actualKeys | Where-Object { $expectedKeys -cnotcontains $_ } | Sort-Object)
    if ($missingKeys.Count -gt 0 -or $unexpectedKeys.Count -gt 0) {
        throw "Plan-artifact resolver $identity violates the closed public result shape; missing=[$($missingKeys -join ',')], unexpected=[$($unexpectedKeys -join ',')]."
    }
    if ([string]$result['status'] -cnotin @('accepted', 'missing', 'refused', 'oversized') -or
        $result['isUntrusted'] -isnot [bool] -or
        $result['isUntrusted'] -ne $true -or
        [string]$result['authority'] -cne 'historical-context-only') {
        throw "Plan-artifact resolver $identity has invalid status or authority metadata."
    }
    if ($null -ne $result['byteCount'] -and
        (-not (Test-JsonInteger -Value $result['byteCount']) -or [int64]$result['byteCount'] -lt 0)) {
        throw "Plan-artifact resolver $identity has an invalid 'byteCount' field."
    }
    if ($result['status'] -ceq 'accepted') {
        foreach ($name in @('planId', 'artifactKind', 'path', 'relationship', 'content')) {
            if ($result[$name] -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$result[$name])) {
                throw "Plan-artifact resolver $identity has an invalid accepted '$name' field."
            }
        }
        if ([string]$result['layout'] -cnotin @('assets', 'legacy') -or
            $result['isArchived'] -isnot [bool] -or
            -not (Test-JsonInteger -Value $result['byteCount']) -or
            [int64]$result['byteCount'] -lt 1 -or
            $null -ne $result['reason']) {
            throw "Plan-artifact resolver $identity has invalid accepted result metadata."
        }
    }
    elseif ($null -ne $result['content']) {
        throw "Plan-artifact resolver $identity leaked content on a non-accepted result."
    }
    elseif ($result['reason'] -isnot [string] -or
        [string]::IsNullOrWhiteSpace([string]$result['reason'])) {
        throw "Plan-artifact resolver $identity has no diagnostic reason."
    }
    $resultIndex++
}

foreach ($result in $results) {
    if ($result['status'] -cne 'accepted') { continue }
    $secretTypes = @(Find-HighConfidenceSecret -Value ([string]$result['content']))
    if ($secretTypes.Count -eq 0) { continue }

    $result['status'] = 'refused'
    $result['content'] = $null
    $result['reason'] =
    "Historical artifact refused before prompt framing: high-confidence credential type(s) $($secretTypes -join ', ') at '$($result['path'])'."
}

$accepted = @($results | Where-Object { $_['status'] -ceq 'accepted' })
$diagnostics = @($results | Where-Object { $_['status'] -cne 'accepted' })
$provenance = @($accepted | ForEach-Object {
        [ordered]@{
            planId = $_['planId']
            artifactKind = $_['artifactKind']
            path = $_['path']
            relationship = $_['relationship']
        }
    })
$untrustedInput = $null
if ($accepted.Count -gt 0) {
    $acceptedJson = ConvertTo-Json -InputObject @($accepted) -Depth 20 -Compress
    $untrustedInput = "<<<UNTRUSTED_INPUT_START>>>`n$acceptedJson`n<<<UNTRUSTED_INPUT_END>>>"
}

[pscustomobject][ordered]@{
    accepted = $accepted
    diagnostics = $diagnostics
    provenance = $provenance
    untrustedInput = $untrustedInput
} | ConvertTo-Json -Depth 20
