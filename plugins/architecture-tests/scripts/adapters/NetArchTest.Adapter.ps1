#requires -Version 7.0
<#
.SYNOPSIS
NetArchTest (C#) deterministic adapter (REQ-9). Runs a human-owned, reviewed NetArchTest test project via
`dotnet test` and parses its TRX result into the strict adapter result contract.

.DESCRIPTION
Only reached for a locked contract whose body hash the dispatcher already verified. Never derives, compiles,
or generates test code from a contract — it runs the reviewed test PROJECT the human owns. When the dotnet
toolchain is absent it returns skip-absent-toolchain (never a false pass, never a hard fail). Real execution
is opt-in (needs a committed fixture; delivered in step 4.3); structural validation never shells dotnet.

Entrypoint: Invoke-NetArchTestAdapter -Context @{ ContractId; TargetRoot; RepoRoot; BodyPaths }.
BodyPaths[0] is the reviewed test project (csproj/dir). TargetRoot is the source root under test.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-NetArchTestCommand {
    <#
    .SYNOPSIS
    Deterministic `dotnet test` command line for a NetArchTest project. Pure string construction (testable
    without a toolchain).
    #>
    param(
        [Parameter(Mandatory)][string]$TestProject,
        [Parameter(Mandatory)][string]$TrxPath
    )
    return @(
        'test'
        $TestProject
        '--nologo'
        '--logger'
        "trx;LogFileName=$TrxPath"
    )
}

function ConvertFrom-NetArchTestTrx {
    <#
    .SYNOPSIS
    Parses a VSTest TRX document into the strict result contract { status; ran; findings[]; artifacts[] }.

    .DESCRIPTION
    Maps per-test TRX outcomes to the adapter taxonomy with a PASSING ALLOW-LIST (never a default-green):
      all tests 'Passed', >=1 test  -> 'pass'
      any test 'Failed'              -> 'fail' (findings carry test name + message)
      any other terminal outcome     -> 'error' (Error/Timeout/Aborted/NotExecuted/Inconclusive/... are NOT a pass)
      zero tests                     -> 'error' (a locked run that executed nothing is not a green)
    Accepts either a TRX file path (-Path) or raw TRX xml (-Xml). ran=$true because a TRX means tests executed.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Path')][string]$Path,
        [Parameter(Mandatory, ParameterSetName = 'Xml')][string]$Xml
    )

    [xml]$doc = if ($PSCmdlet.ParameterSetName -eq 'Path') { Get-Content -LiteralPath $Path -Raw } else { $Xml }

    $ns = [System.Xml.XmlNamespaceManager]::new($doc.NameTable)
    $ns.AddNamespace('t', 'http://microsoft.com/schemas/VisualStudio/TeamTest/2010')

    $results = @($doc.SelectNodes('//t:Results/t:UnitTestResult', $ns))
    $findings = [System.Collections.Generic.List[object]]::new()
    $failed = 0
    $passed = 0
    $other = 0

    foreach ($r in $results) {
        # StrictMode-safe attribute access: a missing @outcome is treated as a non-pass, never a green.
        $outcome = if ($r.Attributes -and $r.Attributes['outcome']) { [string]$r.Attributes['outcome'].Value } else { '' }
        $testName = if ($r.Attributes -and $r.Attributes['testName']) { [string]$r.Attributes['testName'].Value } else { '(unknown)' }

        if ($outcome -eq 'Passed') {
            $passed++
            continue
        }
        if ($outcome -eq 'Failed') {
            $failed++
            $msgNode = $r.SelectSingleNode('t:Output/t:ErrorInfo/t:Message', $ns)
            $msg = if ($msgNode) { $msgNode.InnerText } else { 'test failed' }
            $findings.Add([pscustomobject]@{
                    severity = 'error'
                    test     = $testName
                    message  = ($msg -replace '\s+', ' ').Trim()
                })
            continue
        }
        # Any other terminal outcome (Error/Timeout/Aborted/NotExecuted/Inconclusive/PassedButRunAborted/...).
        $other++
        $findings.Add([pscustomobject]@{
                severity = 'error'
                test     = $testName
                message  = "non-pass outcome: $outcome"
            })
    }

    $total = $results.Count
    # Passing allow-list: only ALL-passed with at least one test is a green. Failed -> fail; anything else -> error.
    $status = if ($total -gt 0 -and $passed -eq $total) { 'pass' }
    elseif ($failed -gt 0) { 'fail' }
    else { 'error' }
    if ($status -eq 'error' -and $total -eq 0) {
        $findings.Add([pscustomobject]@{ severity = 'error'; message = 'TRX contained zero test results' })
    }

    return [pscustomobject]@{
        status    = $status
        ran       = $true
        findings  = @($findings)
        artifacts = @()
    }
}

function Invoke-NetArchTestAdapter {
    param([Parameter(Mandatory)][hashtable]$Context)

    $bodyPaths = @($Context.BodyPaths)
    $testProject = if ($bodyPaths.Count -gt 0) { $bodyPaths[0] } else { $null }
    # Resolve the project path against RepoRoot so the executor and the lock gate agree on the body identity
    # regardless of the current working directory.
    $repoRoot = if ($Context.ContainsKey('RepoRoot') -and $Context.RepoRoot) { [string]$Context.RepoRoot } else { $null }
    if ($testProject -and $repoRoot -and -not [System.IO.Path]::IsPathRooted($testProject)) {
        $testProject = Join-Path $repoRoot $testProject
    }

    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{
            status    = 'skip-absent-toolchain'
            ran       = $false
            findings  = @([pscustomobject]@{ severity = 'info'; message = 'dotnet toolchain not present; NetArchTest run skipped' })
            artifacts = @()
        }
    }

    if ([string]::IsNullOrWhiteSpace($testProject) -or -not (Test-Path -LiteralPath $testProject)) {
        return [pscustomobject]@{
            status    = 'error'
            ran       = $false
            findings  = @([pscustomobject]@{ severity = 'error'; message = "NetArchTest test project not found: '$testProject'" })
            artifacts = @()
        }
    }

    $trxPath = Join-Path ([System.IO.Path]::GetTempPath()) ("netarchtest-$($Context.ContractId)-$([System.Guid]::NewGuid().ToString('N')).trx")
    $dotnetArgs = Get-NetArchTestCommand -TestProject $testProject -TrxPath $trxPath
    & dotnet @dotnetArgs 2>&1 | Out-Null

    if (-not (Test-Path -LiteralPath $trxPath)) {
        return [pscustomobject]@{
            status    = 'error'
            ran       = $false
            findings  = @([pscustomobject]@{ severity = 'error'; message = 'dotnet test produced no TRX result' })
            artifacts = @()
        }
    }

    $parsed = ConvertFrom-NetArchTestTrx -Path $trxPath
    return [pscustomobject]@{
        status    = $parsed.status
        ran       = $parsed.ran
        findings  = $parsed.findings
        artifacts = @($trxPath)
    }
}
