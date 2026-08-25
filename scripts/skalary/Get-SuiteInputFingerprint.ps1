#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:SuiteFingerprintProtocol = 'skalary/suite-input-fingerprint@1'
$script:SuiteMeasurementProtocol = 'skalary/suite-runtime-measurement@1'
$script:SuiteFingerprintExclusions = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]@(
        'testResults.xml',
        'tools/suite-profile.json',
        'tools/suite-runtime.json'
    ),
    [System.StringComparer]::Ordinal
)

function ConvertTo-SuiteBase64Url {
    param([Parameter(Mandatory)][byte[]]$Bytes)

    return [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function ConvertFrom-SuiteBase64Url {
    param([Parameter(Mandatory)][string]$Text)

    $base64 = $Text.Replace('-', '+').Replace('_', '/')
    switch ($base64.Length % 4) {
        0 { }
        2 { $base64 += '==' }
        3 { $base64 += '=' }
        default { throw 'Invalid base64url length.' }
    }
    return [Convert]::FromBase64String($base64)
}

function Get-SuiteLengthBytes {
    param([Parameter(Mandatory)][UInt64]$Length)

    $bytes = [BitConverter]::GetBytes($Length)
    if ([BitConverter]::IsLittleEndian) { [Array]::Reverse($bytes) }
    return $bytes
}

function Add-SuiteFrame {
    param(
        [Parameter(Mandatory)]$Sink,
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes
    )

    $length = Get-SuiteLengthBytes -Length ([UInt64]$Bytes.LongLength)
    $Sink.AppendData($length)
    if ($Bytes.Length -gt 0) { $Sink.AppendData($Bytes) }
}

function Write-SuiteFrame {
    param(
        [Parameter(Mandatory)][System.IO.Stream]$Stream,
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes
    )

    $length = Get-SuiteLengthBytes -Length ([UInt64]$Bytes.LongLength)
    $Stream.Write($length, 0, $length.Length)
    if ($Bytes.Length -gt 0) { $Stream.Write($Bytes, 0, $Bytes.Length) }
}

function Invoke-SuiteGitBytes {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string[]]$Argument
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = 'git'
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($item in @('-C', $Root) + $Argument) {
        [void]$startInfo.ArgumentList.Add($item)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    [void]$process.Start()
    $output = [System.IO.MemoryStream]::new()
    $copyTask = $process.StandardOutput.BaseStream.CopyToAsync($output)
    $errorTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    [void]$copyTask.GetAwaiter().GetResult()
    $errorText = $errorTask.GetAwaiter().GetResult()
    $exitCode = $process.ExitCode
    $process.Dispose()
    if ($exitCode -ne 0) {
        throw "git $($Argument -join ' ') failed with exit $exitCode`: $errorText"
    }
    return $output.ToArray()
}

function Assert-SuitePathHasNoLink {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$RelativePath
    )

    $cursor = [System.IO.Path]::GetFullPath($Root)
    if (([System.IO.File]::GetAttributes($cursor) -band
            [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Repository root '$Root' is a link or reparse point."
    }
    foreach ($segment in $RelativePath.Split('/')) {
        $cursor = [System.IO.Path]::Combine($cursor, $segment)
        if (-not ([System.IO.File]::Exists($cursor) -or
                [System.IO.Directory]::Exists($cursor))) {
            throw "Tracked regular path '$RelativePath' is absent from the working tree."
        }
        if (([System.IO.File]::GetAttributes($cursor) -band
                [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Tracked regular path '$RelativePath' traverses a link or reparse point."
        }
    }
}

function Get-SuiteInputFingerprint {
    [CmdletBinding()]
    param(
        [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    )

    $root = [System.IO.Path]::GetFullPath($RepoRoot)
    $rootPrefix = $root.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    ) + [System.IO.Path]::DirectorySeparatorChar
    $comparison = if ($IsWindows) {
        [System.StringComparison]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparison]::Ordinal
    }
    $utf8 = [System.Text.UTF8Encoding]::new($false, $true)
    $indexBytes = Invoke-SuiteGitBytes -Root $root -Argument @('ls-files', '--stage', '-z')
    $indexText = $utf8.GetString($indexBytes)
    $paths = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

    foreach ($record in $indexText.Split([char]0, [System.StringSplitOptions]::RemoveEmptyEntries)) {
        $match = [regex]::Match($record, '^(?<mode>\d{6}) [0-9a-f]+ \d+\t(?<path>.*)$', 'Singleline')
        if (-not $match.Success) {
            throw "Unparseable git ls-files record: '$record'."
        }
        if ($match.Groups['mode'].Value -notin @('100644', '100755')) { continue }

        $path = $match.Groups['path'].Value
        if ($script:SuiteFingerprintExclusions.Contains($path)) { continue }
        if (-not $seen.Add($path)) {
            throw "Tracked regular path '$path' appears more than once; resolve the index conflict before fingerprinting."
        }
        $paths.Add($path)
    }

    $orderedPaths = [string[]]@($paths)
    [Array]::Sort($orderedPaths, [System.StringComparer]::Ordinal)
    $hash = [System.Security.Cryptography.IncrementalHash]::CreateHash(
        [System.Security.Cryptography.HashAlgorithmName]::SHA256
    )
    try {
        Add-SuiteFrame -Sink $hash -Bytes $utf8.GetBytes($script:SuiteFingerprintProtocol)
        foreach ($path in $orderedPaths) {
            $fullPath = [System.IO.Path]::GetFullPath(
                [System.IO.Path]::Combine(
                    $root,
                    ($path -replace '/', [System.IO.Path]::DirectorySeparatorChar)
                )
            )
            if (-not $fullPath.StartsWith($rootPrefix, $comparison)) {
                throw "Tracked path '$path' escapes repository root '$root'."
            }
            if (-not [System.IO.File]::Exists($fullPath)) {
                throw "Tracked regular path '$path' is absent from the working tree."
            }
            Assert-SuitePathHasNoLink -Root $root -RelativePath $path

            Add-SuiteFrame -Sink $hash -Bytes $utf8.GetBytes($path)
            Add-SuiteFrame -Sink $hash -Bytes ([System.IO.File]::ReadAllBytes($fullPath))
        }
        $digest = $hash.GetHashAndReset()
    }
    finally {
        $hash.Dispose()
    }

    return [pscustomobject]@{
        Protocol    = $script:SuiteFingerprintProtocol
        Fingerprint = [Convert]::ToHexString($digest).ToLowerInvariant()
        FileCount   = $orderedPaths.Count
        Paths       = $orderedPaths
    }
}

function Get-SuiteMeasurementPayloadBytes {
    param(
        [Parameter(Mandatory)][string]$Fingerprint,
        [Parameter(Mandatory)][string]$Nonce,
        [Parameter(Mandatory)][int]$ParentPid
    )

    $utf8 = [System.Text.UTF8Encoding]::new($false, $true)
    $stream = [System.IO.MemoryStream]::new()
    try {
        foreach ($field in @(
                $script:SuiteMeasurementProtocol,
                $Fingerprint,
                $Nonce,
                $ParentPid.ToString([System.Globalization.CultureInfo]::InvariantCulture)
            )) {
            Write-SuiteFrame -Stream $stream -Bytes $utf8.GetBytes($field)
        }
        return $stream.ToArray()
    }
    finally {
        $stream.Dispose()
    }
}

function New-SuiteMeasurementAuthorization {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[0-9a-f]{64}$')]
        [string]$Fingerprint,
        [int]$ParentPid = $PID
    )

    if ($ParentPid -le 0) { throw 'Measurement parent PID must be positive.' }
    $key = [byte[]]::new(32)
    $nonceBytes = [byte[]]::new(32)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($key)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($nonceBytes)
    $nonce = [Convert]::ToHexString($nonceBytes).ToLowerInvariant()
    $payloadBytes = Get-SuiteMeasurementPayloadBytes -Fingerprint $Fingerprint `
        -Nonce $nonce -ParentPid $ParentPid
    $hmac = [System.Security.Cryptography.HMACSHA256]::new($key)
    try {
        $mac = $hmac.ComputeHash($payloadBytes)
    }
    finally {
        $hmac.Dispose()
    }

    $token = [ordered]@{
        protocol    = $script:SuiteMeasurementProtocol
        fingerprint = $Fingerprint
        nonce       = $nonce
        parentPid   = $ParentPid
        hmac        = [Convert]::ToHexString($mac).ToLowerInvariant()
    }
    $tokenBytes = [System.Text.UTF8Encoding]::new($false).GetBytes(
        ($token | ConvertTo-Json -Compress)
    )
    return [pscustomobject]@{
        Token     = ConvertTo-SuiteBase64Url -Bytes $tokenBytes
        Key       = ConvertTo-SuiteBase64Url -Bytes $key
        ParentPid = $ParentPid
        Nonce     = $nonce
    }
}

function Get-SuiteParentProcessId {
    param([Parameter(Mandatory)][int]$ProcessId)

    if ($IsWindows) {
        $process = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId = $ProcessId" `
            -ErrorAction SilentlyContinue
        if ($null -eq $process) { return $null }
        return [int]$process.ParentProcessId
    }

    $statPath = "/proc/$ProcessId/stat"
    if (Test-Path -LiteralPath $statPath -PathType Leaf) {
        $stat = [System.IO.File]::ReadAllText($statPath)
        $close = $stat.LastIndexOf(')')
        if ($close -lt 0) { return $null }
        $tail = $stat.Substring($close + 1).Trim().Split(
            ' ',
            [System.StringSplitOptions]::RemoveEmptyEntries
        )
        if ($tail.Count -lt 2) { return $null }
        return [int]$tail[1]
    }

    $value = (& ps -o ppid= -p $ProcessId 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$value)) { return $null }
    return [int]([string]$value).Trim()
}

function Test-SuiteProcessAncestor {
    param(
        [Parameter(Mandatory)][int]$AncestorPid,
        [int]$CurrentProcessId = $PID
    )

    if ($AncestorPid -le 0 -or $CurrentProcessId -le 0 -or $AncestorPid -eq $CurrentProcessId) {
        return $false
    }
    $cursor = $CurrentProcessId
    for ($depth = 0; $depth -lt 64; $depth++) {
        $parent = Get-SuiteParentProcessId -ProcessId $cursor
        if ($null -eq $parent -or $parent -le 0 -or $parent -eq $cursor) { return $false }
        if ($parent -eq $AncestorPid) { return $true }
        $cursor = $parent
    }
    return $false
}

function Test-SuiteMeasurementAuthorization {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Token,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)]
        [ValidatePattern('^[0-9a-f]{64}$')]
        [string]$ExpectedFingerprint,
        [int]$CurrentProcessId = $PID
    )

    try {
        $tokenBytes = ConvertFrom-SuiteBase64Url -Text $Token
        $tokenObject = [System.Text.UTF8Encoding]::new($false, $true).GetString($tokenBytes) |
            ConvertFrom-Json
        $keyBytes = ConvertFrom-SuiteBase64Url -Text $Key
    }
    catch {
        return [pscustomobject]@{ Status = 'invalid'; Reason = 'token encoding or JSON is invalid' }
    }

    $expectedFields = @('fingerprint', 'hmac', 'nonce', 'parentPid', 'protocol')
    $actualFields = [string[]]@($tokenObject.PSObject.Properties.Name)
    [Array]::Sort($actualFields, [System.StringComparer]::Ordinal)
    if (($actualFields -join [char]0) -ne ($expectedFields -join [char]0)) {
        return [pscustomobject]@{ Status = 'invalid'; Reason = 'token fields are not the closed field set' }
    }
    if ([string]$tokenObject.protocol -ne $script:SuiteMeasurementProtocol) {
        return [pscustomobject]@{ Status = 'invalid'; Reason = 'protocol tag mismatch' }
    }
    if ([string]$tokenObject.fingerprint -ne $ExpectedFingerprint) {
        return [pscustomobject]@{ Status = 'invalid'; Reason = 'fingerprint mismatch' }
    }
    if ([string]$tokenObject.nonce -notmatch '^[0-9a-f]{64}$') {
        return [pscustomobject]@{ Status = 'invalid'; Reason = 'nonce is malformed' }
    }
    if ([string]$tokenObject.hmac -notmatch '^[0-9a-f]{64}$') {
        return [pscustomobject]@{ Status = 'invalid'; Reason = 'HMAC is malformed' }
    }
    $parentPid = 0
    if (-not [int]::TryParse(
            [string]$tokenObject.parentPid,
            [System.Globalization.NumberStyles]::None,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref]$parentPid
        ) -or $parentPid -le 0) {
        return [pscustomobject]@{ Status = 'invalid'; Reason = 'parent PID is malformed' }
    }
    if ($keyBytes.Length -ne 32) {
        return [pscustomobject]@{ Status = 'invalid'; Reason = 'process-local key length is invalid' }
    }

    $payloadBytes = Get-SuiteMeasurementPayloadBytes -Fingerprint ([string]$tokenObject.fingerprint) `
        -Nonce ([string]$tokenObject.nonce) -ParentPid $parentPid
    $hmac = [System.Security.Cryptography.HMACSHA256]::new($keyBytes)
    try {
        $actualMac = $hmac.ComputeHash($payloadBytes)
    }
    finally {
        $hmac.Dispose()
    }
    $claimedMac = [Convert]::FromHexString([string]$tokenObject.hmac)
    if (-not [System.Security.Cryptography.CryptographicOperations]::FixedTimeEquals(
            $actualMac,
            $claimedMac
        )) {
        return [pscustomobject]@{ Status = 'invalid'; Reason = 'HMAC mismatch' }
    }
    if (-not (Test-SuiteProcessAncestor -AncestorPid $parentPid `
                -CurrentProcessId $CurrentProcessId)) {
        return [pscustomobject]@{ Status = 'invalid'; Reason = 'measurement parent is not a live ancestor' }
    }

    return [pscustomobject]@{
        Status      = 'complete'
        Reason      = ''
        Fingerprint = [string]$tokenObject.fingerprint
        ParentPid   = $parentPid
        Nonce       = [string]$tokenObject.nonce
    }
}

