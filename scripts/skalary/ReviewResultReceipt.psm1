#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-ReviewReceiptPropertySet {
    param(
        [Parameter(Mandatory)][object]$Node,
        [Parameter(Mandatory)][string[]]$Required,
        [string[]]$Optional = @(),
        [Parameter(Mandatory)][string]$Label
    )

    if ($Node -isnot [System.Collections.IDictionary]) {
        throw "$Label must be an object."
    }
    $actual = @($Node.Keys | ForEach-Object { [string]$_ } | Sort-Object)
    $allowed = @($Required + $Optional | Sort-Object)
    if (@($actual | Where-Object { $_ -cnotin $allowed }).Count -gt 0 -or
        @($Required | Where-Object { $_ -cnotin $actual }).Count -gt 0) {
        throw "$Label has an unexpected or incomplete property set."
    }
}

function Get-ReviewReceiptNonNegativeInteger {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory)][string]$Label
    )

    if ($null -eq $Value) {
        throw "$Label must be a non-negative integer."
    }
    $integerTypes = @(
        [System.TypeCode]::Byte,
        [System.TypeCode]::SByte,
        [System.TypeCode]::Int16,
        [System.TypeCode]::UInt16,
        [System.TypeCode]::Int32,
        [System.TypeCode]::UInt32,
        [System.TypeCode]::Int64,
        [System.TypeCode]::UInt64
    )
    if ([System.Type]::GetTypeCode($Value.GetType()) -notin $integerTypes) {
        throw "$Label must be a non-negative integer."
    }
    try {
        $integer = [System.Convert]::ToInt64($Value, [System.Globalization.CultureInfo]::InvariantCulture)
    }
    catch {
        throw "$Label exceeds the supported integer range."
    }
    if ($integer -lt 0) {
        throw "$Label must be a non-negative integer."
    }
    return $integer
}

