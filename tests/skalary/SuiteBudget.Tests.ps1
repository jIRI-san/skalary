#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'suite budget' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:budgetPath = Join-Path $script:repoRoot 'tools/suite-budget.psd1'
        $script:runner = Join-Path $script:repoRoot 'scripts/skalary/Run-UnitTests.ps1'
        $script:sandboxes = [System.Collections.Generic.List[string]]::new()
        $script:budget = $null
        if (Test-Path -LiteralPath $script:budgetPath -PathType Leaf) {
            $script:budget = Import-PowerShellDataFile -LiteralPath $script:budgetPath
        }
        # The budget names its own measurement record, so this file checks the figures the
        # budget claims to have been tightened against rather than a path it chose itself.
        $script:runtimePath = Join-Path $script:repoRoot ([string]$script:budget.MeasurementRecord)

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

            $arguments = "-RepoRoot '$SandboxRoot'"
            if ($BudgetClockPath) { $arguments += " -BudgetClockPath '$BudgetClockPath'" }

            $driver = Join-Path $SandboxRoot 'driver.ps1'
            Set-Content -LiteralPath $driver -Encoding utf8 -Value @(
                # A captured escape sequence is written into the NUnit report when a case
                # fails, and 0x1B is not valid XML — the report is lost exactly when it matters.
                '$PSStyle.OutputRendering = ''PlainText'''
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
                Output = (($output | Out-String) -replace '\x1b\[[0-9;]*[a-zA-Z]', '' -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', '')
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

    It 'test:SuiteBudget.WithinHardCeiling keeps every recorded platform figure under its own ceiling' {
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
        @($rows | ForEach-Object { $_.Name }) |
            Should -Contain $current -Because "the platform this suite is running on must carry a measured figure; measure it with scripts/skalary/Measure-SuiteRuntime.ps1"

        foreach ($property in $rows) {
            $platform = $property.Name
            $row = $property.Value

            $entries.Keys |
                Should -Contain $platform -Because "'$platform' has a measurement but no budget entry to check it against"
            [bool]$row.succeeded |
                Should -BeTrue -Because "a stopped run did less work than the one the ceiling governs ('$platform')"
            [double]$row.seconds |
                Should -BeGreaterThan 0 -Because "a zero figure is a measurement that did not happen ('$platform')"
            [double]$row.seconds |
                Should -BeLessOrEqual ([double]$entries[$platform].HardCeilingSeconds) -Because "'$platform' measured $($row.seconds)s against its hard ceiling; split the suite into tiers rather than raising it (D13)"

            # A figure without its environment cannot be attributed: the same suite measured
            # roughly 10x apart between platforms, so the number alone says nothing.
            foreach ($field in @('commit', 'measuredAt', 'source')) {
                [string]$row.$field |
                    Should -Not -BeNullOrEmpty -Because "'$platform' must record the '$field' its figure came from"
            }
            foreach ($field in @('os', 'psVersion', 'processorCount')) {
                @($row.environment.PSObject.Properties.Name) |
                    Should -Contain $field -Because "'$platform' must record the '$field' its figure was measured under"
            }
        }
    }

    It 'test:SuiteBudget.OverBudgetRunFails fails a run over its platform ceiling and names both figures' {
        # REQ-2: the ceiling is only a gate if something enforces it. The runner is that
        # something, and it is the only place the check lives, so this is where an over-budget
        # run has to become a non-zero exit rather than a line in a log.
        $overBudget = New-BudgetSandbox -HardCeilingSeconds 0 -TargetSeconds 0
        $over = Invoke-Runner -SandboxRoot $overBudget
        $over.ExitCode |
            Should -Be 5 -Because "an over-budget run fails with its own code, distinct from a test failure: $($over.Output)"
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

        # D13: a platform the budget does not mention has no ceiling that means anything.
        # Reading that as an exemption would let a whole platform run unbudgeted.
        $unbudgeted = New-BudgetSandbox -HardCeilingSeconds 600 -TargetSeconds 480 -PlatformKey 'NotThisPlatform'
        $unknown = Invoke-Runner -SandboxRoot $unbudgeted
        $unknown.ExitCode |
            Should -Be 6 -Because "a platform with no entry is an error, not an exemption: $($unknown.Output)"
        $unknown.Output | Should -Match 'BudgetNotDefined'

        # A budget missing a field the check reads is the same condition as a missing entry. It
        # must not surface as exit 1: that code means tests failed, and here they passed.
        $malformed = New-BudgetSandbox -HardCeilingSeconds 600 -TargetSeconds 480 -BudgetText @"
@{
    Schema = 'skalary/suite-budget@2'
    MeasuredCommand = 'npm test'
    AbsoluteCapSeconds = 900
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
            Should -Be 6 -Because "a budget missing HardCeilingSeconds cannot be enforced, and the suite it ran did not fail: $($incomplete.Output)"
        $incomplete.Output | Should -Match 'BudgetNotDefined'
        $incomplete.Output | Should -Match 'HardCeilingSeconds'
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
        & pwsh -NoProfile -File $script:runner -RepoRoot $neighbour -StartBudgetClock
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
                schema = 'skalary/suite-budget-clock@1'
                startedAt = [DateTimeOffset]::UtcNow.AddSeconds(-600).ToString('o')
                command = 'npm test'
            } | ConvertTo-Json)

        $clocked = Invoke-Runner -SandboxRoot $sandbox -BudgetClockPath $clock
        $clocked.ExitCode |
            Should -Be 5 -Because "the command started 600s ago against a 120s ceiling: $($clocked.Output)"
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
                schema = 'skalary/suite-budget-clock@1'
                startedAt = [DateTimeOffset]::UtcNow.AddSeconds(-600).ToString('o')
                command = 'npm test'
            } | ConvertTo-Json)

        $redRun = Invoke-Runner -SandboxRoot $red -BudgetClockPath $redClock
        $redRun.ExitCode |
            Should -Be 1 -Because "a failing suite fails as a failing suite, not as an overrun: $($redRun.Output)"
        Test-Path -LiteralPath $redClock -PathType Leaf |
            Should -BeFalse -Because 'the clock is cleared whichever branch the run exits on'
    }
}
