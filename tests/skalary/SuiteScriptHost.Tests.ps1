#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The runspace host replaces a child `pwsh -File` for most cases that invoke a script under
# test (plan 768d7b step 3.2). Everything those cases assert on — the exit code and the
# merged output — now comes from here, so the substitution is only safe while these hold.
Describe 'suite script host' {
    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '..' 'SuiteScriptHost.psm1') -Force -DisableNameChecking

        $script:scriptRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("suite-script-host-" + [Guid]::NewGuid().ToString('n'))
        [void](New-Item -ItemType Directory -Path $script:scriptRoot -Force)

        function Script:New-ScriptUnderTest {
            param(
                [Parameter(Mandatory)][string]$Name,
                [Parameter(Mandatory)][string]$Body
            )

            $path = Join-Path $script:scriptRoot "$Name.ps1"
            Set-Content -LiteralPath $path -Value $Body -Encoding utf8NoBOM
            return $path
        }
    }

    AfterAll {
        if (Test-Path -LiteralPath $script:scriptRoot) {
            Remove-Item -LiteralPath $script:scriptRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:SuiteScriptHost.ReportsTheExitCodeTheScriptChose' {
        $path = Script:New-ScriptUnderTest -Name 'exits-three' -Body @'
param([int]$Code = 3)
Write-Output 'before exit'
exit $Code
'@

        $result = Invoke-SuiteScript -ScriptPath $path -Parameters @{ Code = 3 }
        $result.ExitCode | Should -Be 3
        $result.Output | Should -Match 'before exit'

        # Parameters are bound by name, so the same script reports a different code without
        # a hand-built argument array.
        (Invoke-SuiteScript -ScriptPath $path -Parameters @{ Code = 0 }).ExitCode | Should -Be 0
    }

    It 'test:SuiteScriptHost.MergesEveryStreamTheCallerUsedToReadOffStderr' {
        # A caller reading `2>&1` off a child process saw host, warning and error output in
        # one string. A case that asserted on a warning would pass vacuously if any of these
        # stopped being captured.
        $path = Script:New-ScriptUnderTest -Name 'writes-streams' -Body @'
Write-Host 'host line'
Write-Warning 'warning line'
Write-Error 'error line' -ErrorAction Continue
Write-Output 'output line'
exit 0
'@

        $result = Invoke-SuiteScript -ScriptPath $path
        $result.ExitCode | Should -Be 0
        foreach ($expected in @('host line', 'warning line', 'error line', 'output line')) {
            $result.Output | Should -Match ([regex]::Escape($expected))
        }
    }

    It 'test:SuiteScriptHost.UnhandledErrorIsReportedAsExitOne' {
        # `pwsh -File` exits 1 on an unhandled terminating error; the cases that assert
        # `ExitCode | Should -Not -Be 0` on a rejected input depend on that mapping.
        $path = Script:New-ScriptUnderTest -Name 'throws' -Body @'
$ErrorActionPreference = 'Stop'
throw 'rejected input'
exit 0
'@

        $result = Invoke-SuiteScript -ScriptPath $path
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'rejected input'
    }

    It 'test:SuiteScriptHost.RefusesAScriptWhoseExitCodeItCannotVouchFor' {
        # A runspace has no process boundary resetting $LASTEXITCODE, so a script that ends
        # after a failing native command would be reported as that command's failure. The
        # refusal is the point: reporting a code it cannot vouch for is what would turn an
        # `ExitCode | Should -Not -Be 0` assertion into a vacuous pass.
        $path = Script:New-ScriptUnderTest -Name 'no-terminal-exit' -Body @'
Write-Output 'ran'
& git rev-parse --definitely-not-a-ref 2>$null
'@

        { Invoke-SuiteScript -ScriptPath $path } |
            Should -Throw -ExpectedMessage '*last top-level statement is not*'
    }

    It 'test:SuiteScriptHost.LeavesNoStateBehindForTheNextCase' {
        # The isolation the replaced child process provided: a variable or function defined
        # by one invocation must not be visible to the next.
        $writer = Script:New-ScriptUnderTest -Name 'defines-globals' -Body @'
$global:SuiteScriptHostProbe = 'leaked'
function global:Get-SuiteScriptHostProbe { 'leaked' }
exit 0
'@
        $reader = Script:New-ScriptUnderTest -Name 'reads-globals' -Body @'
$value = Get-Variable -Name 'SuiteScriptHostProbe' -Scope Global -ErrorAction SilentlyContinue
Write-Output ("variable:" + $(if ($value) { 'present' } else { 'absent' }))
$command = Get-Command -Name 'Get-SuiteScriptHostProbe' -ErrorAction SilentlyContinue
Write-Output ("command:" + $(if ($command) { 'present' } else { 'absent' }))
exit 0
'@

        (Invoke-SuiteScript -ScriptPath $writer).ExitCode | Should -Be 0

        $result = Invoke-SuiteScript -ScriptPath $reader
        $result.Output | Should -Match 'variable:absent'
        $result.Output | Should -Match 'command:absent'
    }
}
