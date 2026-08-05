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
        $script:workflowText = $null
        if (Test-Path -LiteralPath $script:workflowPath -PathType Leaf) {
            $script:workflowText = Get-Content -LiteralPath $script:workflowPath -Raw
        }

        # Comments are dropped before anything is matched. A comment naming a gate would
        # otherwise count as that gate running, which is the exact failure these tests exist to
        # catch — prose standing in for an invocation.
        function Remove-CiComment {
            param([string]$Text)

            return (($Text -split '\r?\n' | Where-Object { $_ -notmatch '^\s*#' }) -join "`n")
        }

        # Steps are split on their `- name:` marker rather than parsed as YAML, because no YAML
        # parser is a dependency of this repo and adding one to read seven step names would be a
        # supply-chain cost paid for a string split.
        function Get-CiWorkflowStep {
            param([string]$Text)

            $steps = [System.Collections.Generic.List[object]]::new()
            $chunks = [regex]::Split((Remove-CiComment -Text $Text), '(?m)^ {6}- name: ')
            for ($i = 1; $i -lt $chunks.Count; $i++) {
                $chunk = $chunks[$i]
                $break = $chunk.IndexOf("`n")
                $name = if ($break -ge 0) { $chunk.Substring(0, $break) } else { $chunk }
                $body = if ($break -ge 0) { $chunk.Substring($break + 1) } else { '' }
                $steps.Add([pscustomobject]@{
                        Name = $name.Trim()
                        Body = $body
                    })
            }
            return $steps
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

}