function Use-SuiteMeasurementNonce {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[0-9a-f]{64}$')]
        [string]$Nonce,
        [Parameter(Mandatory)][int]$ParentPid,
        [string]$ClaimRoot = [System.IO.Path]::GetTempPath()
    )

    if ($ParentPid -le 0) {
        return [pscustomobject]@{
            Status    = 'invalid'
            Reason    = 'measurement parent PID is invalid'
            ClaimPath = $null
        }
    }
    if (-not (Test-Path -LiteralPath $ClaimRoot -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $ClaimRoot -Force)
    }
    $claimIdBytes = [System.Text.Encoding]::UTF8.GetBytes(
        "$script:SuiteMeasurementProtocol$([char]0)$Nonce"
    )
    $claimId = [Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData($claimIdBytes)
    ).ToLowerInvariant()
    $claimPath = Join-Path $ClaimRoot "skalary-suite-measurement-$claimId.claim"
    $claim = [ordered]@{
        protocol  = $script:SuiteMeasurementProtocol
        nonce     = $Nonce
        parentPid = $ParentPid
        claimedAt = [DateTimeOffset]::UtcNow.ToString('o')
    }
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes(
        ($claim | ConvertTo-Json -Compress) + "`n"
    )

    try {
        $stream = [System.IO.File]::Open(
            $claimPath,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None
        )
        try {
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush($true)
        }
        finally {
            $stream.Dispose()
        }
    }
    catch [System.IO.IOException] {
        return [pscustomobject]@{
            Status    = 'invalid'
            Reason    = 'measurement nonce was already claimed'
            ClaimPath = $claimPath
        }
    }

    return [pscustomobject]@{
        Status    = 'complete'
        Reason    = ''
        ClaimPath = $claimPath
    }
}

