#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The CI workflow is the only place several of this repo's gates actually run, and it is a
# config file rather than code: nothing else parses it, so a rename, a chained script or a
# dropped step is silent until a release goes out unvalidated. These tests read the workflow
# as the artefact it is — text — and assert the properties REQ-9 names.
Describe 'ci workflow' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:workflowPath = Join-Path $script:repoRoot '.github/workflows/registry-ci.yml'
        # Shared with CiGates.Tests.ps1: one parser for the workflow, because a second copy
        # would be a second thing to drift.
        Import-Module (Join-Path $PSScriptRoot '..' 'CiWorkflow.psm1') -Force -DisableNameChecking
        $script:workflowText = $null
        if (Test-Path -LiteralPath $script:workflowPath -PathType Leaf) {
            $script:workflowText = Get-Content -LiteralPath $script:workflowPath -Raw
        }

        # Each gate the workflow is responsible for, and the invocation that proves it ran. The
        # unit-test pattern excludes the clock-start invocation of the same script: that call
        # writes a timestamp and returns, so counting it as the gate would let the suite be
        # dropped while the check still saw a Run-UnitTests.ps1 line.
        $script:gatePatterns = [ordered]@{
            'PSScriptAnalyzer'       = 'Invoke-ScriptAnalyzer'
            'plan validation'        = 'scripts/skalary/Validate-Plan\.ps1'
            'repository validation'  = 'scripts/validate\.ps1'
            'unit tests and budget'  = 'Run-UnitTests\.ps1(?![^\r\n]*-StartBudgetClock)'
            'registry validation'    = 'Test-Registry\.ps1'
            'dogfood drift'          = 'Sync-Dogfood\.ps1'
            'generated output drift' = 'Build-Registry\.ps1'
        }

        # What makes each gate *fail*, which is not always what names it. The drift gate is
        # `git diff --exit-code`, not the rebuild that precedes it, and a dogfood sync only
        # detects drift with `-WhatIf`. PSScriptAnalyzer is deliberately absent: it writes
        # findings to the output stream and sets no exit code, so its step cannot go red on a
        # finding. That is a real property of the gate rather than an oversight here, and it
        # belongs in the gate inventory as an advisory row rather than in an assertion that
        # would claim an enforcement the step does not have.
        $script:gateEnforcingPatterns = [ordered]@{
            'plan validation'        = 'scripts/skalary/Validate-Plan\.ps1'
            'repository validation'  = 'scripts/validate\.ps1'
            'unit tests and budget'  = 'Run-UnitTests\.ps1(?![^\r\n]*-StartBudgetClock)'
            'registry validation'    = 'Test-Registry\.ps1'
            'dogfood drift'          = 'Sync-Dogfood\.ps1[^\r\n]*-WhatIf'
            'generated output drift' = 'git diff --exit-code'
        }

        function Get-CiJobName {
            param([string]$Text)

            $code = Remove-CiComment -Text $Text
            if ($code -notmatch '(?ms)^jobs:\s*\r?\n(?<body>.*)$') { return @() }
            $body = $Matches['body']
            # A later top-level key would end the jobs block; cut there so its children are not
            # counted as jobs.
            if ($body -match '(?ms)^(?<jobs>.*?)^\S') { $body = $Matches['jobs'] }
            return @([regex]::Matches($body, '(?m)^ {2}(?<job>[A-Za-z0-9_-]+):\s*$') |
                    ForEach-Object { $_.Groups['job'].Value })
        }

        function Get-CiMatrixLeg {
            param([string]$Text)

            $code = Remove-CiComment -Text $Text
            $legs = [System.Collections.Generic.List[object]]::new()
            $pattern = '(?m)^ {10}- os: (?<os>\S+)[^\n]*\n(?<rest>(?: {12}\S[^\n]*\n)*)'
            foreach ($entry in [regex]::Matches($code, $pattern)) {
                $properties = @{}
                foreach ($line in ($entry.Groups['rest'].Value -split "`n")) {
                    if ($line -match '^\s*(?<key>[A-Za-z0-9_-]+):\s*(?<value>.+?)\s*$') {
                        $properties[$Matches['key']] = $Matches['value']
                    }
                }
                $legs.Add([pscustomobject]@{
                        Os         = $entry.Groups['os'].Value
                        Properties = $properties
                    })
            }
            return $legs
        }

        # The matrix names runner images; the budget names platforms. The mapping is stated here
        # so a new runner image is an unmapped-leg failure rather than a silently unbudgeted one.
        $script:budgetPlatformByOs = @{
            'ubuntu-latest'  = 'Linux'
            'windows-latest' = 'Windows'
            'macos-latest'   = 'MacOS'
        }

        function Get-CiMatrixPlatform {
            param([string]$Text)

            return @(Get-CiMatrixLeg -Text $Text | ForEach-Object { $_.Os })
        }

        $script:seedSandboxes = [System.Collections.Generic.List[string]]::new()

        # A repo root the seeded run owns: the runner is pointed at this tree instead of the
        # checkout the suite is running from, so a seeded failure is a failure of the seed and
        # never of the real suite.
        function New-SeededRepo {
            param([Parameter(Mandatory)][string]$TestFileContent)

            $root = Join-Path ([System.IO.Path]::GetTempPath()) ('ci-seeded-' + [System.Guid]::NewGuid().ToString('N'))
            if (Test-Path -LiteralPath $root) { throw "Refusing to reuse an existing sandbox root: '$root'." }

            [void](New-Item -ItemType Directory -Path $root)
            $script:seedSandboxes.Add($root)
            [void](New-Item -ItemType Directory -Path (Join-Path $root 'tests'))
            [void](New-Item -ItemType Directory -Path (Join-Path $root 'tools'))
            [void](New-Item -ItemType Directory -Path (Join-Path $root 'scripts/skalary') -Force)

            # The real budget, copied rather than restated: a sandbox carrying its own ceiling
            # would let this case pass while the ceiling CI enforces says something else.
            Copy-Item -LiteralPath (Join-Path $script:repoRoot 'tools/suite-budget.psd1') `
                -Destination (Join-Path $root 'tools/suite-budget.psd1')
            $fingerprintScript = 'scripts/skalary/Get-SuiteInputFingerprint.ps1'
            Copy-Item -LiteralPath (Join-Path $script:repoRoot $fingerprintScript) `
                -Destination (Join-Path $root $fingerprintScript)

            Set-Content -LiteralPath (Join-Path $root 'tests/Seeded.Tests.ps1') -Value $TestFileContent -Encoding utf8
            & git -C $root init --quiet
            & git -C $root add -- scripts tests tools/suite-budget.psd1
            . (Join-Path $root $fingerprintScript)
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
                    }
                }
            }
            Set-Content -LiteralPath (Join-Path $root 'tools/suite-runtime.json') `
                -Value (($runtime | ConvertTo-Json -Depth 10) + "`n") -Encoding utf8NoBOM
            & git -C $root add -- tools/suite-runtime.json
            return (Resolve-Path -LiteralPath $root).Path
        }

        # Runs the workflow's own command line against a seeded tree, from that tree, so the
        # repo-relative report path the workflow states lands in the sandbox.
        function Invoke-SeededGate {
            param(
                [Parameter(Mandatory)][string]$SandboxRoot,
                [Parameter(Mandatory)][string[]]$RunnerArgument
            )

            Push-Location -LiteralPath $SandboxRoot
            $previousPreference = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
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
                $output = & pwsh @RunnerArgument -RepoRoot $SandboxRoot 2>&1
                $exitCode = $LASTEXITCODE
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
                $ErrorActionPreference = $previousPreference
                Pop-Location
            }

            return [pscustomobject]@{
                ExitCode = $exitCode
                # A captured escape sequence is not valid XML, so a failure message carrying
                # one destroys the NUnit report at the moment it is needed.
                Output   = (($output | Out-String) -replace '\x1b\[[0-9;]*[a-zA-Z]', '' -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', '')
            }
        }
    }

    AfterAll {
        foreach ($sandbox in $script:seedSandboxes) {
            if (Test-Path -LiteralPath $sandbox -PathType Container) {
                Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'test:Ci.InvokesRunUnitTests runs the suite through the runner that owns the budget, on both platforms' {
        $script:workflowText |
            Should -Not -BeNullOrEmpty -Because "REQ-9 rests on '.github/workflows/registry-ci.yml' existing"

        $steps = @(Get-CiWorkflowStep -Text $script:workflowText)
        $unitSteps = @($steps | Where-Object { $_.Body -match $script:gatePatterns['unit tests and budget'] })
        $unitSteps.Count |
            Should -Be 1 -Because 'exactly one step runs the unit suite, through scripts/skalary/Run-UnitTests.ps1'

        $validateSteps = @($steps | Where-Object { $_.Body -match $script:gatePatterns['repository validation'] })
        $validateSteps.Count |
            Should -Be 1 -Because 'validate.ps1 is a gate in its own right and runs as its own named step'

        $unitSteps[0].Name |
            Should -Not -Be $validateSteps[0].Name -Because 'REQ-9 requires the two gates in separate named steps'

        # D2: the budget and the cannot-test exit codes live in Run-UnitTests.ps1 and nowhere
        # else, so a direct Invoke-Pester here would be a second, unbudgeted way to run the suite
        # that reports success having asserted nothing.
        (Remove-CiComment -Text $script:workflowText) |
            Should -Not -Match 'Invoke-Pester' -Because 'the workflow must not run Pester around the script that owns the budget'

        $platforms = @(Get-CiMatrixPlatform -Text $script:workflowText)
        $platforms | Should -Contain 'ubuntu-latest' -Because 'REQ-9 requires every gate on both platforms'
        $platforms | Should -Contain 'windows-latest' -Because 'REQ-9 requires every gate on both platforms'

        # One job holding both gates plus a two-OS matrix is what makes "on both platforms" true
        # without asserting it step by step.
        @(Get-CiJobName -Text $script:workflowText).Count |
            Should -Be 1 -Because 'a second job could carry a gate on one platform only'
        $script:workflowText |
            Should -Match '(?m)^\s*runs-on: \$\{\{ matrix\.os \}\}\s*$' -Because 'the job runs once per matrix platform'

        # Without the clock the runner measures its own leg only and says so — a lower bound, not
        # a verdict on `npm test`. Dropping the clock step would therefore quietly narrow what the
        # ceiling is enforced against, so its presence and its position are both asserted.
        $clockSteps = @($steps | Where-Object { $_.Body -match 'Run-UnitTests\.ps1[^\r\n]*-StartBudgetClock' })
        $clockSteps.Count |
            Should -Be 1 -Because 'the budget is stated against the whole npm test command, which only the clock can span'

        $names = @($steps | ForEach-Object { $_.Name })
        $clockIndex = [array]::IndexOf($names, $clockSteps[0].Name)
        foreach ($leg in @('plan validation', 'repository validation', 'unit tests and budget')) {
            $legStep = @($steps | Where-Object { $_.Body -match $script:gatePatterns[$leg] })[0]
            [array]::IndexOf($names, $legStep.Name) |
                Should -BeGreaterThan $clockIndex -Because "the '$leg' leg is inside the budgeted command, so the clock must start before it"
        }
    }

    It 'test:Ci.GatesRunAsSeparateSteps gives every gate its own step so one failure cannot mask another' {
        $script:workflowText | Should -Not -BeNullOrEmpty

        $steps = @(Get-CiWorkflowStep -Text $script:workflowText)
        $steps.Count | Should -BeGreaterThan 1 -Because 'an unparsed workflow would make every assertion below vacuous'

        foreach ($gate in $script:gatePatterns.Keys) {
            $matching = @($steps | Where-Object { $_.Body -match $script:gatePatterns[$gate] })
            $matching.Count |
                Should -Be 1 -Because "the '$gate' gate must run in exactly one named step, or it is either missing or duplicated"
        }

        # RISK-10: two gates sharing a step means the second never runs once the first fails, and
        # the log shows one red step rather than one red gate and one that was skipped.
        foreach ($step in $steps) {
            $carried = @($script:gatePatterns.Keys | Where-Object { $step.Body -match $script:gatePatterns[$_] })
            $carried.Count |
                Should -BeLessOrEqual 1 -Because "step '$($step.Name)' chains $($carried -join ' + '); a chained gate can be masked by the one before it"
        }

        # Two gates whose enforcement is a second command in the same step: naming the script is
        # not enough, because a rebuild without the comparison rewrites the catalog and reports
        # success, and Sync-Dogfood without -WhatIf syncs the drift away instead of failing on it.
        $driftStep = @($steps | Where-Object { $_.Body -match $script:gatePatterns['generated output drift'] })[0]
        $driftStep.Body |
            Should -Match 'git diff --exit-code' -Because 'the drift gate is the comparison, not the regeneration that precedes it'

        $dogfoodStep = @($steps | Where-Object { $_.Body -match $script:gatePatterns['dogfood drift'] })[0]
        $dogfoodStep.Body |
            Should -Match 'Sync-Dogfood\.ps1[^\r\n]*-WhatIf' -Because 'a dogfood sync that writes cannot also detect drift'
    }

    It 'test:Ci.DeclaresLeastPrivilege gives the workflow read-only credentials it does not keep' {
        $script:workflowText | Should -Not -BeNullOrEmpty
        $code = Remove-CiComment -Text $script:workflowText

        # RISK-8: pull_request_target runs PR-authored code with the base repo's secrets and a
        # writable token. The whole hardening below is worth nothing if the trigger is that one.
        $code | Should -Not -Match '(?m)^\s*pull_request_target:' -Because 'PR-authored code must never run against base-repository credentials'
        $code | Should -Match '(?m)^\s*pull_request:\s*$' -Because 'REQ-9 requires the gates on every PR'

        # Declared at the top level, where no job can widen it, and holding nothing but the one
        # scope the gates need. An allowlist rather than a denylist: GitHub keeps adding scopes,
        # so a list of forbidden ones is out of date the moment a new one ships.
        $code | Should -Match '(?ms)^permissions:\s*\n' -Because 'REQ-9 requires permissions declared for the whole workflow'
        $code -match '(?ms)^permissions:\s*\n(?<body>(?:[ ]{2}\S[^\n]*\n)+)' | Out-Null
        $granted = @($Matches['body'] -split "`n" | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() })
        $granted | Should -Be @('contents: read') -Because 'every scope beyond contents: read is privilege this workflow never uses'

        # A job-level block would override the top-level one, so the check above would be reading
        # a declaration nothing runs under.
        $code | Should -Not -Match '(?m)^ {4}permissions:' -Because 'a job-level permissions block silently replaces the workflow-level one'

        $steps = @(Get-CiWorkflowStep -Text $script:workflowText)
        $checkout = @($steps | Where-Object { $_.Body -match 'uses: actions/checkout@' })
        $checkout.Count | Should -Be 1 -Because 'one checkout, so one place the credential policy is set'
        $checkout[0].Body |
            Should -Match '(?m)^\s*persist-credentials: false\s*$' -Because 'RISK-8: a token left in .git/config outlives the step that needed it'

        $code | Should -Match '(?ms)^concurrency:\s*\n\s+group:' -Because 'REQ-9 requires concurrency, so a superseded run does not hold a runner this suite needs'
    }

    It 'test:Ci.ActionsAndModulesPinnedWithoutSkipPublisherCheck pins what it installs and does not disarm the checks on it' {
        $script:workflowText | Should -Not -BeNullOrEmpty
        $code = Remove-CiComment -Text $script:workflowText

        # Every action is pinned to a 40-hex commit. A tag is a moving pointer the action's owner
        # can repoint, so a tag pin is a statement of intent rather than a supply-chain control.
        $uses = @([regex]::Matches($code, '(?m)^\s*uses:\s*(?<ref>\S+)') | ForEach-Object { $_.Groups['ref'].Value })
        $uses.Count | Should -BeGreaterThan 0 -Because 'no action references would make this assertion vacuous'
        foreach ($ref in $uses) {
            $ref | Should -Match '@[0-9a-f]{40}$' -Because "action '$ref' must be pinned to a commit SHA, not a tag a third party can repoint"
        }

        # D10: both halves, because a version pin over a channel whose signature check is skipped
        # pins only which unverified bytes arrive.
        $code | Should -Not -Match '-SkipPublisherCheck' -Because 'skipping the publisher check discards the signature the version pin is trusting'
        # Both the PowerShellGet and the PSResourceGet way of making the trust permanent: either
        # outlives this workflow on the runner and covers every later install, including ones this
        # workflow never sees.
        $code | Should -Not -Match 'Set-PSRepository[^\n]*Trusted' -Because 'trusting PSGallery globally outlives this workflow on the runner'
        $code | Should -Not -Match 'Set-PSResourceRepository[^\n]*-Trusted' -Because 'trusting PSGallery globally outlives this workflow on the runner'

        $installSteps = @(Get-CiWorkflowStep -Text $script:workflowText |
                Where-Object { $_.Body -match 'Install-PSResource|Install-Module' })
        $installSteps.Count | Should -BeGreaterThan 0 -Because 'the modules the gates need must be installed somewhere this check can read'
        foreach ($step in $installSteps) {
            foreach ($line in ($step.Body -split "`n" | Where-Object { $_ -match 'Install-PSResource|Install-Module' })) {
                # `[x.y.z]` is NuGet's exact range and `-RequiredVersion` is its PowerShellGet
                # equivalent. A bare `-Version 5.9.0` is a *minimum*, which installs whatever is
                # newest and reads like a pin while pinning nothing; a comma turns it into a span,
                # which is the same problem written differently.
                $line |
                    Should -Match '(-Version\s+"?\[[^\],]+\]"?)|(-RequiredVersion\s+\S+)' -Because "install line '$($line.Trim())' must pin one exact version; a bare version is a minimum and a bracketed range is a span"

                # Dropping -SkipPublisherCheck only restores a check if one still runs.
                # PSResourceGet validates nothing unless asked, so its install must ask.
                if ($line -match 'Install-PSResource') {
                    $line |
                        Should -Match '-AuthenticodeCheck' -Because "install line '$($line.Trim())' verifies no signature at all unless -AuthenticodeCheck is passed, which makes removing -SkipPublisherCheck a rename rather than a control"
                }
            }
        }

        # The pinned versions are declared as literals, so the pin is readable rather than
        # resolved at runtime from whatever the gallery offers.
        $code | Should -Match "Name = 'Pester'; Version = '[0-9]+\.[0-9]+\.[0-9]+'" -Because 'the Pester version the gate runs on is part of the gate'
        $code | Should -Match "Name = 'PSScriptAnalyzer'; Version = '[0-9]+\.[0-9]+\.[0-9]+'" -Because 'the analyzer version decides which findings exist'
    }

    It 'test:Ci.LintStepCanFail makes the analyzer step able to go red instead of only reporting' {
        $script:workflowText | Should -Not -BeNullOrEmpty

        # Invoke-ScriptAnalyzer sets no exit code, so a step that merely calls it runs on every
        # PR and can never fail — the shape plan 001 DR1-#17 assumed was enforced and was not.
        $body = (Remove-CiComment -Text $script:workflowText)

        $body | Should -Match 'Invoke-ScriptAnalyzer' -Because 'the lint gate must still run'
        $body | Should -Match "Severity -eq 'Error'" -Because 'the step must separate error findings from the warning backlog it does not enforce'
        $body | Should -Match 'throw "PSScriptAnalyzer found' -Because 'an error-severity finding must fail the build rather than scroll past'
    }

    It 'test:Ci.TimeoutExceedsHardCeiling gives every leg longer than the ceiling it is enforcing' {
        $script:workflowText | Should -Not -BeNullOrEmpty

        $budgetPath = Join-Path $script:repoRoot 'tools/suite-budget.psd1'
        $budget = Import-PowerShellDataFile -LiteralPath $budgetPath

        $legs = @(Get-CiMatrixLeg -Text $script:workflowText)
        $legs.Count | Should -BeGreaterThan 1 -Because 'REQ-9 requires both platforms; an unparsed matrix would make this vacuous'

        (Remove-CiComment -Text $script:workflowText) |
            Should -Match '(?m)^\s*timeout-minutes: \$\{\{ matrix\.timeoutMinutes \}\}\s*$' -Because 'the timeout is per leg (D9), because the platforms are budgeted ~2x apart'

        foreach ($leg in $legs) {
            $script:budgetPlatformByOs.ContainsKey($leg.Os) |
                Should -BeTrue -Because "runner image '$($leg.Os)' has no budget platform mapped, so its timeout cannot be checked against a ceiling"
            $platform = $script:budgetPlatformByOs[$leg.Os]
            $budget.Platforms.Contains($platform) |
                Should -BeTrue -Because "platform '$platform' runs in CI, so it must carry a budget entry"

            $leg.Properties.ContainsKey('timeoutMinutes') |
                Should -BeTrue -Because "leg '$($leg.Os)' must state its own timeout"

            $ceilingMinutes = [double]$budget.Platforms[$platform].HardCeilingSeconds / 60.0
            [double]$leg.Properties['timeoutMinutes'] |
                Should -BeGreaterThan $ceilingMinutes -Because "a $($leg.Os) leg cut off at $($leg.Properties['timeoutMinutes'])m before its $([math]::Round($ceilingMinutes, 1))m ceiling reports a cancelled run instead of an over-budget one"
        }
    }


    It 'test:Ci.ArtifactNamePerPlatform names the report after the platform that produced it, and uploads it even when the run is red' {
        $script:workflowText | Should -Not -BeNullOrEmpty

        $steps = @(Get-CiWorkflowStep -Text $script:workflowText)
        $unitStep = @($steps | Where-Object { $_.Body -match $script:gatePatterns['unit tests and budget'] })[0]

        # A default NUnit path is a fixed name in the working directory, so both legs write the
        # same file and the artifact upload of the second collides with the first. The platform
        # is in the path rather than only in the artifact name so the collision cannot come back
        # through a later step that reads the file.
        $unitStep.Body |
            Should -Match '-TestResultPath\s+\S+' -Because 'Pester writes a fixed default name, which two matrix legs both produce'
        # `${{ matrix.os }}` carries spaces, so the capture runs to end of line rather than to
        # the first whitespace.
        $unitStep.Body -match '-TestResultPath\s+(?<path>[^\n]+)' | Out-Null
        $resultPath = $Matches['path'].Trim()
        $resultPath |
            Should -Match '\$\{\{ matrix\.os \}\}' -Because 'a report that cannot be attributed to a platform is not a diagnosis on a suite that runs ~2x apart across them'

        $uploadSteps = @($steps | Where-Object { $_.Body -match 'uses:\s*actions/upload-artifact@' })
        $uploadSteps.Count | Should -Be 1 -Because 'one upload, so one artifact name to keep unique'
        $upload = $uploadSteps[0]

        $upload.Body -match '(?m)^\s*name:\s*(?<name>[^\n]+)$' | Out-Null
        $Matches['name'].Trim() |
            Should -Match '\$\{\{ matrix\.os \}\}' -Because 'two matrix legs uploading one artifact name is a hard failure, not a merge'

        $upload.Body -match '(?m)^\s*path:\s*(?<path>[^\n]+)$' | Out-Null
        $Matches['path'].Trim() |
            Should -Be $resultPath -Because 'the uploaded path must be the path the runner was told to write, or the artifact is empty for a reason nothing reports'

        # The run worth reading is the failed one. Without always() the report is uploaded
        # exactly when nobody needs it.
        $upload.Body |
            Should -Match '(?m)^\s*if: always\(\)\s*$' -Because 'a red suite is the run whose NUnit report is worth keeping'

        # REQ-9's summary line: a job whose only output is a red step tells a reader which
        # platform failed but not what failed on it.
        $summarySteps = @($steps | Where-Object { $_.Body -match 'GITHUB_STEP_SUMMARY' })
        $summarySteps.Count | Should -Be 1 -Because 'REQ-9 requires a summary line'
        $summarySteps[0].Body |
            Should -Match '(?m)^\s*if: always\(\)\s*$' -Because 'a summary that only appears on green runs summarises nothing worth reading'
        $summarySteps[0].Body |
            Should -Match '\$\{\{ matrix\.os \}\}' -Because 'both legs write into one summary, so each line has to say which leg wrote it'
    }

    It 'test:Ci.SeededFailureIsRed turns the command CI runs red on a seeded failure, and leaves no step a way to swallow it' {
        # REQ-9's last criterion, and the one the epic's success signal rests on: reverting any
        # fix from this plan turns a PR red. That was checked once, by hand, by reverting a fix
        # and watching a run — a proof that expired the moment it was read. Every fix here is
        # carried by a test, so the durable form of the same claim has two halves: the command
        # CI runs goes non-zero when a test fails, and the workflow lets that code through.
        $script:workflowText | Should -Not -BeNullOrEmpty
        $steps = @(Get-CiWorkflowStep -Text $script:workflowText)

        # The command is read out of the workflow rather than written here. A runner that goes
        # red under some invocation of this file's choosing says nothing about the invocation
        # the workflow performs, which is the only one a PR ever runs.
        $unitStep = @($steps | Where-Object { $_.Body -match $script:gatePatterns['unit tests and budget'] })[0]
        $unitCommands = @(Get-CiStepRunLine -Body $unitStep.Body |
                Where-Object { $_ -match $script:gatePatterns['unit tests and budget'] })
        $unitCommands.Count |
            Should -Be 1 -Because 'the unit-test gate must be one command this case can execute as CI executes it'
        $command = $unitCommands[0] -replace '\$\{\{ matrix\.os \}\}', 'seeded'

        $argv = @($command -split '\s+')
        $argv[0] | Should -Be 'pwsh' -Because 'the gate is a pwsh invocation, which is what this case reproduces'
        $fileIndex = [array]::IndexOf($argv, '-File')
        $fileIndex | Should -BeGreaterThan 0 -Because 'the script the gate runs is named by -File'
        # The only edit to the command: the repo-relative script path becomes absolute, because
        # the seeded tree is the working directory. Every flag — including the per-OS report
        # path REQ-9 requires — is the workflow's own.
        $argv[$fileIndex + 1] = Join-Path $script:repoRoot $argv[$fileIndex + 1]
        $runnerArgument = @($argv[1..($argv.Count - 1)])

        # Control first. Without it a sandbox broken for any other reason — a missing budget, a
        # file that never loads — would satisfy the seeded assertion for entirely the wrong one.
        $greenRepo = New-SeededRepo -TestFileContent @'
Describe 'seeded' {
    It 'passes' { $true | Should -BeTrue }
}
'@
        $green = Invoke-SeededGate -SandboxRoot $greenRepo -RunnerArgument $runnerArgument
        $green.ExitCode |
            Should -Be 0 -Because "an unseeded tree must be green, or the seeded run below proves nothing: $($green.Output)"

        $seededRepo = New-SeededRepo -TestFileContent @'
Describe 'seeded' {
    It 'passes' { $true | Should -BeTrue }
    It 'is the seeded failure' { $false | Should -BeTrue }
}
'@
        $seeded = Invoke-SeededGate -SandboxRoot $seededRepo -RunnerArgument $runnerArgument
        $seeded.ExitCode |
            Should -Be 1 -Because "a failing test must make the gate command report a failed run, not a failure count and not a cannot-test code: $($seeded.Output)"

        # The report CI uploads has to name the seeded failure, or a red leg tells a reader
        # which platform failed and nothing about what failed on it.
        $reportIndex = [array]::IndexOf($runnerArgument, '-TestResultPath')
        $reportIndex | Should -BeGreaterThan -1 -Because 'the per-platform NUnit path is part of the command CI runs'
        $report = Join-Path $seededRepo $runnerArgument[$reportIndex + 1]
        Test-Path -LiteralPath $report -PathType Leaf |
            Should -BeTrue -Because "a red run is the one whose report matters: $($seeded.Output)"
        $results = ([xml](Get-Content -LiteralPath $report -Raw)).'test-results'
        [int]$results.failures | Should -Be 1 -Because 'the uploaded report must carry the failure the run reported'
        (Get-Content -LiteralPath $report -Raw) |
            Should -Match 'is the seeded failure' -Because 'the failing case has to be nameable from the artifact alone'

        # --- the half no sandbox can execute: the workflow has to let that code through ---

        # `continue-on-error` turns a red step into a green job. One occurrence anywhere would
        # make every executable assertion above decorative.
        (Remove-CiComment -Text $script:workflowText) |
            Should -Not -Match 'continue-on-error' -Because 'a gate whose failure is tolerated is a gate that cannot be red'

        foreach ($gate in $script:gateEnforcingPatterns.Keys) {
            $enforcing = $script:gateEnforcingPatterns[$gate]
            $step = @($steps | Where-Object { $_.Body -match $script:gatePatterns[$gate] })[0]
            $step | Should -Not -BeNullOrEmpty -Because "the '$gate' gate must be in the workflow to be enforced by it"

            # Without a declared shell the default differs by platform, so the two legs would
            # run the same gate through different interpreters and propagate differently.
            $step.Body |
                Should -Match '(?m)^\s*shell: pwsh\s*$' -Because "the '$gate' step must state its shell, or the two legs run it under different ones"

            # A step reports the exit code of its last statement, so a gate followed by anything
            # else — on the next line or after a semicolon — is a gate whose verdict was
            # overwritten by whatever ran after it.
            $statements = @(Get-CiStepRunLine -Body $step.Body)
            $statements.Count | Should -BeGreaterThan 0 -Because "the '$gate' step must run something"
            $statements[-1] |
                Should -Match $enforcing -Because "the '$gate' gate must be the last statement in its step; '$($statements[-1])' would decide the step instead"

            # The shapes that turn a non-zero into a zero inside the step itself.
            foreach ($swallow in @('\|\|\s*true', '^exit\s+0$', '^\$LASTEXITCODE\s*=', '-ErrorAction\s+SilentlyContinue')) {
                foreach ($statement in $statements) {
                    $statement |
                        Should -Not -Match $swallow -Because "the '$gate' step must not discard the exit code it exists to produce"
                }
            }
        }
    }

}
