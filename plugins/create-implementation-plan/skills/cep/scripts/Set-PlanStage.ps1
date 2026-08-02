#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$PlanFile,

    [Parameter(Mandatory)]
    [string]$Stage
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'PlanState.psm1') -Force -DisableNameChecking

$stageValue = $Stage.Trim()
if ([string]::IsNullOrWhiteSpace($stageValue)) {
    throw 'Stage must be a non-empty value.'
}
if ($stageValue -match '[>\r\n]') {
    throw "Stage '$Stage' must not contain '>' or newlines."
}

# The single writer of the anchor is also the gate on what may be written: a stage that never reaches
# the file cannot later be misread as "skip every check" (RISK-6). Throws on anything outside the set.
$stageValue = (Resolve-PlanStage -Stage $stageValue).Stage

$fullPath = (Resolve-Path -LiteralPath $PlanFile).Path
$raw = Get-Content -LiteralPath $fullPath -Raw
$normalized = $raw -replace "`r`n", "`n"

$anchor = "<!-- cip-stage: $stageValue -->"
$pattern = '<!--\s*cip-stage:\s*[^>]*-->'

if ([regex]::IsMatch($normalized, $pattern)) {
    $updated = [regex]::Replace($normalized, $pattern, $anchor, 1)
}
else {
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.AddRange([string[]]($normalized.Split("`n")))

    $insertAfter = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '<!--\s*plan-id:') { $insertAfter = $i; break }
    }
    if ($insertAfter -lt 0) {
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^#\s') { $insertAfter = $i; break }
        }
    }

    if ($insertAfter -ge 0) {
        $lines.Insert($insertAfter + 1, $anchor)
    }
    else {
        $lines.Insert(0, $anchor)
    }
    $updated = ($lines -join "`n")
}

$content = $updated.TrimEnd("`n") + "`n"
Set-Content -LiteralPath $fullPath -Value $content -Encoding utf8NoBOM -NoNewline

return [pscustomobject]@{
    PlanFile = $fullPath
    Stage    = $stageValue
}
