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
    [int]$MaxCandidates = 32
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRootPath = [System.IO.Path]::GetFullPath($RepoRoot)
$resolverPath = Join-Path $PSScriptRoot 'Get-PlanArtifactContext.ps1'
if (-not (Test-Path -LiteralPath $resolverPath -PathType Leaf)) {
    throw "Installed plan-artifact resolver is missing: '$resolverPath'."
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
[void]$process.Start()
$stdoutTask = $process.StandardOutput.ReadToEndAsync()
$stderrTask = $process.StandardError.ReadToEndAsync()
$process.WaitForExit()
$stdout = $stdoutTask.GetAwaiter().GetResult()
$stderr = $stderrTask.GetAwaiter().GetResult().Trim()
if ($process.ExitCode -ne 0) {
    $diagnostic = if ([string]::IsNullOrWhiteSpace($stderr)) { 'no diagnostic was emitted' } else { $stderr }
    throw "Plan-artifact resolver exited $($process.ExitCode): $diagnostic"
}

try {
    $document = [System.Text.Json.JsonDocument]::Parse($stdout)
}
catch {
    throw "Plan-artifact resolver returned malformed JSON: $($_.Exception.Message)"
}
try {
    if ($document.RootElement.ValueKind -ne [System.Text.Json.JsonValueKind]::Array) {
        throw 'Plan-artifact resolver JSON must have a top-level array.'
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
foreach ($result in $results) {
    if ($result -isnot [System.Collections.IDictionary]) {
        throw 'Plan-artifact resolver array entries must be objects.'
    }
    $actualKeys = @($result.Keys | ForEach-Object { [string]$_ } | Sort-Object)
    if (($actualKeys -join "`n") -cne (($expectedKeys | Sort-Object) -join "`n")) {
        throw 'Plan-artifact resolver result does not match the closed public result shape.'
    }
    if ([string]$result['status'] -cnotin @('accepted', 'missing', 'refused', 'oversized') -or
        $result['isUntrusted'] -ne $true -or
        [string]$result['authority'] -cne 'historical-context-only') {
        throw 'Plan-artifact resolver result has invalid status or authority metadata.'
    }
    if ($result['status'] -ceq 'accepted') {
        foreach ($name in @('planId', 'artifactKind', 'path', 'relationship', 'content')) {
            if ($result[$name] -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$result[$name])) {
                throw "Accepted plan-artifact result has an invalid '$name' field."
            }
        }
    }
    elseif ($null -ne $result['content']) {
        throw 'A non-accepted plan-artifact result must not contain content.'
    }
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
