#requires -Version 7.0
<#
.SYNOPSIS
    Cost-model instrumentation shared by the whole `tests/` tree.
.DESCRIPTION
    Records per-operation call counts and elapsed seconds for the expensive
    fixture operations the suite performs (repo clones, plugin installs,
    registry builds and registry validation).

    Instrumentation is inert unless `SKALARY_SUITE_PROFILE` names a sink file:
    a normal `npm test` run pays only a stopwatch per wrapped call, and
    `scripts/skalary/Measure-SuiteProfile.ps1` is the only caller that turns
    recording on. Samples are appended as JSON Lines so a crashed run still
    leaves the samples it already produced.
#>

Set-StrictMode -Version Latest

$script:SinkVariable = 'SKALARY_SUITE_PROFILE'

function Get-SuiteProfileSink {
    <#
    .SYNOPSIS
        Returns the active sink path, or $null when profiling is off.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $sink = [System.Environment]::GetEnvironmentVariable($script:SinkVariable)
    if ([string]::IsNullOrWhiteSpace($sink)) { return $null }
    return $sink
}

function Write-SuiteOperationSample {
    <#
    .SYNOPSIS
        Appends one operation sample to the active sink.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Operation,

        [Parameter(Mandatory)]
        [double]$Seconds,

        [string]$Source
    )

    $sink = Get-SuiteProfileSink
    if (-not $sink) { return }

    $sample = [ordered]@{
        op = $Operation
        source = if ([string]::IsNullOrWhiteSpace($Source)) { 'unknown' } else { $Source }
        seconds = [math]::Round($Seconds, 4)
        ts = [DateTimeOffset]::UtcNow.ToString('o')
    }
    $line = ($sample | ConvertTo-Json -Compress -Depth 4) + "`n"

    # Child pwsh processes never import this module, but several Pester containers can
    # share one sink through the same process; retry so a transient lock is not a lost sample.
    for ($attempt = 0; $attempt -lt 10; $attempt++) {
        try {
            [System.IO.File]::AppendAllText($sink, $line, [System.Text.UTF8Encoding]::new($false))
            return
        }
        catch [System.IO.IOException] {
            Start-Sleep -Milliseconds 20
        }
    }
}

function Measure-SuiteOperation {
    <#
    .SYNOPSIS
        Times $Body, records it under $Operation, and returns whatever $Body produced.
    .NOTES
        The body runs in a child scope of the caller, so wrapping an existing
        function body neither changes variable resolution nor swallows output.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Operation,

        [Parameter(Mandatory)]
        [scriptblock]$Body,

        [string]$Source
    )

    if (-not $Source) { $Source = $Body.File }
    if (-not $Source) { $Source = $MyInvocation.PSCommandPath }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        & $Body
    }
    finally {
        $stopwatch.Stop()
        Write-SuiteOperationSample -Operation $Operation -Seconds $stopwatch.Elapsed.TotalSeconds -Source $Source
    }
}

Export-ModuleMember -Function Get-SuiteProfileSink, Write-SuiteOperationSample, Measure-SuiteOperation
