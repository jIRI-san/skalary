#requires -Version 7.0
<#
.SYNOPSIS
    Internal implementation body for scripts/skalary/Test-Evals.ps1. Not an entry point.
.DESCRIPTION
    Holds the whole structural-eval operation: scope validation, eval-file selection, the
    Pester run, the required-case contract, and the JSON/Markdown report. The public command
    dot-sources this file for a direct -FullRepository run and supervises it as a child
    process for every focused -Plugin run. Run as a script it reads one bound request from
    stdin, so the supervised child performs the validated operation without re-entering
    public dispatch.

    scripts/skalary/Test-Evals.ps1 stays the documented command; this file is its body.

    Exit codes:
      0  the selected structural evals ran and passed
      1  a selected structural eval failed, errored, or a required case did not pass
      3  NoEvalsDiscovered — the selected plugin asserted nothing
     12  FocusedScopeRequired — the selection was not a single confined plugin or -FullRepository
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..' '_Common.ps1')

function Resolve-ConfinedEvalPath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Label,
        [switch]$AllowMissing,
        [switch]$Directory
    )

    $rootFull = [System.IO.Path]::GetFullPath($Root)
    $candidate = if ([System.IO.Path]::IsPathRooted($Path)) {
        [System.IO.Path]::GetFullPath($Path)
    }
    else {
        [System.IO.Path]::GetFullPath((Join-Path $rootFull $Path))
    }
    $relative = [System.IO.Path]::GetRelativePath($rootFull, $candidate)
    if ([System.IO.Path]::IsPathRooted($relative) -or $relative -eq '..' -or
        $relative.StartsWith("..$([System.IO.Path]::DirectorySeparatorChar)", [System.StringComparison]::Ordinal)) {
        throw "$Label must stay inside the repository: '$candidate'."
    }

    $cursor = [System.IO.Path]::GetPathRoot($candidate)
    foreach ($segment in $candidate.Substring($cursor.Length).Split(
            [char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar),
            [System.StringSplitOptions]::RemoveEmptyEntries)) {
        $cursor = Join-Path $cursor $segment
        $item = Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue
        if ($null -eq $item) {
            if ($AllowMissing) { break }
            throw "$Label does not exist: '$candidate'."
        }
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "$Label must not traverse a link or reparse point: '$cursor'."
        }
    }
    if (-not $AllowMissing -or (Test-Path -LiteralPath $candidate)) {
        $expectedType = if ($Directory) { 'Container' } else { 'Leaf' }
        if (-not (Test-Path -LiteralPath $candidate -PathType $expectedType)) {
            throw "$Label has the wrong path type: '$candidate'."
        }
    }
    return $candidate
}

function Get-PluginNameFromEvalPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $normalizedPath = [System.IO.Path]::GetFullPath($Path).Replace('\', '/')
    if ($normalizedPath -match '/plugins/(?<plugin>[^/]+)/evals/') {
        return [string]$Matches.plugin
    }

    return 'unknown'
}

function Convert-TestResultToEvalOutcome {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Result
    )

    switch -Regex ($Result) {
        '^Passed$' { return 'pass' }
        '^Skipped$' { return 'skip' }
        '^NotRun$' { return 'skip' }
        '^Failed$' { return 'fail' }
        default { return 'error' }
    }
}

function Get-TestArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $TestResult,

        [Parameter(Mandatory)]
        [string]$DefaultArtifact
    )

    if ($null -ne $TestResult.Data -and $TestResult.Data -is [hashtable]) {
        if ($TestResult.Data.ContainsKey('artifact') -and -not [string]::IsNullOrWhiteSpace([string]$TestResult.Data.artifact)) {
            return [string]$TestResult.Data.artifact
        }

        if ($TestResult.Data.ContainsKey('Artifact') -and -not [string]::IsNullOrWhiteSpace([string]$TestResult.Data.Artifact)) {
            return [string]$TestResult.Data.Artifact
        }
    }

    return $DefaultArtifact
}

