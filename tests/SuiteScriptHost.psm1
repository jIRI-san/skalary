#requires -Version 7.0
<#
.SYNOPSIS
    Runs a repo script under test in a fresh PowerShell runspace instead of a child process.
.DESCRIPTION
    Most cases that invoke a script under test spawn `pwsh -NoProfile -File`, then assert on
    its exit code and merged output. The isolation those cases need is a clean session — no
    leaked variables, functions or preferences from the test host — and a runspace gives
    exactly that for roughly a twentieth of the cost: process startup dominated the files
    that call a script once or twice per case.

    What a runspace does *not* give is a separate OS process. Cases that need one — real
    concurrency, a crash, a process-wide setting — must keep spawning; this module is for
    the ones that were only paying for startup.

    The contract deliberately mirrors `pwsh -File`:
      - `ExitCode` is what the script passed to `exit`, or 1 when it terminated on an
        unhandled error, or 0 when it fell off the end.
      - `Output` is every stream merged in emission order, which is what a caller reading
        `2>&1` off a child process already had.

    One thing a runspace cannot reproduce is the *boundary* a process gives `$LASTEXITCODE`.
    `exit N` inside a called script and a native command that returned N write the same
    variable, and control returns to this host either way — so a script that shells out to a
    failing `git` and then falls off the end would be reported as that git failure, where
    `pwsh -File` reports 0. Rather than report a code it cannot vouch for, the module refuses
    a script whose last top-level statement is not `exit`: with a terminal `exit`, the value
    read back is the one the script chose. Assert-SuiteScriptExits states that as a loud
    precondition, so the next file to adopt this helper finds out at the first call instead
    of through a vacuous `Should -Not -Be 0`.
#>

Set-StrictMode -Version Latest

# Reused across invocations: building the session state is the part worth caching, while
# the runspace itself must be fresh for every call or the isolation is the thing lost.
$script:SessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()

# Scripts whose terminal `exit` has already been verified. The check is a parse, so it is
# paid once per script rather than once per case.
$script:ExitCheckedScripts = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

# Runs the script and lets `exit` set $LASTEXITCODE the way it does under `pwsh -File`.
# An unhandled terminating error is written out and mapped to 1, because that is what a
# child process would have reported and what the callers assert on.
$script:HostScript = @'
param($ScriptPath, $BoundParams)

$global:LASTEXITCODE = 0
try {
    & $ScriptPath @BoundParams *>&1 | ForEach-Object { "$_" }
}
catch {
    "$_"
    $global:LASTEXITCODE = 1
}
'@

function Assert-SuiteScriptExits {
    <#
    .SYNOPSIS
        Throws unless $ScriptPath's last top-level statement is an `exit`.
    .DESCRIPTION
        A runspace has no process boundary to reset `$LASTEXITCODE` at, so the code read
        back after the script is only trustworthy when the script itself set it. A terminal
        `exit` guarantees that for every path that reaches the end of the file; without one,
        a leftover native exit code would be reported as the script's own.

        Cached per resolved path: the AST is parsed once per suite run, not per case.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath
    )

    $resolved = (Resolve-Path -LiteralPath $ScriptPath).Path
    if ($script:ExitCheckedScripts.Contains($resolved)) { return }

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($resolved, [ref]$tokens, [ref]$errors)
    if ($errors -and @($errors).Count -gt 0) {
        throw "Script under test does not parse: '$resolved' ($(@($errors)[0].Message))."
    }

    $statements = @($ast.EndBlock.Statements)
    if ($statements.Count -eq 0 -or -not ($statements[-1] -is [System.Management.Automation.Language.ExitStatementAst])) {
        throw "Invoke-SuiteScript cannot report a trustworthy exit code for '$resolved': its last top-level statement is not 'exit', so a native command's exit code would be read as the script's own. Spawn a child process for this script, or give it a terminal exit."
    }

    [void]$script:ExitCheckedScripts.Add($resolved)
}

function Invoke-SuiteScript {
    <#
    .SYNOPSIS
        Invokes $ScriptPath in a fresh runspace and returns its exit code and merged output.
    .PARAMETER Parameters
        Bound by name, so a caller cannot smuggle a parameter past the script's own
        validation the way a hand-built argument array can.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath,

        [hashtable]$Parameters = @{}
    )

    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        throw "Script under test not found: '$ScriptPath'."
    }

    Assert-SuiteScriptExits -ScriptPath $ScriptPath

    $shell = [powershell]::Create($script:SessionState)
    try {
        $shell.Runspace.SessionStateProxy.SetVariable('LASTEXITCODE', 0)
        [void]$shell.AddScript($script:HostScript).AddArgument($ScriptPath).AddArgument($Parameters)

        $lines = @($shell.Invoke())

        # A terminating error that escaped the wrapper leaves the pipeline Failed with the
        # record here rather than in the output, so it is folded in instead of dropped.
        $failure = $shell.InvocationStateInfo.Reason
        $exitCode = [int]$shell.Runspace.SessionStateProxy.GetVariable('LASTEXITCODE')
        if ($failure) {
            $lines += "$failure"
            $exitCode = 1
        }

        return [pscustomobject]@{
            ExitCode = $exitCode
            Output = (@($lines | ForEach-Object { "$_" }) -join "`n")
        }
    }
    finally {
        $shell.Dispose()
    }
}

Export-ModuleMember -Function Invoke-SuiteScript, Assert-SuiteScriptExits
