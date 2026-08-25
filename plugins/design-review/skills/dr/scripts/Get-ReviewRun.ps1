#requires -Version 7.0
<#
.SYNOPSIS
    The only verifying reader of a published review run: prints a selected bounded view after
    checking the manifest, every digest, and every role bound.
.DESCRIPTION
    Plan c21cdc D20/REQ-6, step 1.2. A published run is trustworthy only through its
    `review-run.manifest.json`: this reader schema-validates that manifest, confines every name it
    references to a single path segment, verifies each file's byte count and SHA-256, and only then
    emits the selected summary or full view. Nothing else in the run directory is read, so an unreferenced or
    tampered file cannot reach the caller.

    Output contract: on success the verified Markdown is written to stdout as raw LF-terminated
    UTF-8 (at most 32 KiB for summary or 1 MiB for full), separate from the 8 KiB terminal-status
    object `Build-ReviewReport.ps1` prints — the two are different channels on purpose. `-ListIncomplete`
    prints a JSON array of the frozen-but-unpublished run ids a caller must finalize at review start.

    Verification is independent of the manifest's own claims: every artifact is held to its role's
    byte budget from the schema-owned vocabulary and to the UTF-8-without-BOM/LF/NFC encoding the
    contract writes, and the run directory and each concrete file are re-checked for a reparse point
    immediately before they are read, against the repository root this script resolves.

    The reader is read-only: it never writes, freezes, publishes or removes. Roots are derived from
    this script's installed location exactly as the persistence CLI derives them; the only caller
    inputs are a run id and, for a plan run, a confined plan directory.
.EXAMPLE
    & Get-ReviewRun.ps1 -RunId 8f3c1d2e-5a47-4b90-9c61-2d7e0f4a6b35
.EXAMPLE
    & Get-ReviewRun.ps1 -RunId 8f3c1d2e-5a47-4b90-9c61-2d7e0f4a6b35 -View Full
.EXAMPLE
    & Get-ReviewRun.ps1 -ListIncomplete -PlanDir docs/implementation-plans/<plan>
