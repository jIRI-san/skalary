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
    [string[]]$Relationship,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$RepoRoot,

    [ValidateSet('Object', 'Json')]
    [string]$Format = 'Object',

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
Import-Module (Join-Path $PSScriptRoot 'PlanEvidence.psm1') -DisableNameChecking

$repoRootPath = [System.IO.Path]::GetFullPath($RepoRoot)
$artifactMap = [ordered]@{
    Intent = 'Intent'
    Design = 'Design'
    Decisions = 'Decisions'
    Reviews = 'ReviewRuns'
    Evidence = 'Evidence'
    Learnings = 'Learnings'
}
$utf8 = [System.Text.UTF8Encoding]::new($false, $true)

function Initialize-NativeArtifactHandle {
    if ('SkalaryPlanArtifactHandle' -as [type]) {
        return
    }

    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

public static class SkalaryPlanArtifactHandle
{
    public sealed class Identity
    {
        public string Value { get; set; }
        public ulong LinkCount { get; set; }
        public bool IsRegular { get; set; }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct ByHandleFileInformation
    {
        public uint FileAttributes;
        public System.Runtime.InteropServices.ComTypes.FILETIME CreationTime;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastAccessTime;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWriteTime;
        public uint VolumeSerialNumber;
        public uint FileSizeHigh;
        public uint FileSizeLow;
        public uint NumberOfLinks;
        public uint FileIndexHigh;
        public uint FileIndexLow;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern uint GetFinalPathNameByHandle(
        SafeFileHandle handle,
        StringBuilder path,
        uint pathLength,
        uint flags);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetFileInformationByHandle(
        SafeFileHandle handle,
        out ByHandleFileInformation information);

    [DllImport("libc", SetLastError = true)]
    private static extern int fcntl(int fd, int command, byte[] buffer);

    [DllImport("libc", SetLastError = true)]
    private static extern int fstat(int fd, byte[] buffer);

    private static bool IsSupportedArchitecture(OSPlatform platform, Architecture architecture)
    {
        if (platform == OSPlatform.Windows)
        {
            return architecture == Architecture.X86 ||
                architecture == Architecture.X64 ||
                architecture == Architecture.Arm64;
        }
        return architecture == Architecture.X64 || architecture == Architecture.Arm64;
    }

    private static void AssertSupportedArchitecture(OSPlatform platform, Architecture architecture)
    {
        if (!BitConverter.IsLittleEndian || !IsSupportedArchitecture(platform, architecture))
        {
            throw new PlatformNotSupportedException(
                "Opened artifact identity is not supported on " + platform + "/" + architecture + ".");
        }
    }

    public static bool IsSupportedPlatformArchitecture(string platform, string architecture)
    {
        Architecture parsed;
        if (!Enum.TryParse(architecture, false, out parsed))
        {
            return false;
        }
        if (String.Equals(platform, "Windows", StringComparison.Ordinal))
        {
            return IsSupportedArchitecture(OSPlatform.Windows, parsed);
        }
        if (String.Equals(platform, "Linux", StringComparison.Ordinal))
        {
            return IsSupportedArchitecture(OSPlatform.Linux, parsed);
        }
        if (String.Equals(platform, "macOS", StringComparison.Ordinal))
        {
            return IsSupportedArchitecture(OSPlatform.OSX, parsed);
        }
        return false;
    }

    public static Identity ParseUnixIdentityForTest(string platform, string architecture, byte[] stat)
    {
        Architecture parsed;
        if (!Enum.TryParse(architecture, false, out parsed))
        {
            throw new PlatformNotSupportedException("Unknown test architecture '" + architecture + "'.");
        }
        if (String.Equals(platform, "Linux", StringComparison.Ordinal))
        {
            AssertSupportedArchitecture(OSPlatform.Linux, parsed);
            return ParseLinuxIdentity(stat, parsed);
        }
        if (String.Equals(platform, "macOS", StringComparison.Ordinal))
        {
            AssertSupportedArchitecture(OSPlatform.OSX, parsed);
            return ParseMacIdentity(stat, parsed);
        }
        throw new PlatformNotSupportedException("Unix identity fixture platform must be Linux or macOS.");
    }

    private static Identity ParseLinuxIdentity(byte[] stat, Architecture architecture)
    {
        if (stat == null || stat.Length < 28)
        {
            throw new IOException("Linux fstat buffer is shorter than the supported layout.");
        }

        var device = BitConverter.ToUInt64(stat, 0);
        var inode = BitConverter.ToUInt64(stat, 8);
        ulong links;
        uint mode;
        if (architecture == Architecture.X64)
        {
            links = BitConverter.ToUInt64(stat, 16);
            mode = BitConverter.ToUInt32(stat, 24);
        }
        else if (architecture == Architecture.Arm64)
        {
            mode = BitConverter.ToUInt32(stat, 16);
            links = BitConverter.ToUInt32(stat, 20);
        }
        else
        {
            throw new PlatformNotSupportedException("Linux fstat layout is unsupported on " + architecture + ".");
        }
        return new Identity
        {
            Value = "linux:" + device.ToString("x") + ":" + inode.ToString("x"),
            LinkCount = links,
            IsRegular = (mode & 0xF000) == 0x8000
        };
    }

    private static Identity ParseMacIdentity(byte[] stat, Architecture architecture)
    {
        if (architecture != Architecture.X64 && architecture != Architecture.Arm64)
        {
            throw new PlatformNotSupportedException("macOS fstat layout is unsupported on " + architecture + ".");
        }
        if (stat == null || stat.Length < 16)
        {
            throw new IOException("macOS fstat buffer is shorter than the supported layout.");
        }

        var device = BitConverter.ToUInt32(stat, 0);
        var mode = BitConverter.ToUInt16(stat, 4);
        var links = BitConverter.ToUInt16(stat, 6);
        var inode = BitConverter.ToUInt64(stat, 8);
        return new Identity
        {
            Value = "macos:" + device.ToString("x") + ":" + inode.ToString("x"),
            LinkCount = links,
            IsRegular = (mode & 0xF000) == 0x8000
        };
    }

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

    public static Identity GetIdentity(SafeFileHandle handle)
    {
        if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
        {
            AssertSupportedArchitecture(OSPlatform.Windows, RuntimeInformation.ProcessArchitecture);
            ByHandleFileInformation information;
            if (!GetFileInformationByHandle(handle, out information))
            {
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }
            var fileIndex = ((ulong)information.FileIndexHigh << 32) | information.FileIndexLow;
            return new Identity
            {
                Value = "windows:" + information.VolumeSerialNumber.ToString("x") + ":" + fileIndex.ToString("x"),
                LinkCount = information.NumberOfLinks,
                IsRegular = (information.FileAttributes & 0x10) == 0
            };
        }

        if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux))
        {
            AssertSupportedArchitecture(OSPlatform.Linux, RuntimeInformation.ProcessArchitecture);
        }
        else if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
        {
            AssertSupportedArchitecture(OSPlatform.OSX, RuntimeInformation.ProcessArchitecture);
        }
        else
        {
            throw new PlatformNotSupportedException("Opened artifact identity supports Windows, Linux, and macOS.");
        }

        var stat = new byte[256];
        if (fstat(handle.DangerousGetHandle().ToInt32(), stat) != 0)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error());
        }
        if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux))
        {
            return ParseLinuxIdentity(stat, RuntimeInformation.ProcessArchitecture);
        }
        if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
        {
            return ParseMacIdentity(stat, RuntimeInformation.ProcessArchitecture);
        }

        throw new PlatformNotSupportedException("Opened artifact identity supports Windows, Linux, and macOS.");
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
        [Parameter(Mandatory)][AllowEmptyString()][string]$RequestedPlanId,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Kind,
        [AllowNull()][object]$Plan,
        [AllowNull()][string]$Path,
        [AllowNull()][string]$Reason,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Relationship,
        [ValidateSet('Raw', 'LegacyDecisions')]
        [string]$ReadMode = 'Raw',
        [AllowNull()][string]$CompanionPath = $null,
        [ValidateSet('None', 'ReviewReceipt', 'DecisionsPlan')]
        [string]$CompanionPurpose = 'None',
        [AllowNull()][string]$PhysicalPlanPath = $null,
        [AllowNull()][string]$ReviewRunId = $null
    )

    return [pscustomobject][ordered]@{
        status = $Status
        planId = if ($Plan) { $Plan.Id } else { $RequestedPlanId }
        artifactKind = $Kind
        path = $Path
        relationship = $Relationship
        layout = if ($Plan) { $Plan.Layout } else { $null }
        isArchived = if ($Plan) { [bool]$Plan.IsArchived } else { $null }
        isUntrusted = $true
        authority = 'historical-context-only'
        byteCount = $null
        content = $null
        reason = $Reason
        sourcePath = $Path
        planPath = if ($Plan) { $Plan.Path } else { $null }
        readMode = $ReadMode
        stream = $null
        companionPath = $CompanionPath
        companionStream = $null
        companionPurpose = $CompanionPurpose
        physicalPlanPath = if ($PhysicalPlanPath) {
            $PhysicalPlanPath
        }
        elseif ($Plan -and $Plan.PSObject.Properties.Name -contains 'PhysicalPath') {
            $Plan.PhysicalPath
        }
        else {
            $null
        }
        reviewRunId = $ReviewRunId
    }
}

