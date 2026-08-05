#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'run unit tests' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:runner = Join-Path $script:repoRoot 'scripts/skalary/Run-UnitTests.ps1'
        $script:sandboxes = [System.Collections.Generic.List[string]]::new()

        # A sandbox repo root, so the runner is exercised against a tests tree this file
        # controls rather than against the suite it is currently running inside.
        function New-RunnerSandbox {
            [CmdletBinding()]
            [OutputType([string])]
            param([string]$TestFileContent)

            $root = Join-Path ([System.IO.Path]::GetTempPath()) ('run-unit-tests-' + [System.Guid]::NewGuid().ToString('N'))
            if (Test-Path -LiteralPath $root) {
                throw "Refusing to reuse an existing sandbox root: '$root'."
            }

            [void](New-Item -ItemType Directory -Path $root)
            $script:sandboxes.Add($root)
            [void](New-Item -ItemType Directory -Path (Join-Path $root 'tests'))
            [void](New-Item -ItemType Directory -Path (Join-Path $root 'emptymodules'))

            # The runner enforces a runtime budget and treats a missing one as a failure, so a
            # sandbox exercising the Pester-presence branches has to carry a budget it fits
            # inside — otherwise every case here would pass on the budget verdict instead.
            [void](New-Item -ItemType Directory -Path (Join-Path $root 'tools'))
            Set-Content -LiteralPath (Join-Path $root 'tools/suite-budget.psd1') -Encoding utf8 -Value @'
@{
    Schema = 'skalary/suite-budget@2'
    MeasuredCommand = 'npm test'
    MeasuredLegs = @('validate-plan', 'test:unit', 'validate.ps1')
    BoundCeilingSeconds = 600
    AbsoluteCapSeconds = 900
    MaxCeilingRaises = 1
    Platforms = @{
        Linux = @{ HardCeilingSeconds = 600; TargetSeconds = 480; CeilingRaises = @() }
        Windows = @{ HardCeilingSeconds = 600; TargetSeconds = 480; CeilingRaises = @() }
        MacOS = @{ HardCeilingSeconds = 600; TargetSeconds = 480; CeilingRaises = @() }
    }
}
'@

            if ($TestFileContent) {
                Set-Content -LiteralPath (Join-Path $root 'tests/Sandbox.Tests.ps1') -Value $TestFileContent -Encoding utf8
            }

            return (Resolve-Path -LiteralPath $root).Path
        }

        # The runner runs in a child process: it owns its exit code, and hiding Pester from it
        # means overriding PSModulePath inside that process — PowerShell re-adds the default
        # module paths to an inherited one, so an environment override alone proves nothing.
        function Invoke-Runner {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [string]$SandboxRoot,

                [string]$ModulePath
            )

            $lines = [System.Collections.Generic.List[string]]::new()
            # Plain text, not because it reads better: a captured escape sequence is written
            # into the NUnit report when a case fails, and 0x1B is not valid XML — the whole
            # report is lost at the moment it is needed.
            $lines.Add('$PSStyle.OutputRendering = ''PlainText''')
            if ($ModulePath) { $lines.Add("`$env:PSModulePath = '$ModulePath'") }
            $lines.Add("& '$script:runner' -RepoRoot '$SandboxRoot'")
            $lines.Add('exit $LASTEXITCODE')

            $driver = Join-Path $SandboxRoot 'driver.ps1'
            Set-Content -LiteralPath $driver -Value ($lines -join [System.Environment]::NewLine) -Encoding utf8

            # The child inherits this location, so Pester's NUnit output lands in the sandbox
            # instead of overwriting the real suite's.
            Push-Location -LiteralPath $SandboxRoot
            $previousPreference = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            try {
                $output = & pwsh -NoProfile -File $driver 2>&1
                $exitCode = $LASTEXITCODE
            }
            finally {
                $ErrorActionPreference = $previousPreference
                Pop-Location
            }

            return [pscustomobject]@{
                ExitCode = $exitCode
                Output   = (($output | Out-String) -replace '\x1b\[[0-9;]*[a-zA-Z]', '' -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', '')
            }
        }

        $script:passingTestFile = @'
Describe 'sandbox' {
    It 'passes' { $true | Should -BeTrue }
}
'@

        # Two failures, not one: Pester's own -CI exit is the failure count, so a two-failure
        # run is exactly what collides with a sentinel of 2.
        $script:failingTestFile = @'
Describe 'sandbox' {
    It 'fails once' { $false | Should -BeTrue }
    It 'fails twice' { $false | Should -BeTrue }
}
'@

        # A discoverable file that declares no test: Pester returns a clean zero-failure
        # result for it, which is the shape that used to be reported as a pass.
        $script:noTestsFile = @'
Describe 'sandbox' {
}
'@

        # Unbalanced brace: the file fails to parse during discovery, so Pester counts it as a
        # failed container and none of its tests exist to be counted anywhere else.
        $script:undiscoverableTestFile = @'
