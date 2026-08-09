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

Import-Module (Join-Path $PSScriptRoot 'PlanState.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'AtomicStore.psm1') -Force

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
$filePath = Resolve-PlanAssetPath -PlanDir $planDirFull -Kind $Kind
$fileGeneration = Get-AtomicStoreGeneration -Path $filePath
$fileParent = Split-Path -Parent $filePath
if (-not (Test-Path -LiteralPath $fileParent -PathType Container)) {
    New-Item -ItemType Directory -Path $fileParent -Force | Out-Null
}

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

function Repair-EmptyLearningsSections {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string]$Header,
        [string]$Placeholder
    )
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i].Trim() -ne $Header) { continue }
        $end = $Lines.Count
        for ($j = $i + 1; $j -lt $Lines.Count; $j++) {
            if ($Lines[$j] -match '^##\s') { $end = $j; break }
        }
        $hasEntry = $false
        for ($k = $i + 1; $k -lt $end; $k++) {
            if ($Lines[$k] -match '^\s*-\s') { $hasEntry = $true; break }
        }
        if (-not $hasEntry) {
            $insertAt = [Math]::Min($i + 2, $end)
            $Lines.Insert($insertAt, $Placeholder)
        }
    }
}

function Invoke-LearningsCap {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string]$Header,
        [string]$Placeholder,
        [int]$Max
    )

    $entryIndexes = [System.Collections.Generic.List[int]]::new()
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^\s*-\s\[') { $entryIndexes.Add($i) }
    }
    if ($entryIndexes.Count -le $Max) { return }

    $summaryIndexes = @($entryIndexes | Where-Object { $Lines[$_] -match '\[trigger:overflow-summary\]' })
    $normalIndexes = @($entryIndexes | Where-Object { $Lines[$_] -notmatch '\[trigger:overflow-summary\]' })

    $existingFolded = 0
    foreach ($s in $summaryIndexes) {
        if ($Lines[$s] -match 'Folded\s+(?<n>\d+)') { $existingFolded += [int]$Matches.n }
    }

    $keep = $Max - 1
    $foldNow = $normalIndexes.Count - $keep
    if ($foldNow -lt 1) { $foldNow = 1 }
    $newFolded = $existingFolded + $foldNow

    $oldestIndexes = @($normalIndexes | Select-Object -First $foldNow)
    $oldestStep = '0.0'
    if ($Lines[$oldestIndexes[0]] -match '^\s*-\s\[(?<s>[^\]]+)\]') { $oldestStep = $Matches.s }

    $removeSet = [System.Collections.Generic.SortedSet[int]]::new()
    foreach ($idx in $oldestIndexes) { [void]$removeSet.Add($idx) }
    foreach ($idx in $summaryIndexes) { [void]$removeSet.Add($idx) }
    $removeOrdered = @($removeSet) | Sort-Object -Descending
    foreach ($idx in $removeOrdered) { $Lines.RemoveAt($idx) }

    $summaryLine = "- [$oldestStep] [trigger:overflow-summary] Folded $newFolded additional learnings into this summary."

    $firstHeader = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i].Trim() -eq $Header) { $firstHeader = $i; break }
    }
    if ($firstHeader -lt 0) {
        $Lines.Add($Header)
        $Lines.Add('Phase: 1')
        $Lines.Add('')
        $firstHeader = $Lines.Count - 3
    }
    $insertAt = [Math]::Min($firstHeader + 2, $Lines.Count)
    if ($insertAt -lt $Lines.Count -and $Lines[$insertAt].Trim() -eq $Placeholder) {
        $Lines[$insertAt] = $summaryLine
    }
    else {
        $Lines.Insert($insertAt, $summaryLine)
    }

    Repair-EmptyLearningsSections -Lines $Lines -Header $Header -Placeholder $Placeholder
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

if ($Kind -eq 'Learnings' -and $Message) {
    Invoke-LearningsCap -Lines $lines -Header $config.Header -Placeholder $placeholder -Max $MaxLearnings
}

$content = ($lines -join "`n").TrimEnd("`n") + "`n"
$write = Invoke-WithAtomicStoreLock -Scope $filePath -Action {
    Set-AtomicStoreContent -Path $filePath -Content $content -ExpectedGeneration $fileGeneration
}
if ($write.Status -ne 'complete') {
    throw "Add-WorkflowNote failed with status '$($write.Status)' because the log changed concurrently; retry the command."
}

return [pscustomobject]@{
    Kind     = $Kind
    File     = $filePath
    Phase    = $Phase
    Appended = [bool]$Message
}
