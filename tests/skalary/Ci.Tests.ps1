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
        $script:containerWorkflowPath = Join-Path $script:repoRoot '.github/workflows/autopilot-container-ci.yml'
        $script:containerRunnerPath = Join-Path $script:repoRoot 'scripts/skalary/Invoke-ContainerToolchainGate.ps1'
        # Shared with CiGates.Tests.ps1: one parser for the workflow, because a second copy
        # would be a second thing to drift.
        Import-Module (Join-Path $PSScriptRoot '..' 'CiWorkflow.psm1') -Force -DisableNameChecking
        $script:workflowText = $null
        if (Test-Path -LiteralPath $script:workflowPath -PathType Leaf) {
            $script:workflowText = Get-Content -LiteralPath $script:workflowPath -Raw
        }
        $script:containerWorkflowText = if (Test-Path -LiteralPath $script:containerWorkflowPath -PathType Leaf) {
            Get-Content -LiteralPath $script:containerWorkflowPath -Raw
        }
        else { $null }

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

            # The real budget, copied rather than restated: a sandbox carrying its own ceiling
            # would let this case pass while the ceiling CI enforces says something else.
            Copy-Item -LiteralPath (Join-Path $script:repoRoot 'tools/suite-budget.psd1') `
                -Destination (Join-Path $root 'tools/suite-budget.psd1')

            Set-Content -LiteralPath (Join-Path $root 'tests/Seeded.Tests.ps1') -Value $TestFileContent -Encoding utf8
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
            try {
                $output = & pwsh @RunnerArgument -RepoRoot $SandboxRoot 2>&1
                $exitCode = $LASTEXITCODE
            }
            finally {
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

    It 'test:Ci.WorkflowSecurityContract enforces the container workflow trust and result boundaries' {
                $script:containerWorkflowText |
                    Should -Not -BeNullOrEmpty -Because 'the stable container check must exist as an operational workflow'
                $code = Remove-CiComment -Text $script:containerWorkflowText
                $runnerCode = Remove-CiComment -Text (
                    Get-Content -LiteralPath $script:containerRunnerPath -Raw)
                $jobs = @{}
                foreach ($job in @(Get-CiWorkflowJob -Text $script:containerWorkflowText)) {
                    $jobs[$job.Name] = $job
                }
                @($jobs.Keys | Sort-Object) | Should -Be @('detector', 'gate', 'image')

                $code | Should -Match '(?m)^on:\s*\n\s+pull_request:\s*$'
                $code | Should -Match '(?ms)^\s+push:\s*\n\s+branches:\s*\n\s+- main\s*$'
                $code | Should -Not -Match '(?m)^\s+paths(?:-ignore)?:' -Because 'the final required check must be created for every PR and main push'
                $code | Should -Not -Match '(?m)^\s+pull_request_target:'
                $code | Should -Match '(?ms)^permissions:\s*\n\s+contents: read\s*$'
                $code | Should -Not -Match '(?m)^ {4}permissions:'
                $code | Should -Match '(?ms)^concurrency:\s*\n\s+group:'

                $jobs.detector.Body | Should -Match '(?m)^\s*timeout-minutes: 5\s*$'
                $jobs.image.Body | Should -Match '(?m)^\s*timeout-minutes: 45\s*$'
                $jobs.gate.Body | Should -Match '(?m)^\s*name: autopilot container / gate\s*$'
                $jobs.gate.Body | Should -Match '(?m)^\s*timeout-minutes: 5\s*$'
                $jobs.gate.Body | Should -Match '(?m)^\s*if: always\(\)\s*$'
                $jobs.image.Body |
                    Should -Match "if: needs\.detector\.result == 'success' && needs\.detector\.outputs\.relevance == 'true'"

                $uses = @([regex]::Matches($code, '(?m)^\s*uses:\s*(?<ref>\S+)') |
                        ForEach-Object { $_.Groups['ref'].Value })
                $uses.Count | Should -BeGreaterThan 0
                foreach ($ref in $uses) {
                    $ref | Should -Match '@[0-9a-f]{40}$' -Because "action '$ref' must be immutable"
                }
                $checkoutSteps = @($jobs.Values.Steps | Where-Object {
                        $_.Body -match 'uses: actions/checkout@'
                    })
                $checkoutSteps.Count | Should -Be 7
                foreach ($checkout in $checkoutSteps) {
                    $checkout.Body | Should -Match '(?m)^\s*persist-credentials: false\s*$'
                }
                $continued = @($jobs.Values.Steps | Where-Object {
                        $_.Body -match '(?m)^\s*continue-on-error: true\s*$'
                    })
                $continued.Count | Should -Be 2 -Because 'only the optional detector/image base checkout may be unavailable'
                foreach ($step in $continued) { $step.Name | Should -Be 'Checkout event base' }

                $code | Should -Match '(?m)^\s*CANDIDATE_SHA: \$\{\{ github\.sha \}\}\s*$'
                $code | Should -Match "(?m)^\s*BASE_SHA: \x24\{\{ github\.event_name == 'pull_request' && github\.event\.pull_request\.base\.sha \|\| github\.event\.before \}\}\s*$"
                $code | Should -Match "(?m)^\s*CONTROL_SHA: \x24\{\{ github\.event_name == 'pull_request' && github\.event\.pull_request\.base\.sha \|\| github\.sha \}\}\s*$"
                $code | Should -Match "path: control"
                $code | Should -Match "path: candidate"
                $code | Should -Match "path: base"
                $code | Should -Match 'Assert-CommitSha -Name CANDIDATE_SHA'
                $code | Should -Match 'Assert-CommitSha -Name BASE_SHA'
                $code | Should -Match 'Assert-Head -Name control'
                $code | Should -Match 'Assert-Head -Name candidate'
                $code | Should -Match 'Assert-Head -Name base'

                $runnerMentions = @($jobs.Values.Steps | Where-Object {
                        $_.Body -match 'Invoke-ContainerToolchainGate\.ps1'
                    })
                $runnerSteps = @($runnerMentions | Where-Object {
                        $_.Body -match '& "\$env:CONTROL_ROOT/scripts/skalary/Invoke-ContainerToolchainGate\.ps1"'
                    })
                $runnerSteps.Count | Should -Be 3 -Because 'the runner is invoked once per mode and nowhere else'
                foreach ($step in $runnerMentions) {
                    # Presence probes name the runner without invoking it; whether a step invokes or
                    # only inspects, the path it names must be the trusted control plane's.
                    $step.Body |
                        Should -Not -Match 'CANDIDATE_ROOT/scripts' -Because 'candidate scripts execute only as Docker build/runtime input'
                }
                $jobs.detector.Body | Should -Match '-Mode Detect'
                $jobs.image.Body | Should -Match '-Mode Measure'
                $jobs.gate.Body | Should -Match '-Mode VerifyResult'
                $jobs.gate.Body | Should -Match '\$\{\{ needs\.detector\.result \}\}'
                $jobs.gate.Body | Should -Match '\$\{\{ needs\.detector\.outputs\.relevance \}\}'
                $jobs.gate.Body | Should -Match '\$\{\{ needs\.image\.result \}\}'

                $code | Should -Not -Match '\$\{\{\s*secrets\.'
                $code | Should -Not -Match '\bGITHUB_ENV\b'
                $code | Should -Not -Match 'docker\.sock'
                $combined = "$code`n$runnerCode"
                foreach ($forbidden in @(
                        '(?i)--privileged\b',
                        '(?i)--device(?:=|\s)',
                        '(?i)--cap-add(?:=|\s)',
                        '(?i)--network(?:=|\s+)host\b',
                        '(?i)(?:^|[\s,''"])--mount(?:=|\s)',
                        '(?i)(?:^|[\s,''"])(?:-v|--volume)(?:=|\s)'
                    )) {
                    $combined | Should -Not -Match $forbidden
                }
                $runnerCode |
                    Should -Match "'run', '--rm', '--network', 'none'" -Because 'candidate smoke must have no network or inherited host channels'

                $jobs.image.Body | Should -Match "(?m)^\s*DOCKER_BUILDKIT: '1'\s*$"
                $jobs.image.Body | Should -Not -Match '(?i)cache-(?:from|to)|type=gha|docker/setup-buildx' -Because 'the two builds share only the hosted daemon local cache'
                $jobs.image.Body | Should -Match '(?m)^\s*COPILOT_CLI_VERSION:'
                $code | Should -Match '(?m)^\s*COPILOT_CLI_VERSION: [0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?\s*$'
                $jobs.image.Body | Should -Match '-CopilotVersion \$env:COPILOT_CLI_VERSION'
                $jobs.image.Body | Should -Match '-CandidateBudgetSeconds 1500'
                $jobs.image.Body | Should -Match '-BaseBudgetSeconds 600'
                $jobs.image.Body | Should -Match '-RunnerBudgetSeconds 2100'
                $jobs.image.Body | Should -Match '-AdvisoryGrowthMiB 250'
                $jobs.detector.Body | Should -Match 'candidate_only_reason=\$candidateOnlyReason'
                $jobs.image.Body |
                    Should -Match '-DetectionCandidateOnlyReason \$env:DETECTION_CANDIDATE_ONLY_REASON'
                $code |
                    Should -Match 'DETECTION_CANDIDATE_ONLY_REASON: \$\{\{ needs\.detector\.outputs\.candidate_only_reason \}\}'
                @([regex]::Matches($runnerCode, "'pull', '--platform', 'linux/amd64'")).Count |
                    Should -Be 1 -Because 'candidate and base must share one resolved base-image pull'
                $runnerCode.IndexOf('$candidateTag') |
                    Should -BeLessThan $runnerCode.IndexOf('$baseTag') -Because 'candidate validation owns the first 25 minutes'

                $imageUploads = @($jobs.image.Steps | Where-Object {
                        $_.Body -match 'uses: actions/upload-artifact@'
                    })
                $imageUploads.Count | Should -Be 1
                $imageUploads[0].Body | Should -Match '(?m)^\s*if: always\(\)\s*$'
                $imageUploads[0].Body | Should -Match 'receipt\.json'
                $imageUploads[0].Body | Should -Match 'provenance\.json'
                $imageUploads[0].Body | Should -Match '(?m)^\s*retention-days: 14\s*$'
                $summarySteps = @($jobs.Values.Steps | Where-Object {
                        $_.Body -match 'GITHUB_STEP_SUMMARY'
                    })
                foreach ($step in $summarySteps) {
                    $step.Body |
                        Should -Not -Match 'receipt\.json|provenance\.json|diagnostics\.log' -Because 'raw candidate-derived fields never become workflow commands'
                    if ($step.Body -match 'Get-Content') {
                        # A step may echo a file into the summary only if that file is the runner's
                        # own escaped rendering; the bootstrap step emits workflow literals instead.
                        $step.Body |
                            Should -Match 'summary\.md' -Because 'only the escaped summary rendering is echoed'
                    }
                }

                (Get-Content -LiteralPath (Join-Path $script:repoRoot 'package.json') -Raw) |
                    Should -Not -Match 'Invoke-ContainerToolchainGate|docker' -Because 'ordinary npm test stays Docker-free'
    }

    It 'test:Ci.ContainerControlPlaneBootstrap keeps a base without the runner passing without running candidate code' {
        # A pull request whose base predates this workflow has no trusted runner. The only two ways
        # out are to run the candidate's copy — which is the trust boundary this design exists to
        # deny — or to record the bootstrap and pass, so the shape of that second path is asserted
        # structurally rather than by matching text that could sit inside a comment or a script.
        $parsed = ConvertFrom-CiWorkflowYaml -Text $script:containerWorkflowText
        $jobsNode = $parsed.Document.Value['jobs']
        @($jobsNode.Value.Keys) | Should -Be @('detector', 'image', 'gate')

        foreach ($jobName in @('detector', 'gate')) {
            $steps = @($jobsNode.Value[$jobName].Value['steps'].Value)
            $stepNames = @($steps | ForEach-Object {
                    if ($_.Value.Contains('name')) { $_.Value['name'].Value } else { '' }
                })
            $stepNames | Should -Contain 'Resolve trusted control plane'

            $resolve = @($steps | Where-Object {
                    $_.Value.Contains('name') -and $_.Value['name'].Value -eq 'Resolve trusted control plane'
                })
            $resolve.Count | Should -Be 1
            $resolve[0].Value['id'].Value | Should -Be 'control'
            $resolveRun = $resolve[0].Value['run'].Value
            $resolveRun |
                Should -Match "EVENT_NAME -ne 'pull_request'" -Because 'only a pull request may find the runner missing from its base'
            $resolveRun | Should -Match 'throw'
            $resolveRun | Should -Match 'present='
            $resolve[0].Value.Contains('if') |
                Should -BeFalse -Because 'the resolution itself must always run, or absence is never detected'

            # Every step that invokes the runner is gated on the runner existing, and every step
            # that handles its absence is gated on the complement. No third state can exist.
            foreach ($step in $steps) {
                if (-not $step.Value.Contains('run')) { continue }
                $run = $step.Value['run'].Value
                $guard = if ($step.Value.Contains('if')) { $step.Value['if'].Value } else { '' }
                if ($run -match '& "\$env:CONTROL_ROOT/scripts/skalary/Invoke-ContainerToolchainGate\.ps1"') {
                    $guard | Should -Be "steps.control.outputs.present == 'true'"
                }
                if ($run -match '(?m)Outcome: \*\*bootstrap\*\*|control plane absent from base') {
                    $guard | Should -BeIn @("steps.control.outputs.present != 'true'", 'always()')
                }
            }
        }

        # The detector's relevance output must survive the bootstrap step, or the gate reads an
        # empty relevance and the truth table fails closed on a PR that could never have passed.
        $detectorOutputs = $jobsNode.Value['detector'].Value['outputs'].Value
        $detectorOutputs['relevance'].Value |
            Should -Be '${{ steps.detect.outputs.relevance || steps.bootstrap.outputs.relevance }}'
        $detectorOutputs['control_plane_present'].Value | Should -Be '${{ steps.control.outputs.present }}'

        $bootstrapSteps = @($jobsNode.Value['detector'].Value['steps'].Value | Where-Object {
                $_.Value.Contains('id') -and $_.Value['id'].Value -eq 'bootstrap'
            })
        $bootstrapSteps.Count | Should -Be 1
        $bootstrapSteps[0].Value['if'].Value | Should -Be "steps.control.outputs.present != 'true'"
        $bootstrapSteps[0].Value['run'].Value | Should -Match 'relevance=false'

        # The bootstrap receipt must be a closed, non-blocking one: a blocking bootstrap receipt
        # would make the first pull request unmergeable for a reason no author can fix.
        $gateSteps = @($jobsNode.Value['gate'].Value['steps'].Value)
        $record = @($gateSteps | Where-Object {
                $_.Value.Contains('name') -and $_.Value['name'].Value -eq 'Record control-plane bootstrap'
            })
        $record.Count | Should -Be 1
        $recordRun = $record[0].Value['run'].Value
        $recordReceipt = ([regex]::Match($recordRun, "(?m)^'(?<json>\{.*\})' \|")).Groups['json'].Value |
            ConvertFrom-Json
        $recordReceipt.schema | Should -Be 'skalary/container-toolchain-receipt@1'
        $recordReceipt.blocking | Should -BeFalse
        $recordReceipt.relevant | Should -BeFalse
        $recordReceipt.outcome | Should -Be 'irrelevant'
        $recordRun | Should -Not -Match 'CANDIDATE_ROOT'

        # Bootstrap covers exactly one condition: the base has no runner. A detector job that
        # failed for any other reason must not inherit that pass, so the step reads the detector's
        # conclusion and fails when it is anything but success.
        $record[0].Value['env'].Value['DETECTOR_CONCLUSION'].Value |
            Should -Be '${{ needs.detector.result }}'
        $recordRun | Should -Match "DETECTOR_CONCLUSION -ne 'success'"
        $recordRun | Should -Match 'throw'
        ([regex]::Match($recordRun, "(?ms)DETECTOR_CONCLUSION -ne 'success'.*?\}")).Value |
            Should -Match 'throw' -Because 'the conclusion check must be what raises, not merely precede a raise'
        $recordRun.IndexOf("DETECTOR_CONCLUSION -ne 'success'") |
            Should -BeLessThan $recordRun.IndexOf('container-toolchain-receipt@1') -Because 'the check must precede writing a passing receipt'

        # The image job never runs on the bootstrap path, but if it ever did, it must still refuse
        # to fall back to the candidate's runner.
        $imageSteps = @($jobsNode.Value['image'].Value['steps'].Value)
        $imageAssertions = @($imageSteps | Where-Object {
                $_.Value.Contains('run') -and
                $_.Value['run'].Value -match 'Invoke-ContainerToolchainGate\.ps1'
            })
        $imageAssertions.Count | Should -BeGreaterThan 0
        @($imageAssertions | Where-Object { $_.Value['run'].Value -match 'CANDIDATE_ROOT/scripts' }).Count |
            Should -Be 0
    }

    It 'test:Ci.WorkflowYamlParserIsStrict refuses the shapes a text split silently accepts' {
        # The step boundaries every workflow assertion rests on used to come from splitting on
        # '- name:'. A run block that contains that text is a script, not a step, and a parser
        # that cannot tell them apart lets a gate disappear while the tests stay green.
        $decoy = @(
            'jobs:',
            '  probe:',
            '    steps:',
            '      - name: real step',
            '        run: |',
            '          echo "      - name: fake step"',
            '          echo done'
        ) -join "`n"
        $steps = @(Get-CiWorkflowStep -Text $decoy)
        $steps.Count | Should -Be 1
        $steps[0].Name | Should -Be 'real step'
        $steps[0].Body | Should -Match 'fake step'

        foreach ($unsupported in @(
                "jobs:`n  a: &anchor`n    b: c",
                "jobs:`n  a: { b: c }",
                "---`njobs:`n  a:`n    b: c",
                "jobs:`n`tprobe:`n    steps: []",
                "jobs:`n  probe:`n    name: one`n    name: two"
            )) {
            { Get-CiWorkflowJob -Text $unsupported } |
                Should -Throw -Because 'an unreadable workflow must fail loudly, not parse into a convenient shape'
        }

        # The real workflows must remain inside the supported subset, or the assertions built on
        # the parser stop describing them.
        foreach ($workflow in @(Get-ChildItem -LiteralPath (Join-Path $script:repoRoot '.github/workflows') -Filter '*.yml')) {
            $jobs = @(Get-CiWorkflowJob -Text (Get-Content -LiteralPath $workflow.FullName -Raw))
            $jobs.Count | Should -BeGreaterThan 0 -Because "$($workflow.Name) must parse into jobs"
            foreach ($job in $jobs) {
                @($job.Steps).Count | Should -BeGreaterThan 0 -Because "$($workflow.Name)/$($job.Name) must parse into steps"
                foreach ($step in $job.Steps) { $step.Name | Should -Not -BeNullOrEmpty }
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
