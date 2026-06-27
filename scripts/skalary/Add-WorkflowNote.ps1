#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('CrLog', 'Learnings', 'Capture')]
    [string]$Kind,

    [Parameter(Mandatory)]
    [string]$PlanDir,

    [Parameter(Mandatory)]
    [int]$Phase,

    [string]$Step,

    [string]$Message,

    [ValidateSet('Critical', 'High', 'Med', 'Low')]
    [string]$Sev,

    [ValidateSet('code-review', 'discovery', 'note')]
    [string]$Src,

    [ValidateSet('rework>1', 'plan-contradiction', 'reusable-pattern', 'overflow-summary')]
    [string]$Trigger,

    [int]$MaxLearnings = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-NoteConfig {
    param([string]$Kind)
    switch ($Kind) {
        'CrLog' { return [pscustomobject]@{ FileName = 'cr-log.md'; Header = '## CR Capture' } }
        'Learnings' { return [pscustomobject]@{ FileName = 'learnings.md'; Header = '## Learnings Capture' } }
        'Capture' { return [pscustomobject]@{ FileName = 'capture.md'; Header = '## Capture' } }
    }
}

function ConvertTo-SafeNoteBody {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    $clean = $Text -replace "[`r`n`t]+", ' '
    $clean = $clean.Replace('[', '(').Replace(']', ')')
    $clean = $clean.Replace('`', "'")
    $clean = $clean.Replace('|', '/')
    $clean = $clean.Replace([char]0x00B7, '-')
    $clean = $clean -replace '\s+', ' '
    return $clean.Trim()
}

function Get-StepToken {
    param([string]$Step)
    if ([string]::IsNullOrWhiteSpace($Step)) { return '-' }
    $token = $Step.Trim()
    if ($token -notmatch '^[0-9]+\.[0-9]+[a-z]?$') {
        throw "Step '$Step' must look like '<phase>.<step>' (e.g. 1.4 or 2.3a)."
    }
    return $token
}

function Format-NoteEntry {
    param(
        [string]$Kind,
        [string]$Step,
        [string]$Sev,
        [string]$Src,
        [string]$Trigger,
        [string]$Body
    )

    $stepToken = Get-StepToken -Step $Step
    $safeBody = ConvertTo-SafeNoteBody -Text $Body

    switch ($Kind) {
        'CrLog' {
            if (-not $Sev) { throw 'CrLog notes require -Sev.' }
            $srcToken = if ($Src) { $Src } else { 'code-review' }
            return "- [$stepToken] [src:$srcToken] [sev:$Sev] $safeBody"
        }
        'Learnings' {
            if (-not $Trigger) { throw 'Learnings notes require -Trigger.' }
            return "- [$stepToken] [trigger:$Trigger] $safeBody"
        }
        'Capture' {
            $tokens = ''
            if ($Src) { $tokens += " [src:$Src]" }
            if ($Sev) { $tokens += " [sev:$Sev]" }
            return "- [$stepToken]$tokens $safeBody"
        }
    }
}

$placeholder = 'No entries for this phase.'
$config = Get-NoteConfig -Kind $Kind

$planDirFull = [System.IO.Path]::GetFullPath($PlanDir)
if (-not (Test-Path -LiteralPath $planDirFull -PathType Container)) {
    throw "Plan folder not found: $planDirFull"
}
$filePath = Join-Path $planDirFull $config.FileName

if (Test-Path -LiteralPath $filePath -PathType Leaf) {
    $raw = Get-Content -LiteralPath $filePath -Raw
}
else {
    $raw = ''
}
$normalized = $raw -replace "`r`n", "`n"
$lines = [System.Collections.Generic.List[string]]::new()
if ($normalized.Length -gt 0) {
    $lines.AddRange([string[]]($normalized.TrimEnd("`n").Split("`n")))
}

function Find-SectionRange {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string]$Header,
        [int]$Phase
    )
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i].Trim() -eq $Header -and ($i + 1) -lt $Lines.Count -and $Lines[$i + 1] -match "^\s*Phase:\s*$Phase\s*$") {
            $end = $Lines.Count
            for ($j = $i + 1; $j -lt $Lines.Count; $j++) {
                if ($Lines[$j] -match '^##\s') { $end = $j; break }
            }
            return [pscustomobject]@{ Start = $i; End = $end }
        }
    }
    return $null
}

$range = Find-SectionRange -Lines $lines -Header $config.Header -Phase $Phase

if (-not $range) {
    if ($lines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($lines[$lines.Count - 1])) {
        $lines.Add('')
    }
    $lines.Add($config.Header)
    $lines.Add("Phase: $Phase")
    $lines.Add('')
    if ($Message) {
        $lines.Add((Format-NoteEntry -Kind $Kind -Step $Step -Sev $Sev -Src $Src -Trigger $Trigger -Body $Message))
    }
    else {
        $lines.Add($placeholder)
    }
}
elseif ($Message) {
    $entry = Format-NoteEntry -Kind $Kind -Step $Step -Sev $Sev -Src $Src -Trigger $Trigger -Body $Message

    $placeholderIndex = -1
    $lastEntryIndex = -1
    for ($i = $range.Start; $i -lt $range.End; $i++) {
        if ($lines[$i].Trim() -eq $placeholder) { $placeholderIndex = $i }
        if ($lines[$i] -match '^\s*-\s') { $lastEntryIndex = $i }
    }

    if ($placeholderIndex -ge 0) {
        $lines[$placeholderIndex] = $entry
    }
    elseif ($lastEntryIndex -ge 0) {
        $lines.Insert($lastEntryIndex + 1, $entry)
    }
    else {
        $lines.Insert($range.End, $entry)
    }
}

$content = ($lines -join "`n").TrimEnd("`n") + "`n"
Set-Content -LiteralPath $filePath -Value $content -Encoding utf8NoBOM -NoNewline

return [pscustomobject]@{
    Kind     = $Kind
    File     = $filePath
    Phase    = $Phase
    Appended = [bool]$Message
}
