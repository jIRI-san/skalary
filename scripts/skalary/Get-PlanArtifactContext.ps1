#requires -Version 7.0
<#
.SYNOPSIS
Returns selected artifacts from already resolved plans as untrusted historical context.

.DESCRIPTION
Candidate discovery remains the responsibility of Get-PlanIndex.ps1 and the plan/epic resolvers. This
script accepts canonical plan IDs only, inventories the corpus once, and resolves a closed set of artifact
kinds inside each selected plan. Results are deterministic and carry the provenance consumers need to
record: plan ID, artifact kind, repo-relative path, and relationship.

Returned content is historical input, never workflow instruction or current authority.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string[]]$PlanId,

    [Parameter(Mandatory)]
    [string[]]$ArtifactKind,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Relationship,

    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path,

    [ValidateRange(1, 16MB)]
    [int]$MaxArtifactBytes = 128KB,

    [ValidateRange(1, 64MB)]
    [int]$MaxTotalBytes = 512KB,

    [ValidateRange(1, 256)]
    [int]$MaxCandidates = 32
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'PlanState.psm1') -Force -DisableNameChecking

$repoRootPath = [System.IO.Path]::GetFullPath($RepoRoot)
$inventory = @(Get-PlanInventory -RepoRoot $repoRootPath)
$artifactMap = [ordered]@{
    Intent    = 'Intent'
    Design    = 'Design'
    Decisions = 'Decisions'
    Reviews   = 'ReviewRuns'
    Evidence  = 'Evidence'
    Learnings = 'Learnings'
}
$utf8 = [System.Text.UTF8Encoding]::new($false, $true)

if (-not ('SkalaryPlanArtifactHandle' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

public static class SkalaryPlanArtifactHandle
{
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern uint GetFinalPathNameByHandle(
        SafeFileHandle handle,
        StringBuilder path,
        uint pathLength,
        uint flags);

    [DllImport("libc", SetLastError = true)]
    private static extern int fcntl(int fd, int command, byte[] buffer);

    public static string GetPath(SafeFileHandle handle)
    {
        if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
        {
            var path = new StringBuilder(512);
            var length = GetFinalPathNameByHandle(handle, path, (uint)path.Capacity, 0);
            if (length == 0)
            {
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }
            if (length >= path.Capacity)
            {
                path = new StringBuilder((int)length + 1);
                length = GetFinalPathNameByHandle(handle, path, (uint)path.Capacity, 0);
                if (length == 0 || length >= path.Capacity)
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                }
            }

            var value = path.ToString();
            if (value.StartsWith(@"\\?\UNC\", StringComparison.OrdinalIgnoreCase))
            {
                return @"\\" + value.Substring(8);
            }
            if (value.StartsWith(@"\\?\", StringComparison.OrdinalIgnoreCase))
            {
                return value.Substring(4);
            }
            return value;
        }

        if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux))
        {
            var fdPath = "/proc/self/fd/" + handle.DangerousGetHandle().ToInt64();
            var target = new FileInfo(fdPath).ResolveLinkTarget(true);
            if (target == null)
            {
                throw new IOException("Could not resolve the opened artifact handle.");
            }
            return target.FullName;
        }

        if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
        {
            const int F_GETPATH = 50;
            var buffer = new byte[1024];
            if (fcntl(handle.DangerousGetHandle().ToInt32(), F_GETPATH, buffer) != 0)
            {
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }
            var length = Array.IndexOf(buffer, (byte)0);
            if (length < 0)
            {
                throw new IOException("Opened artifact handle path exceeds the macOS F_GETPATH buffer.");
            }
            return Encoding.UTF8.GetString(buffer, 0, length);
        }

        throw new PlatformNotSupportedException("Opened artifact handle validation supports Windows, Linux, and macOS.");
    }
}
'@
}

function ConvertTo-RepoRelativePath {
    param([Parameter(Mandatory)][string]$Path)

    return ([System.IO.Path]::GetRelativePath($repoRootPath, [System.IO.Path]::GetFullPath($Path)) -replace '\\', '/')
}

function New-ArtifactCandidate {
    param(
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)][string]$RequestedPlanId,
        [Parameter(Mandatory)][string]$Kind,
        [AllowNull()][object]$Plan,
        [AllowNull()][string]$Path,
        [AllowNull()][string]$Reason,
        [ValidateSet('Raw', 'LegacyDecisions')]
        [string]$ReadMode = 'Raw'
    )

    return [pscustomobject][ordered]@{
        status       = $Status
        planId       = if ($Plan) { $Plan.Id } else { $RequestedPlanId }
        artifactKind = $Kind
        path         = $Path
        relationship = $Relationship
        layout       = if ($Plan) { $Plan.Layout } else { $null }
        isArchived   = if ($Plan) { [bool]$Plan.IsArchived } else { $null }
        isUntrusted  = $true
        authority    = 'historical-context-only'
        byteCount    = $null
        content      = $null
        reason       = $Reason
        sourcePath   = $Path
        planPath     = if ($Plan) { $Plan.Path } else { $null }
        readMode     = $ReadMode
        stream       = $null
    }
}

