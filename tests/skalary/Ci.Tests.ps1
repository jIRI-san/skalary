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

        function Get-CiMatrixPlatform {
            param([string]$Text)

            if ($Text -notmatch '(?ms)^ {8}os:\s*\r?\n(?<entries>(?: {10}- .+\r?\n)+)') { return @() }
            return @($Matches['entries'] -split '\r?\n' |
                    Where-Object { $_ -match '^\s*-\s*(?<os>\S+)\s*$' } |
                    ForEach-Object { ($_ -replace '^\s*-\s*', '').Trim() })
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
}