function Assert-ReviewResultReceipt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ReceiptContent,
        [Parameter(Mandatory)]
        [ValidatePattern('^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')]
        [string]$ReviewRunId,
        [Parameter(Mandatory)][string]$ReportName,
        [Parameter(Mandatory)][byte[]]$ReportBytes
    )

    try {
        $receipt = $ReceiptContent | ConvertFrom-Json -AsHashtable -Depth 20
    }
    catch {
        throw "Review result receipt for run '$ReviewRunId' is invalid JSON: $($_.Exception.Message)"
    }

    Assert-ReviewReceiptPropertySet -Node $receipt -Label 'Review result receipt' -Required @(
        'attendance', 'findings', 'legacySource', 'manifestDigest', 'planDigest', 'report',
        'reviewType', 'runDigest', 'runId', 'schema', 'source', 'state', 'verdict'
    )
    Assert-ReviewReceiptPropertySet -Node $receipt['attendance'] -Label 'Review attendance' `
        -Required @('cancelled', 'completed', 'failed', 'omitted', 'pending', 'timed-out')
    Assert-ReviewReceiptPropertySet -Node $receipt['findings'] -Label 'Review findings' `
        -Required @('merged', 'raw', 'severity')
    Assert-ReviewReceiptPropertySet -Node $receipt['findings']['severity'] -Label 'Review severity' `
        -Required @('critical', 'high', 'low', 'medium')
    Assert-ReviewReceiptPropertySet -Node $receipt['report'] -Label 'Review report binding' `
        -Required @('bytes', 'digest', 'name')

    if ($receipt['schema'] -cne 'skalary/review-result-receipt@1' -or
        $receipt['runId'] -cne $ReviewRunId -or
        [string]$receipt['reviewType'] -cnotin @('code', 'design') -or
        [string]$receipt['verdict'] -cnotin @('approved', 'blocked') -or
        [string]$receipt['state'] -cnotin @('clean', 'degraded') -or
        $receipt['legacySource'] -isnot [bool] -or $receipt['legacySource']) {
        throw "Review result receipt for run '$ReviewRunId' has invalid identity or state metadata."
    }

    foreach ($name in @('planDigest', 'runDigest', 'manifestDigest')) {
        if ($receipt[$name] -isnot [string] -or [string]$receipt[$name] -cnotmatch '^sha256:[0-9a-f]{64}$') {
            throw "Review result receipt for run '$ReviewRunId' has an invalid $name binding."
        }
    }

    $source = $receipt['source']
    $mode = if ($source -is [System.Collections.IDictionary] -and $source['mode'] -is [string]) {
        [string]$source['mode']
    }
    else {
        ''
    }
    $sourceKeys = switch ($mode) {
        'branch' { @('base', 'digest', 'head', 'mode', 'pathCount') }
        { $_ -in @('uncommitted', 'paths') } { @('digest', 'head', 'mode', 'pathCount') }
        'design' { @('digest', 'mode', 'pathCount') }
        default { throw "Review result receipt for run '$ReviewRunId' has an invalid source mode." }
    }
    Assert-ReviewReceiptPropertySet -Node $source -Label 'Review source' -Required $sourceKeys
    if (($receipt['reviewType'] -ceq 'code' -and $mode -notin @('branch', 'uncommitted', 'paths')) -or
        ($receipt['reviewType'] -ceq 'design' -and $mode -cne 'design')) {
        throw "Review result receipt for run '$ReviewRunId' has a source mode inconsistent with its review type."
    }
    foreach ($name in @('base', 'head')) {
        if ($source.Contains($name) -and
            ($source[$name] -isnot [string] -or [string]$source[$name] -cnotmatch '^[0-9a-f]{40}$')) {
            throw "Review result receipt for run '$ReviewRunId' has an invalid source.$name binding."
        }
    }
    $pathCount = Get-ReviewReceiptNonNegativeInteger -Value $source['pathCount'] -Label 'Review source.pathCount'
    if ($source['digest'] -isnot [string] -or [string]$source['digest'] -cnotmatch '^sha256:[0-9a-f]{64}$' -or
        ($receipt['reviewType'] -ceq 'code' -and $pathCount -lt 1)) {
        throw "Review result receipt for run '$ReviewRunId' has invalid source metadata."
    }

    $attendance = [ordered]@{}
    foreach ($name in @('completed', 'failed', 'timed-out', 'omitted', 'cancelled', 'pending')) {
        $attendance[$name] = Get-ReviewReceiptNonNegativeInteger `
            -Value $receipt['attendance'][$name] `
            -Label "Review attendance.$name"
    }
    $attendanceTotal = [int64]0
    foreach ($value in $attendance.Values) { $attendanceTotal += $value }
    $nonCompleted = $attendanceTotal - $attendance['completed']
    if ($attendanceTotal -lt 1 -or $attendanceTotal -gt 16 -or
        ($receipt['state'] -ceq 'clean' -and $nonCompleted -ne 0) -or
        ($receipt['state'] -ceq 'degraded' -and $nonCompleted -eq 0)) {
        throw "Review result receipt for run '$ReviewRunId' has attendance inconsistent with its run state."
    }

    $merged = Get-ReviewReceiptNonNegativeInteger -Value $receipt['findings']['merged'] -Label 'Review findings.merged'
    $raw = Get-ReviewReceiptNonNegativeInteger -Value $receipt['findings']['raw'] -Label 'Review findings.raw'
    $severityTotal = [int64]0
    $severity = [ordered]@{}
    foreach ($name in @('critical', 'high', 'medium', 'low')) {
        $severity[$name] = Get-ReviewReceiptNonNegativeInteger `
            -Value $receipt['findings']['severity'][$name] `
            -Label "Review findings.severity.$name"
        $severityTotal += $severity[$name]
    }
    if ($merged -ne $severityTotal -or $raw -lt $merged -or ($merged -eq 0 -and $raw -ne 0)) {
        throw "Review result receipt for run '$ReviewRunId' has inconsistent finding totals."
    }
    if ($receipt['verdict'] -ceq 'approved' -and
        ($receipt['state'] -cne 'clean' -or $severity['critical'] -ne 0 -or $severity['high'] -ne 0)) {
        throw "Review result receipt for run '$ReviewRunId' has an approved verdict inconsistent with its state or blocking findings."
    }

    $report = $receipt['report']
    $reportedByteCount = Get-ReviewReceiptNonNegativeInteger -Value $report['bytes'] -Label 'Review report.bytes'
    $reportDigest = 'sha256:' + [Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData($ReportBytes)
    ).ToLowerInvariant()
    if ($ReportBytes.Length -lt 1 -or $ReportBytes.Length -gt 8192 -or
        $report['name'] -isnot [string] -or [string]$report['name'] -cne $ReportName -or
        $reportedByteCount -ne $ReportBytes.Length -or
        $report['digest'] -isnot [string] -or [string]$report['digest'] -cne $reportDigest) {
        throw "Review run '$ReviewRunId' retained report does not match its receipt."
    }

    return $receipt
}

Export-ModuleMember -Function Assert-ReviewResultReceipt
