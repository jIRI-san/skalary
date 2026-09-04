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

        $missingUnit = Invoke-CapturedPowerShell -ArgumentList @('-File', $script:unitRunner)
        $missingUnit.ExitCode | Should -Be 12
        $missingUnit.Output | Should -Match 'FocusedScopeRequired'

        $missingEval = Invoke-CapturedPowerShell -ArgumentList @('-File', $script:evalRunner)
        $missingEval.ExitCode | Should -Be 12
        $missingEval.Output | Should -Match 'FocusedScopeRequired'

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
$nestedEvalDir = Join-Path $fixtureRoot 'plugins/selected/nested/evals'
[void](New-Item -ItemType Directory -Path $nestedEvalDir -Force)
@"
Describe 'nested trap' {
    It 'fails' { `$false | Should -BeTrue }
}
"@ | Set-Content -LiteralPath (Join-Path $nestedEvalDir 'trap.Tests.ps1') -Encoding utf8NoBOM
"# Required structural evals`n" |
    Set-Content -LiteralPath (Join-Path $fixtureRoot 'tools/required.md') -Encoding utf8NoBOM

        $selectedEval = Invoke-CapturedPowerShell -ArgumentList @(
            '-File', $script:evalRunner,
            '-RepoRoot', $fixtureRoot,
            '-PluginsRoot', (Join-Path $fixtureRoot 'plugins'),
            '-RequiredListPath', (Join-Path $fixtureRoot 'tools/required.md'),
            '-OutputRoot', (Join-Path $fixtureRoot 'tests/evals/output'),
            '-Plugin', 'selected'
        )
        $selectedEval.ExitCode | Should -Be 0 -Because $selectedEval.Output
        $selectedEval.Output | Should -Match 'total: 1'
        $selectedEval.Output | Should -Not -Match 'unselected'
        $selectedEval.Output | Should -Not -Match 'nested trap'

    }

    It 'rejects invalid selected content and empty structural evals' {
        $invalidRelative = 'artifacts/focused-invalid-' + [guid]::NewGuid().ToString('N') + '.json'
        $invalidJson = Join-Path $script:repoRoot $invalidRelative
        [void](New-Item -ItemType Directory -Path (Split-Path -Parent $invalidJson) -Force)
        try {
            Set-Content -LiteralPath $invalidJson -Value '{ invalid' -Encoding utf8NoBOM
            $invalidValidation = Invoke-CapturedPowerShell -ArgumentList @(
                '-File', $script:validator, '-Path', $invalidRelative
            )
            $invalidValidation.ExitCode | Should -Be 1
            $invalidValidation.Output | Should -Match 'invalid JSON'
        }
        finally {
            Remove-Item -LiteralPath $invalidJson -Force -ErrorAction SilentlyContinue
        }

        $fixtureRoot = Join-Path $TestDrive 'empty-eval-repo'
        [void](New-Item -ItemType Directory -Path (Join-Path $fixtureRoot 'plugins/empty/evals') -Force)
        [void](New-Item -ItemType Directory -Path (Join-Path $fixtureRoot 'tests/evals/output') -Force)
        Set-Content -LiteralPath (Join-Path $fixtureRoot 'plugins/empty/evals/empty.Tests.ps1') `
            -Value '# intentionally declares no tests' -Encoding utf8NoBOM
        $emptyEval = Invoke-CapturedPowerShell -ArgumentList @(
            '-File', $script:evalRunner,
            '-RepoRoot', $fixtureRoot,
            '-PluginsRoot', (Join-Path $fixtureRoot 'plugins'),
            '-OutputRoot', (Join-Path $fixtureRoot 'tests/evals/output'),
            '-Plugin', 'empty'
        )
        $emptyEval.ExitCode | Should -Be 3
        $emptyEval.Output | Should -Match 'NoEvalsDiscovered'

        [void](New-Item -ItemType Directory -Path (Join-Path $fixtureRoot 'plugins/broken/evals') -Force)
        Set-Content -LiteralPath (Join-Path $fixtureRoot 'plugins/broken/evals/broken.Tests.ps1') `
            -Value 'this is not valid PowerShell {' -Encoding utf8NoBOM
        $brokenEval = Invoke-CapturedPowerShell -ArgumentList @(
            '-File', $script:evalRunner,
            '-RepoRoot', $fixtureRoot,
            '-PluginsRoot', (Join-Path $fixtureRoot 'plugins'),
            '-OutputRoot', (Join-Path $fixtureRoot 'tests/evals/output'),
            '-Plugin', 'broken'
        )
        $brokenEval.ExitCode | Should -Be 3
        $brokenEval.Output | Should -Match 'NoEvalsDiscovered'

        $expandedEval = Invoke-CapturedPowerShell -ArgumentList @(
            '-File', $script:evalRunner,
            '-RepoRoot', $fixtureRoot,
            '-PluginsRoot', $fixtureRoot,
            '-OutputRoot', (Join-Path $fixtureRoot 'tests/evals/output'),
            '-Plugin', 'plugins'
        )
        $expandedEval.ExitCode | Should -Be 12
        $expandedEval.Output | Should -Match 'require the repository plugins directory'
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
        $validatorText | Should -Not -Match 'Test-ArchitectureContractIntegrity\.ps1|architecture-contract-integrity'
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

        $pluginRoot = Join-Path $wazaFixture 'plugins/selected'
        $outsideEvals = Join-Path $TestDrive 'outside-evals'
        [void](New-Item -ItemType Directory -Path $pluginRoot -Force)
        [void](New-Item -ItemType Directory -Path (Join-Path $outsideEvals 'waza') -Force)
        Set-Content -LiteralPath (Join-Path $outsideEvals 'waza/eval.yaml') -Value 'tasks: []'
        [void](New-Item -ItemType $(if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }) `
                -Path (Join-Path $pluginRoot 'evals') -Target $outsideEvals)
        . (Join-Path $script:repoRoot 'scripts/skalary/Invoke-WazaEvals.ps1')
        {
            Assert-WazaFocusedScope -RepoRoot $wazaFixture -Plugin selected
        } | Should -Throw '*must not traverse a link or reparse point*'

        $callers = Get-ChildItem -LiteralPath (Join-Path $script:repoRoot 'plugins') -Recurse -File |
            Where-Object { $_.Extension -in @('.md', '.ps1') } |
            ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }
        ($callers -join "`n") | Should -Not -Match 'Run-UnitTests\.ps1[^\r\n]*-FullRepository'
        ($callers -join "`n") | Should -Not -Match 'npm run eval:llm'

        $simplicity = Get-Content -LiteralPath (
            Join-Path $script:repoRoot 'docs/design-notes/project/simplicity-first.design.md'
        ) -Raw
        $instructions = Get-Content -LiteralPath (
            Join-Path $script:repoRoot '.github/copilot-instructions.md'
        ) -Raw
        $cr = Get-Content -LiteralPath (
            Join-Path $script:repoRoot 'plugins/code-review/skills/cr/SKILL.md'
        ) -Raw
        $dr = Get-Content -LiteralPath (
            Join-Path $script:repoRoot 'plugins/design-review/skills/dr/SKILL.md'
        ) -Raw
        foreach ($text in @($simplicity, $instructions, $cr, $dr)) {
            $text | Should -Match '(?i)simplicity'
            $text | Should -Match '(?i)deletion, reuse, or a local fix'
        }
        $simplicity | Should -Match '/dr.*?/cr.*?cannot override'
        $simplicity | Should -Match '## Dubious decisions'
        $normalizedSimplicity = $simplicity -replace '\s+', ' '
        $normalizedSimplicity | Should -Match 'trusted local environment'
        foreach ($revisitCondition in @(
                'untrusted contributors',
                'shared service',
                'third-party credentials',
                'trust boundary'
            )) {
            $normalizedSimplicity | Should -Match $revisitCondition
        }

        $readme = Get-Content -LiteralPath (Join-Path $script:repoRoot 'README.md') -Raw
        $readme | Should -Match '(?s)`code-review` and `design-review`.*PowerShell 7\.6\+'
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
            $script:unitRunner = @('RepoRoot', 'TestPath', 'TestName', 'EvidenceTestId',
                'EvidenceResultPath', 'FullRepository', 'TestResultPath',
                'FocusedWarningSeconds', 'FocusedTimeoutSeconds')
            $script:evalRunner = @('RepoRoot', 'OutputRoot', 'PluginsRoot', 'RequiredListPath',
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
        foreach ($path in @($script:unitRunner, $script:evalRunner, $script:validator)) {
            $text = Get-Content -LiteralPath $path -Raw
            $text | Should -Match '\$FocusedWarningSeconds\s*=\s*30'
            $text | Should -Match '\$FocusedTimeoutSeconds\s*=\s*60'
        }

        # Public dispatch must not read a caller-controlled variable or environment value at all.
        foreach ($path in @($script:unitRunner, $script:evalRunner, $script:validator)) {
            $text = Get-Content -LiteralPath $path -Raw
            $text | Should -Not -Match '(?im)^\s*[^#\r\n]*Get-Variable'
            $text | Should -Not -Match '(?im)^\s*[^#\r\n]*\$env:'
            $text | Should -Not -Match '(?im)^\s*[^#\r\n]*GetEnvironmentVariable'
            $text | Should -Match 'InvokeSupervisedBody'
        }

        # The supervised child runs a private body, never the public command again.
        $internalRoot = Join-Path $script:repoRoot 'scripts/skalary/internal'
        Test-Path -LiteralPath $internalRoot -PathType Container | Should -BeTrue
        foreach ($body in @(Get-ChildItem -LiteralPath $internalRoot -File -Filter '*.ps1')) {
            $bodyText = Get-Content -LiteralPath $body.FullName -Raw
            $bodyText | Should -Not -Match '(?im)^\s*[.&]\s+[^\r\n]*(?:Run-UnitTests|Test-Evals|validate)\.ps1' `
                -Because "$($body.Name) must not re-enter public dispatch"
        }

        $fixtureRoot = Join-Path $TestDrive 'supervision-repo'
        [void](New-Item -ItemType Directory -Path (Join-Path $fixtureRoot 'tests') -Force)
        $pidFile = Join-Path $fixtureRoot 'descendant.pid'
        $timeoutBody = Join-Path $fixtureRoot 'timeout-body.ps1'
        Set-Content -LiteralPath $timeoutBody -Encoding utf8NoBOM -Value @'
$request = [System.Console]::In.ReadToEnd() |
    Microsoft.PowerShell.Utility\ConvertFrom-Json
$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = [System.Environment]::ProcessPath
$startInfo.UseShellExecute = $false
foreach ($argument in @('-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 30')) {
    [void]$startInfo.ArgumentList.Add($argument)
}
$child = [System.Diagnostics.Process]::Start($startInfo)
[System.IO.File]::WriteAllText([string]$request.PidFile, [string]$child.Id)
Start-Sleep -Seconds 30
'@
        Set-Content -LiteralPath (Join-Path $fixtureRoot 'tests/Fast.Tests.ps1') -Encoding utf8NoBOM -Value @'
Describe 'fast' {
    It 'test:BypassProbe.Runnable passes' { $true | Should -BeTrue }
}
'@

        $supervision = & (Join-Path $script:repoRoot 'scripts/skalary/internal/FocusedSupervision.ps1')
        $missingBodyCode = & $supervision.InvokeSupervisedBody `
            -BodyPath (Join-Path $fixtureRoot 'missing-body.ps1') -Request @{} `
            -Label 'missing worker probe' -WarningSeconds 0.2 -TimeoutSeconds 2
        $missingBodyCode | Should -Be 14
        (Get-Content -LiteralPath (
                Join-Path $script:repoRoot 'scripts/skalary/internal/FocusedSupervision.ps1'
            ) -Raw) | Should -Match 'FocusedWorkerStartFailed'

        $timeoutCode = & $supervision.InvokeSupervisedBody -BodyPath $timeoutBody `
            -Request @{ PidFile = $pidFile } -Label 'timeout probe' `
            -WarningSeconds 0.2 -TimeoutSeconds 2
        $timeoutCode | Should -Be 13
        Test-Path -LiteralPath $pidFile -PathType Leaf | Should -BeTrue
        $descendantPid = [int](Get-Content -LiteralPath $pidFile -Raw)
        $deadline = [datetime]::UtcNow.AddSeconds(2)
        do {
            $descendant = Get-Process -Id $descendantPid -ErrorAction SilentlyContinue
            if ($null -eq $descendant) { break }
            Start-Sleep -Milliseconds 50
        } while ([datetime]::UtcNow -lt $deadline)
        $descendant |
            Should -BeNullOrEmpty -Because 'the timeout terminates the current child process tree'

        Set-Content -LiteralPath (Join-Path $fixtureRoot 'tests/Slow.Tests.ps1') -Encoding utf8NoBOM -Value @'
Describe 'slow' {
    It 'waits' { Start-Sleep -Seconds 30 }
}
'@
        $publicTimeout = Invoke-CapturedPowerShell -ArgumentList @(
            '-File', $script:unitRunner, '-RepoRoot', $fixtureRoot,
            '-TestPath', 'tests/Slow.Tests.ps1',
            '-FocusedWarningSeconds', '0.2', '-FocusedTimeoutSeconds', '2'
        )
        $publicTimeout.ExitCode | Should -Be 13
        $publicTimeout.Output | Should -Match 'FocusedTimeout'

        # The supervised path still runs the requested work rather than only refusing it.
        $supervisedPass = Invoke-CapturedPowerShell -ArgumentList @(
            '-File', $script:unitRunner, '-RepoRoot', $fixtureRoot,
            '-TestPath', 'tests/Fast.Tests.ps1',
            '-FocusedWarningSeconds', '0.05', '-FocusedTimeoutSeconds', '5')
        $supervisedPass.ExitCode | Should -Be 0 -Because $supervisedPass.Output
        $supervisedPass.Output | Should -Match 'Unit tests: focused \(1 file\(s\)\)'
        $supervisedPass.Output | Should -Match 'FocusedSlow'

        if (-not $IsWindows) {
            Copy-Item -LiteralPath (Join-Path $fixtureRoot 'tests/Fast.Tests.ps1') `
                -Destination (Join-Path $fixtureRoot 'tests/Fast.tests.ps1')
            $wrongCase = Invoke-CapturedPowerShell -ArgumentList @(
                '-File', $script:unitRunner, '-RepoRoot', $fixtureRoot,
                '-TestPath', 'tests/Fast.tests.ps1')
            $wrongCase.ExitCode | Should -Be 12
            $wrongCase.Output | Should -Match 'must name a \*\.Tests\.ps1 file'
        }

        # REQ-5: a -TestName filter that selects nothing must report that it could not test.
        $zeroName = Invoke-CapturedPowerShell -ArgumentList @(
            '-File', $script:unitRunner, '-RepoRoot', $fixtureRoot,
            '-TestPath', 'tests/Fast.Tests.ps1', '-TestName', 'no such focused case')
        $zeroName.ExitCode | Should -Be 3 -Because $zeroName.Output
        $zeroName.Output | Should -Match 'NoTestsDiscovered'
        $zeroName.Output | Should -Match 'matched 0 runnable test'

        . (Join-Path $script:repoRoot 'scripts/skalary/internal/Invoke-UnitTestRun.ps1')
        {
            Resolve-ConfinedRegularPath -Root $fixtureRoot `
                -Path (Join-Path ([System.IO.Path]::GetTempPath()) 'outside.xml') `
                -Label 'Test result path' -AllowMissing
        } | Should -Throw '*must stay inside the repository*'
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
        $package = Get-Content -LiteralPath (Join-Path $script:repoRoot 'package.json') -Raw |
            ConvertFrom-Json
        $declared = [System.Collections.Generic.HashSet[string]]::new(
            [string[]]@($package.scripts.PSObject.Properties.Name), [System.StringComparer]::Ordinal)
        $declared.Count | Should -BeGreaterThan 0

        $guidancePaths = @(
            'README.md',
            'docs/design-notes/project/ci-gates.design.md',
            'docs/design-notes/architecture/plugin-evals.design.md',
            'docs/architecture-notes/arch-eval-gate-separation.md'
        )
        $stale = [System.Collections.Generic.List[string]]::new()
        foreach ($relativePath in $guidancePaths) {
            $text = Get-Content -LiteralPath (Join-Path $script:repoRoot $relativePath) -Raw
            if ([string]::IsNullOrEmpty($text)) { continue }
            foreach ($match in [regex]::Matches($text, 'npm run (?<name>[A-Za-z0-9:_-]+)')) {
                $name = [string]$match.Groups['name'].Value
                if (-not $declared.Contains($name)) {
                    $stale.Add("${relativePath}: npm run $name")
                }
            }
            if ($text -match 'npm test' -and -not $declared.Contains('test')) {
                $stale.Add("${relativePath}: npm test")
            }
        }
        ($stale | Sort-Object -Unique) -join "`n" |
            Should -BeExactly '' -Because 'active guidance may only name package scripts that exist'
    }
}