Describe 'sandbox' {
    It 'never loads' { $true | Should -BeTrue }
'@
    }

    AfterAll {
        foreach ($sandbox in $script:sandboxes) {
            if (Test-Path -LiteralPath $sandbox -PathType Container) {
                Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'test:RunUnitTests.MissingPesterExitsNonZero fails and names the install command when Pester is absent' {
        # REQ-5: the old runner exited 0 with a warning, so `npm test` reported success on a
        # host that had executed zero assertions — and this script is the `test:unit` evidence
        # executor, so that green was indistinguishable from a real one.
        $sandbox = New-RunnerSandbox -TestFileContent $script:passingTestFile

        # Control: the same sandbox is green when Pester is reachable. Without it, a broken
        # sandbox would satisfy the failure assertion for entirely the wrong reason.
        $withPester = Invoke-Runner -SandboxRoot $sandbox
        $withPester.ExitCode | Should -Be 0 -Because "the sandbox passes when Pester is present: $($withPester.Output)"

        $withoutPester = Invoke-Runner -SandboxRoot $sandbox -ModulePath (Join-Path $sandbox 'emptymodules')
        $withoutPester.ExitCode |
            Should -Not -Be 0 -Because "a runner that cannot find its framework must fail: $($withoutPester.Output)"
        $withoutPester.Output | Should -Match 'PesterNotInstalled'
        # RISK-3: failing loudly is only acceptable if the message carries the way out.
        $withoutPester.Output |
            Should -Match ([regex]::Escape('Install-Module Pester -Scope CurrentUser -Force')) -Because 'the message names the install command'

        # "Could not test" has to stay distinguishable from "tested and failed", or the
        # non-zero exit says nothing about whether anything ran.
        $failingSandbox = New-RunnerSandbox -TestFileContent $script:failingTestFile
        $failed = Invoke-Runner -SandboxRoot $failingSandbox
        $failed.ExitCode | Should -Be 1 -Because "a run with failures reports one failed run, not its failure count: $($failed.Output)"
        $failed.ExitCode |
            Should -Not -Be $withoutPester.ExitCode -Because 'a runner that never ran must not report the same code as one that ran and failed'
    }

    It 'test:RunUnitTests.ZeroTestsDiscoveredFails fails when Pester is present but discovers nothing' {
        # REQ-5: the louder half of the same hole. Pester returns a clean zero-failure result
        # for a tests tree that discovers nothing, so the runner reported a pass having
        # asserted nothing — and it is the `test:` evidence executor, so that pass was
        # indistinguishable from a suite that actually ran.
        $emptyFile = New-RunnerSandbox -TestFileContent $script:noTestsFile
        $discoveredNothing = Invoke-Runner -SandboxRoot $emptyFile
        $discoveredNothing.ExitCode |
            Should -Not -Be 0 -Because "a test file that declares no test asserts nothing: $($discoveredNothing.Output)"
        $discoveredNothing.Output | Should -Match 'NoTestsDiscovered'

        # The other shape of the same condition: nothing to discover in the first place. Pester
        # throws here rather than returning a result, so it needs its own answer.
        $noFiles = New-RunnerSandbox
        $nothingToDiscover = Invoke-Runner -SandboxRoot $noFiles
        $nothingToDiscover.ExitCode |
            Should -Not -Be 0 -Because "an empty tests tree asserts nothing: $($nothingToDiscover.Output)"
        $nothingToDiscover.Output | Should -Match 'NoTestsDiscovered'

        # Both must stay separable from a run that did test and failed, or the exit code stops
        # carrying the distinction the requirement exists to make.
        $failing = New-RunnerSandbox -TestFileContent $script:failingTestFile
        $ran = Invoke-Runner -SandboxRoot $failing
        $ran.ExitCode | Should -Be 1 -Because "a run that discovered and failed tests reports a failed run: $($ran.Output)"
        $discoveredNothing.ExitCode | Should -Not -Be $ran.ExitCode
        $nothingToDiscover.ExitCode | Should -Not -Be $ran.ExitCode
    }

    It 'test:RunUnitTests.UndiscoverableTestFileFails fails when a test file never loads, even beside files that did' {
        # A file that throws during discovery contributes nothing to FailedCount or TotalCount
        # — Pester counts it separately — so a whole file can silently not run while the suite
        # reports a pass. That includes this file, which would take the REQ-5 gate down with it.
        $sandbox = New-RunnerSandbox -TestFileContent $script:passingTestFile
        Set-Content -LiteralPath (Join-Path $sandbox 'tests/Undiscoverable.Tests.ps1') -Value $script:undiscoverableTestFile -Encoding utf8

        $result = Invoke-Runner -SandboxRoot $sandbox
        $result.ExitCode |
            Should -Not -Be 0 -Because "a file that never loaded is a gate that never ran: $($result.Output)"
        $result.Output | Should -Match 'TestFilesNotDiscoverable'
        $result.Output |
            Should -Match 'Undiscoverable\.Tests\.ps1' -Because 'the file that did not load has to be nameable from the output'
    }
}
