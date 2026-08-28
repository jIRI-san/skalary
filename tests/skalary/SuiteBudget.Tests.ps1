#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'suite budget' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:budgetPath = Join-Path $script:repoRoot 'tools/suite-budget.psd1'
        $script:runner = Join-Path $script:repoRoot 'scripts/skalary/Run-UnitTests.ps1'
        $script:fingerprintScript = Join-Path $script:repoRoot 'scripts/skalary/Get-SuiteInputFingerprint.ps1'
        $script:measurementScript = Join-Path $script:repoRoot 'scripts/skalary/Measure-SuiteRuntime.ps1'
        $script:sandboxes = [System.Collections.Generic.List[string]]::new()
        $script:budget = $null
        if (Test-Path -LiteralPath $script:budgetPath -PathType Leaf) {
            $script:budget = Import-PowerShellDataFile -LiteralPath $script:budgetPath
        }
        # The budget names its own measurement record, so this file checks the figures the
        # budget claims to have been tightened against rather than a path it chose itself.
        $script:runtimePath = Join-Path $script:repoRoot ([string]$script:budget.MeasurementRecord)
        . $script:fingerprintScript

        function Get-PlanDecisionsText {
            param([string]$PlanId)

            $planRoot = Join-Path $script:repoRoot 'docs/implementation-plans'
            if (-not (Test-Path -LiteralPath $planRoot -PathType Container)) { return $null }

            foreach ($plan in (Get-ChildItem -LiteralPath $planRoot -Recurse -File -Filter 'plan.md')) {
                $head = (Get-Content -LiteralPath $plan.FullName -TotalCount 20) -join "`n"
                if ($head -match "plan-id:\s*$([regex]::Escape($PlanId))\b") {
                    $decisions = Join-Path $plan.DirectoryName 'assets/decisions.md'
                    if (-not (Test-Path -LiteralPath $decisions -PathType Leaf)) {
                        $decisions = Join-Path $plan.DirectoryName 'decisions.md'
                    }
                    if (Test-Path -LiteralPath $decisions -PathType Leaf) {
                        return (Get-Content -LiteralPath $decisions -Raw)
                    }
                }
            }
            return $null
        }

        function Get-CurrentPlatformKey {
            if ($IsWindows) { return 'Windows' }
            if ($IsMacOS) { return 'MacOS' }
            return 'Linux'
        }

        function Get-PlatformEntries {
            $script:budget | Should -Not -BeNullOrEmpty -Because 'tools/suite-budget.psd1 must exist and parse'
            $script:budget.Keys |
                Should -Contain 'Platforms' -Because 'REQ-2 binds the ceiling per platform; without the entries every ceiling assertion below would pass over an empty set'

            $platforms = $script:budget.Platforms
            $entries = [ordered]@{}
            foreach ($key in @($platforms.Keys | Sort-Object)) { $entries[$key] = $platforms[$key] }
            @($entries.Keys).Count |
                Should -BeGreaterThan 0 -Because 'an empty platform set would make the ceiling assertions vacuous'
            return $entries
        }

        # A sandbox repo root carrying one trivial test and a budget this file writes, so the
        # runner's budget branch is exercised against figures the case controls rather than
        # against the suite it is running inside.
        function New-BudgetSandbox {
            [CmdletBinding()]
            [OutputType([string])]
            param(
                [Parameter(Mandatory)]
                [int]$HardCeilingSeconds,

                [Parameter(Mandatory)]
                [int]$TargetSeconds,

                [string]$PlatformKey = (Get-CurrentPlatformKey),

                # Replaces the generated budget wholesale, for cases about a budget that is
                # malformed rather than tight.
                [string]$BudgetText,

                [switch]$FailingTest
            )

            $root = Join-Path ([System.IO.Path]::GetTempPath()) ('suite-budget-' + [System.Guid]::NewGuid().ToString('N'))
            if (Test-Path -LiteralPath $root) {
                throw "Refusing to reuse an existing sandbox root: '$root'."
            }

            [void](New-Item -ItemType Directory -Path $root)
            $script:sandboxes.Add($root)
            [void](New-Item -ItemType Directory -Path (Join-Path $root 'tests'))
            [void](New-Item -ItemType Directory -Path (Join-Path $root 'tools'))

            $assertion = if ($FailingTest) { '$false | Should -BeTrue' } else { '$true | Should -BeTrue' }
            Set-Content -LiteralPath (Join-Path $root 'tests/Sandbox.Tests.ps1') -Encoding utf8 -Value @"
Describe 'sandbox' {
    It 'asserts' { $assertion }
}
"@

            if (-not $BudgetText) {
                $BudgetText = @"
@{
    Schema = 'skalary/suite-budget@2'
    MeasuredCommand = 'npm test'
    MeasuredLegs = @('validate-plan', 'test:unit', 'validate.ps1')
    MeasurementRecord = 'tools/suite-runtime.json'
    BoundCeilingSeconds = 600
    AbsoluteCapSeconds = 900
    MaxCeilingRaises = 1
    Platforms = @{
        '$PlatformKey' = @{
            HardCeilingSeconds = $HardCeilingSeconds
            TargetSeconds = $TargetSeconds
            CeilingRaises = @()
        }
    }
}
"@
            }
            Set-Content -LiteralPath (Join-Path $root 'tools/suite-budget.psd1') -Encoding utf8 -Value $BudgetText
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

            [void](New-Item -ItemType Directory -Path (Join-Path $root 'scripts/skalary') -Force)
            Copy-Item -LiteralPath $script:fingerprintScript `
                -Destination (Join-Path $root 'scripts/skalary/Get-SuiteInputFingerprint.ps1')
            & git -C $root init --quiet
            & git -C $root add -- scripts tests tools/suite-budget.psd1
            $fixtureBudget = Import-PowerShellDataFile -LiteralPath (
                Join-Path $root 'tools/suite-budget.psd1'
            )
            if ($fixtureBudget.Contains('MeasurementRecord')) {
                $fingerprint = Get-SuiteInputFingerprint -RepoRoot $root
                $runtime = [ordered]@{
                    schema          = 'skalary/suite-runtime@2'
                    measuredCommand = [string]$fixtureBudget.MeasuredCommand
                    platforms       = [ordered]@{
                        (Get-CurrentPlatformKey) = [ordered]@{
                            schema              = 'skalary/suite-runtime-row@2'
                            platform            = Get-CurrentPlatformKey
                            measuredCommand     = [string]$fixtureBudget.MeasuredCommand
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
            }

            return (Resolve-Path -LiteralPath $root).Path
        }

        # A child process, not a runspace: the runner runs Pester, and a nested Pester run
        # shares the outer run's module state.
        function Invoke-Runner {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [string]$SandboxRoot,

                [string]$BudgetClockPath
            )

            $arguments = "-RepoRoot '$SandboxRoot' -FullRepository"
            if ($BudgetClockPath) { $arguments += " -BudgetClockPath '$BudgetClockPath'" }

            $driver = Join-Path $SandboxRoot 'driver.ps1'
            Set-Content -LiteralPath $driver -Encoding utf8 -Value @(
                # A captured escape sequence is written into the NUnit report when a case
                # fails, and 0x1B is not valid XML — the report is lost exactly when it matters.
                '$PSStyle.OutputRendering = ''PlainText'''
                'Remove-Item Env:SKALARY_SUITE_MEASUREMENT_TOKEN, Env:SKALARY_SUITE_MEASUREMENT_KEY -ErrorAction SilentlyContinue'
                "& '$script:runner' $arguments"
                'exit $LASTEXITCODE'
            )

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

        function New-MeasurementSandbox {
            $root = Join-Path ([System.IO.Path]::GetTempPath()) (
                'suite-measurement-' + [System.Guid]::NewGuid().ToString('N')
            )
            [void](New-Item -ItemType Directory -Path (Join-Path $root 'scripts/skalary') -Force)
            [void](New-Item -ItemType Directory -Path (Join-Path $root 'tools') -Force)
            $script:sandboxes.Add($root)
            Copy-Item -LiteralPath $script:fingerprintScript `
                -Destination (Join-Path $root 'scripts/skalary/Get-SuiteInputFingerprint.ps1')
            Copy-Item -LiteralPath $script:measurementScript `
                -Destination (Join-Path $root 'scripts/skalary/Measure-SuiteRuntime.ps1')

            $platform = Get-CurrentPlatformKey
            Set-Content -LiteralPath (Join-Path $root 'tools/suite-budget.psd1') `
                -Encoding utf8NoBOM -Value @"
@{
    Schema = 'skalary/suite-budget@2'
    MeasuredCommand = 'npm test'
    MeasurementRecord = 'tools/suite-runtime.json'
    BoundCeilingSeconds = 600
    AbsoluteCapSeconds = 900
    MaxCeilingRaises = 1
    Platforms = @{
        '$platform' = @{
            HardCeilingSeconds = 600
            TargetSeconds = 480
            CeilingRaises = @()
        }
    }
}
"@
            Set-Content -LiteralPath (Join-Path $root 'tools/suite-runtime.json') `
                -Encoding utf8NoBOM -Value @"
{
  "schema": "skalary/suite-runtime@1",
  "measuredCommand": "npm test",
  "platforms": {
    "$platform": {
      "schema": "skalary/suite-runtime-row@1",
      "platform": "$platform",
      "measuredCommand": "npm test",
      "seconds": 1,
      "succeeded": true
    }
  }
}
"@
            Set-Content -LiteralPath (Join-Path $root 'tools/suite-profile.json') `
                -Encoding utf8NoBOM -Value '{"generated":true}'
            Set-Content -LiteralPath (Join-Path $root 'gate.ps1') -Encoding utf8NoBOM -Value @'
param([string]$RepoRoot)
$ErrorActionPreference = 'Stop'
. (Join-Path $RepoRoot 'scripts/skalary/Get-SuiteInputFingerprint.ps1')
$budget = Import-PowerShellDataFile -LiteralPath (Join-Path $RepoRoot 'tools/suite-budget.psd1')
$platform = if ($IsWindows) { 'Windows' } elseif ($IsMacOS) { 'MacOS' } else { 'Linux' }
$noncePath = Join-Path $RepoRoot '.measurement-nonce'
$nonce = if (Test-Path -LiteralPath $noncePath -PathType Leaf) {
    [System.IO.File]::ReadAllText($noncePath)
}
else {
    $null
}
Remove-Item -LiteralPath $noncePath -Force -ErrorAction SilentlyContinue
$result = Test-SuiteRuntimeFreshness -RepoRoot $RepoRoot -Budget $budget `
    -PlatformKey $platform -ExpectedNonce $nonce
if ($result.Status -eq 'measurement-token-invalid') {
    Write-Host "MeasurementTokenInvalid: $($result.Reason)"
    exit 11
}
if ($result.Status -ne 'complete') {
    Write-Host "StaleMeasurement: $($result.Reason)"
    exit 10
}
'@
            Set-Content -LiteralPath (Join-Path $root 'start.ps1') -Encoding utf8NoBOM -Value @'
param([string]$RepoRoot)
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($env:SKALARY_SUITE_MEASUREMENT_TOKEN) -and
    [string]::IsNullOrWhiteSpace($env:SKALARY_SUITE_MEASUREMENT_KEY)) {
    exit 0
}
. (Join-Path $RepoRoot 'scripts/skalary/Get-SuiteInputFingerprint.ps1')
$fingerprint = Get-SuiteInputFingerprint -RepoRoot $RepoRoot
$authorization = Test-SuiteMeasurementAuthorization `
    -Token $env:SKALARY_SUITE_MEASUREMENT_TOKEN `
    -Key $env:SKALARY_SUITE_MEASUREMENT_KEY `
    -ExpectedFingerprint $fingerprint.Fingerprint
if ($authorization.Status -ne 'complete') {
    Write-Host "MeasurementTokenInvalid: $($authorization.Reason)"
    exit 11
}
$claim = Use-SuiteMeasurementNonce -Nonce $authorization.Nonce `
    -ParentPid $authorization.ParentPid -ClaimRoot $RepoRoot
if ($claim.Status -ne 'complete') {
    Write-Host "MeasurementTokenInvalid: $($claim.Reason)"
    exit 11
}
[System.IO.File]::WriteAllText(
    (Join-Path $RepoRoot '.measurement-nonce'),
    $authorization.Nonce,
    [System.Text.UTF8Encoding]::new($false)
)
'@
            Set-Content -LiteralPath (Join-Path $root 'package.json') -Encoding utf8NoBOM -Value @'
{
  "scripts": {
    "pretest": "pwsh -NoProfile -File start.ps1 -RepoRoot .",
    "test": "pwsh -NoProfile -File gate.ps1 -RepoRoot ."
  }
}
'@
            & git -C $root init --quiet
            & git -C $root add -- gate.ps1 start.ps1 package.json scripts tools
            if ($LASTEXITCODE -ne 0) { throw "Unable to stage measurement fixture '$root'." }
            return $root
        }

        function Invoke-MeasurementFixture {
            param(
                [Parameter(Mandatory)][string]$Root,
                [switch]$NoWrite
            )

            $arguments = @(
                '-NoProfile', '-File',
                (Join-Path $Root 'scripts/skalary/Measure-SuiteRuntime.ps1'),
                '-RepoRoot', $Root,
                '-Source', 'test:measurement-mode'
            )
            if ($NoWrite) { $arguments += '-NoWrite' }
            $output = @(& pwsh @arguments 2>&1)
            return [pscustomobject]@{
                ExitCode = $LASTEXITCODE
                Output   = ($output | ForEach-Object { "$_" }) -join "`n"
            }
        }

        function Invoke-AuthorizationVerifier {
            param(
                [Parameter(Mandatory)][string]$Token,
                [Parameter(Mandatory)][string]$Key,
                [Parameter(Mandatory)][string]$Fingerprint
            )

            $driver = Join-Path ([System.IO.Path]::GetTempPath()) (
                'suite-auth-' + [guid]::NewGuid().ToString('N') + '.ps1'
            )
            Set-Content -LiteralPath $driver -Encoding utf8NoBOM -Value @"
. '$script:fingerprintScript'
`$result = Test-SuiteMeasurementAuthorization -Token '$Token' -Key '$Key' ``
    -ExpectedFingerprint '$Fingerprint'
`$result | ConvertTo-Json -Compress
"@
            try {
                return (& pwsh -NoProfile -File $driver | ConvertFrom-Json)
            }
            finally {
                Remove-Item -LiteralPath $driver -Force -ErrorAction SilentlyContinue
            }
        }
    }

    AfterAll {
        foreach ($sandbox in $script:sandboxes) {
            if (Test-Path -LiteralPath $sandbox -PathType Container) {
                Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'test:SuiteBudget.CeilingIsPerPlatform gives every platform its own ceiling and leaves none to a shared default' {
        Test-Path -LiteralPath $script:budgetPath -PathType Leaf |
            Should -BeTrue -Because 'tools/suite-budget.psd1 is the bound ceiling REQ-2 requires'

        $script:budget.Keys |
            Should -Contain 'Platforms' -Because 'REQ-2 binds the ceiling per platform, not once for the repo'

        foreach ($blind in @('HardCeilingSeconds', 'TargetSeconds', 'CeilingRaises')) {
            $script:budget.Keys |
                Should -Not -Contain $blind -Because "a repo-wide '$blind' lets a caller enforce a ceiling without knowing which platform it measured"
        }

        $entries = Get-PlatformEntries
        @($entries.Keys).Count |
            Should -BeGreaterThan 1 -Because 'a single entry is a shared ceiling wearing a platform name'

        foreach ($platform in @('Linux', 'Windows')) {
            $entries.Keys |
                Should -Contain $platform -Because "CI runs the suite on $platform, so $platform needs a ceiling of its own"
        }

        foreach ($platform in $entries.Keys) {
            $entry = $entries[$platform]
            foreach ($key in @('HardCeilingSeconds', 'TargetSeconds', 'CeilingRaises')) {
                $entry.Keys |
                    Should -Contain $key -Because "platform '$platform' must carry its own $key"
            }
        }

        $current = Get-CurrentPlatformKey
        $entries.Keys |
            Should -Contain $current -Because "the runner enforces the entry for the platform it runs on; add a '$current' entry rather than letting it run unbudgeted"
    }

    It 'test:SuiteBudget.AbsoluteCapIs900 caps the ceiling at 900s and keeps the target under it' {
        Test-Path -LiteralPath $script:budgetPath -PathType Leaf |
            Should -BeTrue -Because 'tools/suite-budget.psd1 is the bound ceiling REQ-2 requires'

        [int]$script:budget.AbsoluteCapSeconds | Should -Be 900

        $entries = Get-PlatformEntries
        foreach ($platform in $entries.Keys) {
            $entry = $entries[$platform]
            [int]$entry.HardCeilingSeconds |
                Should -BeGreaterThan 0 -Because "platform '$platform' needs a real ceiling"
            [int]$entry.HardCeilingSeconds |
                Should -BeLessOrEqual ([int]$script:budget.AbsoluteCapSeconds) -Because "no ceiling may exceed the absolute cap ('$platform')"
            [int]$entry.TargetSeconds |
                Should -BeGreaterThan 0 -Because "platform '$platform' needs a real target"
            [int]$entry.TargetSeconds |
                Should -BeLessOrEqual ([int]$entry.HardCeilingSeconds) -Because "the target sits under the ceiling ('$platform')"
        }
    }

    It 'test:SuiteBudget.CeilingCannotBeRaisedWithoutJustification rejects a raise with no recorded justification' {
        [int]$script:budget.BoundCeilingSeconds |
            Should -Be 600 -Because 'the ceiling bound in phase 1 is the immutable reference every platform ceiling is checked against'
        [int]$script:budget.MaxCeilingRaises | Should -Be 1

        $entries = Get-PlatformEntries
        $decisions = $null

        # Totalled and asserted before the per-platform checks: a per-platform failure below must not
        # short-circuit the "once across the whole plan" rule.
        $totalRaises = 0
        foreach ($platform in $entries.Keys) { $totalRaises += @($entries[$platform].CeilingRaises).Count }
        $totalRaises |
            Should -BeLessOrEqual ([int]$script:budget.MaxCeilingRaises) -Because 'the escape hatch may be used once across the whole plan, not once per platform'

        foreach ($platform in $entries.Keys) {
            $entry = $entries[$platform]
            $raises = @($entry.CeilingRaises)

            if ([int]$entry.HardCeilingSeconds -le [int]$script:budget.BoundCeilingSeconds) {
                $raises.Count |
                    Should -Be 0 -Because "a ceiling at or under the bound value was never raised ('$platform')"
                continue
            }

            $raises.Count |
                Should -Be 1 -Because "a raised ceiling must record the raise that produced it ('$platform')"

            $raise = $raises[0]
            [int]$raise.Seconds |
                Should -Be ([int]$entry.HardCeilingSeconds) -Because "the recorded raise must be the ceiling in force ('$platform')"
            [int]$raise.Seconds | Should -BeLessOrEqual ([int]$script:budget.AbsoluteCapSeconds)
            [string]$raise.Step | Should -Not -BeNullOrEmpty
            [string]$raise.Justification | Should -Not -BeNullOrEmpty

            if ($null -eq $decisions) {
                $planId = [string]$script:budget.JustificationPlanId
                $planId | Should -Not -BeNullOrEmpty
                $decisions = Get-PlanDecisionsText -PlanId $planId
                $decisions | Should -Not -BeNullOrEmpty -Because "plan '$planId' must carry the decisions record the justification lives in"
            }
            $decisions |
                Should -Match ([regex]::Escape([string]$raise.Justification)) -Because "the justification must be written into the plan decisions, not only into the budget file ('$platform')"
        }
    }

    It 'test:SuiteBudget.MeasuresFullNpmTest budgets the whole npm test command, not the Pester leg alone' {
        [string]$script:budget.MeasuredCommand | Should -Be 'npm test'

        $packageJson = Get-Content -LiteralPath (Join-Path $script:repoRoot 'package.json') -Raw | ConvertFrom-Json
        $testScript = [string]$packageJson.scripts.test
        $testScript | Should -Not -BeNullOrEmpty

        $legs = @($script:budget.MeasuredLegs)
        $legs.Count | Should -BeGreaterThan 1
        foreach ($leg in $legs) {
            $testScript |
                Should -Match ([regex]::Escape([string]$leg)) -Because "the budgeted command must cover the '$leg' leg"
        }

        # The runner is the last leg and reads a clock the first one started. Either half alone
        # measures a subset: no clock and it times itself; not last and it stops timing before
        # the command does.
        $packageJson.scripts.PSObject.Properties.Name |
            Should -Contain 'pretest' -Because 'a leg can only measure a command spanning three of them from a clock started before the first'
        [string]$packageJson.scripts.pretest |
            Should -Match 'StartBudgetClock' -Because 'the pretest hook is what starts the budget clock'
        $testScript.LastIndexOf('test:unit') |
            Should -BeGreaterThan ($testScript.LastIndexOf('validate.ps1')) -Because 'the leg that reads the clock has to be the last one, or the legs after it are unmeasured'
    }

    It 'test:SuiteBudget.WithinHardCeiling reports recorded platform figures against advisory ceilings' {
        # REQ-4's stop condition, read off the recorded measurement rather than off a run this
        # test performs: the figure is `npm test` end to end, which a test inside that command
        # cannot time.
        [string]$script:budget.MeasurementRecord |
            Should -Not -BeNullOrEmpty -Because 'the budget must name the record its figures were tightened against'
        Test-Path -LiteralPath $script:runtimePath -PathType Leaf |
            Should -BeTrue -Because 'step 4.1 records the achieved figure per platform in tools/suite-runtime.json'

        $runtime = Get-Content -LiteralPath $script:runtimePath -Raw | ConvertFrom-Json
        [string]$runtime.measuredCommand |
            Should -Be ([string]$script:budget.MeasuredCommand) -Because 'a figure for another command cannot be compared with this budget'

        $rows = @($runtime.platforms.PSObject.Properties)
        $rows.Count | Should -BeGreaterThan 0 -Because 'an empty record would make every assertion below vacuous'

        $entries = Get-PlatformEntries
        $current = Get-CurrentPlatformKey
        $isMeasurementRun = (
            -not [string]::IsNullOrWhiteSpace($env:SKALARY_SUITE_MEASUREMENT_TOKEN) -and
            -not [string]::IsNullOrWhiteSpace($env:SKALARY_SUITE_MEASUREMENT_KEY)
        )
        if (-not $isMeasurementRun) {
            $freshness = Test-SuiteRuntimeFreshness -RepoRoot $script:repoRoot `
                -Budget $script:budget -PlatformKey $current
            if ($freshness.Status -ne 'complete') {
                Write-Warning "StaleMeasurement: $($freshness.Reason). Runtime rows are advisory."
            }
        }

        foreach ($property in $rows) {
            $platform = $property.Name
            $row = $property.Value

            $entries.Keys |
                Should -Contain $platform -Because "'$platform' has a measurement but no budget entry to check it against"
            [bool]$row.succeeded |
                Should -BeTrue -Because "a stopped run did less work than the one the ceiling governs ('$platform')"
            if ([double]$row.seconds -le 0) {
                Write-Warning "Suite budget: '$platform' has a non-positive advisory runtime observation."
            }
            if ([double]$row.seconds -gt [double]$entries[$platform].HardCeilingSeconds) {
                Write-Warning "OverBudget: '$platform' measured $($row.seconds)s against advisory ceiling $($entries[$platform].HardCeilingSeconds)s."
            }

            # A figure without its environment cannot be attributed: the same suite measured
            # roughly 10x apart between platforms, so the number alone says nothing.
            foreach ($field in @('commit', 'measuredAt', 'source')) {
                [string]$row.$field |
                    Should -Not -BeNullOrEmpty -Because "'$platform' must record the '$field' its figure came from"
            }
            foreach ($field in @('os', 'psVersion', 'processorCount')) {
                @($row.environment.PSObject.Properties.Name) |
                    Should -Contain $field -Because "'$platform' must record the '$field' its figure was measured under"
                [string]$row.environment.$field |
                    Should -Not -BeNullOrEmpty -Because "'$platform' must retain the measured '$field' value"
            }
        }
    }

    It 'test:SuiteBudget.MeasurementModeRefreshesStaleRows authorizes one stale run and records its exact tracked inputs' {
        $root = New-MeasurementSandbox
        $platform = Get-CurrentPlatformKey
        $runtimePath = Join-Path $root 'tools/suite-runtime.json'
        $runtime = Get-Content -LiteralPath $runtimePath -Raw | ConvertFrom-Json
        $runtime.platforms.PSObject.Properties.Remove($platform)
        Set-Content -LiteralPath $runtimePath -Value (
            ($runtime | ConvertTo-Json -Depth 10) + "`n"
        ) -Encoding utf8NoBOM
        $before = Get-SuiteInputFingerprint -RepoRoot $root
        $result = Invoke-MeasurementFixture -Root $root
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.Output | Should -Match 'SUITE-RUNTIME-ROW:'

        $after = Get-SuiteInputFingerprint -RepoRoot $root
        $after.Fingerprint | Should -Be $before.Fingerprint
        $runtime = Get-Content -LiteralPath $runtimePath -Raw |
            ConvertFrom-Json
        $row = $runtime.platforms.$platform
        [string]$runtime.schema | Should -Be 'skalary/suite-runtime@2'
        [string]$row.schema | Should -Be 'skalary/suite-runtime-row@2'
        [string]$row.fingerprintProtocol | Should -Be $after.Protocol
        [string]$row.inputFingerprint | Should -Be $after.Fingerprint
        [double]$row.seconds | Should -BeGreaterThan 0
        [double]$row.seconds | Should -BeLessOrEqual 600

        Set-Content -LiteralPath (Join-Path $root 'tools/suite-runtime.json') `
            -Value '{"excluded":"runtime"}' -Encoding utf8NoBOM
        Set-Content -LiteralPath (Join-Path $root 'tools/suite-profile.json') `
            -Value '{"excluded":"profile"}' -Encoding utf8NoBOM
        (Get-SuiteInputFingerprint -RepoRoot $root).Fingerprint |
            Should -Be $after.Fingerprint -Because 'only the three generated outputs are excluded'

        Add-Content -LiteralPath (
            Join-Path $root 'scripts/skalary/Get-SuiteInputFingerprint.ps1'
        ) -Value '# producer mutation'
        (Get-SuiteInputFingerprint -RepoRoot $root).Fingerprint |
            Should -Not -Be $after.Fingerprint -Because 'the fingerprint producer is an input too'
    }

    It 'test:SuiteBudget.MeasurementModeRejectsMismatchedOrReplayedToken validates every authorization field and ancestry' {
        $root = New-MeasurementSandbox
        $fingerprint = (Get-SuiteInputFingerprint -RepoRoot $root).Fingerprint
        $authorization = New-SuiteMeasurementAuthorization -Fingerprint $fingerprint -ParentPid $PID
        $valid = Invoke-AuthorizationVerifier -Token $authorization.Token `
            -Key $authorization.Key -Fingerprint $fingerprint
        $valid.Status | Should -Be 'complete'

        $mismatch = Invoke-AuthorizationVerifier -Token $authorization.Token `
            -Key $authorization.Key -Fingerprint ('0' * 64)
        $mismatch.Status | Should -Be 'invalid'
        $mismatch.Reason | Should -Match 'fingerprint'

        $wrongKey = ConvertTo-SuiteBase64Url -Bytes ([byte[]](1..32))
        $badMac = Invoke-AuthorizationVerifier -Token $authorization.Token `
            -Key $wrongKey -Fingerprint $fingerprint
        $badMac.Status | Should -Be 'invalid'
        $badMac.Reason | Should -Match 'HMAC'

        $replayed = New-SuiteMeasurementAuthorization -Fingerprint $fingerprint `
            -ParentPid ([int]::MaxValue)
        $replayResult = Invoke-AuthorizationVerifier -Token $replayed.Token `
            -Key $replayed.Key -Fingerprint $fingerprint
        $replayResult.Status | Should -Be 'invalid'
        $replayResult.Reason | Should -Match 'live ancestor'

        $budget = Import-PowerShellDataFile -LiteralPath (
            Join-Path $root 'tools/suite-budget.psd1'
        )
        $liveParent = Get-SuiteParentProcessId -ProcessId $PID
        $clockAuthorization = New-SuiteMeasurementAuthorization `
            -Fingerprint $fingerprint -ParentPid $liveParent
        $authorizedOnce = Test-SuiteRuntimeFreshness -RepoRoot $root -Budget $budget `
            -PlatformKey (Get-CurrentPlatformKey) `
            -MeasurementToken $clockAuthorization.Token `
            -MeasurementKey $clockAuthorization.Key `
            -ExpectedNonce $clockAuthorization.Nonce
        $authorizedOnce.Status | Should -Be 'complete'
        $consumed = Test-SuiteRuntimeFreshness -RepoRoot $root -Budget $budget `
            -PlatformKey (Get-CurrentPlatformKey) `
            -MeasurementToken $clockAuthorization.Token `
            -MeasurementKey $clockAuthorization.Key
        $consumed.Status | Should -Be 'measurement-token-invalid'
        $consumed.Reason | Should -Match 'consumed'
        $claimRoot = Join-Path $root 'claims'
        $firstClaim = Use-SuiteMeasurementNonce -Nonce $clockAuthorization.Nonce `
            -ParentPid $clockAuthorization.ParentPid -ClaimRoot $claimRoot
        $firstClaim.Status | Should -Be 'complete'
        $replayClaim = Use-SuiteMeasurementNonce -Nonce $clockAuthorization.Nonce `
            -ParentPid $clockAuthorization.ParentPid -ClaimRoot $claimRoot
        $replayClaim.Status | Should -Be 'invalid'
        $replayClaim.Reason | Should -Match 'already claimed'

        $clockPath = Join-Path $root 'replay-clock.json'
        $previousToken = [Environment]::GetEnvironmentVariable(
            'SKALARY_SUITE_MEASUREMENT_TOKEN'
        )
        $previousKey = [Environment]::GetEnvironmentVariable(
            'SKALARY_SUITE_MEASUREMENT_KEY'
        )
        $defaultClaim = $null
        try {
            [Environment]::SetEnvironmentVariable(
                'SKALARY_SUITE_MEASUREMENT_TOKEN',
                $authorization.Token
            )
            [Environment]::SetEnvironmentVariable(
                'SKALARY_SUITE_MEASUREMENT_KEY',
                $authorization.Key
            )
            & pwsh -NoProfile -File $script:runner -RepoRoot $root `
                -StartBudgetClock -BudgetClockPath $clockPath
            $LASTEXITCODE | Should -Be 0
            & pwsh -NoProfile -File $script:runner -RepoRoot $root `
                -StartBudgetClock -BudgetClockPath $clockPath
            $LASTEXITCODE | Should -Be 11
            $defaultClaim = Use-SuiteMeasurementNonce `
                -Nonce $authorization.Nonce -ParentPid $authorization.ParentPid
        }
        finally {
            if ($null -ne $defaultClaim -and
                -not [string]::IsNullOrWhiteSpace([string]$defaultClaim.ClaimPath)) {
                Remove-Item -LiteralPath $defaultClaim.ClaimPath -Force `
                    -ErrorAction SilentlyContinue
            }
            if ($null -eq $previousToken) {
                Remove-Item -LiteralPath Env:SKALARY_SUITE_MEASUREMENT_TOKEN `
                    -ErrorAction SilentlyContinue
            }
            else {
                [Environment]::SetEnvironmentVariable(
                    'SKALARY_SUITE_MEASUREMENT_TOKEN',
                    $previousToken
                )
            }
            if ($null -eq $previousKey) {
                Remove-Item -LiteralPath Env:SKALARY_SUITE_MEASUREMENT_KEY `
                    -ErrorAction SilentlyContinue
            }
            else {
                [Environment]::SetEnvironmentVariable(
                    'SKALARY_SUITE_MEASUREMENT_KEY',
                    $previousKey
                )
            }
        }

        $tokenObject = [System.Text.Encoding]::UTF8.GetString(
            (ConvertFrom-SuiteBase64Url -Text $authorization.Token)
        ) | ConvertFrom-Json
        $tokenObject.protocol = 'wrong-protocol'
        $mutatedToken = ConvertTo-SuiteBase64Url -Bytes (
            [System.Text.Encoding]::UTF8.GetBytes(($tokenObject | ConvertTo-Json -Compress))
        )
        $badProtocol = Invoke-AuthorizationVerifier -Token $mutatedToken `
            -Key $authorization.Key -Fingerprint $fingerprint
        $badProtocol.Status | Should -Be 'invalid'
        $badProtocol.Reason | Should -Match 'protocol'

        if (-not $IsWindows) {
            $literalBackslash = [System.IO.Path]::Combine($root, 'literal\name.txt')
            [System.IO.File]::WriteAllText(
                $literalBackslash,
                'literal backslash',
                [System.Text.UTF8Encoding]::new($false)
            )
            & git -C $root add -- 'literal\name.txt'
            $pathFingerprint = Get-SuiteInputFingerprint -RepoRoot $root
            $pathFingerprint.Paths |
                Should -Contain 'literal\name.txt' -Because 'backslash is filename data on Unix, not a separator'

            $linkRoot = New-MeasurementSandbox
            $linkedDirectory = Join-Path $linkRoot 'linked'
            [void](New-Item -ItemType Directory -Path $linkedDirectory)
            Set-Content -LiteralPath (Join-Path $linkedDirectory 'record.txt') `
                -Value 'inside' -Encoding utf8NoBOM
            & git -C $linkRoot add -- linked/record.txt
            Remove-Item -LiteralPath $linkedDirectory -Recurse -Force
            $outside = Join-Path ([System.IO.Path]::GetTempPath()) (
                'suite-link-outside-' + [guid]::NewGuid().ToString('N')
            )
            [void](New-Item -ItemType Directory -Path $outside)
            $script:sandboxes.Add($outside)
            Set-Content -LiteralPath (Join-Path $outside 'record.txt') `
                -Value 'outside' -Encoding utf8NoBOM
            [void](New-Item -ItemType SymbolicLink -Path $linkedDirectory -Target $outside)
            {
                Get-SuiteInputFingerprint -RepoRoot $linkRoot
            } | Should -Throw '*traverses a link or reparse point*'
        }
    }

    It 'test:SuiteBudget.OrdinaryModeRejectsStaleRows refuses an unmeasured tracked-input change' {
        $root = New-MeasurementSandbox
        $previousToken = [Environment]::GetEnvironmentVariable(
            'SKALARY_SUITE_MEASUREMENT_TOKEN'
        )
        $previousKey = [Environment]::GetEnvironmentVariable(
            'SKALARY_SUITE_MEASUREMENT_KEY'
        )
        try {
            Remove-Item -LiteralPath Env:SKALARY_SUITE_MEASUREMENT_TOKEN `
                -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath Env:SKALARY_SUITE_MEASUREMENT_KEY `
                -ErrorAction SilentlyContinue
            $result = @(
                & pwsh -NoProfile -File (Join-Path $root 'gate.ps1') -RepoRoot $root 2>&1
            )
            $LASTEXITCODE | Should -Be 10
            ($result | ForEach-Object { "$_" }) -join "`n" |
                Should -Match 'StaleMeasurement'

            $measured = Invoke-MeasurementFixture -Root $root
            $measured.ExitCode | Should -Be 0 -Because $measured.Output
            $fresh = @(
                & pwsh -NoProfile -File (Join-Path $root 'gate.ps1') -RepoRoot $root 2>&1
            )
            $LASTEXITCODE |
                Should -Be 0 -Because (($fresh | ForEach-Object { "$_" }) -join "`n")

            Add-Content -LiteralPath (Join-Path $root 'gate.ps1') -Value '# tracked mutation'
            $stale = @(
                & pwsh -NoProfile -File (Join-Path $root 'gate.ps1') -RepoRoot $root 2>&1
            )
            $LASTEXITCODE | Should -Be 10
            ($stale | ForEach-Object { "$_" }) -join "`n" |
                Should -Match 'StaleMeasurement'
        }
        finally {
            if ($null -eq $previousToken) {
                Remove-Item -LiteralPath Env:SKALARY_SUITE_MEASUREMENT_TOKEN `
                    -ErrorAction SilentlyContinue
            }
            else {
                [Environment]::SetEnvironmentVariable(
                    'SKALARY_SUITE_MEASUREMENT_TOKEN',
                    $previousToken
                )
            }
            if ($null -eq $previousKey) {
                Remove-Item -LiteralPath Env:SKALARY_SUITE_MEASUREMENT_KEY `
                    -ErrorAction SilentlyContinue
            }
            else {
                [Environment]::SetEnvironmentVariable(
                    'SKALARY_SUITE_MEASUREMENT_KEY',
                    $previousKey
                )
            }
        }
    }

    It 'test:SuiteBudget.OverBudgetRunFails reports a run over its platform ceiling without failing' {
        # Runtime observations remain actionable in logs, but they cannot turn passing tests red
        # while the test infrastructure is awaiting redesign.
        $overBudget = New-BudgetSandbox -HardCeilingSeconds 0 -TargetSeconds 0
        $over = Invoke-Runner -SandboxRoot $overBudget
        $over.ExitCode |
            Should -Be 0 -Because "an over-budget run is advisory after tests pass: $($over.Output)"
        $over.Output | Should -Match 'OverBudget'
        $over.Output |
            Should -Match 'against a ceiling of 0s' -Because 'the report names the budgeted value, or the failure cannot be acted on'
        $over.Output |
            Should -Match 'measured \d+(\.\d+)?s' -Because 'the report names the measured value'

        # Control: the same sandbox is green under a ceiling it fits, so the failure above is
        # the budget rather than a broken sandbox.
        $withinBudget = New-BudgetSandbox -HardCeilingSeconds 600 -TargetSeconds 480
        $within = Invoke-Runner -SandboxRoot $withinBudget
        $within.ExitCode | Should -Be 0 -Because "a run inside its ceiling passes: $($within.Output)"
        $within.Output | Should -Match 'Suite budget: measured'

        Add-Content -LiteralPath (Join-Path $withinBudget 'tests/Sandbox.Tests.ps1') -Value '# tracked mutation'
        $stale = Invoke-Runner -SandboxRoot $withinBudget
        $stale.ExitCode |
            Should -Be 0 -Because "stale advisory runtime evidence does not invalidate passing tests: $($stale.Output)"
        $stale.Output | Should -Match 'StaleMeasurement'

        # D13: a platform the budget does not mention has no ceiling that means anything.
        # Reading that as an exemption would let a whole platform run unbudgeted.
        $unbudgeted = New-BudgetSandbox -HardCeilingSeconds 600 -TargetSeconds 480 -PlatformKey 'NotThisPlatform'
        $unknown = Invoke-Runner -SandboxRoot $unbudgeted
        $unknown.ExitCode |
            Should -Be 0 -Because "a platform with no advisory entry does not invalidate passing tests: $($unknown.Output)"
        $unknown.Output | Should -Match 'BudgetNotDefined'

        # A budget missing a field the check reads is the same condition as a missing entry. It
        # must not surface as exit 1: that code means tests failed, and here they passed.
        $malformed = New-BudgetSandbox -HardCeilingSeconds 600 -TargetSeconds 480 -BudgetText @"
@{
    Schema = 'skalary/suite-budget@2'
    MeasuredCommand = 'npm test'
    AbsoluteCapSeconds = 900
    MeasurementRecord = 'tools/suite-runtime.json'
    Platforms = @{
        '$(Get-CurrentPlatformKey)' = @{
            TargetSeconds = 480
            CeilingRaises = @()
        }
    }
}
"@
        $incomplete = Invoke-Runner -SandboxRoot $malformed
        $incomplete.ExitCode |
            Should -Be 0 -Because "missing advisory budget fields do not invalidate passing tests: $($incomplete.Output)"
        $incomplete.Output | Should -Match 'BudgetNotDefined'
        $incomplete.Output | Should -Match 'HardCeilingSeconds'

        $missingRecord = New-BudgetSandbox -HardCeilingSeconds 600 -TargetSeconds 480 `
            -BudgetText @"
@{
    Schema = 'skalary/suite-budget@2'
    MeasuredCommand = 'npm test'
    AbsoluteCapSeconds = 900
    Platforms = @{
        '$(Get-CurrentPlatformKey)' = @{
            HardCeilingSeconds = 600
            TargetSeconds = 480
            CeilingRaises = @()
        }
    }
}
"@
        $withoutFreshness = Invoke-Runner -SandboxRoot $missingRecord
        $withoutFreshness.ExitCode |
            Should -Be 0 -Because "missing advisory freshness evidence does not invalidate passing tests: $($withoutFreshness.Output)"
        $withoutFreshness.Output | Should -Match 'BudgetNotDefined'
        $withoutFreshness.Output | Should -Match 'MeasurementRecord'

        $invalidSyntax = New-BudgetSandbox -HardCeilingSeconds 600 -TargetSeconds 480
        Set-Content -LiteralPath (Join-Path $invalidSyntax 'tools/suite-budget.psd1') `
            -Value '@{ Platforms = ' -Encoding utf8NoBOM
        $unreadable = Invoke-Runner -SandboxRoot $invalidSyntax
        $unreadable.ExitCode |
            Should -Be 0 -Because "invalid advisory metadata does not invalidate passing tests: $($unreadable.Output)"
        $unreadable.Output | Should -Match 'BudgetNotDefined'
        $unreadable.Output | Should -Match 'could not be read'
    }

    It 'test:SuiteBudget.ClockedRunIsMeasuredAsTheWholeCommand charges the runner with the legs that ran before it' {
        # D2: budgeting the Pester leg while the goal is stated for `npm test` measures a
        # different quantity than the one the ceiling exists to bound. The clock is what closes
        # that gap, so a run whose command started long before this leg has to be over a ceiling
        # its own leg fits inside comfortably.
        $sandbox = New-BudgetSandbox -HardCeilingSeconds 120 -TargetSeconds 60
        $neighbour = New-BudgetSandbox -HardCeilingSeconds 120 -TargetSeconds 60

        # A clock belonging to a different repo root, started the way `pretest` starts one.
        $clockPattern = Join-Path ([System.IO.Path]::GetTempPath()) 'skalary-suite-budget-clock-*.json'
        $before = @(Get-ChildItem -Path $clockPattern -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
        $outerToken = [Environment]::GetEnvironmentVariable(
            'SKALARY_SUITE_MEASUREMENT_TOKEN'
        )
        $outerKey = [Environment]::GetEnvironmentVariable(
            'SKALARY_SUITE_MEASUREMENT_KEY'
        )
        try {
            Remove-Item -LiteralPath Env:SKALARY_SUITE_MEASUREMENT_TOKEN `
                -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath Env:SKALARY_SUITE_MEASUREMENT_KEY `
                -ErrorAction SilentlyContinue
            & pwsh -NoProfile -File $script:runner -RepoRoot $neighbour -StartBudgetClock
        }
        finally {
            if ($null -eq $outerToken) {
                Remove-Item -LiteralPath Env:SKALARY_SUITE_MEASUREMENT_TOKEN `
                    -ErrorAction SilentlyContinue
            }
            else {
                [Environment]::SetEnvironmentVariable(
                    'SKALARY_SUITE_MEASUREMENT_TOKEN',
                    $outerToken
                )
            }
            if ($null -eq $outerKey) {
                Remove-Item -LiteralPath Env:SKALARY_SUITE_MEASUREMENT_KEY `
                    -ErrorAction SilentlyContinue
            }
            else {
                [Environment]::SetEnvironmentVariable(
                    'SKALARY_SUITE_MEASUREMENT_KEY',
                    $outerKey
                )
            }
        }
        $neighbourClock = @(Get-ChildItem -Path $clockPattern -File -ErrorAction SilentlyContinue |
                Where-Object { $before -notcontains $_.FullName })
        $neighbourClock.Count |
            Should -Be 1 -Because 'the pretest hook writes one clock for the root it was started against'

        $unclocked = Invoke-Runner -SandboxRoot $sandbox
        $unclocked.ExitCode | Should -Be 0 -Because "the leg alone fits the ceiling: $($unclocked.Output)"
        $unclocked.Output |
            Should -Match 'lower bound' -Because 'an unclocked run measures a subset and must not read as a verdict on the whole command'

        # The suite runs this script against sandbox roots while a real run of it is in
        # progress. A clock shared across roots would let one of those nested runs consume the
        # clock of the run that spawned it, which is how the outer run silently loses its scope.
        Test-Path -LiteralPath $neighbourClock[0].FullName -PathType Leaf |
            Should -BeTrue -Because 'a run against another repo root must not consume this root''s clock'
        Remove-Item -LiteralPath $neighbourClock[0].FullName -Force -ErrorAction SilentlyContinue

        $clock = Join-Path $sandbox 'budget-clock.json'
        # 600s against a 120s ceiling: far enough over that a staleness rule scaled to the
        # ceiling would have discarded the clock and passed the run — the worse the overrun,
        # the more certainly it would have been excused.
        Set-Content -LiteralPath $clock -Encoding utf8 -Value (@{
                schema    = 'skalary/suite-budget-clock@1'
                startedAt = [DateTimeOffset]::UtcNow.AddSeconds(-600).ToString('o')
                command   = 'npm test'
            } | ConvertTo-Json)

        $clocked = Invoke-Runner -SandboxRoot $sandbox -BudgetClockPath $clock
        $clocked.ExitCode |
            Should -Be 0 -Because "the command overrun is reported without invalidating passing tests: $($clocked.Output)"
        $clocked.Output | Should -Match 'OverBudget:'
        $clocked.Output |
            Should -Match ([regex]::Escape('(npm test)')) -Because 'the report names the scope it measured, so a full-command figure is not read as a leg figure'

        # Consumed on read: a clock left behind by a run that crashed would otherwise fail the
        # next run for time it never spent.
        Test-Path -LiteralPath $clock -PathType Leaf |
            Should -BeFalse -Because 'the clock is consumed by the run that reads it'

        # Every branch, not only the green one. A red suite, an absent Pester or a failing
        # earlier leg all end the command with the clock still on disk, and the next direct
        # `npm run test:unit` would be charged the abandoned run's wall clock — reported as an
        # overrun of a suite that ran for a second.
        $red = New-BudgetSandbox -HardCeilingSeconds 120 -TargetSeconds 60 -FailingTest
        $redClock = Join-Path $red 'budget-clock.json'
        Set-Content -LiteralPath $redClock -Encoding utf8 -Value (@{
                schema    = 'skalary/suite-budget-clock@1'
                startedAt = [DateTimeOffset]::UtcNow.AddSeconds(-600).ToString('o')
                command   = 'npm test'
            } | ConvertTo-Json)

        $redRun = Invoke-Runner -SandboxRoot $red -BudgetClockPath $redClock
        $redRun.ExitCode |
            Should -Be 1 -Because "a failing suite fails as a failing suite, not as an overrun: $($redRun.Output)"
        Test-Path -LiteralPath $redClock -PathType Leaf |
            Should -BeFalse -Because 'the clock is cleared whichever branch the run exits on'
    }
}
