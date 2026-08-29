#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'run unit tests' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:runner = Join-Path $script:repoRoot 'scripts/skalary/Run-UnitTests.ps1'
        $script:fingerprintScript = Join-Path $script:repoRoot 'scripts/skalary/Get-SuiteInputFingerprint.ps1'
        $script:sandboxes = [System.Collections.Generic.List[string]]::new()
        . $script:fingerprintScript

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
            [void](New-Item -ItemType Directory -Path (Join-Path $root 'scripts/skalary') -Force)
            Copy-Item -LiteralPath $script:fingerprintScript `
                -Destination (Join-Path $root 'scripts/skalary/Get-SuiteInputFingerprint.ps1')
            Set-Content -LiteralPath (Join-Path $root 'tools/suite-budget.psd1') -Encoding utf8 -Value @'
@{
    Schema = 'skalary/suite-budget@2'
    MeasuredCommand = 'npm test'
    MeasuredLegs = @('validate-plan', 'test:unit', 'validate.ps1')
    MeasurementRecord = 'tools/suite-runtime.json'
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
            Set-Content -LiteralPath (Join-Path $root 'tools/suite-tier.psd1') -Encoding utf8NoBOM -Value @'
@{
    Schema = 'skalary/suite-tier@1'
    FastFocusedHardCeilingSeconds = 60
    SlowHardCeilingSeconds = 600
    CiSetupAllowanceSeconds = 60
    DedicatedFiles = @()
    SlowFiles = @()
}
'@

            if ($TestFileContent) {
                Set-Content -LiteralPath (Join-Path $root 'tests/Sandbox.Tests.ps1') -Value $TestFileContent -Encoding utf8
            }

            & git -C $root init --quiet
            & git -C $root add -- scripts tests tools/suite-budget.psd1
            $fingerprint = Get-SuiteInputFingerprint -RepoRoot $root
            $platform = if ($IsWindows) { 'Windows' } elseif ($IsMacOS) { 'MacOS' } else { 'Linux' }
            $runtime = [ordered]@{
                schema          = 'skalary/suite-runtime@2'
                measuredCommand = 'npm test'
                platforms       = [ordered]@{
                    $platform = [ordered]@{
                        schema              = 'skalary/suite-runtime-row@2'
                        platform            = $platform
                        measuredCommand     = 'npm test'
                        fingerprintProtocol = $fingerprint.Protocol
                        inputFingerprint    = $fingerprint.Fingerprint
                        seconds             = 1
                        succeeded           = $true
                        measuredAt          = '2026-08-10T00:00:00Z'
                        commit              = 'fixture'
                        source              = 'test'
                        note                = ''
                        environment         = [ordered]@{}
                    }
                }
            }
            Set-Content -LiteralPath (Join-Path $root 'tools/suite-runtime.json') `
                -Value (($runtime | ConvertTo-Json -Depth 10) + "`n") -Encoding utf8NoBOM
            & git -C $root add -- tools/suite-runtime.json

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

                [string]$ModulePath,

                [string[]]$ExtraArguments = @(),

                [switch]$ExactArguments
            )

            $lines = [System.Collections.Generic.List[string]]::new()
            # Plain text, not because it reads better: a captured escape sequence is written
            # into the NUnit report when a case fails, and 0x1B is not valid XML — the whole
            # report is lost at the moment it is needed.
            $lines.Add('$PSStyle.OutputRendering = ''PlainText''')
            $lines.Add('Remove-Item Env:SKALARY_SUITE_MEASUREMENT_TOKEN, Env:SKALARY_SUITE_MEASUREMENT_KEY -ErrorAction SilentlyContinue')
            if ($ModulePath) { $lines.Add("`$env:PSModulePath = '$ModulePath'") }
            $argumentText = $ExtraArguments -join ' '
            if (-not $ExactArguments -and
                $argumentText -notmatch '(?i)-(FullRepository|TestPath|StartBudgetClock)\b' -and
                $argumentText -notmatch '(?i)-Tier\s+(Slow|All)\b') {
                $ExtraArguments += '-FullRepository'
            }
            $extra = if ($ExtraArguments.Count -gt 0) { ' ' + ($ExtraArguments -join ' ') } else { '' }
            $lines.Add("& '$script:runner' -RepoRoot '$SandboxRoot'$extra")
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

        function Set-SandboxTier {
            param(
                [Parameter(Mandatory)]
                [string]$SandboxRoot,

                [Parameter(Mandatory)]
                [ValidateSet('Fast', 'Slow')]
                [string]$Tier,

                [string[]]$SlowFiles = @('tests/Sandbox.Tests.ps1')
            )

            if ($Tier -eq 'Slow') {
                $quotedPaths = @($SlowFiles | ForEach-Object { "        '$($_)'" }) -join [Environment]::NewLine
                @"
@{
    Schema = 'skalary/suite-tier@1'
    FastFocusedHardCeilingSeconds = 60
    SlowHardCeilingSeconds = 600
    CiSetupAllowanceSeconds = 60
    DedicatedFiles = @()
    SlowFiles = @(
$quotedPaths
    )
}
"@ | Set-Content -LiteralPath (Join-Path $SandboxRoot 'tools/suite-tier.psd1') -Encoding utf8NoBOM
            }

            return @('-Tier', $Tier)
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

        $script:skippedReviewEvidenceFile = @'
Describe 'skipped evidence' {
    It 'test:ReviewReport.MandatorySeam executes' {
        Set-ItResult -Skipped -Because 'seeded missing mandatory seam'
    }
}
'@

        # Unbalanced brace: the file fails to parse during discovery, so Pester counts it as a
        # failed container and none of its tests exist to be counted anywhere else.
        $script:undiscoverableTestFile = @'
Describe 'sandbox' {
    It 'never loads' { $true | Should -BeTrue }
'@

        # Passes while repointing HOME at a temp directory, which is what the eval tests did: the
        # suite is green and the caller's shell is the thing that broke.
        $script:environmentLeakingTestFile = @'
Describe 'sandbox' {
    It 'leaks HOME' {
        $env:HOME = (Join-Path $TestDrive 'home')
        $true | Should -BeTrue
    }
}
'@

        # Creating a variable that did not exist is the other half, and the half that is easy to miss
        # locally: on a developer box HOME and LOCALAPPDATA are already set, so only a clean
        # environment like CI's shows the difference between "unset" and "set to empty".
        $script:environmentCreatingTestFile = @'
Describe 'sandbox' {
    It 'creates a variable that was never set' {
        $env:SKALARY_LEAK_PROBE = ''
        $true | Should -BeTrue
    }
}
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

        $evidencePath = Join-Path $sandbox 'missing-pester-evidence.json'
        $withoutPesterEvidence = Invoke-Runner -SandboxRoot $sandbox `
            -ModulePath (Join-Path $sandbox 'emptymodules') -ExactArguments -ExtraArguments @(
                '-Tier Fast',
                "-TestPath 'tests/Sandbox.Tests.ps1'",
                "-EvidenceTestId 'RunUnitTests.MissingPester'",
                "-EvidenceResultPath '$evidencePath'"
            )
        $withoutPesterEvidence.ExitCode | Should -Be 2 -Because $withoutPesterEvidence.Output
        $evidence = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
        $evidence.results[0].status | Should -Be 'unrun'
        $evidence.results[0].message | Should -Match 'Pester is not installed'

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
        foreach ($tier in @('Fast', 'Slow')) {
            $emptyFile = New-RunnerSandbox -TestFileContent $script:noTestsFile
            $tierArgs = Set-SandboxTier -SandboxRoot $emptyFile -Tier $tier
            $discoveredNothing = Invoke-Runner -SandboxRoot $emptyFile -ExtraArguments $tierArgs
            $discoveredNothing.ExitCode |
                Should -Be 3 -Because "$tier must fail when a test file declares no test: $($discoveredNothing.Output)"
            $discoveredNothing.Output | Should -Match 'NoTestsDiscovered'
        }

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

    It 'test:RunUnitTests.RequiredReviewEvidenceSkippedFails exits 8 when a review-report evidence marker is skipped' {
        foreach ($tier in @('Fast', 'Slow')) {
            $sandbox = New-RunnerSandbox -TestFileContent $script:skippedReviewEvidenceFile
            $tierArgs = Set-SandboxTier -SandboxRoot $sandbox -Tier $tier
            $result = Invoke-Runner -SandboxRoot $sandbox -ExtraArguments $tierArgs

            $result.ExitCode | Should -Be 8 -Because "$tier must fail on skipped required evidence"
            $result.Output | Should -Match 'RequiredEvidenceSkipped'
            $result.Output | Should -Match 'test:ReviewReport\.MandatorySeam'
        }
    }

    It 'test:ReviewReport.ConsumerInstallDedicatedGate keeps the expensive matrix out of the budgeted unit suite and in blocking CI' {
        $runnerText = Get-Content -LiteralPath $script:runner -Raw
        $dedicated = Join-Path $script:repoRoot 'scripts/skalary/Test-ReviewConsumerInstall.ps1'
        $workflow = Get-Content -LiteralPath (Join-Path $script:repoRoot '.github/workflows/registry-ci.yml') -Raw
        $tiers = Import-PowerShellDataFile -LiteralPath (Join-Path $script:repoRoot 'tools/suite-tier.psd1')

        @($tiers.DedicatedFiles) | Should -Contain 'tests/skalary/ReviewConsumerInstall.Tests.ps1'
        $runnerText | Should -Match 'DedicatedFiles'
        Test-Path -LiteralPath $dedicated -PathType Leaf | Should -BeTrue
        (Get-Content -LiteralPath $dedicated -Raw) | Should -Match 'ReviewConsumerInstall\.Tests\.ps1'
        $workflow | Should -Match 'name:\s*Review consumer install matrix'
        $workflow | Should -Match 'scripts/skalary/Test-ReviewConsumerInstall\.ps1'
        $workflow | Should -Not -Match 'Test-ReviewConsumerInstall\.ps1[^\r\n]*-TestPath'

        $sandbox = New-RunnerSandbox -TestFileContent $script:passingTestFile
        $fixture = Join-Path $sandbox 'tests/Sandbox.Tests.ps1'
        $passOutput = & pwsh -NoProfile -File $dedicated -RepoRoot $sandbox -TestPath $fixture 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($passOutput | Out-String)

        Set-Content -LiteralPath $fixture -Value $script:failingTestFile -Encoding utf8NoBOM
        $failOutput = & pwsh -NoProfile -File $dedicated -RepoRoot $sandbox -TestPath $fixture 2>&1
        $LASTEXITCODE | Should -Be 1 -Because ($failOutput | Out-String)

        Set-Content -LiteralPath $fixture -Value $script:skippedReviewEvidenceFile -Encoding utf8NoBOM
        $skipOutput = & pwsh -NoProfile -File $dedicated -RepoRoot $sandbox -TestPath $fixture 2>&1
        $LASTEXITCODE | Should -Be 3 -Because "skipped runtime evidence is cannot-test, never green: $($skipOutput | Out-String)"

        $cleanupFixture = Join-Path $TestDrive 'cleanup-cli'
        [void](New-Item -ItemType Directory -Path $cleanupFixture -Force)
        Copy-Item -LiteralPath (Join-Path $script:repoRoot 'scripts/skalary/Remove-ReviewRun.ps1') -Destination $cleanupFixture
        @'
function Finalize-ReviewPlanRun {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$RunId, [string]$PlanDir, [string]$Verdict)
    return [pscustomobject]@{
        RunId = $RunId; Verdict = $Verdict; Report = 'report'; Receipt = 'receipt'
        Preview = $false; CleanupPending = $true; CleanupDiagnostic = 'access denied while deleting tombstone'
    }
}
Export-ModuleMember -Function Finalize-ReviewPlanRun
'@ | Set-Content -LiteralPath (Join-Path $cleanupFixture 'ReviewRun.psm1') -Encoding utf8NoBOM
        $cleanupOutput = & pwsh -NoProfile -File (Join-Path $cleanupFixture 'Remove-ReviewRun.ps1') `
            -RunId '8f3c1d2e-5a47-4b90-9c61-2d7e0f4a6b35' -PlanDir 'docs/implementation-plans/example' -Verdict blocked 2>&1
        $LASTEXITCODE | Should -Be 4 -Because 'durable evidence with pending cleanup is retryable failure, not success'
        ($cleanupOutput | Out-String) | Should -Match 'access denied while deleting tombstone'
    }

    It 'test:RunUnitTests.TierExecution isolates Fast and Slow while preserving the runner verdicts' {
        $sandbox = New-RunnerSandbox -TestFileContent $script:failingTestFile
        Set-Content -LiteralPath (Join-Path $sandbox 'tests/Slow.Tests.ps1') -Value $script:passingTestFile -Encoding utf8NoBOM
        Set-Content -LiteralPath (Join-Path $sandbox 'tools/suite-tier.psd1') -Encoding utf8NoBOM -Value @'
@{
    Schema = 'skalary/suite-tier@1'
    FastFocusedHardCeilingSeconds = 60
    SlowHardCeilingSeconds = 600
    CiSetupAllowanceSeconds = 60
    DedicatedFiles = @()
    SlowFiles = @('tests/Slow.Tests.ps1')
}
'@

        $fastFails = Invoke-Runner -SandboxRoot $sandbox -ExtraArguments @('-Tier Fast')
        $slowPasses = Invoke-Runner -SandboxRoot $sandbox -ExtraArguments @('-Tier Slow')
        $fastFails.ExitCode | Should -Be 1 -Because $fastFails.Output
        $slowPasses.ExitCode | Should -Be 0 -Because $slowPasses.Output
        $slowPasses.Output | Should -Match 'Suite tier: Slow'
        $slowPasses.Output | Should -Match 'Slow tier runtime:'

        Set-Content -LiteralPath (Join-Path $sandbox 'tests/Sandbox.Tests.ps1') -Value $script:passingTestFile -Encoding utf8NoBOM
        Set-Content -LiteralPath (Join-Path $sandbox 'tests/Slow.Tests.ps1') -Value $script:failingTestFile -Encoding utf8NoBOM

        $fastPasses = Invoke-Runner -SandboxRoot $sandbox -ExtraArguments @('-Tier Fast')
        $slowFails = Invoke-Runner -SandboxRoot $sandbox -ExtraArguments @('-Tier Slow')
        $fastPasses.ExitCode | Should -Be 0 -Because $fastPasses.Output
        $slowFails.ExitCode | Should -Be 1 -Because $slowFails.Output
        $fastPasses.Output | Should -Match 'Suite tier: Fast'
        $fastPasses.Output | Should -Match 'Suite budget:'

        $clockPath = Join-Path $sandbox 'slow-must-not-consume-clock.json'
        $null = Invoke-Runner -SandboxRoot $sandbox -ExtraArguments @('-StartBudgetClock', "-BudgetClockPath '$clockPath'")
        $slowWithClock = Invoke-Runner -SandboxRoot $sandbox -ExtraArguments @('-Tier Slow', "-BudgetClockPath '$clockPath'")
        $slowWithClock.ExitCode | Should -Be 1 -Because $slowWithClock.Output
        Test-Path -LiteralPath $clockPath -PathType Leaf |
            Should -BeTrue -Because 'Slow is unbudgeted and cannot consume Fast measurement state'
    }

    It 'test:RunUnitTests.FocusedFastScope requires explicit paths, runs only them, and reports sixty seconds' {
        $sandbox = New-RunnerSandbox -TestFileContent $script:failingTestFile
        Set-Content -LiteralPath (Join-Path $sandbox 'tests/Focused.Tests.ps1') -Value $script:passingTestFile -Encoding utf8NoBOM

        $missingScope = Invoke-Runner -SandboxRoot $sandbox -ExactArguments
        $missingScope.ExitCode | Should -Be 12 -Because $missingScope.Output
        $missingScope.Output | Should -Match 'FocusedScopeRequired'
        $missingScope.Output | Should -Match 'FullRepository'

        $focused = Invoke-Runner -SandboxRoot $sandbox -ExtraArguments @("-TestPath 'tests/Focused.Tests.ps1'")
        $focused.ExitCode | Should -Be 0 -Because $focused.Output
        $focused.Output | Should -Match 'Suite tier: Fast focused \(1 file\(s\)\)'
        $focused.Output | Should -Match 'Focused Fast runtime:'
        $focused.Output | Should -Match 'ceiling of 60s'

        Set-Content -LiteralPath (Join-Path $sandbox 'tests/Slow.Tests.ps1') -Encoding utf8NoBOM -Value @'
Describe 'focused slow file' {
    It 'selected case passes' { $true | Should -BeTrue }
    It 'unselected case fails' { $true | Should -BeFalse }
}
'@
        Set-SandboxTier -SandboxRoot $sandbox -Tier Slow -SlowFiles @('tests/Slow.Tests.ps1') | Out-Null
        $named = Invoke-Runner -SandboxRoot $sandbox -ExtraArguments @(
            "-TestPath 'tests/Slow.Tests.ps1'",
            "-TestName '*selected case passes'"
        )
        $named.ExitCode | Should -Be 0 -Because $named.Output
        $named.Output | Should -Match 'Tests Passed: 1'

        $manifestPath = Join-Path $sandbox 'tools/suite-tier.psd1'
        $manifestText = Get-Content -LiteralPath $manifestPath -Raw
        $manifestText.Replace('FastFocusedHardCeilingSeconds = 60', 'FastFocusedHardCeilingSeconds = 0.001') |
            Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM
        $overBudget = Invoke-Runner -SandboxRoot $sandbox -ExtraArguments @("-TestPath 'tests/Focused.Tests.ps1'")
        $overBudget.ExitCode | Should -Be 0 -Because $overBudget.Output
        $overBudget.Output | Should -Match 'OverBudget:'
        $overBudget.Output | Should -Match 'advisory ceiling'
    }

    It 'test:RunUnitTests.UndiscoverableTestFileFails fails when a test file never loads, even beside files that did' {
        # A file that throws during discovery contributes nothing to FailedCount or TotalCount
        # — Pester counts it separately — so a whole file can silently not run while the suite
        # reports a pass. That includes this file, which would take the REQ-5 gate down with it.
        foreach ($tier in @('Fast', 'Slow')) {
            $sandbox = New-RunnerSandbox -TestFileContent $script:passingTestFile
            Set-Content -LiteralPath (Join-Path $sandbox 'tests/Undiscoverable.Tests.ps1') -Value $script:undiscoverableTestFile -Encoding utf8
            $tierArgs = Set-SandboxTier -SandboxRoot $sandbox -Tier $tier -SlowFiles @('tests/Sandbox.Tests.ps1', 'tests/Undiscoverable.Tests.ps1')

            $result = Invoke-Runner -SandboxRoot $sandbox -ExtraArguments $tierArgs
            $result.ExitCode |
                Should -Be 4 -Because "$tier must fail when a file never loads: $($result.Output)"
            $result.Output | Should -Match 'TestFilesNotDiscoverable'
            $result.Output |
                Should -Match 'Undiscoverable\.Tests\.ps1' -Because 'the file that did not load has to be nameable from the output'
        }
    }

    It 'test:RunUnitTests.WritesNUnitToRequestedPath puts the report where CI asked, creating the folder it named' {
        # REQ-9: two matrix legs both writing Pester's default name produce one file and one
        # artifact upload that collides with the other. The path is therefore given per platform,
        # and a runner that quietly ignored it would leave CI uploading nothing while still green.
        $sandbox = New-RunnerSandbox -TestFileContent $script:passingTestFile
        $relative = 'artifacts/test-results/nunit-sandbox.xml'
        $expected = Join-Path $sandbox $relative

        Test-Path -LiteralPath (Split-Path -Parent $expected) |
            Should -BeFalse -Because 'the point is that the runner creates the directory CI names, so it must not exist first'

        $result = Invoke-Runner -SandboxRoot $sandbox -ExtraArguments @("-TestResultPath '$relative'")
        $result.ExitCode | Should -Be 0 -Because "the sandbox suite passes: $($result.Output)"

        Test-Path -LiteralPath $expected -PathType Leaf |
            Should -BeTrue -Because "the NUnit report must land at the requested path: $($result.Output)"

        # Present but empty would upload an artifact that says nothing, so the report is read
        # rather than merely counted.
        ([xml](Get-Content -LiteralPath $expected -Raw)).'test-results'.total |
            Should -Be '1' -Because 'the report has to describe the run that produced it'
    }

    It 'test:RunUnitTests.EnvironmentLeakFails fails a passing suite that leaves the caller-s environment changed' {
        # Pester runs in-process, so a test assigning $env:X rewrites the shell that invoked the
        # suite. Nothing in a green run says so: the eval tests left HOME under TestDrive, and git
        # then looked for .gitconfig and .ssh in a deleted temp directory until the shell was closed.
        foreach ($tier in @('Fast', 'Slow')) {
            $sandbox = New-RunnerSandbox -TestFileContent $script:environmentLeakingTestFile
            $tierArgs = Set-SandboxTier -SandboxRoot $sandbox -Tier $tier

            $result = Invoke-Runner -SandboxRoot $sandbox -ExtraArguments $tierArgs
            $result.ExitCode |
                Should -Be 7 -Because "$tier must catch an environment leak after passing tests: $($result.Output)"
            $result.Output | Should -Match 'EnvironmentLeaked'
            $result.Output | Should -Match 'HOME'
        }
    }

    It 'test:RunUnitTests.EnvironmentCreationIsALeak treats a variable that did not exist before as leaked' {
        # Setting an absent variable to '' is still a change, and it is the case a developer box
        # hides: locally the variable is usually already set, so the restore looks correct and only a
        # clean environment disagrees. The report has to distinguish unset from empty, or the
        # difference renders as "('' -> '')" and reads like a bug in the check.
        foreach ($tier in @('Fast', 'Slow')) {
            $sandbox = New-RunnerSandbox -TestFileContent $script:environmentCreatingTestFile
            $tierArgs = Set-SandboxTier -SandboxRoot $sandbox -Tier $tier

            $result = Invoke-Runner -SandboxRoot $sandbox -ExtraArguments $tierArgs
            $result.ExitCode |
                Should -Be 7 -Because "$tier must treat environment creation as a leak: $($result.Output)"
            $result.Output | Should -Match 'SKALARY_LEAK_PROBE'
            $result.Output | Should -Match '<unset>'
        }
    }

    It 'test:RunUnitTests.InvalidTierManifestExitsNine fails malformed and incomplete manifests diagnostically' {
        $invalidManifests = @(
            "@{ Schema = 'skalary/suite-tier@1'; SlowFiles = @(",
            "@{ Schema = 'wrong'; SlowHardCeilingSeconds = 600; CiSetupAllowanceSeconds = 60; DedicatedFiles = @(); SlowFiles = @() }",
            "@{ Schema = 'skalary/suite-tier@1' }",
            "@{ Schema = 'skalary/suite-tier@1'; SlowHardCeilingSeconds = 0; CiSetupAllowanceSeconds = 60; DedicatedFiles = @(); SlowFiles = @() }",
            "@{ Schema = 'skalary/suite-tier@1'; SlowHardCeilingSeconds = 600; CiSetupAllowanceSeconds = 60; DedicatedFiles = @(); SlowFiles = @('tests/missing.Tests.ps1') }",
            "@{ Schema = 'skalary/suite-tier@1'; SlowHardCeilingSeconds = 600; CiSetupAllowanceSeconds = 60; DedicatedFiles = @('tests/Sandbox.Tests.ps1'); SlowFiles = @('tests/Sandbox.Tests.ps1') }",
            "@{ Schema = 'skalary/suite-tier@1'; SlowHardCeilingSeconds = 600; CiSetupAllowanceSeconds = 60; DedicatedFiles = @(); SlowFiles = @('../escape.Tests.ps1') }"
        )
        foreach ($manifest in $invalidManifests) {
            $sandbox = New-RunnerSandbox -TestFileContent $script:passingTestFile
            Set-Content -LiteralPath (Join-Path $sandbox 'tools/suite-tier.psd1') -Value $manifest -Encoding utf8NoBOM

            $result = Invoke-Runner -SandboxRoot $sandbox
            $result.ExitCode | Should -Be 9 -Because $result.Output
            $result.Output | Should -Match 'SuiteTierInvalid'
        }

        $missing = New-RunnerSandbox -TestFileContent $script:passingTestFile
        Remove-Item -LiteralPath (Join-Path $missing 'tools/suite-tier.psd1') -Force
        foreach ($tier in @('Fast', 'Slow', 'All')) {
            $result = Invoke-Runner -SandboxRoot $missing -ExtraArguments @('-Tier', $tier)
            $result.ExitCode | Should -Be 9 -Because "$tier requires the tracked tier authority"
            $result.Output | Should -Match 'SuiteTierInvalid'
        }
    }

    It 'test:RunUnitTests.SlowOverBudgetFails reports both Slow runtime figures without failing' {
        $sandbox = New-RunnerSandbox -TestFileContent $script:passingTestFile
        @'
@{
    Schema = 'skalary/suite-tier@1'
    FastFocusedHardCeilingSeconds = 60
    SlowHardCeilingSeconds = 0.001
    CiSetupAllowanceSeconds = 60
    DedicatedFiles = @()
    SlowFiles = @('tests/Sandbox.Tests.ps1')
}
'@ | Set-Content -LiteralPath (Join-Path $sandbox 'tools/suite-tier.psd1') -Encoding utf8NoBOM

        $result = Invoke-Runner -SandboxRoot $sandbox -ExtraArguments @('-Tier', 'Slow')
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.Output | Should -Match 'OverBudget: Slow tier runtime'
        $result.Output | Should -Match '0\.001s advisory ceiling'
    }
}
