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

    Steps are parsed from a small, strict block-YAML subset rather than split on their `- name:`
    marker: a `- name:` line inside a `run:` block scalar is text, and a split cannot tell that
    from a step boundary. The subset throws on anything it does not model — anchors, aliases,
    flow collections, multiple documents, tabs — so an unreadable workflow fails loudly instead
    of parsing into a shape the assertions happen to accept.
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

function Test-CiYamlSignificantLine {
    param([string]$Line)
    return -not ($Line -match '^[ ]*$' -or $Line -match '^[ ]*#')
}

function Get-CiYamlIndent {
    param([string]$Line)
    if ($Line -match "`t") { throw "CI workflow YAML must not contain tabs: '$Line'." }
    return ($Line -replace '^( *).*$', '$1').Length
}

function Get-CiYamlScalarValue {
    <#
    .SYNOPSIS
        Unquotes a plain or quoted flow scalar and rejects the constructs this subset excludes.
    #>
    param([string]$Raw)

    $value = $Raw.Trim()
    if ($value -match '^[&*]') { throw "CI workflow YAML anchors and aliases are not supported: '$Raw'." }
    if ($value -match '^[\[{]') { throw "CI workflow YAML flow collections are not supported: '$Raw'." }
    if ($value.StartsWith('"') -and $value.EndsWith('"') -and $value.Length -ge 2) {
        return $value.Substring(1, $value.Length - 2).Replace('\"', '"')
    }
    if ($value.StartsWith("'") -and $value.EndsWith("'") -and $value.Length -ge 2) {
        return $value.Substring(1, $value.Length - 2).Replace("''", "'")
    }
    return $value
}