function ConvertTo-PublicArtifactResult {
    param([Parameter(Mandatory)][object]$Candidate)

    return [pscustomobject][ordered]@{
        status = $Candidate.status
        planId = $Candidate.planId
        artifactKind = $Candidate.artifactKind
        path = $Candidate.path
        relationship = $Candidate.relationship
        layout = $Candidate.layout
        isArchived = $Candidate.isArchived
        isUntrusted = $Candidate.isUntrusted
        authority = $Candidate.authority
        byteCount = $Candidate.byteCount
        content = $Candidate.content
        reason = $Candidate.reason
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
        [Parameter(Mandatory)][string]$Path,
        [AllowNull()][string]$PhysicalPlanPath
    )

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item -isnot [System.IO.FileInfo] -or
        ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Resolved artifact '$Path' is not a regular file."
    }

    $physicalPlan = if ([string]::IsNullOrWhiteSpace($PhysicalPlanPath)) {
        Resolve-PhysicalRepoPath -Path $PlanPath
    }
    else {
        $PhysicalPlanPath
    }
    $physicalFile = Resolve-PhysicalRepoPath -Path $item.FullName
    $prefix = $physicalPlan.TrimEnd([char[]]@(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        )) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $physicalFile.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
        throw "Resolved artifact '$Path' escapes canonical plan folder '$PlanPath'."
    }

    return [pscustomobject]@{
        Item = $item
        PhysicalPath = $physicalFile
        PhysicalPlanPath = $physicalPlan
    }
}

