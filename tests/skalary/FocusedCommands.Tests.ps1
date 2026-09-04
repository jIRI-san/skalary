#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'local-first focused command contracts' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:unitRunner = Join-Path $script:repoRoot 'scripts/skalary/Run-UnitTests.ps1'
        $script:evalRunner = Join-Path $script:repoRoot 'scripts/skalary/Test-Evals.ps1'
        $script:validator = Join-Path $script:repoRoot 'scripts/validate.ps1'

        function Invoke-CapturedPowerShell {
            param([Parameter(Mandatory)][string[]]$ArgumentList)

            $output = & pwsh -NoProfile @ArgumentList 2>&1
            # Escape sequences captured from a child are written verbatim into the NUnit report
            # when a case fails, and 0x1B is not valid XML: the report is lost exactly when it
            # is needed. Strip them here rather than in every assertion.
            $text = ($output | Out-String) -replace '\x1b\[[0-9;]*[a-zA-Z]', '' -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', ''
            return [pscustomobject]@{
                ExitCode = $LASTEXITCODE
                Output = $text
            }
        }
    }

    It 'test:FocusedCommands.Contract confines scope, selects only requested work, and enforces the 30/60 process contract' {
        foreach ($runner in @($script:unitRunner, $script:evalRunner, $script:validator)) {
            (Get-Command -Name $runner).Parameters.Keys |
                Should -Not -Contain 'InternalFocusedChild'
        }

        $bypassAttempts = @(
            [pscustomobject]@{
                Arguments = @('-File', $script:unitRunner, '-TestPath',
                    'tests/skalary/FocusedCommands.Tests.ps1', '-InternalFocusedChild')
            },
            [pscustomobject]@{
                Arguments = @('-File', $script:evalRunner, '-Plugin', 'plugin-manager',
                    '-InternalFocusedChild')
            },
            [pscustomobject]@{
                Arguments = @('-File', $script:validator, '-Path', 'package.json',
                    '-InternalFocusedChild')
            }
        )
        foreach ($probe in $bypassAttempts) {
            $attempt = Invoke-CapturedPowerShell -ArgumentList $probe.Arguments
            $attempt.ExitCode | Should -Not -Be 0
            $attempt.Output | Should -Match 'InternalFocusedChild'
            $attempt.Output | Should -Match '(?i)parameter cannot be found|named parameter'
            $attempt.Output | Should -Not -Match 'Validation passed|Tests completed successfully'
        }

        $missingUnit = Invoke-CapturedPowerShell -ArgumentList @('-File', $script:unitRunner)
        $missingUnit.ExitCode | Should -Be 12
        $missingUnit.Output | Should -Match 'FocusedScopeRequired'
        (Invoke-CapturedPowerShell -ArgumentList @(
                '-File', $script:unitRunner,
                '-TestPath', '../outside.Tests.ps1'
            )).ExitCode | Should -Be 12
        (Invoke-CapturedPowerShell -ArgumentList @(
                '-File', $script:unitRunner,
                '-TestPath', 'tests/skalary/FocusedCommands.Tests.ps1',
                '-FullRepository'
            )).ExitCode | Should -Be 12

        $missingEval = Invoke-CapturedPowerShell -ArgumentList @('-File', $script:evalRunner)
        $missingEval.ExitCode | Should -Be 12
        $missingEval.Output | Should -Match 'FocusedScopeRequired'
        (Invoke-CapturedPowerShell -ArgumentList @(
                '-File', $script:evalRunner, '-Plugin', '../outside'
            )).ExitCode | Should -Be 12
        (Invoke-CapturedPowerShell -ArgumentList @(
                '-File', $script:evalRunner, '-Plugin', 'plugin-manager', '-FullRepository'
            )).ExitCode | Should -Be 12

        $missingValidation = Invoke-CapturedPowerShell -ArgumentList @('-File', $script:validator)
        $missingValidation.ExitCode | Should -Be 12
        $missingValidation.Output | Should -Match 'FocusedScopeRequired'

        $escapedValidation = Invoke-CapturedPowerShell -ArgumentList @(
            '-File', $script:validator, '-Path', '../outside.json'
        )
        $escapedValidation.ExitCode | Should -Be 12
        $escapedValidation.Output | Should -Match 'inside the repository'

        $conflictingValidation = Invoke-CapturedPowerShell -ArgumentList @(
            '-File', $script:validator, '-Path', 'package.json', '-FullRepository'
        )
        $conflictingValidation.ExitCode | Should -Be 12

        $focusedValidation = Invoke-CapturedPowerShell -ArgumentList @(
            '-File', $script:validator, '-Path', 'package.json'
        )
        $focusedValidation.ExitCode | Should -Be 0 -Because $focusedValidation.Output
        $focusedValidation.Output | Should -Match '0 PowerShell and 1 JSON file'

        $fixtureRoot = Join-Path $TestDrive 'eval-repo'
        $goodEvalDir = Join-Path $fixtureRoot 'plugins/selected/evals'
        $badEvalDir = Join-Path $fixtureRoot 'plugins/unselected/evals'
        [void](New-Item -ItemType Directory -Path $goodEvalDir -Force)
        [void](New-Item -ItemType Directory -Path $badEvalDir -Force)
        [void](New-Item -ItemType Directory -Path (Join-Path $fixtureRoot 'tests/evals/output') -Force)
        [void](New-Item -ItemType Directory -Path (Join-Path $fixtureRoot 'tools') -Force)
        @"
Describe 'selected' {
    It 'passes' { `$true | Should -BeTrue }
}
"@ | Set-Content -LiteralPath (Join-Path $goodEvalDir 'selected.Tests.ps1') -Encoding utf8NoBOM
        @"
Describe 'unselected' {
    It 'fails' { `$false | Should -BeTrue }
}
"@ | Set-Content -LiteralPath (Join-Path $badEvalDir 'unselected.Tests.ps1') -Encoding utf8NoBOM
        '{"schema":"skalary/structural-eval-required@1","caseIds":[]}' |
            Set-Content -LiteralPath (Join-Path $fixtureRoot 'tools/required.json') -Encoding utf8NoBOM

        $selectedEval = Invoke-CapturedPowerShell -ArgumentList @(
            '-File', $script:evalRunner,
            '-RepoRoot', $fixtureRoot,
            '-PluginsRoot', (Join-Path $fixtureRoot 'plugins'),
            '-RequiredContractPath', (Join-Path $fixtureRoot 'tools/required.json'),
            '-OutputRoot', (Join-Path $fixtureRoot 'tests/evals/output'),
            '-Plugin', 'selected'
        )
        $selectedEval.ExitCode | Should -Be 0 -Because $selectedEval.Output
        $selectedEval.Output | Should -Match 'total: 1'
        $selectedEval.Output | Should -Not -Match 'unselected'

        $timedValidation = Invoke-CapturedPowerShell -ArgumentList @(
            '-File', $script:validator,
            '-Path', 'package.json',
            '-FocusedWarningSeconds', '0.05',
            '-FocusedTimeoutSeconds', '0.1'
        )
        $timedValidation.ExitCode | Should -Be 13 -Because $timedValidation.Output
        $timedValidation.Output | Should -Match 'FocusedTimeout'

        $timedEval = Invoke-CapturedPowerShell -ArgumentList @(
            '-File', $script:evalRunner,
            '-RepoRoot', $fixtureRoot,
            '-PluginsRoot', (Join-Path $fixtureRoot 'plugins'),
            '-OutputRoot', (Join-Path $fixtureRoot 'tests/evals/output'),
            '-Plugin', 'selected',
            '-FocusedWarningSeconds', '0.05',
            '-FocusedTimeoutSeconds', '0.1'
        )
        $timedEval.ExitCode | Should -Be 13 -Because $timedEval.Output
        $timedEval.Output | Should -Match 'FocusedTimeout'

        $timeoutRoot = Join-Path $TestDrive 'timeout-repo'
        [void](New-Item -ItemType Directory -Path (Join-Path $timeoutRoot 'tests') -Force)
        [void](New-Item -ItemType Directory -Path (Join-Path $timeoutRoot 'tools') -Force)
        @'
@{
    Schema = 'skalary/suite-tier@1'
    FastFocusedHardCeilingSeconds = 60
    SlowHardCeilingSeconds = 600
    CiSetupAllowanceSeconds = 60
    DedicatedFiles = @()
    SlowFiles = @()
}
'@ | Set-Content -LiteralPath (Join-Path $timeoutRoot 'tools/suite-tier.psd1') -Encoding utf8NoBOM
        $pidFile = Join-Path $timeoutRoot 'child.pid'
        @'
Describe 'timeout process tree' {
    It 'starts a descendant and waits' {
        $child = Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList @('-NoProfile', '-Command', 'Start-Sleep -Seconds 30') -PassThru
        Set-Content -LiteralPath $env:SKALARY_FOCUSED_PID_FILE -Value $child.Id
        Start-Sleep -Seconds 30
    }
}
'@ | Set-Content -LiteralPath (Join-Path $timeoutRoot 'tests/Timeout.Tests.ps1') -Encoding utf8NoBOM
        $oldPidFile = $env:SKALARY_FOCUSED_PID_FILE
        $env:SKALARY_FOCUSED_PID_FILE = $pidFile
        try {
            $timedOut = Invoke-CapturedPowerShell -ArgumentList @(
                '-File', $script:unitRunner,
                '-RepoRoot', $timeoutRoot,
                '-TestPath', 'tests/Timeout.Tests.ps1',
                '-FocusedWarningSeconds', '0.2',
                '-FocusedTimeoutSeconds', '4'
            )
        }
        finally {
            $env:SKALARY_FOCUSED_PID_FILE = $oldPidFile
        }
        $timedOut.ExitCode | Should -Be 13 -Because $timedOut.Output
        $timedOut.Output | Should -Match 'FocusedTimeout'
        Test-Path -LiteralPath $pidFile -PathType Leaf |
            Should -BeTrue -Because 'the timed test must start its descendant before timeout'
        $descendantPid = [int](Get-Content -LiteralPath $pidFile -Raw)
        Start-Sleep -Milliseconds 200
        Get-Process -Id $descendantPid -ErrorAction SilentlyContinue |
            Should -BeNullOrEmpty -Because 'the focused timeout terminates the directly launched process tree'

        Set-Content -LiteralPath (Join-Path $timeoutRoot 'tests/Fast.Tests.ps1') -Encoding utf8NoBOM -Value @'
Describe 'fast completion' {
    It 'passes after the warning threshold' {
        Start-Sleep -Milliseconds 400
        $true | Should -BeTrue
    }
}
'@
        $slowComplete = Invoke-CapturedPowerShell -ArgumentList @(
            '-File', $script:unitRunner,
            '-RepoRoot', $timeoutRoot,
            '-TestPath', 'tests/Fast.Tests.ps1',
            '-FocusedWarningSeconds', '0.2',
            '-FocusedTimeoutSeconds', '5'
        )
        $slowComplete.ExitCode | Should -Be 0 -Because $slowComplete.Output
        $slowComplete.Output | Should -Match 'FocusedSlow'
        $slowComplete.Output.IndexOf('FocusedSlow') |
            Should -BeGreaterThan $slowComplete.Output.IndexOf('Tests completed')
    }

    It 'test:LocalFirst.BaselineContract removes hosted and implicit broad entry points while retaining direct explicit routes' {
        @(Get-ChildItem -LiteralPath (Join-Path $script:repoRoot '.github/workflows') `
                -File -ErrorAction SilentlyContinue).Count | Should -Be 0

        $package = Get-Content -LiteralPath (Join-Path $script:repoRoot 'package.json') -Raw |
            ConvertFrom-Json
        foreach ($scriptValue in @($package.scripts.PSObject.Properties.Value)) {
            [string]$scriptValue | Should -Not -Match 'FullRepository'
            [string]$scriptValue | Should -Not -Match 'Invoke-WazaEvals|Test-Evals'
        }
        [string]$package.scripts.build | Should -Match 'validate\.ps1 -Path '
        [string]$package.scripts.test | Should -Match 'Run-UnitTests\.ps1 -TestPath '

        $unitText = Get-Content -LiteralPath $script:unitRunner -Raw
        $evalText = Get-Content -LiteralPath $script:evalRunner -Raw
        $wazaText = Get-Content -LiteralPath (
            Join-Path $script:repoRoot 'scripts/skalary/Invoke-WazaEvals.ps1'
        ) -Raw
        $unitText | Should -Match '\[switch\]\$FullRepository'
        $evalText | Should -Match '\[switch\]\$FullRepository'
        $validatorText = Get-Content -LiteralPath $script:validator -Raw
        foreach ($text in @($unitText, $evalText, $validatorText)) {
            $text | Should -Not -Match '\$InternalFocusedChild'
        }
        $wazaText | Should -Match 'Waza requires one explicit -Plugin'

        $wazaFixture = Join-Path $TestDrive 'waza-repo'
        [void](New-Item -ItemType Directory -Path $wazaFixture)
        $wazaRefusal = Invoke-CapturedPowerShell -ArgumentList @(
            '-File', (Join-Path $script:repoRoot 'scripts/skalary/Invoke-WazaEvals.ps1'),
            '-RepoRoot', $wazaFixture
        )
        $wazaRefusal.ExitCode | Should -Be 12
        Test-Path -LiteralPath (Join-Path $wazaFixture 'tests/evals/output') |
            Should -BeFalse -Because 'scope refusal precedes provisioning and output creation'

        $callers = Get-ChildItem -LiteralPath (Join-Path $script:repoRoot 'plugins') -Recurse -File |
            Where-Object { $_.Extension -in @('.md', '.ps1') } |
            ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }
        ($callers -join "`n") | Should -Not -Match 'Run-UnitTests\.ps1[^\r\n]*-FullRepository'
        ($callers -join "`n") | Should -Not -Match 'npm run eval:llm'
    }

    It 'test:FocusedCommands.SupervisionIsNotSelectable proves no parameter, variable, or environment marker can reach an unsupervised focused run' {
        # This case is deliberately written against the invariant rather than against the name
        # of the switch that used to carry it: a rename would leave every assertion here failing.
        $commonParameters = [System.Collections.Generic.HashSet[string]]::new(
            [string[]]@(
                [System.Management.Automation.PSCmdlet]::CommonParameters +
                [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
            ),
            [System.StringComparer]::OrdinalIgnoreCase)

        $allowlists = [ordered]@{
            $script:unitRunner = @('RepoRoot', 'Tier', 'TestPath', 'TestName', 'EvidenceTestId',
                'EvidenceResultPath', 'FullRepository', 'StartBudgetClock', 'BudgetClockPath',
                'TestResultPath', 'FocusedWarningSeconds', 'FocusedTimeoutSeconds')
            $script:evalRunner = @('RepoRoot', 'OutputRoot', 'PluginsRoot', 'RequiredContractPath',
                'Plugin', 'FullRepository', 'FocusedWarningSeconds', 'FocusedTimeoutSeconds')
            $script:validator = @('Path', 'FullRepository', 'FocusedWarningSeconds',
                'FocusedTimeoutSeconds')
        }
        foreach ($entry in $allowlists.GetEnumerator()) {
            $declared = @((Get-Command -Name $entry.Key).Parameters.Keys |
                    Where-Object { -not $commonParameters.Contains([string]$_) } |
                    Sort-Object)
            ($declared -join ',') |
                Should -BeExactly ((@($entry.Value) | Sort-Object) -join ',') `
                    -Because "$($entry.Key) must expose exactly its documented scope parameters and nothing that selects a worker mode"
        }

        # Public dispatch must not read a caller-controlled variable or environment value at all.
        foreach ($path in @($script:unitRunner, $script:evalRunner, $script:validator)) {
            $text = Get-Content -LiteralPath $path -Raw
            $text | Should -Not -Match '(?im)^\s*[^#\r\n]*Get-Variable'
            $text | Should -Not -Match '(?im)^\s*[^#\r\n]*\$env:'
            $text | Should -Not -Match '(?im)^\s*[^#\r\n]*GetEnvironmentVariable'
        }

        # The supervised child runs a private body, never the public command again.
        $internalRoot = Join-Path $script:repoRoot 'scripts/skalary/internal'
        Test-Path -LiteralPath $internalRoot -PathType Container | Should -BeTrue
        foreach ($body in @(Get-ChildItem -LiteralPath $internalRoot -File -Filter '*.ps1')) {
            $bodyText = Get-Content -LiteralPath $body.FullName -Raw
            $bodyText | Should -Not -Match '(?im)^\s*[.&]\s+[^\r\n]*(?:Run-UnitTests|Test-Evals|validate)\.ps1' `
                -Because "$($body.Name) must not re-enter public dispatch"
        }

        $fixtureRoot = Join-Path $TestDrive 'bypass-repo'
        [void](New-Item -ItemType Directory -Path (Join-Path $fixtureRoot 'tests') -Force)
        [void](New-Item -ItemType Directory -Path (Join-Path $fixtureRoot 'tools') -Force)
        Set-Content -LiteralPath (Join-Path $fixtureRoot 'tools/suite-tier.psd1') -Encoding utf8NoBOM -Value @'
@{
    Schema = 'skalary/suite-tier@1'
    FastFocusedHardCeilingSeconds = 60
    SlowHardCeilingSeconds = 600
    CiSetupAllowanceSeconds = 60
    DedicatedFiles = @()
    SlowFiles = @()
}
'@
        Set-Content -LiteralPath (Join-Path $fixtureRoot 'tests/Sleeper.Tests.ps1') -Encoding utf8NoBOM -Value @'
Describe 'sleeper' {
    It 'outlives the focused timeout' { Start-Sleep -Seconds 30 }
}
'@
        Set-Content -LiteralPath (Join-Path $fixtureRoot 'tests/Fast.Tests.ps1') -Encoding utf8NoBOM -Value @'
Describe 'fast' {
    It 'test:BypassProbe.Runnable passes' { $true | Should -BeTrue }
}
'@

        # A decoy the old environment protocol would have executed in place of the real body.
        $decoyMarker = Join-Path $fixtureRoot 'decoy-ran.txt'
        $decoy = Join-Path $fixtureRoot 'decoy.ps1'
        Set-Content -LiteralPath $decoy -Encoding utf8NoBOM -Value @"
param([Parameter(ValueFromRemainingArguments)]`$Rest)
Set-Content -LiteralPath '$decoyMarker' -Value 'ran' -Encoding utf8NoBOM
exit 0
"@

        $sentinelNames = @(
            '__SkalaryFocusedUnitChild', '__SkalaryFocusedEvalChild',
            '__SkalaryFocusedValidationChild', 'InternalFocusedChild', 'SkalaryFocusedChild',
            'isFocusedChild'
        )
        $preamble = [System.Collections.Generic.List[string]]::new()
        $preamble.Add('$PSStyle.OutputRendering = ''PlainText''')
        foreach ($name in $sentinelNames) {
            $preamble.Add("`$script:$name = `$true")
            $preamble.Add("`$global:$name = `$true")
        }
        foreach ($prefix in @('UNIT', 'EVAL', 'VALIDATION')) {
            $preamble.Add("`$env:SKALARY_FOCUSED_${prefix}_CHILD = '1'")
            $preamble.Add("`$env:SKALARY_FOCUSED_${prefix}_SCRIPT = '$decoy'")
            $preamble.Add("`$env:SKALARY_FOCUSED_${prefix}_REQUEST = '{}'")
        }

        function Invoke-BypassProbe {
            param(
                [Parameter(Mandatory)][string]$Operator,
                [Parameter(Mandatory)][string]$ScriptPath,
                [Parameter(Mandatory)][string]$ArgumentText,
                [Parameter(Mandatory)][System.Collections.Generic.List[string]]$Preamble,
                [Parameter(Mandatory)][string]$DriverPath
            )

            $lines = [System.Collections.Generic.List[string]]::new($Preamble)
            $lines.Add("$Operator '$ScriptPath' $ArgumentText")
            $lines.Add('exit $LASTEXITCODE')
            Set-Content -LiteralPath $DriverPath -Value ($lines -join [Environment]::NewLine) -Encoding utf8NoBOM
            return (Invoke-CapturedPowerShell -ArgumentList @('-File', $DriverPath))
        }

        $unitTimeoutText = "-RepoRoot '$fixtureRoot' -TestPath 'tests/Sleeper.Tests.ps1' " +
            '-FocusedWarningSeconds 0.2 -FocusedTimeoutSeconds 1.5'

        # `&` and `.` are the two host forms a caller can reach the same script through besides
        # the documented -File form, which the 30/60 contract case above already drives. All of
        # them must land in the supervisor and be killed at the bound even with every sentinel
        # variable and environment marker preseeded.
        foreach ($operator in @('&', '.')) {
            $driver = Join-Path $fixtureRoot ("driver-unit-" + ($operator -replace '\W', 'x') + '.ps1')
            $probe = Invoke-BypassProbe -Operator $operator -ScriptPath $script:unitRunner `
                -ArgumentText $unitTimeoutText -Preamble $preamble -DriverPath $driver
            $probe.ExitCode | Should -Be 13 -Because "$operator '$($script:unitRunner)' produced: $($probe.Output)"
            $probe.Output | Should -Match 'FocusedTimeout'
        }

        foreach ($operator in @('&', '.')) {
            $driver = Join-Path $fixtureRoot ("driver-validate-" + ($operator -replace '\W', 'x') + '.ps1')
            $probe = Invoke-BypassProbe -Operator $operator -ScriptPath $script:validator `
                -ArgumentText "-Path 'package.json' -FocusedWarningSeconds 0.05 -FocusedTimeoutSeconds 0.1" `
                -Preamble $preamble -DriverPath $driver
            $probe.ExitCode | Should -Be 13 -Because "$operator '$($script:validator)' produced: $($probe.Output)"
            $probe.Output | Should -Match 'FocusedTimeout'
        }

        $driver = Join-Path $fixtureRoot 'driver-eval.ps1'
        $evalProbe = Invoke-BypassProbe -Operator '&' -ScriptPath $script:evalRunner `
            -ArgumentText "-Plugin 'plugin-manager' -FocusedWarningSeconds 0.05 -FocusedTimeoutSeconds 0.1" `
            -Preamble $preamble -DriverPath $driver
        $evalProbe.ExitCode | Should -Be 13 -Because $evalProbe.Output
        $evalProbe.Output | Should -Match 'FocusedTimeout'

        Test-Path -LiteralPath $decoyMarker |
            Should -BeFalse -Because 'no environment value names the script the supervised child executes'

        # The supervised path still runs the requested work rather than only refusing it.
        $supervisedPass = Invoke-CapturedPowerShell -ArgumentList @(
            '-File', $script:unitRunner, '-RepoRoot', $fixtureRoot,
            '-TestPath', 'tests/Fast.Tests.ps1')
        $supervisedPass.ExitCode | Should -Be 0 -Because $supervisedPass.Output
        $supervisedPass.Output | Should -Match 'Suite tier: Fast focused \(1 file\(s\)\)'
        $supervisedPass.Output | Should -Match 'Tests Passed: 1, Failed: 0'

        # REQ-5: a -TestName filter that selects nothing must report that it could not test.
        $zeroName = Invoke-CapturedPowerShell -ArgumentList @(
            '-File', $script:unitRunner, '-RepoRoot', $fixtureRoot,
            '-TestPath', 'tests/Fast.Tests.ps1', '-TestName', 'no such focused case')
        $zeroName.ExitCode | Should -Be 3 -Because $zeroName.Output
        $zeroName.Output | Should -Match 'NoTestsDiscovered'
        $zeroName.Output | Should -Match 'matched 0 runnable test'
    }

    It 'test:LocalFirst.ActiveAuthorityReferences keeps the corrected architecture notes free of removed workflow authority' {
        # Path-specific on purpose. Parked explorations and the write-scope denylists legitimately
        # name `.github/workflows`; the active architecture notes are the surface that stopped
        # being true when the workflows were removed, so only they are asserted here.
        $authorityRoot = Join-Path $script:repoRoot 'docs/design-notes/architecture'
        $authorityFiles = @(Get-ChildItem -LiteralPath $authorityRoot -File -Filter '*.design.md')
        $authorityFiles.Count | Should -BeGreaterThan 5

        foreach ($required in @('autopilot-execution.design.md', 'review-reporting.design.md',
                'plugin-evals.design.md')) {
            @($authorityFiles | Where-Object { $_.Name -eq $required }).Count |
                Should -Be 1 -Because "$required is corrected active authority and must stay in the scanned set"
        }

        $removedAuthority = [ordered]@{
            'names a removed workflow file' = 'registry-ci\.yml|autopilot-container-ci\.yml'
            'claims a hosted matrix or CI leg' = '(?i)matrix legs?|\bCI legs?\b|platform legs'
            'claims a workflow carries or uploads run output' = '(?i)workflow (uploads|carries)'
            'claims production or CI execution' = '(?i)for local use and CI|Production and CI|CI/unattended|unattended/CI|dev/CI|autopilot/CI|\bCI step\b'
        }

        $stale = [System.Collections.Generic.List[string]]::new()
        foreach ($file in $authorityFiles) {
            $lines = @(Get-Content -LiteralPath $file.FullName)
            for ($index = 0; $index -lt $lines.Count; $index++) {
                foreach ($rule in $removedAuthority.GetEnumerator()) {
                    if ($lines[$index] -match $rule.Value) {
                        $stale.Add("$($file.Name):$($index + 1) $($rule.Key)")
                    }
                }
            }
        }
        ($stale | Sort-Object -Unique) -join "`n" |
            Should -BeExactly '' -Because 'active architecture notes may not assert authority the removed workflows carried'

        # The identifiers that merely contain the letters CI are names, not workflow claims, and
        # must survive the correction.
        $evalNotes = Get-Content -LiteralPath (Join-Path $authorityRoot 'plugin-evals.design.md') -Raw
        $evalNotes | Should -Match 'eval:FleetDispatch\.CI\.ConsumerContract'
        $evalNotes | Should -Match 'eval:FleetDispatch\.CIP\.ConsumerContract'
    }

    It 'test:LocalFirst.PackageScriptReferences keeps active guidance free of removed npm aliases' {
        # Guidance surfaces only. Measurement tooling under scripts/ is owned by the separately
        # tracked tier/profile cleanup and is not corrected here.
        $package = Get-Content -LiteralPath (Join-Path $script:repoRoot 'package.json') -Raw |
            ConvertFrom-Json
        $declared = [System.Collections.Generic.HashSet[string]]::new(
            [string[]]@($package.scripts.PSObject.Properties.Name), [System.StringComparer]::Ordinal)
        $declared.Count | Should -BeGreaterThan 0

        $extensions = @('.md', '.json', '.yaml', '.yml', '.ps1', '.psm1')
        $files = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
        $files.Add((Get-Item -LiteralPath (Join-Path $script:repoRoot 'README.md')))
        foreach ($root in @('docs/design-notes', 'docs/architecture-notes', '.github', 'plugins')) {
            $rootPath = Join-Path $script:repoRoot $root
            if (-not (Test-Path -LiteralPath $rootPath -PathType Container)) { continue }
            foreach ($file in Get-ChildItem -LiteralPath $rootPath -Recurse -File) {
                if ($extensions -contains $file.Extension) { $files.Add($file) }
            }
        }
        $files.Count | Should -BeGreaterThan 50

        $stale = [System.Collections.Generic.List[string]]::new()
        foreach ($file in $files) {
            $text = Get-Content -LiteralPath $file.FullName -Raw
            if ([string]::IsNullOrEmpty($text)) { continue }
            foreach ($match in [regex]::Matches($text, 'npm run (?<name>[A-Za-z0-9:_-]+)')) {
                $name = [string]$match.Groups['name'].Value
                if (-not $declared.Contains($name)) {
                    $stale.Add("$($file.FullName): npm run $name")
                }
            }
            if ($text -match 'npm test' -and -not $declared.Contains('test')) {
                $stale.Add("$($file.FullName): npm test")
            }
        }
        ($stale | Sort-Object -Unique) -join "`n" |
            Should -BeExactly '' -Because 'active guidance may only name package scripts that exist'
    }
}
