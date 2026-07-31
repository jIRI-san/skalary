#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [AllowEmptyCollection()]
    [object[]]$Result,

    [string]$Commit,

    [int]$Phase,

    [string]$PlanDir,

    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$receiptPath = $null
if ($PlanDir) {
    Import-Module (Join-Path $PSScriptRoot 'PlanState.psm1') -Force -DisableNameChecking
    $receiptPath = Resolve-PlanAssetPath -PlanDir $PlanDir -Kind Evidence
}

if (-not $Commit) {
    $repoRootPath = [System.IO.Path]::GetFullPath($RepoRoot)
    $Commit = (& git -C $repoRootPath rev-parse HEAD 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($Commit)) {
        throw 'Build-EvidenceReceipt could not resolve HEAD; pass -Commit explicitly.'
    }
    $Commit = $Commit.Trim()
}

$dash = [char]0x2014
$sep = " $dash "

function Get-ResultField {
    param([object]$Object, [string]$Name)
    if ($Object.PSObject.Properties.Name -contains $Name) { return $Object.$Name }
    return $null
}

$lines = [System.Collections.Generic.List[string]]::new()
$reqOrder = [System.Collections.Generic.List[string]]::new()
$reqStatus = [ordered]@{}

foreach ($item in $Result) {
    $req = Get-ResultField -Object $item -Name 'Req'
    $marker = Get-ResultField -Object $item -Name 'Marker'
    if ([string]::IsNullOrWhiteSpace($req) -or [string]::IsNullOrWhiteSpace($marker)) {
        throw 'Each evidence result requires a non-empty Req and Marker.'
    }

    $success = Get-ResultField -Object $item -Name 'Success'
    $note = Get-ResultField -Object $item -Name 'Note'
    $message = Get-ResultField -Object $item -Name 'Message'

    if ($success -eq $true) {
        $glyph = [char]0x2713
        $base = 'passed'
    }
    elseif ($success -eq $false) {
        $glyph = [char]0x2717
        $base = 'failed'
    }
    else {
        $glyph = [char]0x2717
        $base = 'unrun'
    }

    $detail = $null
    if (-not [string]::IsNullOrWhiteSpace($note)) {
        $detail = $note
    }
    elseif ($success -ne $true -and -not [string]::IsNullOrWhiteSpace($message)) {
        $detail = $message
    }
    $resultText = if ($detail) { "${base}: $detail" } else { $base }

    $lines.Add("$glyph $req$sep$marker$sep$resultText$sep$Commit")

    if (-not $reqStatus.Contains($req)) {
        $reqOrder.Add($req)
        $reqStatus[$req] = $true
    }
    if ($success -ne $true) {
        $reqStatus[$req] = $false
    }
}

$textLines = [System.Collections.Generic.List[string]]::new()
if ($PSBoundParameters.ContainsKey('Phase')) {
    $textLines.Add("Phase $Phase Crosscheck:")
}
$textLines.AddRange($lines)

$allPassed = $true
foreach ($req in $reqOrder) {
    if (-not $reqStatus[$req]) { $allPassed = $false; break }
}

return [pscustomobject]@{
    Commit      = $Commit
    Lines       = $lines.ToArray()
    Text        = ($textLines -join "`n")
    ReqStatus   = $reqStatus
    AllPassed   = ($reqOrder.Count -gt 0 -and $allPassed)
    ReceiptPath = $receiptPath
}
