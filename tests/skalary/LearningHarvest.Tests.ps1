#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Installed learning harvest workflow' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:ciScript = Join-Path $script:repoRoot 'plugins/continue-implementation/skills/ci/scripts/Invoke-PhaseHarvest.ps1'
        $script:autopilotScript = Join-Path $script:repoRoot 'plugins/autopilot/skills/autopilot/scripts/Invoke-PhaseHarvest.ps1'
        $script:noteScript = Join-Path $script:repoRoot 'scripts/skalary/Add-WorkflowNote.ps1'
        $script:phaseStateScript = Join-Path $script:repoRoot 'scripts/skalary/Get-PhaseExecutionState.ps1'

        function Script:New-HarvestFixture {
            param(
                [switch]$MalformedCapture,
                [switch]$MissingCrLog,
                [ValidateRange(1, 99)][int]$PhaseCount = 1,
                [ValidateRange(0, 99)][int]$PhaseStart = 1
            )

            $root = Join-Path ([System.IO.Path]::GetTempPath()) ('learning-harvest-' + [guid]::NewGuid().ToString('N'))
            $planDir = Join-Path $root 'docs/implementation-plans/2026-08-09-a1b2c3-harvest-fixture'
            $logs = Join-Path $planDir 'assets/logs'
            [void](New-Item -ItemType Directory -Path $logs -Force)
            $planLines = [System.Collections.Generic.List[string]]::new()
            $planLines.Add('# a1b2c3: Harvest fixture')
            $planLines.Add('<!-- plan-id: a1b2c3 -->')
            $planLines.Add('')
            $phaseEnd = $PhaseStart + $PhaseCount - 1
            for ($phase = $PhaseStart; $phase -le $phaseEnd; $phase++) {
                    $requirement = $phase - $PhaseStart + 1
                    $planLines.Add("## Phase ${phase}: Fixture")
                    $planLines.Add("- [x] $phase.1 Fixture step (REQ-$requirement, RISK-1) ``S``")
                    $planLines.Add('')
            }
            [System.IO.File]::WriteAllText(
                    (Join-Path $planDir 'plan.md'),
                    ($planLines -join "`n"),
                    [System.Text.UTF8Encoding]::new($false)
            )
            $requirementLines = [System.Collections.Generic.List[string]]::new()
            $requirementLines.Add('# Requirements')
            $requirementLines.Add('')
            $requirementLines.Add('| ID | Requirement | Acceptance Criteria | Phases/Steps |')
            $requirementLines.Add('|----|-------------|---------------------|--------------|')
            for ($phase = $PhaseStart; $phase -le $phaseEnd; $phase++) {
                    $requirement = $phase - $PhaseStart + 1
                    $requirementLines.Add("| REQ-$requirement | Fixture $phase | ``test:fixture-$phase`` | $phase.1 |")
            }
            $requirementLines.Add('')
            [System.IO.File]::WriteAllText(
                    (Join-Path $planDir 'assets/requirements.md'),
                    ($requirementLines -join "`n"),
                    [System.Text.UTF8Encoding]::new($false)
            )
            $captureSections = [System.Collections.Generic.List[string]]::new()
            $learningSections = [System.Collections.Generic.List[string]]::new()
            $crSections = [System.Collections.Generic.List[string]]::new()
            for ($phase = $PhaseStart; $phase -le $phaseEnd; $phase++) {
                    $captureSections.Add("## Capture`nPhase: $phase`n`nNo entries for this phase.`n")
                    $learningSections.Add("## Learnings Capture`nPhase: $phase`n`nNo entries for this phase.`n")
                    $crSections.Add("## CR Capture`nPhase: $phase`n`nNo entries for this phase.`n")
            }
            [System.IO.File]::WriteAllText(
                    (Join-Path $logs 'capture.md'),
                    $(if ($MalformedCapture) {
                        "## Capture`nPhase: 1`n"
                    }
                    else {
                            $captureSections -join "`n"
                        }),
                    [System.Text.UTF8Encoding]::new($false)
            )
            [System.IO.File]::WriteAllText(
                    (Join-Path $logs 'learnings.md'),
                    ($learningSections -join "`n"),
                    [System.Text.UTF8Encoding]::new($false)
            )
            if (-not $MissingCrLog) {
                    [System.IO.File]::WriteAllText(
                        (Join-Path $logs 'cr-log.md'),
                        ($crSections -join "`n"),
                        [System.Text.UTF8Encoding]::new($false)
                    )
            }
            return [pscustomobject]@{ Root = $root; PlanDir = $planDir; Logs = $logs }
        }

        function Script:Add-HarvestNote {
            param(
                    [Parameter(Mandatory)]$Fixture,
                    [Parameter(Mandatory)][ValidateSet('CrLog', 'Learnings', 'Capture')][string]$Kind,
                    [Parameter(Mandatory)][int]$Phase,
                    [Parameter(Mandatory)][string]$Concern,
                    [Parameter(Mandatory)][string[]]$Requirement,
                    [Parameter(Mandatory)][string]$Message,
                    [ValidateSet('cr', 'dr', 'none')][string]$ReviewType = 'none',
                    [ValidateSet('Critical', 'High', 'Med', 'Low')][string]$Severity = 'Med',
                    [ValidateSet('rework>1', 'plan-contradiction', 'reusable-pattern')][string]$Trigger = 'reusable-pattern'
            )

            $parameters = @{
                    Kind = $Kind
                    PlanDir = $Fixture.PlanDir
                    RepoRoot = $Fixture.Root
                    Phase = $Phase
                    Step = "$Phase.1"
                    Concern = $Concern
                    Requirement = $Requirement
                    ReviewType = $ReviewType
                    Message = $Message
            }
            if ($Kind -eq 'CrLog') {
                    $parameters['Sev'] = $Severity
                    $parameters['Src'] = 'code-review'
            }
            elseif ($Kind -eq 'Learnings') {
                    $parameters['Trigger'] = $Trigger
            }
            & $script:noteScript @parameters | Out-Null
        }

        function Script:Invoke-InstalledHarvest {
            param(
                    [Parameter(Mandatory)][string]$ScriptPath,
                    [Parameter(Mandatory)]$Fixture,
                    [Parameter(Mandatory)][ValidateSet('ci', 'autopilot')][string]$Source,
                    [int]$Phase = 1,
                    [switch]$FinalSweep,
                    [switch]$ValidateReceipt
            )

            $arguments = @(
                    '-NoProfile', '-File', $ScriptPath,
                    '-PlanDir', $Fixture.PlanDir,
                    '-Src', $Source,
                    '-RepoRoot', $Fixture.Root
            )
            if ($FinalSweep) {
                    $arguments += '-FinalSweep'
            }
            elseif ($ValidateReceipt) {
                    $arguments += @('-Phase', [string]$Phase, '-ValidateReceipt')
            }
            else {
                    $arguments += @('-Phase', [string]$Phase)
            }
            $output = & pwsh @arguments 2>&1
            return [pscustomobject]@{
                    ExitCode = $LASTEXITCODE
                    Output = ($output | Out-String)
            }
        }
    }

    It 'test:LearningHarvest.InstalledInvocationAndAutopilotAllowlist invokes both installed copies and surfaces malformed or missing sections as degraded' {
        $ciGuide = [System.IO.File]::ReadAllText(
            (Join-Path $script:repoRoot 'plugins/continue-implementation/skills/ci/assets/crosscheck-guide.md')
        )
        $agent = [System.IO.File]::ReadAllText(
            (Join-Path $script:repoRoot 'plugins/autopilot/agents/autopilot.agent.md')
        )
        $ciGuide | Should -Match '\.github/skills/ci/scripts/Invoke-PhaseHarvest\.ps1'
        $ciGuide | Should -Match '\-Phase <N> \-Src ci'
        $agent | Should -Match '\.github/skills/autopilot/scripts/Invoke-PhaseHarvest\.ps1'
        $agent | Should -Match '\-Phase <N> \-Src autopilot'
        $agent | Should -Match 'Workflow carve-out.+Invoke-PhaseHarvest\.ps1'
        $agent | Should -Match 'stage the returned receipt path'
        $ciGuide | Should -Match 'stage the returned receipt path'
        $agent | Should -Match 'stop phase completion'
        $ciGuide | Should -Match 'stop phase completion'
        $agent | Should -Match 'stop before branch selection or archival'
        $ciGuide | Should -Match 'stop before branch selection or archival'
        $agent | Should -Not -Match 'Test-Path docs/review-ledger/security\.md'
        $ciGuide | Should -Not -Match 'Test-Path docs/review-ledger/security\.md'

        $ciFixture = New-HarvestFixture -MalformedCapture
        $autopilotFixture = New-HarvestFixture -MissingCrLog
        try {
            $ci = Invoke-InstalledHarvest -ScriptPath $script:ciScript -Fixture $ciFixture -Source ci
            $ci.ExitCode | Should -Be 3
            $ci.Output | Should -Match 'Status'
            $ci.Output | Should -Match 'degraded'
            $ci.Output | Should -Match 'placeholder'

            $autopilot = Invoke-InstalledHarvest -ScriptPath $script:autopilotScript `
                -Fixture $autopilotFixture -Source autopilot
            $autopilot.ExitCode | Should -Be 3
            $autopilot.Output | Should -Match 'Status'
            $autopilot.Output | Should -Match 'degraded'
            $autopilot.Output | Should -Match 'Missing required workflow log'
        }
        finally {
            Remove-Item -LiteralPath $ciFixture.Root -Recurse -Force
            Remove-Item -LiteralPath $autopilotFixture.Root -Recurse -Force
        }
    }

    It 'declares both scripts, modules, and receipt scaffolds in standalone plugin manifests' {
        foreach ($plugin in @('continue-implementation', 'autopilot')) {
            $manifest = Get-Content -LiteralPath (Join-Path $script:repoRoot "plugins/$plugin/plugin.json") `
                -Raw | ConvertFrom-Json
            $destinations = @($manifest.files.dest)
            $skill = if ($plugin -eq 'autopilot') { 'autopilot' } else { 'ci' }
            $destinations | Should -Contain "skills/$skill/scripts/Invoke-PhaseHarvest.ps1"
            $destinations | Should -Contain "skills/$skill/scripts/LedgerStore.psm1"
            if ($plugin -eq 'autopilot') {
                $destinations | Should -Contain 'skills/autopilot/scripts/Get-PhaseExecutionState.ps1'
            }
            @($manifest.scaffolds.path) | Should -Contain 'docs/implementation-plans/<plan>/assets/harvest-receipts/**'
            @($manifest.scaffolds.path) | Should -Contain 'docs/implementation-plans/<plan>/harvest-receipts/**'
        }
    }

    It 'validates an immutable close receipt after the plan is archived' {
        $fixture = New-HarvestFixture
        try {
            & git -C $fixture.Root init --quiet
            & git -C $fixture.Root config user.name fixture
            & git -C $fixture.Root config user.email fixture@example.invalid
            & git -C $fixture.Root add --all
            & git -C $fixture.Root commit --quiet -m initial
            $created = Invoke-InstalledHarvest -ScriptPath $script:autopilotScript `
                -Fixture $fixture -Source autopilot
            $created.ExitCode | Should -Be 0 -Because $created.Output

            $pending = & pwsh -NoProfile -File $script:phaseStateScript `
                -PlanPath (Join-Path $fixture.PlanDir 'plan.md') -Phase 1 `
                -RepoRoot $fixture.Root -HarvestValidator $script:autopilotScript 2>&1
            $LASTEXITCODE | Should -Be 0
            ($pending -join "`n").Trim() | Should -Be 'close-pending'
            & git -C $fixture.Root add --all
            & git -C $fixture.Root commit --quiet -m 'persist close receipt'

            $archiveRoot = Join-Path $fixture.Root 'docs/implementation-plans/archived'
            [void](New-Item -ItemType Directory -Path $archiveRoot -Force)
            $archivedDir = Join-Path $archiveRoot (Split-Path $fixture.PlanDir -Leaf)
            Move-Item -LiteralPath $fixture.PlanDir -Destination $archiveRoot
            $archivedFixture = [pscustomobject]@{
                Root = $fixture.Root
                PlanDir = $archivedDir
            }
            & git -C $fixture.Root add --all
            & git -C $fixture.Root commit --quiet -m archive

            $validated = Invoke-InstalledHarvest -ScriptPath $script:autopilotScript `
                -Fixture $archivedFixture -Source autopilot -ValidateReceipt
            $validated.ExitCode | Should -Be 0 -Because $validated.Output
            $validated.Output | Should -Match 'Validated immutable phase receipt'

            $state = & pwsh -NoProfile -File $script:phaseStateScript `
                -PlanPath (Join-Path $archivedDir 'plan.md') -Phase 1 `
                -RepoRoot $fixture.Root -HarvestValidator $script:autopilotScript 2>&1
            $LASTEXITCODE | Should -Be 0
            ($state -join "`n").Trim() | Should -Be 'closed'
        }
        finally {
            Remove-Item -LiteralPath $fixture.Root -Recurse -Force
        }
    }

    It 'supports committed Phase 0 close receipts' {
        $fixture = New-HarvestFixture -PhaseStart 0
        try {
            & git -C $fixture.Root init --quiet
            & git -C $fixture.Root config user.name fixture
            & git -C $fixture.Root config user.email fixture@example.invalid
            & git -C $fixture.Root add --all
            & git -C $fixture.Root commit --quiet -m initial

            Add-HarvestNote -Fixture $fixture -Kind CrLog -Phase 0 `
                -Concern correctness-reliability -Requirement 'REQ-1' `
                -ReviewType cr -Message 'phase zero close'
            $created = Invoke-InstalledHarvest -ScriptPath $script:autopilotScript `
                -Fixture $fixture -Source autopilot -Phase 0
            $created.ExitCode | Should -Be 0 -Because $created.Output
            & git -C $fixture.Root add --all
            & git -C $fixture.Root commit --quiet -m 'persist phase zero close'

            $state = & pwsh -NoProfile -File $script:phaseStateScript `
                -PlanPath (Join-Path $fixture.PlanDir 'plan.md') -Phase 0 `
                -RepoRoot $fixture.Root -HarvestValidator $script:autopilotScript 2>&1
            $LASTEXITCODE | Should -Be 0
            ($state -join "`n").Trim() | Should -Be 'closed'
        }
        finally {
            Remove-Item -LiteralPath $fixture.Root -Recurse -Force
        }
    }

    It 'test:LearningHarvest.MultiPhaseBatchAndProvenance preserves source classes, phase and REQ provenance, refuses forgery, collisions, ceilings, and concurrent category writes' {
        $fixture = New-HarvestFixture -PhaseCount 2
        try {
            Add-HarvestNote -Fixture $fixture -Kind Capture -Phase 1 -Concern security `
                -Requirement REQ-1 -Message 'Normalize THIS , please!!'
            Add-HarvestNote -Fixture $fixture -Kind Capture -Phase 1 -Concern security `
                -Requirement REQ-1 -Message 'normalize this, please!!'
            Add-HarvestNote -Fixture $fixture -Kind CrLog -Phase 1 `
                -Concern correctness-reliability -Requirement REQ-1 -ReviewType cr `
                -Severity High -Message 'Phase one reviewed finding'
            Add-HarvestNote -Fixture $fixture -Kind Capture -Phase 1 `
                -Concern architecture-patterns -Requirement REQ-1, REQ-2 `
                -Message 'Cross-phase requirement provenance'
            for ($index = 1; $index -le 11; $index++) {
                Add-HarvestNote -Fixture $fixture -Kind Learnings -Phase 1 -Concern performance `
                    -Requirement REQ-1 -Message "Performance learning $index"
            }
            Add-HarvestNote -Fixture $fixture -Kind Capture -Phase 2 -Concern testing-evidence `
                -Requirement REQ-2 -ReviewType dr -Message 'Phase two planning evidence'

            $phaseOne = Invoke-InstalledHarvest -ScriptPath $script:ciScript -Fixture $fixture -Source ci -Phase 1
            $phaseOne.ExitCode | Should -Be 0
            $receipt = Get-Content -LiteralPath (Join-Path $fixture.PlanDir 'assets/harvest-receipts/phase-001.json') `
                -Raw | ConvertFrom-Json -Depth 12
            $sourceKinds = @($receipt.payload.candidates.SourceKind | Select-Object -Unique)
            $sourceKinds | Should -Contain 'Capture'
            $sourceKinds | Should -Contain 'CrLog'
            $sourceKinds | Should -Contain 'Learnings'
            @($receipt.payload.candidates.SourcePath | Where-Object { $_ -match 'learning-overflow' }).Count |
                Should -BeGreaterThan 0
            @($receipt.payload.candidates | Where-Object { $_.Tags -contains 'req-1' }).Count |
                Should -Be @($receipt.payload.candidates).Count
            @($receipt.payload.candidates | Where-Object { $_.Tags -contains 'phase-1' }).Count |
                Should -Be @($receipt.payload.candidates).Count
            $crossPhase = @($receipt.payload.candidates |
                    Where-Object Entry -eq 'Cross-phase requirement provenance')
            $crossPhase.Count | Should -Be 1
            @($crossPhase[0].Requirements) | Should -Be @('REQ-1', 'REQ-2')
            @($crossPhase[0].Tags) | Should -Contain 'req-1'
            @($crossPhase[0].Tags) | Should -Contain 'req-2'
            @(Get-Content -LiteralPath (Join-Path $fixture.Root 'docs/review-ledger/security.md') |
                    Where-Object { $_ -match '^\- \[' }).Count | Should -Be 1
            Test-Path -LiteralPath (Join-Path $fixture.Root 'docs/review-ledger/plan-structure.md') |
                Should -BeFalse

            $phaseTwo = Invoke-InstalledHarvest -ScriptPath $script:ciScript -Fixture $fixture -Source ci -Phase 2
            $phaseTwo.ExitCode | Should -Be 0
            Get-Content -LiteralPath (Join-Path $fixture.Root 'docs/review-ledger/plan-structure.md') -Raw |
                Should -Match 'Phase two planning evidence'
        }
        finally {
            Remove-Item -LiteralPath $fixture.Root -Recurse -Force
        }

        $forged = New-HarvestFixture
        try {
            Add-HarvestNote -Fixture $forged -Kind Capture -Phase 1 -Concern security `
                -Requirement REQ-1 -Message 'Routing must be authenticated'
            $capturePath = Join-Path $forged.Logs 'capture.md'
            $text = [System.IO.File]::ReadAllText($capturePath).Replace(
                '[concern:security]',
                '[concern:performance]'
            )
            [System.IO.File]::WriteAllText($capturePath, $text, [System.Text.UTF8Encoding]::new($false))
            $result = Invoke-InstalledHarvest -ScriptPath $script:ciScript -Fixture $forged -Source ci
            $result.ExitCode | Should -Be 3
            $result.Output | Should -Match 'source-record digest mismatch'
            Test-Path -LiteralPath (Join-Path $forged.PlanDir 'assets/harvest-receipts/phase-001.json') |
                Should -BeFalse
            Test-Path -LiteralPath (Join-Path $forged.Root 'docs/review-ledger/performance.md') |
                Should -BeFalse
        }
        finally {
            Remove-Item -LiteralPath $forged.Root -Recurse -Force
        }

        $ceiling = New-HarvestFixture
        try {
            Add-HarvestNote -Fixture $ceiling -Kind Capture -Phase 1 -Concern security `
                -Requirement REQ-1 -Message 'Plus one must fail atomically'
            Add-HarvestNote -Fixture $ceiling -Kind Capture -Phase 1 -Concern performance `
                -Requirement REQ-1 -Message 'Admissible category must not partially write'
            $ledgerDir = Join-Path $ceiling.Root 'docs/review-ledger'
            [void](New-Item -ItemType Directory -Path $ledgerDir -Force)
            $builder = [System.Text.StringBuilder]::new()
            for ($index = 0; $index -lt 10000; $index++) {
                [void]$builder.AppendLine(
                    "- [2026-08-09] seeded lesson $index (plan-a1b2c3, src:ci, sev:Med) #seed-$index"
                )
            }
            $ledgerPath = Join-Path $ledgerDir 'security.md'
            [System.IO.File]::WriteAllText($ledgerPath, $builder.ToString(), [System.Text.UTF8Encoding]::new($false))
            $before = [System.Security.Cryptography.SHA256]::HashData([System.IO.File]::ReadAllBytes($ledgerPath))
            $result = Invoke-InstalledHarvest -ScriptPath $script:ciScript -Fixture $ceiling -Source ci
            $result.ExitCode | Should -Be 4
            $result.Output | Should -Match 'capacity-blocked'
            [Convert]::ToHexString(
                [System.Security.Cryptography.SHA256]::HashData([System.IO.File]::ReadAllBytes($ledgerPath))
            ) | Should -Be ([Convert]::ToHexString($before))
            Test-Path -LiteralPath (Join-Path $ceiling.PlanDir 'assets/harvest-receipts/phase-001.json') |
                Should -BeFalse
            Test-Path -LiteralPath (Join-Path $ceiling.Root 'docs/review-ledger/performance.md') |
                Should -BeFalse
        }
        finally {
            Remove-Item -LiteralPath $ceiling.Root -Recurse -Force
        }

        $concurrent = New-HarvestFixture -PhaseCount 2
        $processes = @()
        try {
            Add-HarvestNote -Fixture $concurrent -Kind Capture -Phase 1 -Concern security `
                -Requirement REQ-1 -Message 'Concurrent security lesson'
            Add-HarvestNote -Fixture $concurrent -Kind Capture -Phase 2 -Concern security `
                -Requirement REQ-2 -Message 'Concurrent second security lesson'
            $processes = @(
                Start-Process -FilePath pwsh -ArgumentList @(
                    '-NoProfile', '-File', $script:ciScript, '-PlanDir', $concurrent.PlanDir,
                    '-Phase', '1', '-Src', 'ci', '-RepoRoot', $concurrent.Root
                ) -PassThru -NoNewWindow
                Start-Process -FilePath pwsh -ArgumentList @(
                    '-NoProfile', '-File', $script:ciScript, '-PlanDir', $concurrent.PlanDir,
                    '-Phase', '2', '-Src', 'ci', '-RepoRoot', $concurrent.Root
                ) -PassThru -NoNewWindow
            )
            foreach ($process in $processes) {
                $process.WaitForExit(30000) | Should -BeTrue
                $process.ExitCode | Should -Be 0
            }
            $security = Get-Content -LiteralPath (
                Join-Path $concurrent.Root 'docs/review-ledger/security.md'
            ) -Raw
            $security | Should -Match 'Concurrent security lesson'
            $security | Should -Match 'Concurrent second security lesson'
        }
        finally {
            foreach ($process in @($processes)) {
                if ($process -and -not $process.HasExited) { $process.Kill() }
            }
            Remove-Item -LiteralPath $concurrent.Root -Recurse -Force
        }
    }

    It 'test:LearningHarvest.FinalSweepReceiptReplay replays immutable receipts without redistilling changed logs' {
        $fixture = New-HarvestFixture -PhaseCount 2
        try {
            Add-HarvestNote -Fixture $fixture -Kind Capture -Phase 1 -Concern security `
                -Requirement REQ-1 -Message 'Receipt phase one'
            Add-HarvestNote -Fixture $fixture -Kind Capture -Phase 2 -Concern performance `
                -Requirement REQ-2 -Message 'Receipt phase two'
            (Invoke-InstalledHarvest -ScriptPath $script:ciScript -Fixture $fixture -Source ci -Phase 1).ExitCode |
                Should -Be 0
            (Invoke-InstalledHarvest -ScriptPath $script:ciScript -Fixture $fixture -Source ci -Phase 2).ExitCode |
                Should -Be 0

            Add-HarvestNote -Fixture $fixture -Kind Capture -Phase 1 `
                -Concern operability-observability `
                -Requirement REQ-1 -Message 'Late log mutation must not be redistilled'
            $ledgerRoot = Join-Path $fixture.Root 'docs/review-ledger'
            foreach ($file in @(Get-ChildItem -LiteralPath $ledgerRoot -File -Filter '*.md')) {
                Remove-Item -LiteralPath $file.FullName -Force
            }
            $first = Invoke-InstalledHarvest -ScriptPath $script:ciScript -Fixture $fixture `
                -Source ci -FinalSweep
            $first.ExitCode | Should -Be 0
            $first.Output | Should -Match 'Receipts'
            $first.Output | Should -Match '2'
            Get-Content -LiteralPath (Join-Path $ledgerRoot 'security.md') -Raw |
                Should -Match 'Receipt phase one'
            Get-Content -LiteralPath (Join-Path $ledgerRoot 'performance.md') -Raw |
                Should -Match 'Receipt phase two'
            Test-Path -LiteralPath (Join-Path $ledgerRoot 'observability.md') | Should -BeFalse

            $before = @(
                Get-ChildItem -LiteralPath $ledgerRoot -File -Filter '*.md' |
                    ForEach-Object { "$($_.Name):$($_.Length)" } |
                    Sort-Object
            ) -join '|'
            $second = Invoke-InstalledHarvest -ScriptPath $script:ciScript -Fixture $fixture `
                -Source ci -FinalSweep
            $second.ExitCode | Should -Be 0
            $after = @(
                Get-ChildItem -LiteralPath $ledgerRoot -File -Filter '*.md' |
                    ForEach-Object { "$($_.Name):$($_.Length)" } |
                    Sort-Object
            ) -join '|'
            $after | Should -Be $before

            $receiptPath = Join-Path $fixture.PlanDir 'assets/harvest-receipts/phase-001.json'
            $tampered = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json -Depth 12
            $tampered.payload.candidates[0].Entry = 'tampered receipt text'
            [System.IO.File]::WriteAllText(
                $receiptPath,
                (($tampered | ConvertTo-Json -Depth 12 -Compress) + "`n"),
                [System.Text.UTF8Encoding]::new($false)
            )
            $ledgerBeforeTamper = @(
                Get-ChildItem -LiteralPath $ledgerRoot -File -Filter '*.md' |
                    ForEach-Object {
                        "$($_.Name):$([Convert]::ToHexString(
                            [System.Security.Cryptography.SHA256]::HashData(
                                [System.IO.File]::ReadAllBytes($_.FullName)
                            )
                        ))"
                    } |
                    Sort-Object
            ) -join '|'
            $refused = Invoke-InstalledHarvest -ScriptPath $script:ciScript -Fixture $fixture `
                -Source ci -FinalSweep
            $refused.ExitCode | Should -Be 3
            $refused.Output | Should -Match 'digest mismatch'
            $ledgerAfterTamper = @(
                Get-ChildItem -LiteralPath $ledgerRoot -File -Filter '*.md' |
                    ForEach-Object {
                        "$($_.Name):$([Convert]::ToHexString(
                            [System.Security.Cryptography.SHA256]::HashData(
                                [System.IO.File]::ReadAllBytes($_.FullName)
                            )
                        ))"
                    } |
                    Sort-Object
            ) -join '|'
            $ledgerAfterTamper | Should -Be $ledgerBeforeTamper
        }
        finally {
            Remove-Item -LiteralPath $fixture.Root -Recurse -Force
        }
    }

    It 'test:LearningHarvest.ActiveReceiptCapacityBoundary accepts receipt 64, blocks 65 before mutation, and excludes archives' {
        $fixture = New-HarvestFixture -PhaseCount 2
        try {
            Add-HarvestNote -Fixture $fixture -Kind Capture -Phase 1 -Concern performance `
                -Requirement REQ-1 -Message 'Receipt sixty four writes a real candidate'
            Add-HarvestNote -Fixture $fixture -Kind Capture -Phase 2 -Concern security `
                -Requirement REQ-2 -Message 'Receipt sixty five must not mutate'
            $receiptRoot = Join-Path $fixture.PlanDir 'assets/harvest-receipts'
            [void](New-Item -ItemType Directory -Path $receiptRoot -Force)
            for ($index = 100; $index -lt 163; $index++) {
                [System.IO.File]::WriteAllText(
                    (Join-Path $receiptRoot ("phase-{0:D3}.json" -f $index)),
                    '{}',
                    [System.Text.UTF8Encoding]::new($false)
                )
            }
            $sixtyFour = Invoke-InstalledHarvest -ScriptPath $script:ciScript -Fixture $fixture `
                -Source ci -Phase 1
            $sixtyFour.ExitCode | Should -Be 0 -Because $sixtyFour.Output
            @(Get-ChildItem -LiteralPath $receiptRoot -File -Filter 'phase-*.json').Count |
                Should -Be 64
            Get-Content -LiteralPath (Join-Path $fixture.Root 'docs/review-ledger/performance.md') -Raw |
                Should -Match 'Receipt sixty four writes a real candidate'

            $beforeFiles = @(Get-ChildItem -LiteralPath $fixture.Root -File -Recurse |
                    ForEach-Object FullName | Sort-Object)
            $sixtyFive = Invoke-InstalledHarvest -ScriptPath $script:ciScript -Fixture $fixture `
                -Source ci -Phase 2
            $sixtyFive.ExitCode | Should -Be 4
            $sixtyFive.Output | Should -Match 'capacity-blocked'
            Test-Path -LiteralPath (Join-Path $receiptRoot 'phase-002.json') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $fixture.Root 'docs/review-ledger/security.md') |
                Should -BeFalse
            @(Get-ChildItem -LiteralPath $fixture.Root -File -Recurse |
                    ForEach-Object FullName | Sort-Object) | Should -Be $beforeFiles
        }
        finally {
            Remove-Item -LiteralPath $fixture.Root -Recurse -Force
        }

        $replayCapacity = New-HarvestFixture
        try {
            Add-HarvestNote -Fixture $replayCapacity -Kind Capture -Phase 1 -Concern security `
                -Requirement REQ-1 -Message 'Existing receipt replay must preserve capacity status'
            (Invoke-InstalledHarvest -ScriptPath $script:ciScript -Fixture $replayCapacity `
                    -Source ci).ExitCode | Should -Be 0
            $replayReceiptRoot = Join-Path $replayCapacity.PlanDir 'assets/harvest-receipts'
            for ($index = 100; $index -lt 164; $index++) {
                [System.IO.File]::WriteAllText(
                    (Join-Path $replayReceiptRoot ("phase-{0:D3}.json" -f $index)),
                    '{}',
                    [System.Text.UTF8Encoding]::new($false)
                )
            }
            $replayLedgerPath = Join-Path $replayCapacity.Root 'docs/review-ledger/security.md'
            $replayLedgerBefore = [System.IO.File]::ReadAllBytes($replayLedgerPath)
            $replay = Invoke-InstalledHarvest -ScriptPath $script:ciScript `
                -Fixture $replayCapacity -Source ci
            $replay.ExitCode | Should -Be 4
            $replay.Output | Should -Match 'capacity-blocked'
            $replay.Output | Should -Not -Match 'degraded'
            [Convert]::ToHexString([System.IO.File]::ReadAllBytes($replayLedgerPath)) |
                Should -Be ([Convert]::ToHexString($replayLedgerBefore))
        }
        finally {
            Remove-Item -LiteralPath $replayCapacity.Root -Recurse -Force
        }

        $racing = New-HarvestFixture -PhaseCount 2
        $raceProcesses = @()
        try {
            Add-HarvestNote -Fixture $racing -Kind Capture -Phase 1 -Concern security `
                -Requirement REQ-1 -Message 'Concurrent receipt boundary one'
            Add-HarvestNote -Fixture $racing -Kind Capture -Phase 2 -Concern performance `
                -Requirement REQ-2 -Message 'Concurrent receipt boundary two'
            $raceReceiptRoot = Join-Path $racing.PlanDir 'assets/harvest-receipts'
            [void](New-Item -ItemType Directory -Path $raceReceiptRoot -Force)
            for ($index = 100; $index -lt 163; $index++) {
                [System.IO.File]::WriteAllText(
                    (Join-Path $raceReceiptRoot ("phase-{0:D3}.json" -f $index)),
                    '{}',
                    [System.Text.UTF8Encoding]::new($false)
                )
            }
            $raceProcesses = @(
                Start-Process -FilePath pwsh -ArgumentList @(
                    '-NoProfile', '-File', $script:ciScript, '-PlanDir', $racing.PlanDir,
                    '-Phase', '1', '-Src', 'ci', '-RepoRoot', $racing.Root
                ) -PassThru -NoNewWindow
                Start-Process -FilePath pwsh -ArgumentList @(
                    '-NoProfile', '-File', $script:ciScript, '-PlanDir', $racing.PlanDir,
                    '-Phase', '2', '-Src', 'ci', '-RepoRoot', $racing.Root
                ) -PassThru -NoNewWindow
            )
            foreach ($process in $raceProcesses) {
                $process.WaitForExit(30000) | Should -BeTrue
            }
            @($raceProcesses.ExitCode | Sort-Object) | Should -Be @(0, 4)
            @(Get-ChildItem -LiteralPath $raceReceiptRoot -File -Filter 'phase-*.json').Count |
                Should -Be 64
            $boundaryEntries = 0
            foreach ($category in @('security', 'performance')) {
                $path = Join-Path $racing.Root "docs/review-ledger/$category.md"
                if (Test-Path -LiteralPath $path -PathType Leaf) {
                    $boundaryEntries += @(Get-Content -LiteralPath $path |
                            Where-Object { $_ -match '^\- \[' }).Count
                }
            }
            $boundaryEntries | Should -Be 1
        }
        finally {
            foreach ($process in $raceProcesses) {
                if (-not $process.HasExited) { $process.Kill() }
            }
            Remove-Item -LiteralPath $racing.Root -Recurse -Force
        }

        $archived = New-HarvestFixture
        try {
            $archiveRoot = Join-Path $archived.PlanDir 'assets/harvest-receipts/archive'
            [void](New-Item -ItemType Directory -Path $archiveRoot -Force)
            for ($index = 1; $index -le 64; $index++) {
                [System.IO.File]::WriteAllText(
                    (Join-Path $archiveRoot ("phase-{0:D3}.json" -f $index)),
                    '{}',
                    [System.Text.UTF8Encoding]::new($false)
                )
            }
            $result = Invoke-InstalledHarvest -ScriptPath $script:ciScript -Fixture $archived -Source ci
            $result.ExitCode | Should -Be 0
            Test-Path -LiteralPath (
                Join-Path $archived.PlanDir 'assets/harvest-receipts/phase-001.json'
            ) | Should -BeTrue
        }
        finally {
            Remove-Item -LiteralPath $archived.Root -Recurse -Force
        }
    }
}