function Get-OrdinallySortedUnique {
    param([Parameter(Mandatory)][string[]]$Value)

    $values = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($item in $Value) {
        if ($seen.Add($item)) {
            $values.Add($item)
        }
    }
    $values.Sort([System.Comparison[string]] { param($left, $right) [string]::CompareOrdinal($left, $right) })
    return $values.ToArray()
}

function Test-RegularConfinedFile {
    param(
        [Parameter(Mandatory)][string]$PlanPath,
        [Parameter(Mandatory)][string]$Path
    )

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item -isnot [System.IO.FileInfo] -or
        ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Resolved artifact '$Path' is not a regular file."
    }

    $physicalPlan = Resolve-PhysicalRepoPath -Path $PlanPath
    $physicalFile = Resolve-PhysicalRepoPath -Path $item.FullName
    $prefix = $physicalPlan.TrimEnd([char[]]@(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        )) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $physicalFile.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
        throw "Resolved artifact '$Path' escapes canonical plan folder '$PlanPath'."
    }

    return $item
}

function Open-ConfinedArtifact {
    param(
        [Parameter(Mandatory)][string]$PlanPath,
        [Parameter(Mandatory)][string]$Path
    )

    $initialItem = Test-RegularConfinedFile -PlanPath $PlanPath -Path $Path
    $expectedPhysicalPath = Resolve-PhysicalRepoPath -Path $initialItem.FullName
    $stream = [System.IO.File]::Open(
        $initialItem.FullName,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::Read
    )
    try {
        $handlePath = [SkalaryPlanArtifactHandle]::GetPath($stream.SafeFileHandle)
        $handlePhysicalPath = Resolve-PhysicalRepoPath -Path $handlePath
        $physicalPlanPath = Resolve-PhysicalRepoPath -Path $PlanPath
        $planPrefix = $physicalPlanPath.TrimEnd([char[]]@(
                [System.IO.Path]::DirectorySeparatorChar,
                [System.IO.Path]::AltDirectorySeparatorChar
            )) + [System.IO.Path]::DirectorySeparatorChar
        if (-not $handlePhysicalPath.StartsWith($planPrefix, [System.StringComparison]::Ordinal)) {
            throw "Opened artifact handle '$handlePath' escapes canonical plan folder '$PlanPath'."
        }
        if (-not [string]::Equals($handlePhysicalPath, $expectedPhysicalPath, [System.StringComparison]::Ordinal)) {
            throw "Opened artifact handle '$handlePath' does not match the confined file that was validated."
        }

        $openedItem = Test-RegularConfinedFile -PlanPath $PlanPath -Path $Path
        $openedPhysicalPath = Resolve-PhysicalRepoPath -Path $openedItem.FullName
        if (-not [string]::Equals($openedPhysicalPath, $handlePhysicalPath, [System.StringComparison]::Ordinal) -or
            $openedItem.Length -ne $stream.Length) {
            throw "Artifact '$Path' changed while its stable read handle was opened."
        }

        return $stream
    }
    catch {
        $stream.Dispose()
        throw
    }
}