function Read-CiYamlNode {
    <#
    .SYNOPSIS
        Parses one block-YAML node (mapping, sequence, or scalar) starting at $Index.
    .NOTES
        This is a deliberately small subset — block mappings, block sequences, block scalars and
        flow scalars — that throws on anything else. A parser that silently ignores what it does
        not understand is worse than no parser: the assertions built on it would keep passing
        while the structure they describe drifted. Each node also records the source line range so
        callers can still assert against the original text rather than a re-rendering of it.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][AllowEmptyCollection()][string[]]$Lines,
        [Parameter(Mandatory)][ref]$Index,
        [Parameter(Mandatory)][int]$Indent,
        [switch]$Sequence
    )

    $start = $Index.Value
    $entries = [ordered]@{}
    $items = [System.Collections.Generic.List[object]]::new()
    while ($Index.Value -lt $Lines.Count) {
        $line = $Lines[$Index.Value]
        if (-not (Test-CiYamlSignificantLine -Line $line)) { $Index.Value++; continue }
        $lineIndent = Get-CiYamlIndent -Line $line
        if ($lineIndent -lt $Indent) { break }
        if ($lineIndent -gt $Indent) {
            throw "Unexpected indentation at line $($Index.Value + 1): '$line'."
        }
        $content = $line.Substring($Indent)
        if ($content -match '^[\[{]') {
            throw "CI workflow YAML flow collections are not supported at line $($Index.Value + 1)."
        }
        if ($Sequence) {
            if ($content -notmatch '^- ?(?<rest>.*)$') { break }
            $rest = $Matches['rest']
            if ($rest -match '^(?:"[^"]*"|''[^'']*''|[A-Za-z_][A-Za-z0-9_.\-]*):(?: |$)') {
                # An inline mapping key on the dash line: re-indent the dash away so the mapping
                # parser sees a normal block mapping without disturbing the line numbering.
                $rewritten = $Lines.Clone()
                $rewritten[$Index.Value] = (' ' * ($Indent + 2)) + $rest
                $items.Add((Read-CiYamlNode -Lines $rewritten -Index $Index -Indent ($Indent + 2)))
                continue
            }
            if ([string]::IsNullOrWhiteSpace($rest)) {
                $Index.Value++
                $items.Add((Read-CiYamlNode -Lines $Lines -Index $Index -Indent ($Indent + 2)))
                continue
            }
            $items.Add([pscustomobject]@{
                    Kind = 'scalar'; Value = (Get-CiYamlScalarValue -Raw $rest)
                    Start = $Index.Value; End = $Index.Value
                })
            $Index.Value++
            continue
        }

        if ($content -match '^- ') { break }
        if ($content -notmatch '^(?<key>"[^"]*"|''[^'']*''|[A-Za-z_][A-Za-z0-9_.\-]*):(?<rest>.*)$') {
            throw "Unsupported CI workflow YAML at line $($Index.Value + 1): '$line'."
        }
        $key = Get-CiYamlScalarValue -Raw $Matches['key']
        $rest = $Matches['rest']
        if ($entries.Contains($key)) {
            throw "Duplicate key '$key' at line $($Index.Value + 1)."
        }
        $keyLine = $Index.Value
        if ($rest -match '^ *(?<style>[|>][-+]?) *$') {
            # Block scalar: every deeper-indented line belongs to the value verbatim, including
            # lines that look like comments or like the start of another step.
            $style = $Matches['style']
            $Index.Value++
            $blockLines = [System.Collections.Generic.List[string]]::new()
            $blockIndent = -1
            while ($Index.Value -lt $Lines.Count) {
                $blockLine = $Lines[$Index.Value]
                if ($blockLine -match '^[ ]*$') { $blockLines.Add(''); $Index.Value++; continue }
                $currentIndent = Get-CiYamlIndent -Line $blockLine
                if ($currentIndent -le $Indent) { break }
                if ($blockIndent -lt 0) { $blockIndent = $currentIndent }
                $blockLines.Add($blockLine.Substring([Math]::Min($blockIndent, $currentIndent)))
                $Index.Value++
            }
            while ($blockLines.Count -gt 0 -and $blockLines[$blockLines.Count - 1] -eq '') {
                $blockLines.RemoveAt($blockLines.Count - 1)
            }
            $separator = if ($style.StartsWith('>')) { ' ' } else { "`n" }
            $entries[$key] = [pscustomobject]@{
                Kind = 'scalar'; Value = ($blockLines -join $separator)
                Start = $keyLine; End = $Index.Value - 1
            }
            continue
        }
        if ($rest.Trim()) {
            $entries[$key] = [pscustomobject]@{
                Kind = 'scalar'; Value = (Get-CiYamlScalarValue -Raw $rest)
                Start = $keyLine; End = $keyLine
            }
            $Index.Value++
            continue
        }

        $Index.Value++
        $next = $Index.Value
        while ($next -lt $Lines.Count -and -not (Test-CiYamlSignificantLine -Line $Lines[$next])) { $next++ }
        if ($next -ge $Lines.Count) {
            $entries[$key] = [pscustomobject]@{ Kind = 'scalar'; Value = ''; Start = $keyLine; End = $keyLine }
            continue
        }
        $nextIndent = Get-CiYamlIndent -Line $Lines[$next]
        $nextContent = $Lines[$next].Substring($nextIndent)
        if ($nextIndent -ge $Indent -and $nextContent -match '^- ?') {
            $Index.Value = $next
            $child = Read-CiYamlNode -Lines $Lines -Index $Index -Indent $nextIndent -Sequence
        }
        elseif ($nextIndent -gt $Indent) {
            $Index.Value = $next
            $child = Read-CiYamlNode -Lines $Lines -Index $Index -Indent $nextIndent
        }
        else {
            $entries[$key] = [pscustomobject]@{ Kind = 'scalar'; Value = ''; Start = $keyLine; End = $keyLine }
            continue
        }
        $entries[$key] = [pscustomobject]@{
            Kind = $child.Kind; Value = $child.Value; Start = $keyLine; End = $child.End
        }
    }

    $end = [Math]::Max($start, $Index.Value - 1)
    if ($Sequence) {
        return [pscustomobject]@{ Kind = 'sequence'; Value = $items.ToArray(); Start = $start; End = $end }
    }
    return [pscustomobject]@{ Kind = 'mapping'; Value = $entries; Start = $start; End = $end }
}