function Get-StructuralEvalEntryList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $PesterResult
    )

    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($test in @($PesterResult.Tests)) {
        $scriptBlockFile = $null
        if ($null -ne $test.ScriptBlock -and -not [string]::IsNullOrWhiteSpace([string]$test.ScriptBlock.File)) {
            $scriptBlockFile = [string]$test.ScriptBlock.File
        }

        $scriptPath = if (-not [string]::IsNullOrWhiteSpace($scriptBlockFile)) {
            $scriptBlockFile
        }
        elseif (-not [string]::IsNullOrWhiteSpace([string]$test.Path)) {
            [string]$test.Path
        }
        else {
            '<unknown>'
        }

        $caseName = if (-not [string]::IsNullOrWhiteSpace([string]$test.ExpandedPath)) {
            [string]$test.ExpandedPath
        }
        elseif (-not [string]::IsNullOrWhiteSpace([string]$test.ExpandedName)) {
            [string]$test.ExpandedName
        }
        else {
            [string]$test.Name
        }

        $errorMessage = $null
        if ($null -ne $test.ErrorRecord) {
            $errorRecordHasException = $test.ErrorRecord.PSObject.Properties.Name -contains 'Exception'
            if ($errorRecordHasException -and
                $null -ne $test.ErrorRecord.Exception -and
                -not [string]::IsNullOrWhiteSpace([string]$test.ErrorRecord.Exception.Message)) {
                $errorMessage = [string]$test.ErrorRecord.Exception.Message
            }
            elseif (-not [string]::IsNullOrWhiteSpace([string]$test.ErrorRecord)) {
                $errorMessage = [string]$test.ErrorRecord
            }
        }

        $entries.Add([ordered]@{
                plugin = Get-PluginNameFromEvalPath -Path $scriptPath
                case = $caseName
                artifact = Get-TestArtifact -TestResult $test -DefaultArtifact $scriptPath
                tier = 'structural'
                outcome = Convert-TestResultToEvalOutcome -Result ([string]$test.Result)
                score = $null
                threshold = $null
                message = $errorMessage
                transcriptPath = $null
            })
    }

    return @($entries)
}

function Get-OutcomeCount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Entries,

        [Parameter(Mandatory)]
        [string]$Outcome
    )

    return @($Entries | Where-Object { [string]$_.outcome -eq $Outcome }).Count
}

function ConvertTo-MarkdownCell {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Value
    )

    if ([string]::IsNullOrEmpty($Value)) {
        return ''
    }

    return (($Value -replace '\r?\n', ' ') -replace '\|', '\|')
}