function Invoke-ArtifactOpenTestHook {
    param([Parameter(Mandatory)][ValidateSet('preflight-first-open', 'first-verification-open')][string]$Phase)

    $hookValue = [string]$env:SKALARY_PLAN_ARTIFACT_CONTEXT_TEST_HOOK
    if ([string]::IsNullOrWhiteSpace($hookValue)) {
        return
    }

    $hookRoot = [System.IO.Path]::GetFullPath($hookValue)
    $repoPrefix = $repoRootPath.TrimEnd([char[]]@(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        )) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $hookRoot.StartsWith($repoPrefix, [System.StringComparison]::Ordinal) -or
        [System.IO.Path]::GetFileName($hookRoot) -cne '.skalary-plan-artifact-context-test-hook') {
        throw 'The plan-artifact test hook must be the fixed test-hook directory inside RepoRoot.'
    }
    $hookItem = Get-Item -LiteralPath $hookRoot -Force -ErrorAction Stop
    if ($hookItem -isnot [System.IO.DirectoryInfo] -or
        ($hookItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'The plan-artifact test hook root must be a regular directory.'
    }

    $readyPath = Join-Path $hookRoot "$Phase.ready"
    $continuePath = Join-Path $hookRoot "$Phase.continue"
    [System.IO.File]::WriteAllText($readyPath, $Phase, [System.Text.UTF8Encoding]::new($false))
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not [System.IO.File]::Exists($continuePath)) {
        if ([DateTime]::UtcNow -ge $deadline) {
            throw "Timed out waiting for the plan-artifact '$Phase' test hook."
        }
        [System.Threading.Thread]::Sleep(10)
    }
}