function ConvertFrom-CiWorkflowYaml {
    <#
    .SYNOPSIS
        Parses a workflow into a structural tree of Kind/Value/Start/End nodes.
    .NOTES
        Structure — which job owns which step, and where a step ends — has to come from a parse
        rather than from a `- name:` split, because a `- name:` line inside a `run:` block scalar
        is text, not a step, and a split cannot tell the two apart.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Text)

    $lines = @(($Text -replace "`r`n", "`n") -split "`n")
    foreach ($line in $lines) {
        if ($line -match '^(---|\.\.\.)\s*$') { throw 'Multi-document CI workflow YAML is not supported.' }
    }
    $index = 0
    $document = Read-CiYamlNode -Lines $lines -Index ([ref]$index) -Indent 0
    return [pscustomobject]@{ Document = $document; Lines = $lines }
}

function Get-CiYamlNodeText {
    param(
        [Parameter(Mandatory)][object]$Node,
        [Parameter(Mandatory)][AllowEmptyString()][AllowEmptyCollection()][string[]]$Lines,
        [int]$SkipLeadingLines = 0
    )
    $from = $Node.Start + $SkipLeadingLines
    if ($from -gt $Node.End) { return '' }
    return (($Lines[$from..$Node.End]) -join "`n")
}

function Get-CiWorkflowJob {
    <#
    .SYNOPSIS
        Returns the jobs in a workflow as Name/Body/Steps objects.
    .NOTES
        Job identity matters once workflows contain conditional detector, image, and final
        jobs. Flattening their steps would let a gate run in the wrong trust boundary while
        preserving the same invocation text. Bodies stay raw source text so callers can assert
        against what is actually committed, but their boundaries come from the parse.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param([string]$Text)

    $parsed = ConvertFrom-CiWorkflowYaml -Text $Text
    $root = $parsed.Document.Value
    if (-not $root.Contains('jobs')) { return @() }
    $jobsNode = $root['jobs']
    if ($jobsNode.Kind -ne 'mapping') { return @() }

    $jobs = [System.Collections.Generic.List[object]]::new()
    foreach ($jobName in $jobsNode.Value.Keys) {
        $jobNode = $jobsNode.Value[$jobName]
        $steps = [System.Collections.Generic.List[object]]::new()
        if ($jobNode.Kind -eq 'mapping' -and $jobNode.Value.Contains('steps')) {
            $stepsNode = $jobNode.Value['steps']
            if ($stepsNode.Kind -eq 'sequence') {
                foreach ($stepNode in @($stepsNode.Value)) {
                    if ($stepNode.Kind -ne 'mapping') { continue }
                    $stepName = if ($stepNode.Value.Contains('name')) { $stepNode.Value['name'].Value } else { '' }
                    # The name line is excluded from Body so a step body stays what the step does.
                    $skip = if ($stepNode.Value.Contains('name') -and $stepNode.Value['name'].Start -eq $stepNode.Start) { 1 } else { 0 }
                    $steps.Add([pscustomobject]@{
                            Name = $stepName
                            Body = (Remove-CiComment -Text (Get-CiYamlNodeText -Node $stepNode -Lines $parsed.Lines -SkipLeadingLines $skip))
                            Node = $stepNode
                        })
                }
            }
        }
        $jobs.Add([pscustomobject]@{
                Name  = $jobName
                Body  = (Remove-CiComment -Text (Get-CiYamlNodeText -Node $jobNode -Lines $parsed.Lines))
                Steps = $steps.ToArray()
                Node  = $jobNode
            })
    }
    return $jobs.ToArray()
}

function Get-CiWorkflowStep {
    <#
    .SYNOPSIS
        Returns every step in the workflow, in document order, as Name/Body pairs.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param([string]$Text)

    return @(@(Get-CiWorkflowJob -Text $Text) | ForEach-Object { $_.Steps })
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

Export-ModuleMember -Function Remove-CiComment, Get-CiWorkflowStep, Get-CiWorkflowJob, Get-CiStepRunLine, ConvertFrom-CiWorkflowYaml, Get-CiYamlNodeText
