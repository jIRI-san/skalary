#requires -Version 7.0
<#
.SYNOPSIS
Rehashes every file named by a bounded historical-artifact manifest.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ManifestPath,

    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [System.IO.Path]::GetFullPath($RepoRoot)
$rootPrefix = $root.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) +
    [System.IO.Path]::DirectorySeparatorChar
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json -Depth 20

if ([string]$manifest.startingCommit -notmatch '^[a-f0-9]{40}$') {
    throw 'Historical manifest startingCommit must be a full lowercase Git SHA.'
}
$startingCommit = [string]$manifest.startingCommit

function Get-GitBlobSha256 {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$Commit,
        [Parameter(Mandatory)][string]$Path
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = 'git'
    $startInfo.WorkingDirectory = $RepositoryRoot
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.ArgumentList.Add('cat-file')
    $startInfo.ArgumentList.Add('blob')
    $startInfo.ArgumentList.Add("${Commit}:$Path")

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    [void]$process.Start()
    $buffer = [System.IO.MemoryStream]::new()
    $process.StandardOutput.BaseStream.CopyTo($buffer)
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) {
        $buffer.Dispose()
        $process.Dispose()
        throw "Historical path '$Path' does not exist at starting commit '$Commit': $($stderr.Trim())"
    }
    $process.Dispose()
    try {
        $digest = [System.Security.Cryptography.SHA256]::HashData($buffer.ToArray())
        return -join ($digest | ForEach-Object { $_.ToString('x2') })
    }
    finally {
        $buffer.Dispose()
    }
}

function Assert-NoReparsePath {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$RelativePath
    )

    $current = $RepositoryRoot
    foreach ($segment in $RelativePath.Split('/')) {
        $current = Join-Path $current $segment
        if (([System.IO.File]::GetAttributes($current) -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Historical manifest path traverses a link or reparse point: '$RelativePath'."
        }
    }
}

$files = @($manifest.files)
if ($files.Count -eq 0) {
    throw 'Historical manifest must list at least one file.'
}

$seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$verified = [System.Collections.Generic.List[object]]::new()
foreach ($entry in $files) {
    $relative = ([string]$entry.path).Replace('\', '/')
    if ([string]::IsNullOrWhiteSpace($relative) -or
        [System.IO.Path]::IsPathRooted($relative) -or
        $relative -match '(^|/)\.\.(/|$)') {
        throw "Historical manifest path is not repository-relative: '$relative'."
    }
    if (-not $seen.Add($relative)) {
        throw "Historical manifest contains duplicate path '$relative'."
    }
    if ([string]$entry.sha256 -notmatch '^[a-f0-9]{64}$') {
        throw "Historical manifest has an invalid SHA256 for '$relative'."
    }

    $fullPath = [System.IO.Path]::GetFullPath((Join-Path $root $relative))
    if (-not $fullPath.StartsWith($rootPrefix, [System.StringComparison]::Ordinal)) {
        throw "Historical manifest path escapes the repository: '$relative'."
    }
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "Historical manifest path is missing: '$relative'."
    }
    Assert-NoReparsePath -RepositoryRoot $root -RelativePath $relative

    $actual = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if (-not [string]::Equals($actual, [string]$entry.sha256, [System.StringComparison]::Ordinal)) {
        throw "Historical manifest hash mismatch for '$relative': expected $($entry.sha256), got $actual."
    }
    $baseline = Get-GitBlobSha256 -RepositoryRoot $root -Commit $startingCommit -Path $relative
    if (-not [string]::Equals($baseline, [string]$entry.sha256, [System.StringComparison]::Ordinal)) {
        throw "Historical manifest baseline mismatch for '$relative': starting commit contains $baseline, manifest records $($entry.sha256)."
    }
    $verified.Add([pscustomobject]@{ Path = $relative; Sha256 = $actual; BaselineSha256 = $baseline })
}

[pscustomobject]@{
    StartingCommit = $startingCommit
    Count          = $verified.Count
    Files          = @($verified)
}