function Open-ConfinedArtifact {
    param(
        [Parameter(Mandatory)][string]$PlanPath,
        [Parameter(Mandatory)][string]$Path,
        [AllowNull()][string]$PhysicalPlanPath
    )

    $validated = Test-RegularConfinedFile `
        -PlanPath $PlanPath `
        -Path $Path `
        -PhysicalPlanPath $PhysicalPlanPath
    Invoke-ArtifactOpenTestHook -Phase preflight-first-open
    Initialize-NativeArtifactHandle
    $stream = [System.IO.File]::Open(
        $validated.Item.FullName,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::Read
    )
    try {
        $handlePath = [SkalaryPlanArtifactHandle]::GetPath($stream.SafeFileHandle)
        $handlePhysicalPath = Resolve-PhysicalRepoPath -Path $handlePath
        $physicalPlanPath = $validated.PhysicalPlanPath
        $planPrefix = $physicalPlanPath.TrimEnd([char[]]@(
                [System.IO.Path]::DirectorySeparatorChar,
                [System.IO.Path]::AltDirectorySeparatorChar
            )) + [System.IO.Path]::DirectorySeparatorChar
        if (-not $handlePhysicalPath.StartsWith($planPrefix, [System.StringComparison]::Ordinal)) {
            throw "Opened artifact handle '$handlePath' escapes canonical plan folder '$PlanPath'."
        }
        if (-not [string]::Equals($handlePhysicalPath, $validated.PhysicalPath, [System.StringComparison]::Ordinal)) {
            throw "Opened artifact handle '$handlePath' does not match the confined file that was validated."
        }

        $identity = [SkalaryPlanArtifactHandle]::GetIdentity($stream.SafeFileHandle)
        if (-not $identity.IsRegular -or $identity.LinkCount -ne 1) {
            throw "Opened artifact '$Path' is not a single-link regular file."
        }

        Invoke-ArtifactOpenTestHook -Phase first-verification-open
        $verification = [System.IO.File]::Open(
            $Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::Read
        )
        try {
            $verificationPath = Resolve-PhysicalRepoPath -Path ([SkalaryPlanArtifactHandle]::GetPath($verification.SafeFileHandle))
            $verificationIdentity = [SkalaryPlanArtifactHandle]::GetIdentity($verification.SafeFileHandle)
            if (-not [string]::Equals($verificationPath, $handlePhysicalPath, [System.StringComparison]::Ordinal) -or
                -not [string]::Equals($verificationIdentity.Value, $identity.Value, [System.StringComparison]::Ordinal) -or
                $verification.Length -ne $stream.Length) {
                throw "Artifact '$Path' changed while its stable read handle was opened."
            }
        }
        finally {
            $verification.Dispose()
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
        return [pscustomobject]@{ Status = 'refused'; ByteCount = 0; Content = $null; Bytes = $null }
    }
    if ($Stream.Length -gt $MaxArtifactBytes) {
        return [pscustomobject]@{ Status = 'oversized'; ByteCount = $Stream.Length; Content = $null; Bytes = $null }
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
        return [pscustomobject]@{ Status = 'oversized'; ByteCount = $null; Content = $null; Bytes = $null }
    }

    return [pscustomobject]@{
        Status = 'accepted'
        ByteCount = $length
        Content = $utf8.GetString($bytes)
        Bytes = $bytes
    }
}

$relationshipValues = @(
    'reuses', 'extends', 'supersedes', 'conflicts', 'dependency', 'sibling', 'operator-selected'
)
$relationshipSet = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]$relationshipValues,
    [System.StringComparer]::Ordinal
)
$relationshipByPlan = [System.Collections.Generic.Dictionary[string, string]]::new(
    [System.StringComparer]::Ordinal
)
$relationshipError = $null
if ($Relationship.Count -ne 1 -and $Relationship.Count -ne $PlanId.Count) {
    $relationshipError = 'Relationship must contain one value for all plans or one value aligned with each PlanId.'
}
else {
    for ($index = 0; $index -lt $PlanId.Count; $index++) {
        $id = [string]$PlanId[$index]
        $mappedRelationship = [string]$(if ($Relationship.Count -eq 1) { $Relationship[0] } else { $Relationship[$index] })
        if (-not $relationshipSet.Contains($mappedRelationship)) {
            $relationshipError = "Relationship '$mappedRelationship' is not supported."
            break
        }
        if ($relationshipByPlan.ContainsKey($id) -and
            -not [string]::Equals($relationshipByPlan[$id], $mappedRelationship, [System.StringComparison]::Ordinal)) {
            $relationshipError = "Plan ID '$id' has conflicting relationship values."
            break
        }
        $relationshipByPlan[$id] = $mappedRelationship
    }
}

$ids = @(Get-OrdinallySortedUnique -Value $PlanId)
$kinds = @(Get-OrdinallySortedUnique -Value $ArtifactKind)
$combinationCount = [int64]$ids.Count * [int64]$kinds.Count
$inputError = $relationshipError
if (-not $inputError) {
    foreach ($inputSet in @(
            [pscustomobject]@{ Name = 'PlanId'; Values = @($PlanId) }
            [pscustomobject]@{ Name = 'ArtifactKind'; Values = @($ArtifactKind) }
            [pscustomobject]@{ Name = 'Relationship'; Values = @($Relationship) }
        )) {
        for ($index = 0; $index -lt $inputSet.Values.Count; $index++) {
            $value = [string]$inputSet.Values[$index]
            if ([string]::IsNullOrWhiteSpace($value)) {
                $inputError = "$($inputSet.Name)[$index] is empty."
                break
            }
            if ($value.Length -gt 64) {
                $inputError = "$($inputSet.Name)[$index] exceeds the 64-character limit."
                break
            }
        }
        if ($inputError) { break }
    }
}
if (-not $inputError -and ($ids.Count -eq 0 -or $kinds.Count -eq 0)) {
    $inputError = 'PlanId and ArtifactKind must each contain at least one value.'
}
if (-not $inputError -and $combinationCount -gt $MaxCandidates) {
    $inputError = "Selection expands to $combinationCount candidates, exceeding the $MaxCandidates-candidate limit."
}
if ($inputError) {
    $refusal = New-ArtifactCandidate `
        -Status 'refused' `
        -RequestedPlanId $(if ($ids.Count -eq 1 -and $ids[0].Length -le 64) { $ids[0] } else { '' }) `
        -Kind $(if ($kinds.Count -eq 1 -and $kinds[0].Length -le 64) { $kinds[0] } else { '' }) `
        -Relationship $(if ($Relationship.Count -eq 1 -and $Relationship[0].Length -le 64) { $Relationship[0] } else { '' }) `
        -Plan $null `
        -Path $null `
        -Reason $inputError
    $publicRefusal = ConvertTo-PublicArtifactResult -Candidate $refusal
    if ([string]::IsNullOrEmpty($publicRefusal.planId)) { $publicRefusal.planId = $null }
    if ([string]::IsNullOrEmpty($publicRefusal.artifactKind)) { $publicRefusal.artifactKind = $null }
    if ([string]::IsNullOrEmpty($publicRefusal.relationship)) { $publicRefusal.relationship = $null }
    if ($Format -eq 'Json') {
        ConvertTo-Json -InputObject @($publicRefusal) -Depth 5
    }
    else {
        $publicRefusal
    }
    return
}

