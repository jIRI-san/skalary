#requires -Version 7.0
<#
.SYNOPSIS
    Reads the repository's CI workflows as the artefacts they are — text.
.DESCRIPTION
    The workflow is the only place several of this repo's gates actually run, and nothing
    else parses it, so a rename, a chained script or a dropped step is silent until a
    release goes out unvalidated. Two test files assert properties of it — the gate shape
    (`Ci.Tests.ps1`) and the gate inventory (`CiGates.Tests.ps1`) — and a second copy of
    the parser would be a second thing to drift, which is the defect shape both files exist
    to catch.

    Steps are split on their `- name:` marker rather than parsed as YAML: no YAML parser is
    a dependency of this repo, and adding one to read a handful of step names would be a
    supply-chain cost paid for a string split.
#>

Set-StrictMode -Version Latest

function Remove-CiComment {
    <#
    .SYNOPSIS
        Drops comment lines before anything is matched.
    .NOTES
        A comment naming a gate would otherwise count as that gate running — prose standing
        in for an invocation is exactly the failure these tests exist to catch.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string]$Text)

    return (($Text -split '\r?\n' | Where-Object { $_ -notmatch '^\s*#' }) -join "`n")
}

function Get-CiWorkflowStep {
    <#
    .SYNOPSIS
        Returns the workflow's steps as Name/Body pairs, comments removed.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param([string]$Text)

    $steps = [System.Collections.Generic.List[object]]::new()
    $chunks = [regex]::Split((Remove-CiComment -Text $Text), '(?m)^ {6}- name: ')
    for ($i = 1; $i -lt $chunks.Count; $i++) {
        $chunk = $chunks[$i]
        $break = $chunk.IndexOf("`n")
        $name = if ($break -ge 0) { $chunk.Substring(0, $break) } else { $chunk }
        $body = if ($break -ge 0) { $chunk.Substring($break + 1) } else { '' }
        $steps.Add([pscustomobject]@{
                Name = $name.Trim()
                Body = $body
            })
    }

    return $steps.ToArray()
}

function Get-CiWorkflowJob {
    <#
    .SYNOPSIS
        Returns the jobs in a workflow as Name/Body/Steps objects, comments removed.
    .NOTES
        Job identity matters once workflows contain conditional detector, image, and final
        jobs. Flattening their steps would let a gate run in the wrong trust boundary while
        preserving the same invocation text.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param([string]$Text)

    $code = Remove-CiComment -Text $Text
    if ($code -notmatch '(?ms)^jobs:[ \t]*\r?\n(?<body>.*)$') { return @() }
    $body = $Matches['body']
    if ($body -match '(?ms)^(?<jobs>.*?)^\S') { $body = $Matches['jobs'] }

    $matches = @([regex]::Matches(
            $body,
            '(?m)^ {2}(?<name>[A-Za-z][A-Za-z0-9_-]*):[ \t]*(?:\r?\n|$)'
        ))
    $jobs = [System.Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $matches.Count; $index++) {
        $start = $matches[$index].Index + $matches[$index].Length
        $end = if ($index + 1 -lt $matches.Count) { $matches[$index + 1].Index } else { $body.Length }
        $jobBody = $body.Substring($start, $end - $start)
        $jobs.Add([pscustomobject]@{
                Name  = $matches[$index].Groups['name'].Value
                Body  = $jobBody
                Steps = @(Get-CiWorkflowStep -Text $jobBody)
            })
    }
    return $jobs.ToArray()
}

function Get-CiStepRunLine {
    <#
    .SYNOPSIS
        Returns the statements a step runs, in order.
    .NOTES
        A step reports the exit code of its *last* statement, so reading the run block as one
        blob would let a trailing command mask the gate before it — and `;` separates
        statements exactly as a newline does, so a swallow appended after a semicolon has to
        be read as its own statement rather than as part of the command it neuters.

        The block ends at the first line indented no deeper than the `run:` key, so a later
        YAML key on the same step is not mistaken for a command.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([string]$Body)

    $lines = @((Remove-CiComment -Text $Body) -split "`n")
    $runIndex = -1
    $runIndent = 0
    $inline = ''
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^(?<indent>[ \t]*)run:[ \t]*(?<rest>.*)$') {
            $runIndex = $i
            $runIndent = $Matches['indent'].Length
            $inline = $Matches['rest'].Trim()
            break
        }
    }
    if ($runIndex -lt 0) { return @() }

    $collected = [System.Collections.Generic.List[string]]::new()
    # `|`, `|-` and `>` introduce a block scalar; anything else on the line is the command
    # itself, which is the flow-scalar form.
    if ($inline -and $inline -notmatch '^[|>][-+]?$') { $collected.Add($inline) }

    for ($i = $runIndex + 1; $i -lt $lines.Count; $i++) {
        $line = $lines[$i].TrimEnd()
        if (-not $line.Trim()) { continue }
        $indent = ($line -replace '^([ \t]*).*$', '$1').Length
        if ($indent -le $runIndent) { break }
        $collected.Add($line.Trim())
    }

    $statements = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $collected) {
        foreach ($statement in ($line -split ';')) {
            if ($statement.Trim()) { $statements.Add($statement.Trim()) }
        }
    }
    return $statements.ToArray()
}

Export-ModuleMember -Function Remove-CiComment, Get-CiWorkflowStep, Get-CiWorkflowJob, Get-CiStepRunLine