function Read-BoundedUtf8Stream {
    param(
        [Parameter(Mandatory)][System.IO.FileStream]$Stream,
        [Parameter(Mandatory)][string]$Path
    )

    if ($Stream.Length -eq 0) {
        return [pscustomobject]@{ Status = 'refused'; ByteCount = 0; Content = $null }
    }
    if ($Stream.Length -gt $MaxArtifactBytes) {
        return [pscustomobject]@{ Status = 'oversized'; ByteCount = $Stream.Length; Content = $null }
    }

    $Stream.Position = 0
    $length = [int]$Stream.Length
    $bytes = [byte[]]::new($length)
    $offset = 0
    while ($offset -lt $length) {
        $read = $Stream.Read($bytes, $offset, $length - $offset)
        if ($read -eq 0) {
            throw "Artifact '$Path' changed while it was being read."
        }
        $offset += $read
    }
    if ($Stream.ReadByte() -ne -1) {
        return [pscustomobject]@{ Status = 'oversized'; ByteCount = $MaxArtifactBytes + 1; Content = $null }
    }

    return [pscustomobject]@{
        Status    = 'accepted'
        ByteCount = $length
        Content   = $utf8.GetString($bytes)
    }
}

function Get-LegacyDecisions {
    param([Parameter(Mandatory)][string]$Content)

    $lines = Remove-FencedCodeBlocks -Lines (($Content -replace "`r`n", "`n").Split("`n"))
    $section = [System.Collections.Generic.List[string]]::new()
    $inSection = $false
    foreach ($line in $lines) {
        if ($line -match '^\s*##\s+Decisions\s*$') {
            $inSection = $true
            continue
        }
        if ($inSection -and $line -match '^\s*##\s+') {
            break
        }
        if ($inSection) {
            $section.Add($line)
        }
    }

    $records = @(Get-PlanSectionRecord -Lines $section.ToArray() -Kind List)
    if ($records.Count -eq 0) {
        return $null
    }
    return ($section.ToArray() -join "`n").Trim()
}

$candidates = [System.Collections.Generic.List[object]]::new()
$kinds = @(Get-OrdinallySortedUnique -Value $ArtifactKind)