$plansRoot = Join-Path $repoRootPath 'docs/implementation-plans'
if (-not (Test-Path -LiteralPath $repoRootPath -PathType Container)) {
    throw "RepoRoot '$repoRootPath' is not an existing directory."
}
if (-not (Test-Path -LiteralPath $plansRoot -PathType Container)) {
    throw "RepoRoot '$repoRootPath' does not contain the required plan corpus at '$plansRoot'."
}

$inventory = @(Get-PlanInventory -RepoRoot $repoRootPath)
$candidates = [System.Collections.Generic.List[object]]::new()
$selectionOverflow = $false

function Add-ArtifactCandidate {
    param([Parameter(Mandatory)][object]$Candidate)

    if ($script:candidates.Count -eq $MaxCandidates) {
        $script:selectionOverflow = $true
        return
    }
    $script:candidates.Add($Candidate)
}

foreach ($id in $ids) {
    $planRelationship = $relationshipByPlan[$id]
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
                $planValidation = Test-RegularConfinedFile -PlanPath $entry.Path -Path $planFile
                $plan = [pscustomobject]@{
                    Id = $entry.Id
                    Path = $entry.Path
                    PhysicalPath = $planValidation.PhysicalPlanPath
                    IsArchived = [bool]$entry.IsArchived
                    Layout = Get-PlanLayout -PlanDir $entry.Path
                    InventoryEntry = $entry
                }
            }
            catch {
                $planRefusal = $_.Exception.Message
            }
        }
    }

    foreach ($kind in $kinds) {
        if ($planRefusal) {
            Add-ArtifactCandidate (New-ArtifactCandidate -Status 'refused' -RequestedPlanId $id -Kind $kind -Relationship $planRelationship -Plan $null -Path $null -Reason $planRefusal)
            continue
        }
        if ($artifactMap.Keys -cnotcontains $kind) {
            Add-ArtifactCandidate (New-ArtifactCandidate -Status 'refused' -RequestedPlanId $id -Kind $kind -Relationship $planRelationship -Plan $plan -Path $null -Reason "Artifact kind '$kind' is not supported.")
            continue
        }

        try {
            $resolvedPath = Resolve-PlanAssetPath `
                -PlanDir $plan.Path `
                -Kind $artifactMap[$kind] `
                -Layout $plan.Layout

            if ($kind -eq 'Reviews') {
                $relativeRoot = ConvertTo-RepoRelativePath $resolvedPath
                if (-not (Test-Path -LiteralPath $resolvedPath)) {
                    Add-ArtifactCandidate (New-ArtifactCandidate -Status 'missing' -RequestedPlanId $id -Kind $kind -Relationship $planRelationship -Plan $plan -Path $relativeRoot -Reason 'No finalized review artifact exists.')
                    continue
                }

                $reviewRoot = Get-Item -LiteralPath $resolvedPath -Force -ErrorAction Stop
                if ($reviewRoot -isnot [System.IO.DirectoryInfo] -or
                    ($reviewRoot.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                    throw "Resolved review root '$resolvedPath' is not a regular directory."
                }
                $physicalReviewRoot = Resolve-PhysicalRepoPath -Path $reviewRoot.FullName
                $planPrefix = $plan.PhysicalPath.TrimEnd([char[]]@(
                        [System.IO.Path]::DirectorySeparatorChar,
                        [System.IO.Path]::AltDirectorySeparatorChar
                    )) + [System.IO.Path]::DirectorySeparatorChar
                if (-not $physicalReviewRoot.StartsWith($planPrefix, [System.StringComparison]::Ordinal)) {
                    throw "Resolved review root '$resolvedPath' escapes canonical plan folder '$($plan.Path)'."
                }

                $reviewPaths = [System.Collections.Generic.List[object]]::new()
                $scannedEntries = 0
                $reviewOverflow = $false
                foreach ($reviewPath in [System.IO.Directory]::EnumerateFileSystemEntries(
                        $resolvedPath,
                        '*',
                        [System.IO.SearchOption]::TopDirectoryOnly
                    )) {
                    $scannedEntries++
                    if ($scannedEntries -gt $MaxCandidates) {
                        $reviewOverflow = $true
                        break
                    }
                    $reviewName = [System.IO.Path]::GetFileName($reviewPath)
                    if ($reviewName -cnotmatch '^(?<id>[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12})\.review\.md$') {
                        continue
                    }
                    $reviewPaths.Add([pscustomobject]@{
                            Path = $reviewPath
                            Name = $reviewName
                            RunId = [string]$Matches.id
                        })
                }
                if ($reviewOverflow) {
                    $selectionOverflow = $true
                    Add-ArtifactCandidate (New-ArtifactCandidate -Status 'refused' -RequestedPlanId $id -Kind $kind -Relationship $planRelationship -Plan $plan -Path $relativeRoot -Reason "Review directory exceeds the $MaxCandidates-entry scan limit.")
                    continue
                }
                $reviewPaths.Sort([System.Comparison[object]] {
                        param($left, $right)
                        [string]::CompareOrdinal([string]$left.Path, [string]$right.Path)
                    })
                $finalizedCount = 0
                foreach ($reviewEntry in $reviewPaths) {
                    $finalizedCount++
                    $reviewPath = [string]$reviewEntry.Path
                    $relativePath = ConvertTo-RepoRelativePath $reviewPath
                    $receiptPath = Join-Path $resolvedPath "$($reviewEntry.RunId).receipt.json"
                    if (-not (Test-Path -LiteralPath $receiptPath)) {
                        Add-ArtifactCandidate (New-ArtifactCandidate -Status 'refused' -RequestedPlanId $id -Kind $kind -Relationship $planRelationship -Plan $plan -Path $relativePath -Reason 'Finalized review artifact has no matching receipt.')
                        continue
                    }
                    try {
                        $reviewFile = Get-Item -LiteralPath $reviewPath -Force -ErrorAction Stop
                        if ($reviewFile -isnot [System.IO.FileInfo]) {
                            throw "Finalized review '$reviewPath' is not a regular file."
                        }
                        $receiptFile = Get-Item -LiteralPath $receiptPath -Force -ErrorAction Stop
                        if ($receiptFile -isnot [System.IO.FileInfo]) {
                            throw "Finalized review receipt '$receiptPath' is not a regular file."
                        }
                    }
                    catch {
                        Add-ArtifactCandidate (New-ArtifactCandidate -Status 'refused' -RequestedPlanId $id -Kind $kind -Relationship $planRelationship -Plan $plan -Path $relativePath -Reason "Finalized review pair was refused: $($_.Exception.Message)")
                        continue
                    }
                    Add-ArtifactCandidate (New-ArtifactCandidate -Status 'pending' -RequestedPlanId $id -Kind $kind -Relationship $planRelationship -Plan $plan -Path $relativePath -Reason $null -CompanionPath (ConvertTo-RepoRelativePath $receiptPath) -CompanionPurpose ReviewReceipt -ReviewRunId $reviewEntry.RunId)
                }
                if ($finalizedCount -eq 0) {
                    Add-ArtifactCandidate (New-ArtifactCandidate -Status 'missing' -RequestedPlanId $id -Kind $kind -Relationship $planRelationship -Plan $plan -Path $relativeRoot -Reason 'No finalized review artifact exists.')
                }
                continue
            }

            if ($kind -eq 'Decisions') {
                $planFile = Join-Path $plan.Path 'plan.md'
                if (-not (Test-Path -LiteralPath $resolvedPath)) {
                    Add-ArtifactCandidate (New-ArtifactCandidate -Status 'pending' -RequestedPlanId $id -Kind $kind -Relationship $planRelationship -Plan $plan -Path (ConvertTo-RepoRelativePath $planFile) -Reason $null -ReadMode LegacyDecisions)
                    continue
                }
                Add-ArtifactCandidate (New-ArtifactCandidate -Status 'pending' -RequestedPlanId $id -Kind $kind -Relationship $planRelationship -Plan $plan -Path (ConvertTo-RepoRelativePath $resolvedPath) -Reason $null -CompanionPath (ConvertTo-RepoRelativePath $planFile) -CompanionPurpose DecisionsPlan)
                continue
            }

            $relativePath = ConvertTo-RepoRelativePath $resolvedPath
            if (-not (Test-Path -LiteralPath $resolvedPath)) {
                Add-ArtifactCandidate (New-ArtifactCandidate -Status 'missing' -RequestedPlanId $id -Kind $kind -Relationship $planRelationship -Plan $plan -Path $relativePath -Reason 'Artifact file does not exist.')
                continue
            }

            Add-ArtifactCandidate (New-ArtifactCandidate -Status 'pending' -RequestedPlanId $id -Kind $kind -Relationship $planRelationship -Plan $plan -Path $relativePath -Reason $null)
        }
        catch {
            Add-ArtifactCandidate (New-ArtifactCandidate -Status 'refused' -RequestedPlanId $id -Kind $kind -Relationship $planRelationship -Plan $plan -Path $null -Reason $_.Exception.Message)
        }
    }
}

$eligibleBytes = [int64]0
try {
    $pendingCandidates = @($candidates | Where-Object status -eq 'pending')
    $requiredHandles = @($pendingCandidates | ForEach-Object {
            if (-not [string]::IsNullOrWhiteSpace($_.companionPath)) { 2 } else { 1 }
        } | Measure-Object -Sum).Sum
    if ($selectionOverflow -or $requiredHandles -gt $MaxCandidates) {
        foreach ($candidate in $candidates) {
            $candidate.status = 'refused'
            $candidate.content = $null
            $candidate.reason = "Selection exceeds the $MaxCandidates-candidate or open-handle limit."
        }
        $pendingCandidates = @()
    }

    foreach ($candidate in $pendingCandidates) {
        try {
            if (-not [string]::IsNullOrWhiteSpace($candidate.companionPath)) {
                $companionFullPath = Join-Path $repoRootPath $candidate.companionPath
                $candidate.companionStream = Open-ConfinedArtifact `
                    -PlanPath $candidate.planPath `
                    -Path $companionFullPath `
                    -PhysicalPlanPath $candidate.physicalPlanPath
                if ($candidate.companionStream.Length -eq 0) {
                    throw "$($candidate.companionPurpose) companion '$($candidate.companionPath)' is empty."
                }
                if ($candidate.companionStream.Length -gt $MaxArtifactBytes) {
                    $candidate.status = 'oversized'
                    $candidate.byteCount = [int64]$candidate.companionStream.Length
                    $candidate.reason = "$($candidate.companionPurpose) companion is $($candidate.companionStream.Length) bytes; the per-artifact limit is $MaxArtifactBytes bytes."
                    $candidate.companionStream.Dispose()
                    $candidate.companionStream = $null
                    continue
                }
            }

            $fullPath = Join-Path $repoRootPath $candidate.sourcePath
            $stream = Open-ConfinedArtifact `
                -PlanPath $candidate.planPath `
                -Path $fullPath `
                -PhysicalPlanPath $candidate.physicalPlanPath
            $candidate.stream = $stream
            $candidate.byteCount = [int64]$stream.Length
            if ($stream.Length -eq 0) {
                $candidate.status = 'refused'
                $candidate.reason = 'Artifact file is empty.'
                $stream.Dispose()
                $candidate.stream = $null
                if ($null -ne $candidate.companionStream) {
                    $candidate.companionStream.Dispose()
                    $candidate.companionStream = $null
                }
            }
            elseif ($stream.Length -gt $MaxArtifactBytes) {
                $candidate.status = 'oversized'
                $candidate.reason = "Artifact is $($stream.Length) bytes; the per-artifact limit is $MaxArtifactBytes bytes."
                $stream.Dispose()
                $candidate.stream = $null
                if ($null -ne $candidate.companionStream) {
                    $candidate.companionStream.Dispose()
                    $candidate.companionStream = $null
                }
            }
            else {
                $eligibleBytes += $stream.Length
                if ($null -ne $candidate.companionStream) {
                    $eligibleBytes += $candidate.companionStream.Length
                }
            }
        }
        catch {
            if ($null -ne $candidate.stream) {
                $candidate.stream.Dispose()
                $candidate.stream = $null
            }
            if ($null -ne $candidate.companionStream) {
                $candidate.companionStream.Dispose()
                $candidate.companionStream = $null
            }
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
                $candidate.byteCount = if ($null -eq $read.ByteCount) { $null } else { [int64]$read.ByteCount }
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

                $companionRead = $null
                if ($null -ne $candidate.companionStream) {
                    $companionRead = Read-BoundedUtf8Stream -Stream $candidate.companionStream -Path $candidate.companionPath
                    if ($companionRead.Status -ne 'accepted') {
                        $candidate.status = $companionRead.Status
                        $candidate.byteCount = if ($null -eq $companionRead.ByteCount) {
                            $null
                        }
                        else {
                            [int64]$companionRead.ByteCount
                        }
                        $candidate.reason = if ($companionRead.Status -eq 'oversized') {
                            "$($candidate.companionPurpose) companion exceeded the per-artifact limit of $MaxArtifactBytes bytes while being read."
                        }
                        else {
                            "$($candidate.companionPurpose) companion is empty."
                        }
                        continue
                    }
                }

                if ($candidate.companionPurpose -eq 'ReviewReceipt') {
                    $null = Assert-ReviewResultReceipt `
                        -ReviewRunId $candidate.reviewRunId `
                        -ReportName ([System.IO.Path]::GetFileName($candidate.sourcePath)) `
                        -ReportBytes $read.Bytes `
                        -ReceiptContent $companionRead.Content
                }

                $content = if ($candidate.artifactKind -eq 'Decisions') {
                    $decisionSection = if ($candidate.readMode -eq 'LegacyDecisions') {
                        Resolve-PlanSection `
                            -PlanDir $candidate.planPath `
                            -Section Decisions `
                            -LegacyContent $read.Content `
                            -AssetAbsent
                    }
                    else {
                        Resolve-PlanSection `
                            -PlanDir $candidate.planPath `
                            -Section Decisions `
                            -LegacyContent $companionRead.Content `
                            -AssetContent $read.Content `
                            -AssetPath (Join-Path $repoRootPath $candidate.sourcePath)
                    }
                    if ($decisionSection.Source -eq 'none') {
                        $null
                    }
                    else {
                        (@($decisionSection.Lines) -join "`n").Trim()
                    }
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
                $candidate.byteCount = [int64]$read.ByteCount
                if ($candidate.companionPurpose -eq 'ReviewReceipt') {
                    $candidate.byteCount += [int64]$companionRead.ByteCount
                }
                $actualBytes += [int64]$read.ByteCount
                if ($null -ne $companionRead) {
                    $actualBytes += [int64]$companionRead.ByteCount
                }
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
        if ($null -ne $candidate.companionStream) {
            $candidate.companionStream.Dispose()
        }
    }
}

$output = [System.Collections.Generic.List[object]]::new()
foreach ($candidate in $candidates) {
    $output.Add((ConvertTo-PublicArtifactResult -Candidate $candidate))
}
if ($Format -eq 'Json') {
    ConvertTo-Json -InputObject $output.ToArray() -Depth 5
}
else {
    $output.ToArray()
}