function ConvertTo-EvalMarkdownReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Report
    )

    $builder = [System.Text.StringBuilder]::new()
    [void]$builder.AppendLine('# Eval Report')
    [void]$builder.AppendLine()
    [void]$builder.AppendLine("- Generated: $($Report.generatedAt)")
    [void]$builder.AppendLine()

    $summary = $Report.summary
    [void]$builder.AppendLine('## Summary')
    [void]$builder.AppendLine()
    [void]$builder.AppendLine('| Total | Pass | Fail | Skip | Error |')
    [void]$builder.AppendLine('|---|---|---|---|---|')
    [void]$builder.AppendLine("| $($summary.total) | $($summary.pass) | $($summary.fail) | $($summary.skip) | $($summary.error) |")
    [void]$builder.AppendLine()

    $structural = @($Report.entries | Where-Object { [string]$_.tier -eq 'structural' })
    $llm = @($Report.entries | Where-Object { [string]$_.tier -eq 'llm' })

    if ($structural.Count -gt 0) {
        [void]$builder.AppendLine('## Structural (Tier 1)')
        [void]$builder.AppendLine()
        [void]$builder.AppendLine('| Plugin | Case | Outcome | Message |')
        [void]$builder.AppendLine('|---|---|---|---|')
        foreach ($entry in $structural) {
            [void]$builder.AppendLine("| $(ConvertTo-MarkdownCell ([string]$entry.plugin)) | $(ConvertTo-MarkdownCell ([string]$entry.case)) | $($entry.outcome) | $(ConvertTo-MarkdownCell ([string]$entry.message)) |")
        }
        [void]$builder.AppendLine()
    }

    if ($llm.Count -gt 0) {
        [void]$builder.AppendLine('## LLM (Tier 2)')
        [void]$builder.AppendLine()
        [void]$builder.AppendLine('| Plugin | Case | Outcome | Score | Threshold | Transcript |')
        [void]$builder.AppendLine('|---|---|---|---|---|---|')
        foreach ($entry in $llm) {
            $score = if ($null -ne $entry.score) { '{0:0.00}' -f [double]$entry.score } else { '' }
            $threshold = if ($null -ne $entry.threshold) { '{0:0.00}' -f [double]$entry.threshold } else { '' }
            $transcript = if (-not [string]::IsNullOrWhiteSpace([string]$entry.transcriptPath)) { ConvertTo-MarkdownCell ([string]$entry.transcriptPath) } else { '' }
            [void]$builder.AppendLine("| $(ConvertTo-MarkdownCell ([string]$entry.plugin)) | $(ConvertTo-MarkdownCell ([string]$entry.case)) | $($entry.outcome) | $score | $threshold | $transcript |")
        }
        [void]$builder.AppendLine()
        [void]$builder.AppendLine('### Judge Rationale')
        [void]$builder.AppendLine()
        foreach ($entry in $llm) {
            [void]$builder.AppendLine("- **$(ConvertTo-MarkdownCell ([string]$entry.plugin)) / $(ConvertTo-MarkdownCell ([string]$entry.case))** ($($entry.outcome)): $(ConvertTo-MarkdownCell ([string]$entry.message))")
        }
        [void]$builder.AppendLine()
    }

    return $builder.ToString()
}

