#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'focused supervision containment invariants' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:unitRunner = Join-Path $script:repoRoot 'scripts/skalary/Run-UnitTests.ps1'
        $script:evalRunner = Join-Path $script:repoRoot 'scripts/skalary/Test-Evals.ps1'
        $script:validator = Join-Path $script:repoRoot 'scripts/validate.ps1'
        $script:supervisionPath = Join-Path $script:repoRoot 'scripts/skalary/internal/FocusedSupervision.ps1'
        $script:supervisionText = Get-Content -LiteralPath $script:supervisionPath -Raw

        function Invoke-CapturedPowerShell {
            param([Parameter(Mandatory)][string[]]$ArgumentList)

            $output = & pwsh -NoProfile @ArgumentList 2>&1
            # 0x1B is not valid XML, and escape sequences captured from a child are written
            # verbatim into the NUnit report when a case fails: the report is lost exactly when
            # it is needed. Strip them here rather than in every assertion.
            $text = ($output | Out-String) -replace '\x1b\[[0-9;]*[a-zA-Z]', '' -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', ''
            return [pscustomobject]@{
                ExitCode = $LASTEXITCODE
                Output = $text
            }
        }

        function New-FocusedFixtureRoot {
            param([Parameter(Mandatory)][string]$Path)

            [void](New-Item -ItemType Directory -Path (Join-Path $Path 'tests') -Force)
            [void](New-Item -ItemType Directory -Path (Join-Path $Path 'tools') -Force)
            Set-Content -LiteralPath (Join-Path $Path 'tools/suite-tier.psd1') -Encoding utf8NoBOM -Value @'
@{
    Schema = 'skalary/suite-tier@1'
    FastFocusedHardCeilingSeconds = 60
    SlowHardCeilingSeconds = 600
    CiSetupAllowanceSeconds = 60
    DedicatedFiles = @()
    SlowFiles = @()
}
'@
            return $Path
        }

        function Wait-ForFile {
            param(
                [Parameter(Mandatory)][string]$Path,
                [int]$TimeoutMilliseconds = 20000
            )

            $clock = [System.Diagnostics.Stopwatch]::StartNew()
            while ($clock.ElapsedMilliseconds -lt $TimeoutMilliseconds) {
                if (Test-Path -LiteralPath $Path -PathType Leaf) {
                    $text = (Get-Content -LiteralPath $Path -Raw)
                    if (-not [string]::IsNullOrWhiteSpace($text)) { return $text.Trim() }
                }
                Start-Sleep -Milliseconds 50
            }
            return $null
        }

        function Test-ProcessAlive {
            param([Parameter(Mandatory)][int]$ProcessId)

            $found = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
            if ($null -eq $found) { return $false }
            return -not $found.HasExited
        }

        function Wait-ForProcessExit {
            param(
                [Parameter(Mandatory)][int]$ProcessId,
                [int]$TimeoutMilliseconds = 10000
            )

            $clock = [System.Diagnostics.Stopwatch]::StartNew()
            while ($clock.ElapsedMilliseconds -lt $TimeoutMilliseconds) {
                if (-not (Test-ProcessAlive -ProcessId $ProcessId)) { return $true }
                Start-Sleep -Milliseconds 50
            }
            return $false
        }

        function Start-UnrelatedSleeper {
            $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
            $startInfo.FileName = [System.Environment]::ProcessPath
            $startInfo.UseShellExecute = $false
            $startInfo.RedirectStandardOutput = $true
            $startInfo.RedirectStandardError = $true
            foreach ($argument in @('-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 45')) {
                [void]$startInfo.ArgumentList.Add($argument)
            }
            return [System.Diagnostics.Process]::Start($startInfo)
        }
    }

    It 'test:FocusedContainment.NoCommandResolution keeps every supervision step off command-name lookup' {
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $script:supervisionPath, [ref]$tokens, [ref]$parseErrors)
        @($parseErrors).Count | Should -Be 0

        # Every invocation in the supervision helper must be a scriptblock held in a variable or
        # a script addressed by path. A bare command name is resolvable by an alias or function
        # in the calling session, which is exactly the hijack this file must not be open to.
        $named = [System.Collections.Generic.List[string]]::new()
        foreach ($command in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)) {
            $first = $command.CommandElements[0]
            if ($first -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                $named.Add([string]$first.Value)
            }
        }
        ($named | Sort-Object -Unique) -join ',' |
            Should -BeExactly '' -Because 'the supervision helper must invoke no command by name'

        foreach ($path in @($script:unitRunner, $script:evalRunner, $script:validator)) {
            $text = Get-Content -LiteralPath $path -Raw
            $text | Should -Not -Match '(?m)^[^#\r\n]*Get-Process'
            $text | Should -Not -Match '(?m)^[^#\r\n]*Start-Process'
            $text | Should -Match '&\s+\$supervision\.InvokeSupervisedBody'
            $text | Should -Not -Match 'Invoke-SkalarySupervisedBody'
        }

        foreach ($body in @('Invoke-UnitTestRun.ps1', 'Invoke-EvalRun.ps1', 'Invoke-FocusedValidation.ps1')) {
            $bodyText = Get-Content -LiteralPath (
                Join-Path $script:repoRoot "scripts/skalary/internal/$body") -Raw
            $bodyText | Should -Match '&\s+\$supervision\.ReadBodyRequest'
            $bodyText | Should -Not -Match 'Read-SkalaryBodyRequest'
        }
    }

    It 'test:FocusedContainment.PoisonedCommandsCannotRedirect survives function and alias hijacking of every dispatch step' {
        $fixtureRoot = New-FocusedFixtureRoot -Path (Join-Path $TestDrive 'poison-repo')
        Set-Content -LiteralPath (Join-Path $fixtureRoot 'tests/Sleeper.Tests.ps1') -Encoding utf8NoBOM -Value @'
Describe 'sleeper' {
    It 'test:PoisonProbe.Sleeps outlives the focused timeout' { Start-Sleep -Seconds 30 }
}
'@
        Set-Content -LiteralPath (Join-Path $fixtureRoot 'tests/Fast.Tests.ps1') -Encoding utf8NoBOM -Value @'
Describe 'fast' {
    It 'test:PoisonProbe.Runnable passes' { $true | Should -BeTrue }
}
'@

        $marker = Join-Path $fixtureRoot 'poison-ran.txt'
        # Aliases outrank functions in command resolution, so both forms are seeded for every
        # name the dispatch could plausibly have resolved: host discovery, path building, the
        # request encoder, the output writer, and the supervision entry points themselves.
        $poisonNames = @(
            'Get-Process', 'Start-Process', 'Stop-Process', 'Wait-Process',
            'Join-Path', 'Split-Path', 'Resolve-Path', 'Test-Path', 'Convert-Path',
            'Get-Item', 'Get-ChildItem', 'Get-Content', 'Set-Content', 'Out-File',
            'Write-Host', 'Write-Warning', 'Write-Output', 'Out-String', 'Out-Null',
            'ConvertTo-Json', 'ConvertFrom-Json', 'New-Object', 'Add-Type',
            'Get-Command', 'Invoke-Expression', 'Import-Module', 'Start-Sleep',
            'ForEach-Object', 'Where-Object', 'Select-Object', 'Sort-Object',
            'Invoke-SkalarySupervisedBody', 'Read-SkalaryBodyRequest',
            'Write-SkalaryChildOutput', 'ConvertTo-SkalaryAsciiRequest',
            'Invoke-SkalaryUnitTestRun', 'Invoke-SkalaryEvalRun',
            'Invoke-SkalaryFocusedValidation'
        )

        $preamble = [System.Collections.Generic.List[string]]::new()
        $preamble.Add('$PSStyle.OutputRendering = ''PlainText''')
        $preamble.Add('function Invoke-SkalaryPoison {')
        $preamble.Add("    [System.IO.File]::AppendAllText('$marker', 'ran')")
        $preamble.Add('    return 0')
        $preamble.Add('}')
        foreach ($name in $poisonNames) {
            $preamble.Add("function global:$name { Invoke-SkalaryPoison }")
            $preamble.Add("Set-Alias -Name '$name' -Value Invoke-SkalaryPoison -Scope Global -Force")
        }

        function Invoke-PoisonedProbe {
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

        # A poisoned session must still be timed out at the bound rather than answered by the
        # decoy, through both host forms a caller can reach a script by besides -File.
        foreach ($operator in @('&', '.')) {
            $probe = Invoke-PoisonedProbe -Operator $operator -ScriptPath $script:validator `
                -ArgumentText "-Path 'package.json' -FocusedWarningSeconds 0.05 -FocusedTimeoutSeconds 0.1" `
                -Preamble $preamble `
                -DriverPath (Join-Path $fixtureRoot ("driver-validate-" + ($operator -replace '\W', 'x') + '.ps1'))
            $probe.ExitCode | Should -Be 13 -Because $probe.Output
            $probe.Output | Should -Match 'FocusedTimeout'
        }

        $unitProbe = Invoke-PoisonedProbe -Operator '&' -ScriptPath $script:unitRunner `
            -ArgumentText ("-RepoRoot '$fixtureRoot' -TestPath 'tests/Sleeper.Tests.ps1' " +
                '-FocusedWarningSeconds 0.2 -FocusedTimeoutSeconds 1.5') `
            -Preamble $preamble -DriverPath (Join-Path $fixtureRoot 'driver-unit-timeout.ps1')
        $unitProbe.ExitCode | Should -Be 13 -Because $unitProbe.Output
        $unitProbe.Output | Should -Match 'FocusedTimeout'

        $evalProbe = Invoke-PoisonedProbe -Operator '&' -ScriptPath $script:evalRunner `
            -ArgumentText "-Plugin 'plugin-manager' -FocusedWarningSeconds 0.05 -FocusedTimeoutSeconds 0.1" `
            -Preamble $preamble -DriverPath (Join-Path $fixtureRoot 'driver-eval.ps1')
        $evalProbe.ExitCode | Should -Be 13 -Because $evalProbe.Output
        $evalProbe.Output | Should -Match 'FocusedTimeout'

        # And a poisoned session must still run the real work, not merely refuse it.
        $unitPass = Invoke-PoisonedProbe -Operator '&' -ScriptPath $script:unitRunner `
            -ArgumentText "-RepoRoot '$fixtureRoot' -TestPath 'tests/Fast.Tests.ps1'" `
            -Preamble $preamble -DriverPath (Join-Path $fixtureRoot 'driver-unit-pass.ps1')
        $unitPass.ExitCode | Should -Be 0 -Because $unitPass.Output
        $unitPass.Output | Should -Match 'Tests Passed: 1, Failed: 0'

        $validatePass = Invoke-PoisonedProbe -Operator '&' -ScriptPath $script:validator `
            -ArgumentText "-Path 'package.json'" `
            -Preamble $preamble -DriverPath (Join-Path $fixtureRoot 'driver-validate-pass.ps1')
        $validatePass.ExitCode | Should -Be 0 -Because $validatePass.Output
        $validatePass.Output | Should -Match 'Validation passed'

        Test-Path -LiteralPath $marker |
            Should -BeFalse -Because 'no supervision step is selected by a name a caller can bind'
    }

    It 'test:FocusedContainment.LeakyDescendantRootExitTimesOut bounds a run whose root exits leaving a descendant on the output pipes' {
        $fixtureRoot = New-FocusedFixtureRoot -Path (Join-Path $TestDrive 'leaky-repo')
        $pidFile = (Join-Path $fixtureRoot 'descendant.pid') -replace '\\', '/'
        Set-Content -LiteralPath (Join-Path $fixtureRoot 'tests/Leaky.Tests.ps1') -Encoding utf8NoBOM -Value @"
Describe 'leaky descendant' {
    It 'test:LeakyProbe.Spawns leaves a descendant holding the inherited output pipes' {
        `$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        `$startInfo.FileName = [System.Environment]::ProcessPath
        `$startInfo.UseShellExecute = `$false
        foreach (`$argument in @('-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 45')) {
            [void]`$startInfo.ArgumentList.Add(`$argument)
        }
        `$descendant = [System.Diagnostics.Process]::Start(`$startInfo)
        [System.IO.File]::WriteAllText('$pidFile', [string]`$descendant.Id)
        `$true | Should -BeTrue
    }
}
"@

        $unrelated = Start-UnrelatedSleeper
        try {
            $timedOut = Invoke-CapturedPowerShell -ArgumentList @(
                '-File', $script:unitRunner,
                '-RepoRoot', $fixtureRoot,
                '-TestPath', 'tests/Leaky.Tests.ps1',
                '-FocusedWarningSeconds', '0.5',
                '-FocusedTimeoutSeconds', '8'
            )

            # The root exits on its own well inside the bound; only the descendant keeps the run
            # alive, and the one deadline must still close it.
            $timedOut.ExitCode | Should -Be 13 -Because $timedOut.Output
            $timedOut.Output | Should -Match 'FocusedTimeout'
            $timedOut.Output | Should -Not -Match 'FocusedSlow' -Because 'a killed run is never reported as a slow completion'
            $timedOut.Output | Should -Match 'Tests Passed: 1' -Because 'output completed after termination is still reported'

            $descendantPid = Wait-ForFile -Path ($pidFile -replace '/', [System.IO.Path]::DirectorySeparatorChar) -TimeoutMilliseconds 2000
            $descendantPid | Should -Not -BeNullOrEmpty
            Wait-ForProcessExit -ProcessId ([int]$descendantPid) |
                Should -BeTrue -Because 'the owned containment terminates descendants the exited root left behind'

            Test-ProcessAlive -ProcessId $unrelated.Id |
                Should -BeTrue -Because 'containment terminates only what the focused run created'
        }
        finally {
            try { if (-not $unrelated.HasExited) { $unrelated.Kill($true) } } catch { }
            $unrelated.Dispose()
        }
    }

    It 'test:FocusedContainment.RunningRootTimesOutWithDescendants bounds a still-running root and kills the descendants it detached' {
        $fixtureRoot = New-FocusedFixtureRoot -Path (Join-Path $TestDrive 'running-repo')
        $pidFile = (Join-Path $fixtureRoot 'descendant.pid') -replace '\\', '/'
        # This descendant redirects its own streams, so nothing but process-group ownership can
        # reach it: pipe coupling is deliberately removed from the proof.
        Set-Content -LiteralPath (Join-Path $fixtureRoot 'tests/Running.Tests.ps1') -Encoding utf8NoBOM -Value @"
Describe 'running root' {
    It 'test:RunningProbe.Sleeps starts a detached descendant and keeps running' {
        `$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        `$startInfo.FileName = [System.Environment]::ProcessPath
        `$startInfo.UseShellExecute = `$false
        `$startInfo.RedirectStandardOutput = `$true
        `$startInfo.RedirectStandardError = `$true
        foreach (`$argument in @('-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 45')) {
            [void]`$startInfo.ArgumentList.Add(`$argument)
        }
        `$descendant = [System.Diagnostics.Process]::Start(`$startInfo)
        [System.IO.File]::WriteAllText('$pidFile', [string]`$descendant.Id)
        Start-Sleep -Seconds 45
    }
}
"@

        $unrelated = Start-UnrelatedSleeper
        try {
            $timedOut = Invoke-CapturedPowerShell -ArgumentList @(
                '-File', $script:unitRunner,
                '-RepoRoot', $fixtureRoot,
                '-TestPath', 'tests/Running.Tests.ps1',
                '-FocusedWarningSeconds', '0.5',
                '-FocusedTimeoutSeconds', '8'
            )
            $timedOut.ExitCode | Should -Be 13 -Because $timedOut.Output
            $timedOut.Output | Should -Match 'FocusedTimeout'
            $timedOut.Output | Should -Not -Match 'FocusedSlow'

            $descendantPid = Wait-ForFile -Path ($pidFile -replace '/', [System.IO.Path]::DirectorySeparatorChar) -TimeoutMilliseconds 2000
            $descendantPid | Should -Not -BeNullOrEmpty
            Wait-ForProcessExit -ProcessId ([int]$descendantPid) |
                Should -BeTrue -Because 'the owned containment reaches descendants that share no pipe with the supervisor'

            Test-ProcessAlive -ProcessId $unrelated.Id |
                Should -BeTrue -Because 'containment terminates only what the focused run created'
        }
        finally {
            try { if (-not $unrelated.HasExited) { $unrelated.Kill($true) } } catch { }
            $unrelated.Dispose()
        }
    }

    It 'test:FocusedContainment.CompleteOutputPrecedesSlowWarning reports both streams in full before warning about a slow completion' {
        $fixtureRoot = New-FocusedFixtureRoot -Path (Join-Path $TestDrive 'slow-repo')
        Set-Content -LiteralPath (Join-Path $fixtureRoot 'tests/Slow.Tests.ps1') -Encoding utf8NoBOM -Value @'
Describe 'slow but complete' {
    It 'test:SlowProbe.Emits writes to both streams and passes after the warning threshold' {
        [System.Console]::Out.WriteLine('FOCUSED-STDOUT-MARKER')
        [System.Console]::Out.Flush()
        [System.Console]::Error.WriteLine('FOCUSED-STDERR-MARKER')
        [System.Console]::Error.Flush()
        Start-Sleep -Milliseconds 700
        $true | Should -BeTrue
    }
}
'@
        $slow = Invoke-CapturedPowerShell -ArgumentList @(
            '-File', $script:unitRunner,
            '-RepoRoot', $fixtureRoot,
            '-TestPath', 'tests/Slow.Tests.ps1',
            '-FocusedWarningSeconds', '0.3',
            '-FocusedTimeoutSeconds', '30'
        )
        $slow.ExitCode | Should -Be 0 -Because $slow.Output
        $slow.Output | Should -Match 'FOCUSED-STDOUT-MARKER'
        $slow.Output | Should -Match 'FOCUSED-STDERR-MARKER'
        $slow.Output | Should -Match 'Tests Passed: 1, Failed: 0'
        $slow.Output | Should -Match 'FocusedSlow'
        $slow.Output.IndexOf('FocusedSlow') |
            Should -BeGreaterThan $slow.Output.IndexOf('FOCUSED-STDOUT-MARKER')
        $slow.Output.IndexOf('FocusedSlow') |
            Should -BeGreaterThan $slow.Output.IndexOf('FOCUSED-STDERR-MARKER')
        $slow.Output.IndexOf('FocusedSlow') |
            Should -BeGreaterThan $slow.Output.IndexOf('Tests Passed')
    }

    It 'test:FocusedContainment.OwnsDescendantsAcrossRootExit terminates an owned descendant through the native containment' {
        $supervision = & $script:supervisionPath
        $pidFile = Join-Path $TestDrive 'contained-descendant.pid'
        $childScript = "`$startInfo = [System.Diagnostics.ProcessStartInfo]::new(); " +
            "`$startInfo.FileName = [System.Environment]::ProcessPath; " +
            "`$startInfo.UseShellExecute = `$false; " +
            "`$startInfo.RedirectStandardOutput = `$true; " +
            "`$startInfo.RedirectStandardError = `$true; " +
            "foreach (`$a in @('-NoProfile','-NonInteractive','-Command','Start-Sleep -Seconds 45')) { [void]`$startInfo.ArgumentList.Add(`$a) }; " +
            "`$d = [System.Diagnostics.Process]::Start(`$startInfo); " +
            "[System.IO.File]::WriteAllText('$($pidFile -replace '\\', '/')', [string]`$d.Id); " +
            'Start-Sleep -Seconds 45'

        $contained = & $supervision.StartContainedProcess `
            -ExecutablePath (& $supervision.ResolveHostExecutable) `
            -Arguments @('-NoProfile', '-NonInteractive', '-Command', $childScript)
        try {
            $rootPid = $contained.Process.Id
            $descendantPid = Wait-ForFile -Path $pidFile
            $descendantPid | Should -Not -BeNullOrEmpty -Because 'the contained root must have started its descendant'

            & $contained.Terminate

            Wait-ForProcessExit -ProcessId $rootPid | Should -BeTrue
            Wait-ForProcessExit -ProcessId ([int]$descendantPid) |
                Should -BeTrue -Because 'the job object / process group owns descendants the supervisor never launched itself'
        }
        finally {
            & $contained.Dispose
        }
    }

    It 'test:FocusedContainment.FailsClosedWithoutContainment refuses to run work it could not own' {
        $supervision = & $script:supervisionPath
        $marker = (Join-Path $TestDrive 'contained-ran.txt') -replace '\\', '/'
        $probeArguments = @('-NoProfile', '-NonInteractive', '-Command',
            "[System.IO.File]::WriteAllText('$marker', 'ran'); Start-Sleep -Seconds 20")

        # A host executable that is not an existing absolute leaf fails closed on every platform,
        # before any child exists.
        {
            & $supervision.StartContainedProcess `
                -ExecutablePath (Join-Path $TestDrive 'no-such-host-executable') `
                -Arguments $probeArguments
        } | Should -Throw

        Start-Sleep -Milliseconds 200
        Test-Path -LiteralPath ($marker -replace '/', [System.IO.Path]::DirectorySeparatorChar) |
            Should -BeFalse -Because 'nothing runs when containment cannot be established'

        # The whole focused command reports the closed failure rather than proceeding.
        $resolved = & $supervision.ResolveHostExecutable
        [System.IO.Path]::IsPathFullyQualified($resolved) | Should -BeTrue
        Test-Path -LiteralPath $resolved -PathType Leaf | Should -BeTrue
        [System.IO.Path]::GetFileNameWithoutExtension($resolved) | Should -BeExactly 'pwsh'
    }

    It 'test:FocusedContainment.FailsClosedWithoutSessionLauncher refuses a launcher that is not a validated absolute leaf' -Skip:$IsWindows {
        $supervision = & $script:supervisionPath
        $marker = Join-Path $TestDrive 'launcher-ran.txt'

        $launcher = & $supervision.ResolveSessionLauncher
        [System.IO.Path]::IsPathFullyQualified($launcher) | Should -BeTrue
        Test-Path -LiteralPath $launcher -PathType Leaf | Should -BeTrue

        {
            & $supervision.StartContainedProcess `
                -ExecutablePath (& $supervision.ResolveHostExecutable) `
                -Arguments @('-NoProfile', '-NonInteractive', '-Command',
                    "[System.IO.File]::WriteAllText('$marker', 'ran'); Start-Sleep -Seconds 20") `
                -LauncherPath (Join-Path $TestDrive 'no-such-session-launcher')
        } | Should -Throw -ExpectedMessage '*FocusedContainmentUnavailable*'

        Start-Sleep -Milliseconds 200
        Test-Path -LiteralPath $marker |
            Should -BeFalse -Because 'a session the supervisor cannot create is never released'
    }

    It 'test:FocusedContainment.WindowsJobObjectOwnership pins the Windows containment mechanism and its ordering' {
        # Linux runs the containment above for real; this case keeps the Windows half honest on
        # every platform by pinning the mechanism, the kill-on-close limit, and the fact that
        # assignment completes before the stdin handshake releases the child.
        $text = $script:supervisionText
        foreach ($needle in @(
                'CreateJobObjectW', 'SetInformationJobObject', 'AssignProcessToJobObject',
                'TerminateJobObject', 'CloseHandle', '0x2000')) {
            $text | Should -Match ([regex]::Escape($needle))
        }
        $text | Should -Match 'JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE'

        $assignIndex = $text.IndexOf('$assigned = [int]$native[''AssignProcessToJobObject'']')
        $handshakeIndex = $text.IndexOf('$process.StandardInput.WriteAsync($requestJson)')
        $assignIndex | Should -BeGreaterThan 0
        $handshakeIndex | Should -BeGreaterThan 0
        $assignIndex | Should -BeLessThan $handshakeIndex

        # No process-control command name and no compile-through-a-cmdlet shortcut.
        foreach ($forbidden in @('Get-Process', 'Stop-Process', 'Start-Process', 'Add-Type', 'taskkill')) {
            $text | Should -Not -Match ('(?m)^[^#\r\n]*' + [regex]::Escape($forbidden))
        }

        # The single deadline covers start/handoff/root exit/stdout EOF/stderr EOF, and a
        # result is only ever read from a wait that completed.
        $text | Should -Match 'IsCompletedSuccessfully'
        $text | Should -Match '\$process\.WaitForExit\(\(& \$remaining\)\)'
        $text | Should -Match '& \$waitBounded \$stdoutTask \(& \$remaining\)'
        $text | Should -Match '& \$waitBounded \$stderrTask \(& \$remaining\)'
    }
}