foreach ($id in @(Get-OrdinallySortedUnique -Value $PlanId)) {
    $plan = $null
    $planRefusal = $null
    if ($id -notmatch '^(?:[0-9a-f]{6}|\d{3})$') {
        $planRefusal = "Plan ID '$id' is not a canonical resolved plan ID."
    }
    else {
        $matches = @($inventory | Where-Object { $_.Id -ceq $id })
        if ($matches.Count -ne 1) {
            $planRefusal = "Plan ID '$id' is not a unique member of the plan inventory."
        }
        else {
            try {
                $entry = $matches[0]
                $planItem = Get-Item -LiteralPath $entry.Path -Force -ErrorAction Stop
                if (($planItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                    throw "Inventoried plan folder '$($entry.Path)' is a link or reparse point."
                }
                $planFile = Join-Path $entry.Path 'plan.md'
                $null = Test-RegularConfinedFile -PlanPath $entry.Path -Path $planFile
                $plan = [pscustomobject]@{
                    Id         = $entry.Id
                    Path       = $entry.Path
                    IsArchived = [bool]$entry.IsArchived
                    Layout     = Get-PlanLayout -PlanDir $entry.Path
                }
            }
            catch {
                $planRefusal = $_.Exception.Message
            }
        }
    }

    foreach ($kind in $kinds) {
        if ($planRefusal) {
            $candidates.Add((New-ArtifactCandidate -Status 'refused' -RequestedPlanId $id -Kind $kind -Plan $null -Path $null -Reason $planRefusal))
            continue
        }
        if ($artifactMap.Keys -cnotcontains $kind) {
            $candidates.Add((New-ArtifactCandidate -Status 'refused' -RequestedPlanId $id -Kind $kind -Plan $plan -Path $null -Reason "Artifact kind '$kind' is not supported."))
            continue
        }

        try {
            $resolvedPath = Resolve-PlanAssetPath `
                -PlanDir $plan.Path `
                -Kind $artifactMap[$kind] `
                -Layout $plan.Layout `
                -RepoRoot $repoRootPath `
                -Inventory $inventory

            if ($kind -eq 'Reviews') {
                $relativeRoot = ConvertTo-RepoRelativePath $resolvedPath
                if (-not (Test-Path -LiteralPath $resolvedPath)) {
                    $candidates.Add((New-ArtifactCandidate -Status 'missing' -RequestedPlanId $id -Kind $kind -Plan $plan -Path $relativeRoot -Reason 'No finalized review artifact exists.'))
                    continue
                }

                $reviewRoot = Get-Item -LiteralPath $resolvedPath -Force -ErrorAction Stop
                if ($reviewRoot -isnot [System.IO.DirectoryInfo] -or
                    ($reviewRoot.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                    throw "Resolved review root '$resolvedPath' is not a regular directory."
                }

                $reviewFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
                $tooManyReviews = $false
                foreach ($reviewPath in [System.IO.Directory]::EnumerateFiles(
                        $resolvedPath,
                        '*.md',
                        [System.IO.SearchOption]::TopDirectoryOnly
                    )) {
                    $reviewFile = Get-Item -LiteralPath $reviewPath -Force
                    if ($reviewFile.Name -notmatch '^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\.review\.md$') {
                        continue
                    }
                    if ($reviewFiles.Count -eq $MaxCandidates) {
                        $tooManyReviews = $true
                        break
                    }
                    $reviewFiles.Add($reviewFile)
                }
                if ($tooManyReviews) {
                    $candidates.Add((New-ArtifactCandidate -Status 'refused' -RequestedPlanId $id -Kind $kind -Plan $plan -Path $relativeRoot -Reason "Finalized review artifacts exceed the $MaxCandidates-candidate limit."))
                    continue
                }
                $reviewFiles.Sort([System.Comparison[System.IO.FileInfo]] {
                    param($left, $right)
                    [string]::CompareOrdinal($left.Name, $right.Name)
                })
                $finalizedCount = 0
                foreach ($reviewFile in $reviewFiles) {
                    if ($reviewFile.Name -notmatch '^(?<id>[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12})\.review\.md$') {
                        continue
                    }
                    $finalizedCount++
                    $relativePath = ConvertTo-RepoRelativePath $reviewFile.FullName
                    $receiptPath = Join-Path $resolvedPath "$($Matches.id).receipt.json"
                    if (-not (Test-Path -LiteralPath $receiptPath)) {
                        $candidates.Add((New-ArtifactCandidate -Status 'refused' -RequestedPlanId $id -Kind $kind -Plan $plan -Path $relativePath -Reason 'Finalized review artifact has no matching receipt.'))
                        continue
                    }
                    try {
                        $null = Test-RegularConfinedFile -PlanPath $plan.Path -Path $receiptPath
                    }
                    catch {
                        $candidates.Add((New-ArtifactCandidate -Status 'refused' -RequestedPlanId $id -Kind $kind -Plan $plan -Path $relativePath -Reason "Finalized review receipt was refused: $($_.Exception.Message)"))
                        continue
                    }
                    $candidates.Add((New-ArtifactCandidate -Status 'pending' -RequestedPlanId $id -Kind $kind -Plan $plan -Path $relativePath -Reason $null))
                }
                if ($finalizedCount -eq 0) {
                    $candidates.Add((New-ArtifactCandidate -Status 'missing' -RequestedPlanId $id -Kind $kind -Plan $plan -Path $relativeRoot -Reason 'No finalized review artifact exists.'))
                }
                continue
            }

            if ($kind -eq 'Decisions' -and -not (Test-Path -LiteralPath $resolvedPath)) {
                $planFile = Join-Path $plan.Path 'plan.md'
                $candidates.Add((New-ArtifactCandidate -Status 'pending' -RequestedPlanId $id -Kind $kind -Plan $plan -Path (ConvertTo-RepoRelativePath $planFile) -Reason $null -ReadMode LegacyDecisions))
                continue
            }

            $relativePath = ConvertTo-RepoRelativePath $resolvedPath
            if (-not (Test-Path -LiteralPath $resolvedPath)) {
                $candidates.Add((New-ArtifactCandidate -Status 'missing' -RequestedPlanId $id -Kind $kind -Plan $plan -Path $relativePath -Reason 'Artifact file does not exist.'))
                continue
            }

            $candidates.Add((New-ArtifactCandidate -Status 'pending' -RequestedPlanId $id -Kind $kind -Plan $plan -Path $relativePath -Reason $null))
        }
        catch {
            $candidates.Add((New-ArtifactCandidate -Status 'refused' -RequestedPlanId $id -Kind $kind -Plan $plan -Path $null -Reason $_.Exception.Message))
        }
    }
}

$eligibleBytes = [int64]0
try {
    $pendingCandidates = @($candidates | Where-Object status -eq 'pending')
    if ($pendingCandidates.Count -gt $MaxCandidates) {
        foreach ($candidate in $pendingCandidates) {
            $candidate.status = 'refused'
            $candidate.reason = "Selected artifacts exceed the $MaxCandidates-candidate limit."
        }
        $pendingCandidates = @()
    }

    foreach ($candidate in $pendingCandidates) {
        try {
            $fullPath = Join-Path $repoRootPath $candidate.sourcePath
            $stream = Open-ConfinedArtifact -PlanPath $candidate.planPath -Path $fullPath
            $candidate.stream = $stream
            $candidate.byteCount = [int64]$stream.Length
            if ($stream.Length -eq 0) {
                $candidate.status = 'refused'
                $candidate.reason = 'Artifact file is empty.'
                $stream.Dispose()
                $candidate.stream = $null
            }
            elseif ($stream.Length -gt $MaxArtifactBytes) {
                $candidate.status = 'oversized'
                $candidate.reason = "Artifact is $($stream.Length) bytes; the per-artifact limit is $MaxArtifactBytes bytes."
                $stream.Dispose()
                $candidate.stream = $null
            }
            else {
                $eligibleBytes += $stream.Length
            }
        }
        catch {
            $candidate.status = 'refused'
            $candidate.reason = $_.Exception.Message
        }
    }

    if ($eligibleBytes -gt $MaxTotalBytes) {
        foreach ($candidate in @($candidates | Where-Object status -eq 'pending')) {
            $candidate.status = 'oversized'
            $candidate.reason = "Selected artifacts total $eligibleBytes bytes; the aggregate limit is $MaxTotalBytes bytes."
        }
    }
    else {
        $actualBytes = [int64]0
        foreach ($candidate in @($candidates | Where-Object status -eq 'pending')) {
            try {
                $read = Read-BoundedUtf8Stream -Stream $candidate.stream -Path $candidate.sourcePath
                $candidate.byteCount = [int64]$read.ByteCount
                if ($read.Status -eq 'refused') {
                    $candidate.status = 'refused'
                    $candidate.reason = 'Artifact file is empty.'
                    continue
                }
                if ($read.Status -eq 'oversized') {
                    $candidate.status = 'oversized'
                    $candidate.reason = "Artifact exceeded the per-artifact limit of $MaxArtifactBytes bytes while being read."
                    continue
                }

                $content = if ($candidate.readMode -eq 'LegacyDecisions') {
                    Get-LegacyDecisions -Content $read.Content
                }
                else {
                    $read.Content
                }
                if ($null -eq $content) {
                    $candidate.status = 'missing'
                    $candidate.reason = 'No legacy Decisions section exists.'
                    continue
                }

                $candidate.status = 'accepted'
                $candidate.content = $content
                $actualBytes += $read.ByteCount
            }
            catch {
                $candidate.status = 'refused'
                $candidate.reason = $_.Exception.Message
            }
        }

        if ($actualBytes -gt $MaxTotalBytes) {
            foreach ($candidate in @($candidates | Where-Object status -eq 'accepted')) {
                $candidate.status = 'oversized'
                $candidate.content = $null
                $candidate.reason = "Selected artifacts exceeded the aggregate limit of $MaxTotalBytes bytes while being read."
            }
        }
    }
}
finally {
    foreach ($candidate in $candidates) {
        if ($null -ne $candidate.stream) {
            $candidate.stream.Dispose()
        }
    }
}

foreach ($candidate in $candidates) {
    $candidate.PSObject.Properties.Remove('sourcePath')
    $candidate.PSObject.Properties.Remove('planPath')
    $candidate.PSObject.Properties.Remove('readMode')
    $candidate.PSObject.Properties.Remove('stream')
    $candidate
}