#>
[CmdletBinding(DefaultParameterSetName = 'Read')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Read')]
    [Parameter(Mandatory, ParameterSetName = 'Prepare')]
    [Parameter(Mandatory, ParameterSetName = 'Rollup')]
    [Parameter(Mandatory, ParameterSetName = 'Admission')]
    [string]$RunId,

    [Parameter(ParameterSetName = 'Read')]
    [Parameter(ParameterSetName = 'List')]
    [Parameter(ParameterSetName = 'Prepare')]
    [Parameter(ParameterSetName = 'Rollup')]
    [Parameter(ParameterSetName = 'Admission')]
    [string]$PlanDir,

    [Parameter(ParameterSetName = 'Read')]
    [ValidateSet('Summary', 'Full')]
    [string]$View = 'Summary',

    [Parameter(Mandatory, ParameterSetName = 'List')]
    [switch]$ListIncomplete,

    [Parameter(Mandatory, ParameterSetName = 'Prepare')]
    [switch]$Prepare,

    [Parameter(Mandatory, ParameterSetName = 'Rollup')]
    [switch]$VerifyAdmissionRollup,

    [Parameter(Mandatory, ParameterSetName = 'Admission')]
    [switch]$ReadAdmission
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$utf8 = [System.Text.UTF8Encoding]::new($false)

function Write-RawStdout {
    param([Parameter(Mandatory)][string]$Text)
    $bytes = $utf8.GetBytes($Text)
    $stdout = [Console]::OpenStandardOutput()
    $stdout.Write($bytes, 0, $bytes.Length)
    $stdout.Flush()
}

function Write-EncodedStderr {
    param([Parameter(Mandatory)][string]$Text)
    # Encoded and bounded (REQ-11): at most 16 KiB, control characters stripped.
    $flat = ([string]$Text) -replace '[\x00-\x08\x0b\x0c\x0e-\x1f]', ' '
    $bytes = $utf8.GetBytes($flat + [Environment]::NewLine)
    if ($bytes.Length -gt 16384) { $bytes = $bytes[0..16383] }
    $stderr = [Console]::OpenStandardError()
    $stderr.Write($bytes, 0, $bytes.Length)
    $stderr.Flush()
}

# The reader's exits are bounded exactly like the publisher's: `0` read, `2` unreadable or
# unresolvable, `4` unexpected. Loading the engine is inside the boundary so a broken install is a
# reported `4` rather than an unhandled error.
try {
    Import-Module (Join-Path $PSScriptRoot 'ReviewRun.psm1') -Force -DisableNameChecking
}
catch {
    Write-EncodedStderr -Text "Cannot load the review-run engine: $($_.Exception.Message)"
    exit 4
}

if ($PSCmdlet.ParameterSetName -eq 'List') {
    try {
        # Resolution goes through the engine's store resolver, so `-ListIncomplete` is confined and
        # inventory-validated exactly like Freeze/Publish rather than trusting the path it was given.
        $incomplete = @(Find-IncompleteReviewRun -PlanDir $PlanDir)
    }
    catch {
        Write-EncodedStderr -Text "Cannot list incomplete runs: $($_.Exception.Message)"
        exit 2
    }
    try {
        Write-RawStdout -Text ((ConvertTo-Json -InputObject @($incomplete) -Compress) + "`n")
        exit 0
    }
    catch {
        Write-EncodedStderr -Text "Cannot write the incomplete-run list: $($_.Exception.Message)"
        exit 4
    }
}

if ($PSCmdlet.ParameterSetName -eq 'Prepare') {
    try {
        $prepared = Resolve-ReviewRunPreparation -RunId $RunId -PlanDir $PlanDir
        Write-RawStdout -Text ((ConvertTo-Json -InputObject $prepared -Compress) + "`n")
        exit 0
    }
    catch {
        Write-EncodedStderr -Text "Cannot prepare run root: $($_.Exception.Message)"
        exit 2
    }
}

if ($PSCmdlet.ParameterSetName -eq 'Rollup') {
    try {
        $rollup = Get-ReviewAdmissionRollup -ParentRunId $RunId -PlanDir $PlanDir
        Write-RawStdout -Text ((ConvertTo-Json -InputObject $rollup -Depth 8 -Compress) + "`n")
        exit 0
    }
    catch {
        Write-EncodedStderr -Text "Cannot verify admission rollup: $($_.Exception.Message)"
        exit 2
    }
}

if ($PSCmdlet.ParameterSetName -eq 'Admission') {
    try {
        $runRoot = Resolve-ReviewRunRoot -RunId $RunId -PlanDir $PlanDir
        $admission = Read-ReviewAdmissionMarker -RunDir $runRoot -Boundary (Get-ReviewRepoRoot)
        Write-RawStdout -Text ((ConvertTo-Json -InputObject $admission.Marker -Depth 8 -Compress) + "`n")
        exit 0
    }
    catch {
        Write-EncodedStderr -Text "Cannot read admission state: $($_.Exception.Message)"
        exit 2
    }
}

try {
    $runDir = Resolve-ReviewRunRoot -RunId $RunId -PlanDir $PlanDir
}
catch {
    Write-EncodedStderr -Text "Cannot resolve run root: $($_.Exception.Message)"
    exit 2
}

try {
    $viewText = Get-ReviewRunViewText -RunDir $runDir -View $View -Boundary (Get-ReviewRepoRoot)
}
catch {
    Write-EncodedStderr -Text "Run '$RunId' is not readable: $($_.Exception.Message)"
    exit 2
}

try {
    Write-RawStdout -Text $viewText
    exit 0
}
catch {
    Write-EncodedStderr -Text "Cannot write the verified $($View.ToLowerInvariant()) view: $($_.Exception.Message)"
    exit 4
}
