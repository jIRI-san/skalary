#requires -Version 7.0
<#
.SYNOPSIS
    Runs deterministic structural evals for one explicitly selected plugin.
.DESCRIPTION
    Routine use requires -Plugin and always runs that plugin's eval files in a supervised
    child process executing the private body `internal/Invoke-EvalRun.ps1`: the run targets
    less than 30 seconds, warns after a 30-60 second completion, and has its owned process
    group terminated at 60 seconds. No parameter, variable or environment value selects an
    unsupervised focused run, and no step of the focused dispatch is reachable by
    command-name resolution. The direct operator-only -FullRepository route runs in this
    process and retains the global required-ID checks.

    Exit codes:
      0  the selected structural evals ran and passed
      1  a selected structural eval failed, errored, or a required case did not pass
      3  NoEvalsDiscovered — the selected plugin asserted nothing
     12  FocusedScopeRequired — the selection was not a single confined plugin or -FullRepository
     13  FocusedTimeout — the supervised run exceeded the focused timeout and its owned
            process group was terminated
     14  FocusedContainmentUnavailable — descendant ownership could not be established, so the
            supervisor refused to start the work
.EXAMPLE
    pwsh -NoProfile -File scripts/skalary/Test-Evals.ps1 -Plugin code-review
.EXAMPLE
    pwsh -NoProfile -File scripts/skalary/Test-Evals.ps1 -FullRepository
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, '..', '..')),
    [string]$OutputRoot,
    [string]$PluginsRoot,
    [string]$RequiredContractPath,
    [string]$Plugin,
    [switch]$FullRepository,
    [ValidateRange(0.05, 30)]
    [double]$FocusedWarningSeconds = 30,
    [ValidateRange(0.1, 60)]
    [double]$FocusedTimeoutSeconds = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The only check that stays here: a warning threshold at or past the timeout would make the
# supervisor unable to distinguish a slow run from a killed one, and no child can report that.
# Focused dispatch below resolves no command by name: an alias or function in the calling
# session cannot redirect the body path, the request, or the supervisor.
if ($FocusedWarningSeconds -ge $FocusedTimeoutSeconds) {
    [System.Console]::Out.WriteLine('FocusedScopeRequired: focused warning threshold must be lower than the focused timeout.')
    exit 12
}

$evalBody = [System.IO.Path]::Combine($PSScriptRoot, 'internal', 'Invoke-EvalRun.ps1')

$request = @{
    RepoRoot = $RepoRoot
    FullRepository = [bool]$FullRepository
}
if ($OutputRoot) { $request.OutputRoot = $OutputRoot }
if ($PluginsRoot) { $request.PluginsRoot = $PluginsRoot }
if ($RequiredContractPath) { $request.RequiredContractPath = $RequiredContractPath }
if ($Plugin) { $request.Plugin = $Plugin }

# Direct broad runs stay in this process. Everything else is focused and enters the supervisor:
# nothing a caller can pass reaches the branch below, so no caller can select the unsupervised
# path for a focused run.
if ($FullRepository) {
    . $evalBody
    Invoke-SkalaryEvalRun @request
    exit 0
}

$supervision = & ([System.IO.Path]::Combine($PSScriptRoot, 'internal', 'FocusedSupervision.ps1'))
exit (& $supervision.InvokeSupervisedBody -BodyPath $evalBody -Request $request `
        -Label 'selected structural eval' -WarningSeconds $FocusedWarningSeconds `
        -TimeoutSeconds $FocusedTimeoutSeconds)