function Test-SuiteRuntimeFreshness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)]$Budget,
        [Parameter(Mandatory)][string]$PlatformKey,
        [string]$MeasurementToken = $env:SKALARY_SUITE_MEASUREMENT_TOKEN,
        [string]$MeasurementKey = $env:SKALARY_SUITE_MEASUREMENT_KEY,
        [string]$ExpectedNonce,
        [int]$CurrentProcessId = $PID
    )

    $fingerprint = Get-SuiteInputFingerprint -RepoRoot $RepoRoot
    $hasToken = -not [string]::IsNullOrWhiteSpace($MeasurementToken)
    $hasKey = -not [string]::IsNullOrWhiteSpace($MeasurementKey)
    $authorization = $null
    if ($hasToken -or $hasKey) {
        if (-not ($hasToken -and $hasKey)) {
            return [pscustomobject]@{
                Status      = 'measurement-token-invalid'
                Reason      = 'measurement token and key must both be present'
                Fingerprint = $fingerprint
            }
        }
        $authorization = Test-SuiteMeasurementAuthorization -Token $MeasurementToken `
            -Key $MeasurementKey -ExpectedFingerprint $fingerprint.Fingerprint `
            -CurrentProcessId $CurrentProcessId
        if ($authorization.Status -ne 'complete') {
            return [pscustomobject]@{
                Status      = 'measurement-token-invalid'
                Reason      = $authorization.Reason
                Fingerprint = $fingerprint
            }
        }
        if ([string]::IsNullOrWhiteSpace($ExpectedNonce) -or
            -not [string]::Equals(
                $authorization.Nonce,
                $ExpectedNonce,
                [System.StringComparison]::Ordinal
            )) {
            return [pscustomobject]@{
                Status      = 'measurement-token-invalid'
                Reason      = 'measurement nonce is absent, mismatched, or already consumed'
                Fingerprint = $fingerprint
            }
        }
    }

    $recordPath = Join-Path $RepoRoot ([string]$Budget.MeasurementRecord)
    if (-not (Test-Path -LiteralPath $recordPath -PathType Leaf)) {
        if ($null -ne $authorization) {
            return [pscustomobject]@{
                Status          = 'complete'
                Reason          = ''
                MeasurementMode = $true
                StaleRowAllowed = $true
                Fingerprint     = $fingerprint
                Row             = $null
            }
        }
        return [pscustomobject]@{
            Status      = 'stale'
            Reason      = "measurement record '$recordPath' is missing"
            Fingerprint = $fingerprint
        }
    }
    $record = Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json
    if ($record.PSObject.Properties.Name -notcontains 'platforms' -or
        $null -eq $record.platforms) {
        if ($null -ne $authorization) {
            return [pscustomobject]@{
                Status          = 'complete'
                Reason          = ''
                MeasurementMode = $true
                StaleRowAllowed = $true
                Fingerprint     = $fingerprint
                Row             = $null
            }
        }
        return [pscustomobject]@{
            Status      = 'stale'
            Reason      = 'measurement record has no platforms object'
            Fingerprint = $fingerprint
        }
    }
    $rowProperties = @($record.platforms.PSObject.Properties)
    foreach ($property in $rowProperties) {
        $candidateFields = @($property.Value.PSObject.Properties.Name)
        if (
            $candidateFields -notcontains 'fingerprintProtocol' -or
            $candidateFields -notcontains 'inputFingerprint' -or
            [string]$property.Value.fingerprintProtocol -ne $fingerprint.Protocol -or
            [string]$property.Value.inputFingerprint -ne $fingerprint.Fingerprint
        ) {
            if ($null -eq $authorization) {
                return [pscustomobject]@{
                    Status      = 'stale'
                    Reason      = "'$($property.Name)' runtime row does not match the current tracked-input fingerprint"
                    Fingerprint = $fingerprint
                    Row         = $property.Value
                }
            }
        }
    }

    $rowProperty = @(
        $rowProperties |
            Where-Object Name -EQ $PlatformKey
    )
    if ($rowProperty.Count -ne 1) {
        if ($null -ne $authorization) {
            return [pscustomobject]@{
                Status          = 'complete'
                Reason          = ''
                MeasurementMode = $true
                StaleRowAllowed = $true
                Fingerprint     = $fingerprint
                Row             = $null
            }
        }
        return [pscustomobject]@{
            Status      = 'stale'
            Reason      = "measurement record has no unique '$PlatformKey' row"
            Fingerprint = $fingerprint
        }
    }

    $row = $rowProperty[0].Value
    $rowFields = @($row.PSObject.Properties.Name)
    $fresh = (
        $rowFields -contains 'fingerprintProtocol' -and
        $rowFields -contains 'inputFingerprint' -and
        [string]$row.fingerprintProtocol -eq $fingerprint.Protocol -and
        [string]$row.inputFingerprint -eq $fingerprint.Fingerprint
    )
    if (-not $fresh -and $null -eq $authorization) {
        return [pscustomobject]@{
            Status      = 'stale'
            Reason      = "'$PlatformKey' runtime row does not match the current tracked-input fingerprint"
            Fingerprint = $fingerprint
            Row         = $row
        }
    }

    return [pscustomobject]@{
        Status          = 'complete'
        Reason          = ''
        MeasurementMode = ($null -ne $authorization)
        StaleRowAllowed = (-not $fresh)
        Fingerprint     = $fingerprint
        Row             = $row
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Get-SuiteInputFingerprint -RepoRoot $RepoRoot
}
