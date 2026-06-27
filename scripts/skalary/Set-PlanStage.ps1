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

$stageValue = $Stage.Trim()
if ([string]::IsNullOrWhiteSpace($stageValue)) {
    throw 'Stage must be a non-empty value.'
}
if ($stageValue -match '[>\r\n]') {
    throw "Stage '$Stage' must not contain '>' or newlines."
}

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