function Invoke-SkalaryEvalRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [string]$OutputRoot,
        [string]$PluginsRoot,
        [string]$RequiredListPath,
        [string]$Plugin,
        [bool]$FullRepository
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $repoRootPath = [System.IO.Path]::GetFullPath($RepoRoot)
    try {
        [void](Resolve-ConfinedEvalPath -Root $repoRootPath -Path $repoRootPath -Label 'Repository root' -Directory)
        if ($FullRepository -and -not [string]::IsNullOrWhiteSpace($Plugin)) {
            throw 'Choose -Plugin or -FullRepository, not both.'
        }
        if (-not $FullRepository -and [string]::IsNullOrWhiteSpace($Plugin)) {
            throw 'Structural evals require an explicit -Plugin. Use -FullRepository only for a direct broad run.'
        }
        if (-not [string]::IsNullOrWhiteSpace($Plugin) -and $Plugin -cnotmatch '^[a-z0-9][a-z0-9-]*$') {
            throw "Plugin must be a lowercase plugin directory name: '$Plugin'."
        }
        $pluginsRoot = Resolve-ConfinedEvalPath -Root $repoRootPath `
            -Path $(if ($PluginsRoot) { $PluginsRoot } else { 'plugins' }) -Label 'Plugins root' -Directory
        $outputRootPath = Resolve-ConfinedEvalPath -Root $repoRootPath `
            -Path $(if ($OutputRoot) { $OutputRoot } else { 'tests/evals/output' }) `
            -Label 'Eval output root' -AllowMissing -Directory
        $requiredPath = if ($FullRepository) {
            Resolve-ConfinedEvalPath -Root $repoRootPath `
                -Path $(if ($RequiredListPath) { $RequiredListPath } else { 'tools/structural-eval-required.md' }) `
                -Label 'Required structural-eval list'
        }
        else {
            $null
        }
        if ($Plugin) {
            $pluginRoot = Resolve-ConfinedEvalPath -Root $pluginsRoot -Path $Plugin -Label 'Selected plugin' -Directory
        }
    }
    catch {
        Write-Host "FocusedScopeRequired: $($_.Exception.Message)" -ForegroundColor Red
        exit 12
    }

    $evalTestFiles = @(
        if ($Plugin) {
            Get-ChildItem -LiteralPath $pluginRoot -Recurse -File -Filter '*.Tests.ps1' |
                Where-Object { $_.FullName -match '[\\/]evals[\\/]' } |
                Sort-Object FullName
        }
        else {
            Get-ChildItem -LiteralPath $pluginsRoot -Recurse -File -Filter '*.Tests.ps1' |
                Where-Object { $_.FullName -match '[\\/]evals[\\/]' } |
                Sort-Object FullName
        }
    )
    if ($Plugin -and $evalTestFiles.Count -eq 0) {
        Write-Host "FocusedScopeRequired: selected plugin '$Plugin' has no structural eval tests." -ForegroundColor Red
        exit 12
    }
    foreach ($file in $evalTestFiles) {
        try {
            [void](Resolve-ConfinedEvalPath -Root $repoRootPath -Path $file.FullName -Label 'Structural eval test')
        }
        catch {
            Write-Host "FocusedScopeRequired: $($_.Exception.Message)" -ForegroundColor Red
            exit 12
        }
    }

    $runStamp = (Get-Date).ToString('yyyy-MM-dd_HH-mm-ss')
    $runDir = Join-Path $outputRootPath $runStamp
    if (Test-Path -LiteralPath $runDir) {
        $runDir = Join-Path $outputRootPath ($runStamp + '-' + (Get-Date).ToString('fff'))
    }
    [void](New-Item -ItemType Directory -Path $runDir -Force)
    $reportPath = Join-Path $runDir 'report.json'
    $reportMdPath = Join-Path $runDir 'report.md'

    $entries = [System.Collections.Generic.List[object]]::new()
    $testResult = $null

    if ($evalTestFiles.Count -gt 0) {
        if (-not (Get-Command Invoke-Pester -ErrorAction SilentlyContinue)) {
            throw 'Pester is required to run eval tests. Install Pester and rerun.'
        }

        $testResult = Invoke-Pester -Path $evalTestFiles.FullName -PassThru
        foreach ($entry in @(Get-StructuralEvalEntryList -PesterResult $testResult)) {
            $entries.Add($entry)
        }
    }
    else {
        Write-Host 'No structural eval tests found under plugins/*/evals/**/*.Tests.ps1.' -ForegroundColor Yellow
    }

    $entryArray = @($entries)
    $requiredCaseIds = @()
    $requiredFailures = [System.Collections.Generic.List[string]]::new()
    if ($FullRepository -and (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        $requiredLines = @(Get-Content -LiteralPath $requiredPath)
        $requiredCaseIds = @($requiredLines | ForEach-Object {
                if ($_ -match '^- `(eval:[A-Za-z0-9][A-Za-z0-9_.-]*)`$') {
                    $Matches[1]
                }
            })
        $invalidEntries = @($requiredLines | Where-Object {
                $_ -match '^\s*-\s+' -and $_ -notmatch '^- `eval:[A-Za-z0-9][A-Za-z0-9_.-]*`$'
            })
        if ($invalidEntries.Count -gt 0) {
            $requiredFailures.Add('required structural-eval list contains an invalid entry')
        }
        if ($requiredCaseIds.Count -eq 0 -or @($requiredCaseIds | Sort-Object -Unique).Count -ne $requiredCaseIds.Count) {
            $requiredFailures.Add('required structural-eval case ids must be non-empty and unique')
        }
        foreach ($caseId in $requiredCaseIds) {
            $matches = @($entryArray | Where-Object {
                    [regex]::IsMatch([string]$_.case, "(?:^|\.)$([regex]::Escape($caseId))(?:\s|$)")
                })
            if ($matches.Count -ne 1) {
                $requiredFailures.Add("required structural eval '$caseId' executed $($matches.Count) times")
                continue
            }
            if ([string]$matches[0].outcome -ne 'pass') {
                $requiredFailures.Add("required structural eval '$caseId' completed as '$($matches[0].outcome)'")
            }
        }
    }
    elseif ($FullRepository) {
        $requiredFailures.Add("required structural-eval list is missing: $requiredPath")
    }

    $failedContainers = 0
    if ($null -ne $testResult -and
        (@($testResult.PSObject.Properties.Name) -contains 'FailedContainersCount')) {
        $failedContainers = [int]$testResult.FailedContainersCount
    }
    if ($FullRepository -and $failedContainers -gt 0) {
        $requiredFailures.Add("$failedContainers structural eval file(s) failed to load")
    }

    $summary = [ordered]@{
        total = $entryArray.Count
        pass = Get-OutcomeCount -Entries $entryArray -Outcome 'pass'
        fail = Get-OutcomeCount -Entries $entryArray -Outcome 'fail'
        skip = Get-OutcomeCount -Entries $entryArray -Outcome 'skip'
        error = (Get-OutcomeCount -Entries $entryArray -Outcome 'error') + $failedContainers
    }

    $report = [ordered]@{
        generatedAt = (Get-Date).ToString('o')
        summary = $summary
        requiredCases = [ordered]@{
            expected = @($requiredCaseIds)
            failures = @($requiredFailures)
        }
        entries = $entryArray
    }

    $reportJson = ($report | ConvertTo-Json -Depth 20)
    Set-Content -LiteralPath $reportPath -Value ($reportJson + "`n") -Encoding utf8
    Set-Content -LiteralPath $reportMdPath -Value (ConvertTo-EvalMarkdownReport -Report $report) -Encoding utf8

    Write-Host 'Eval summary:' -ForegroundColor Cyan
    Write-Host "  total: $($summary.total)"
    Write-Host "  pass:  $($summary.pass)" -ForegroundColor Green
    Write-Host "  fail:  $($summary.fail)" -ForegroundColor Red
    Write-Host "  skip:  $($summary.skip)" -ForegroundColor Yellow
    Write-Host "  error: $($summary.error)" -ForegroundColor Red
    Write-Host "  required: $($requiredCaseIds.Count - $requiredFailures.Count)/$($requiredCaseIds.Count)"
    Write-Host "  run dir: $runDir"
    Write-Host "  report:  $reportPath"
    Write-Host "  summary: $reportMdPath"

    if ($summary.fail -gt 0 -or $summary.error -gt 0 -or $requiredFailures.Count -gt 0) {
        foreach ($failure in $requiredFailures) { Write-Host "  required failure: $failure" -ForegroundColor Red }
        exit 1
    }

    # The focused selection has the same zero-assertion hole as the unit runner: eval files that
    # load but declare nothing, or files that never load at all, leave a clean zero-failure summary
    # that would otherwise be reported as a passing plugin gate. The report is written first so the
    # operator still gets the artifacts that name what was selected.
    if (-not $FullRepository) {
        if ($failedContainers -gt 0) {
            Write-Host "NoEvalsDiscovered: $failedContainers structural eval file(s) for plugin '$Plugin' failed to load, so their cases never ran." -ForegroundColor Red
            exit 3
        }
        if ($entryArray.Count -eq 0) {
            Write-Host "NoEvalsDiscovered: plugin '$Plugin' discovered 0 structural eval case(s). A run that asserts nothing is not a pass." -ForegroundColor Red
            exit 3
        }
    }

    exit 0
}

# Script mode is the supervised child: one bound request arrives on stdin, and the same body
# the public command dot-sources runs it. There is no other input path and no re-dispatch.
if ($MyInvocation.InvocationName -ne '.') {
    $supervision = & ([System.IO.Path]::Combine($PSScriptRoot, 'FocusedSupervision.ps1'))
    $request = & $supervision.ReadBodyRequest
    Invoke-SkalaryEvalRun @request
    exit 0
}
