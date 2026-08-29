#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Evidence truth' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:builder = Join-Path $script:repoRoot 'scripts/skalary/Build-EvidenceReceipt.ps1'
        $script:testPlan = Join-Path $script:repoRoot 'scripts/skalary/Test-Plan.ps1'
        $script:runner = Join-Path $script:repoRoot 'scripts/skalary/Run-UnitTests.ps1'
        Import-Module (Join-Path $script:repoRoot 'scripts/skalary/PlanEvidence.psm1') -Force -DisableNameChecking
        $script:head = (& git -C $script:repoRoot rev-parse HEAD).Trim()
        $script:tempRoots = [System.Collections.Generic.List[string]]::new()

        function New-EvidencePlanFixture {
            param([string[]]$Markers = @('test:EvidenceTruth.Sample'))

            $root = Join-Path ([System.IO.Path]::GetTempPath()) ('evidence-truth-' + [guid]::NewGuid().ToString('N'))
            [void](New-Item -ItemType Directory -Path $root)
            $script:tempRoots.Add($root)
            $criteria = @($Markers | ForEach-Object { '{0}{1}{0}' -f [char]0x60, $_ }) -join ' · '
            @"
# abcdef: Evidence fixture
<!-- plan-id: abcdef -->
<!-- evidence: required -->

## Requirements

| ID | Requirement | Acceptance Criteria | Phases/Steps |
|---|---|---|---|
| REQ-1 | Truthful evidence | $criteria | 1.1 |

## Risks

| ID | Risk | Likelihood | Impact | Mitigation | Steps |
|---|---|---|---|---|---|
| RISK-1 | False green | Low | High | Block non-passing evidence | 1.1 |

## Phase 1: Evidence

- [x] 1.1 Exercise evidence truth (REQ-1, RISK-1) ``S``
"@ | Set-Content -LiteralPath (Join-Path $root 'plan.md') -Encoding utf8NoBOM
            return $root
        }

        function Write-Waiver {
            param(
                [Parameter(Mandatory)][string]$PlanDir,
                [string]$Marker = 'test:EvidenceTruth.Sample',
                [string]$Outcome = 'skipped',
                [string]$Plan = 'abcdef',
                [string]$Requirement = 'REQ-1',
                [string]$Reason = 'Unavailable on this platform',
                [string]$Platform
            )

            $entry = [ordered]@{
                plan = $Plan
                requirement = $Requirement
                marker = $Marker
                outcome = $Outcome
                reason = $Reason
            }
            if ($PSBoundParameters.ContainsKey('Platform')) {
                $entry['platform'] = $Platform
            }
            [ordered]@{
                schema = 'skalary/evidence-waivers@1'
                waivers = @($entry)
            } | ConvertTo-Json -Depth 8 |
                Set-Content -LiteralPath (Join-Path $PlanDir 'evidence-waivers.json') -Encoding utf8NoBOM
        }

        function Invoke-TestPlanFixture {
            param([Parameter(Mandatory)][string]$PlanDir)

            $output = & pwsh -NoProfile -File $script:testPlan `
                -PlanPath (Join-Path $PlanDir 'plan.md') -RepoRoot $script:repoRoot `
                -Stage PlanCrosscheck 2>&1
            return [pscustomobject]@{
                ExitCode = $LASTEXITCODE
                Output = ($output | Out-String)
            }
        }

        function New-RunnerFixture {
            param([Parameter(Mandatory)][string]$Content)

            $root = Join-Path ([System.IO.Path]::GetTempPath()) ('evidence-runner-' + [guid]::NewGuid().ToString('N'))
            [void](New-Item -ItemType Directory -Path (Join-Path $root 'tests') -Force)
            [void](New-Item -ItemType Directory -Path (Join-Path $root 'tools') -Force)
            $script:tempRoots.Add($root)
            Set-Content -LiteralPath (Join-Path $root 'tests/Fixture.Tests.ps1') -Value $Content -Encoding utf8NoBOM
            @'
@{
    Schema = 'skalary/suite-tier@1'
    FastFocusedHardCeilingSeconds = 60
    SlowHardCeilingSeconds = 600
    CiSetupAllowanceSeconds = 60
    DedicatedFiles = @()
    SlowFiles = @()
}
'@ | Set-Content -LiteralPath (Join-Path $root 'tools/suite-tier.psd1') -Encoding utf8NoBOM
            return $root
        }

        function Invoke-EvidenceRunner {
            param(
                [Parameter(Mandatory)][string]$Root,
                [Parameter(Mandatory)][string[]]$Id,
                [string[]]$Path = @('tests/Fixture.Tests.ps1'),
                [switch]$SimulateInterruption
            )

            $resultPath = Join-Path $Root '.github/.skalary/evidence-results/evidence-results.json'
            $quotedIds = @($Id | ForEach-Object { "'$_'" }) -join ','
            $quotedPaths = @($Path | ForEach-Object { "'$_'" }) -join ','
            $driver = Join-Path $Root 'driver.ps1'
            $interruptionArgument = if ($SimulateInterruption) { ' -SimulateInterruption' } else { '' }
            @"
& '$script:runner' -RepoRoot '$Root' -TestPath @($quotedPaths) -EvidenceTestId @($quotedIds) -EvidenceResultPath '$resultPath'$interruptionArgument
exit `$LASTEXITCODE
"@ | Set-Content -LiteralPath $driver -Encoding utf8NoBOM
            $output = & pwsh -NoProfile -File $driver 2>&1
            return [pscustomobject]@{
                ExitCode = $LASTEXITCODE
                Output = ($output | Out-String)
                Result = if (Test-Path -LiteralPath $resultPath -PathType Leaf) {
                    Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
                }
                else {
                    $null
                }
                ResultPath = $resultPath
            }
        }
    }

    AfterAll {
        foreach ($root in $script:tempRoots) {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:EvidenceTruth.OutcomeAggregationAndRendering preserves every outcome and never relabels a non-pass' {
        $statuses = @('passed', 'failed', 'skipped', 'unrun', 'stale', 'degraded')
        $results = for ($index = 0; $index -lt $statuses.Count; $index++) {
            [pscustomobject]@{
                Req = "REQ-$($index + 1)"
                Marker = "test:status.$($statuses[$index])"
                Status = $statuses[$index]
                Note = "detail-$index"
            }
        }
        $receipt = & $script:builder -Result $results -Commit $script:head

        @($receipt.Outcomes.Status) | Should -Be $statuses
        $receipt.Lines[0] | Should -Match '^✓ REQ-1 .+ passed: detail-0 '
        foreach ($line in $receipt.Lines[1..($receipt.Lines.Count - 1)]) {
            $line | Should -Match '^✗ '
        }
        $receipt.AllPassed | Should -BeFalse

        { & $script:builder -Result @([pscustomobject]@{
                    Req = 'REQ-1'; Marker = 'test:conflict'; Status = 'skipped'; Success = $true
                }) -Commit $script:head } | Should -Throw '*conflicting Status and Success*'
    }

    It 'test:EvidenceTruth.PlanLocalWaivers applies only an exact skipped or degraded binding' {
        $planDir = New-EvidencePlanFixture
        Write-Waiver -PlanDir $planDir
        $receipt = & $script:builder -Result @([pscustomobject]@{
                Req = 'REQ-1'; Marker = 'test:EvidenceTruth.Sample'; Status = 'skipped'
            }) -Commit $script:head -PlanDir $planDir -RepoRoot $script:repoRoot

        $receipt.Lines[0] | Should -Match '^⊘ REQ-1 .+ waived: from skipped: Unavailable on this platform '
        $receipt.Outcomes[0].Status | Should -Be 'waived'
        $receipt.AllPassed | Should -BeTrue

        $failed = & $script:builder -Result @([pscustomobject]@{
                Req = 'REQ-1'; Marker = 'test:EvidenceTruth.Sample'; Status = 'failed'
            }) -Commit $script:head -PlanDir $planDir -RepoRoot $script:repoRoot
        $failed.Outcomes[0].Status | Should -Be 'failed'
        $failed.AllPassed | Should -BeFalse

        Write-Waiver -PlanDir $planDir -Marker 'test:*'
        { & $script:builder -Result @([pscustomobject]@{
                    Req = 'REQ-1'; Marker = 'test:EvidenceTruth.Sample'; Status = 'skipped'
                }) -Commit $script:head -PlanDir $planDir -RepoRoot $script:repoRoot } |
            Should -Throw '*undeclared or wildcard*'

        Write-Waiver -PlanDir $planDir -Plan 'fedcba'
        { & $script:builder -Result @([pscustomobject]@{
                    Req = 'REQ-1'; Marker = 'test:EvidenceTruth.Sample'; Status = 'skipped'
                }) -Commit $script:head -PlanDir $planDir -RepoRoot $script:repoRoot } |
            Should -Throw '*expected*abcdef*'

        Write-Waiver -PlanDir $planDir -Plan 'ABCDEF'
        { & $script:builder -Result @([pscustomobject]@{
                    Req = 'REQ-1'; Marker = 'test:EvidenceTruth.Sample'; Status = 'skipped'
                }) -Commit $script:head -PlanDir $planDir -RepoRoot $script:repoRoot } |
            Should -Throw '*expected*abcdef*'

        Write-Waiver -PlanDir $planDir -Outcome 'degraded'
        $degraded = & $script:builder -Result @([pscustomobject]@{
                Req = 'REQ-1'; Marker = 'test:EvidenceTruth.Sample'; Status = 'degraded'
            }) -Commit $script:head -PlanDir $planDir -RepoRoot $script:repoRoot
        $degraded.Outcomes[0].Status | Should -Be 'waived'

        foreach ($forbiddenOutcome in @('failed', 'unrun', 'stale')) {
            Write-Waiver -PlanDir $planDir -Outcome $forbiddenOutcome
            { & $script:builder -Result @([pscustomobject]@{
                        Req = 'REQ-1'; Marker = 'test:EvidenceTruth.Sample'; Status = $forbiddenOutcome
                    }) -Commit $script:head -PlanDir $planDir -RepoRoot $script:repoRoot } |
                Should -Throw '*may target only skipped or degraded*'
        }

        $currentPlatform = if ($IsWindows) { 'Windows' } elseif ($IsMacOS) { 'MacOS' } else { 'Linux' }
        $otherPlatform = @('Windows', 'Linux', 'MacOS') |
            Where-Object { $_ -ne $currentPlatform } |
            Select-Object -First 1
        Write-Waiver -PlanDir $planDir -Platform $currentPlatform
        (& $script:builder -Result @([pscustomobject]@{
                    Req = 'REQ-1'; Marker = 'test:EvidenceTruth.Sample'; Status = 'skipped'
                }) -Commit $script:head -PlanDir $planDir -RepoRoot $script:repoRoot).Outcomes[0].Status |
            Should -Be 'waived'
        Write-Waiver -PlanDir $planDir -Platform $otherPlatform
        (& $script:builder -Result @([pscustomobject]@{
                    Req = 'REQ-1'; Marker = 'test:EvidenceTruth.Sample'; Status = 'skipped'
                }) -Commit $script:head -PlanDir $planDir -RepoRoot $script:repoRoot).Outcomes[0].Status |
            Should -Be 'skipped'

        foreach ($invalidPolicy in @(
                '{"schema":"skalary/evidence-waivers@1","waivers":{"plan":"abcdef","requirement":"REQ-1","marker":"test:EvidenceTruth.Sample","outcome":"skipped","reason":"seeded"}}',
                '{"schema":"skalary/evidence-waivers@1","waivers":[{"plan":"abcdef","requirement":"REQ-1","marker":"test:EvidenceTruth.Sample","outcome":"skipped","reason":42}]}',
                '{"schema":"skalary/evidence-waivers@1","waivers":[{"plan":"abcdef","requirement":"REQ-1","marker":"test:EvidenceTruth.Sample","outcome":"skipped","reason":"seeded","platform":null}]}'
            )) {
            Set-Content -LiteralPath (Join-Path $planDir 'evidence-waivers.json') `
                -Value $invalidPolicy -Encoding utf8NoBOM
            { & $script:builder -Result @([pscustomobject]@{
                        Req = 'REQ-1'; Marker = 'test:EvidenceTruth.Sample'; Status = 'skipped'
                    }) -Commit $script:head -PlanDir $planDir -RepoRoot $script:repoRoot } |
                Should -Throw
        }
    }

    It 'test:EvidenceTruth.FocusedStructuredResults reports pass, skip, degraded, missing, and discovery outcomes' {
        $fixture = New-RunnerFixture -Content @'
Describe 'focused evidence' {
    It 'test:EvidenceTruth.Pass works' { $true | Should -BeTrue }
    it -Name 'test:EvidenceTruth.Named works' { $true | Should -BeTrue }
    IT "test:EvidenceTruth.Expandable $($true) works" { $true | Should -BeTrue }
    It 'test:EvidenceTruth.CaseSensitive works' { throw 'wrong-case evidence selector executed' }
    It 'test:EvidenceTruth.Mixed passes' { $true | Should -BeTrue }
    It 'test:EvidenceTruth.Mixed skips' { Set-ItResult -Skipped -Because seeded }
    It 'test:EvidenceTruth.Skip skips' { Set-ItResult -Skipped -Because seeded }
    It 'test:EvidenceTruth.Fail fails' { throw 'seeded evidence failure' }
    It 'unselected failure stays unexecuted' { throw 'evidence selection widened' }
    Context 'test:EvidenceTruth.Parent context' {
        It 'unrelated child fails if selected through its parent' { throw 'parent name widened evidence selection' }
    }
}
'@
        $result = Invoke-EvidenceRunner -Root $fixture -Id @(
            'EvidenceTruth.Pass',
            'EvidenceTruth.Named',
            'EvidenceTruth.Expandable',
            'EvidenceTruth.Mixed',
            'EvidenceTruth.Skip',
            'EvidenceTruth.Missing'
        )
        $result.ExitCode | Should -Be 8 -Because $result.Output
        $result.Result | Should -Not -BeNullOrEmpty -Because $result.Output
        $byMarker = @{}
        foreach ($record in $result.Result.results) { $byMarker[[string]$record.marker] = $record }
        $byMarker['test:EvidenceTruth.Pass'].status | Should -Be 'passed'
        $byMarker['test:EvidenceTruth.Named'].status | Should -Be 'passed'
        $byMarker['test:EvidenceTruth.Expandable'].status | Should -Be 'passed'
        $byMarker['test:EvidenceTruth.Mixed'].status | Should -Be 'degraded'
        $byMarker['test:EvidenceTruth.Skip'].status | Should -Be 'skipped'
        $byMarker['test:EvidenceTruth.Missing'].status | Should -Be 'unrun'
        $byMarker['test:EvidenceTruth.Mixed'].selectedCount | Should -Be 2
        $byMarker['test:EvidenceTruth.Mixed'].executedCount | Should -Be 1

        $planDir = New-EvidencePlanFixture -Markers @(
            'test:EvidenceTruth.Pass',
            'test:EvidenceTruth.Named',
            'test:EvidenceTruth.Expandable',
            'test:EvidenceTruth.Mixed',
            'test:EvidenceTruth.Skip',
            'test:EvidenceTruth.Missing'
        )
        $structuredReceipt = & $script:builder -StructuredTestResultPath $result.ResultPath `
            -Commit $script:head -PlanDir $planDir -RepoRoot $script:repoRoot
        @($structuredReceipt.Outcomes).Count | Should -Be 6
        @($structuredReceipt.Outcomes | Where-Object Status -eq 'passed').Count | Should -Be 3
        @($structuredReceipt.Outcomes | Where-Object Status -eq 'degraded').Count | Should -Be 1

        $basePayload = Get-Content -LiteralPath $result.ResultPath -Raw | ConvertFrom-Json -AsHashtable
        foreach ($contradiction in @(
                @{ Status = 'passed'; Selected = 1; Executed = 1; Outcomes = @('Failed') },
                @{ Status = 'passed'; Selected = 1; Executed = 0; Outcomes = @('Passed') },
                @{ Status = 'passed'; Selected = 0; Executed = 0; Outcomes = @() }
            )) {
            $payload = $basePayload | ConvertTo-Json -Depth 20 | ConvertFrom-Json -AsHashtable
            $payload['results'] = @($payload['results'][0])
            $payload['results'][0]['status'] = $contradiction.Status
            $payload['results'][0]['selectedCount'] = $contradiction.Selected
            $payload['results'][0]['executedCount'] = $contradiction.Executed
            $payload['results'][0]['outcomes'] = $contradiction.Outcomes
            $payload['selectedCount'] = $contradiction.Selected
            $payload['executedCount'] = $contradiction.Executed
            Set-Content -LiteralPath $result.ResultPath `
                -Value ($payload | ConvertTo-Json -Depth 20) -Encoding utf8NoBOM
            { & $script:builder -StructuredTestResultPath $result.ResultPath `
                    -Commit $script:head -PlanDir $planDir -RepoRoot $script:repoRoot } |
                Should -Throw
        }

        $passed = Invoke-EvidenceRunner -Root $fixture -Id @('EvidenceTruth.Pass')
        $passed.ExitCode | Should -Be 0 -Because $passed.Output
        $passed.Result.results[0].status | Should -Be 'passed'

        $wrongCase = Invoke-EvidenceRunner -Root $fixture -Id @('evidencetruth.casesensitive')
        $wrongCase.ExitCode | Should -Be 8 -Because $wrongCase.Output
        $wrongCase.Result.results[0].status | Should -Be 'unrun'

        $parentName = Invoke-EvidenceRunner -Root $fixture -Id @('EvidenceTruth.Parent')
        $parentName.ExitCode | Should -Be 8 -Because $parentName.Output
        $parentName.Result.results[0].status | Should -Be 'unrun'

        $failed = Invoke-EvidenceRunner -Root $fixture -Id @('EvidenceTruth.Fail')
        $failed.ExitCode | Should -Be 1 -Because $failed.Output
        $failed.Result.results[0].status | Should -Be 'failed'

        $notRunFixture = New-RunnerFixture -Content @'
$prefix = 'test:EvidenceTruth'
Describe 'not-run evidence' {
    It "$prefix.NotRun never starts" { $true | Should -BeTrue }
}
'@
        $notRun = Invoke-EvidenceRunner -Root $notRunFixture -Id @('EvidenceTruth.NotRun')
        $notRun.ExitCode | Should -Be 8 -Because $notRun.Output
        $notRun.Result.results[0].status | Should -Be 'unrun'
        $notRun.Result.results[0].outcomes | Should -Contain 'NotRun'

        $interrupted = Invoke-EvidenceRunner -Root $fixture -Id @('EvidenceTruth.Pass') -SimulateInterruption
        $interrupted.ExitCode | Should -Be 4 -Because $interrupted.Output
        $interrupted.Output | Should -Match 'TestRunInterrupted'
        $interrupted.Result.results[0].status | Should -Be 'unrun'
        $interrupted.Result.results[0].message | Should -Match 'interrupted'

        @'
@{
    Schema = 'skalary/suite-tier@1'
    FastFocusedHardCeilingSeconds = 60
    SlowHardCeilingSeconds = 600
    CiSetupAllowanceSeconds = 60
    DedicatedFiles = @()
    SlowFiles = @('tests/Fixture.Tests.ps1')
}
'@ | Set-Content -LiteralPath (Join-Path $fixture 'tools/suite-tier.psd1') -Encoding utf8NoBOM
        $slowOwned = Invoke-EvidenceRunner -Root $fixture -Id @('EvidenceTruth.Pass')
        $slowOwned.ExitCode | Should -Be 0 -Because $slowOwned.Output
        $slowOwned.Result.results[0].status | Should -Be 'passed'

        $selectorlessOutput = & pwsh -NoProfile -File $script:runner -RepoRoot $fixture `
            -TestPath 'tests/Fixture.Tests.ps1' 2>&1
        $LASTEXITCODE | Should -Be 12 -Because ($selectorlessOutput | Out-String)

        Set-Content -LiteralPath (Join-Path $fixture 'tests/Fixture.Tests.ps1') -Value @'
Describe 'broken' {
    It 'test:EvidenceTruth.Broken never loads' { $true | Should -BeTrue }
'@ -Encoding utf8NoBOM
        $broken = Invoke-EvidenceRunner -Root $fixture -Id @('EvidenceTruth.Broken')
        $broken.ExitCode | Should -Be 4 -Because $broken.Output
        $broken.Result.results[0].status | Should -Be 'unrun'
        $broken.Result.results[0].message | Should -Match 'discovery error'

        Set-Content -LiteralPath (Join-Path $fixture 'tests/Fixture.Tests.ps1') -Value @'
Describe 'passing selected file' {
    It 'test:EvidenceTruth.DiscoveryConflict passes' { $true | Should -BeTrue }
}
'@ -Encoding utf8NoBOM
        Set-Content -LiteralPath (Join-Path $fixture 'tests/Broken.Tests.ps1') -Value @'
Describe 'broken selected file' {
    It 'test:EvidenceTruth.DiscoveryConflict never loads' { $true | Should -BeTrue }
'@ -Encoding utf8NoBOM
        $discoveryConflict = Invoke-EvidenceRunner -Root $fixture `
            -Id @('EvidenceTruth.DiscoveryConflict') `
            -Path @('tests/Fixture.Tests.ps1', 'tests/Broken.Tests.ps1')
        $discoveryConflict.ExitCode | Should -Be 4 -Because $discoveryConflict.Output
        $discoveryConflict.Result.results[0].status | Should -Be 'unrun'
        $discoveryConflict.Result.results[0].message | Should -Match 'discovery error'
    }

    It 'test:EvidenceTruth.PhysicalConfinement rejects linked runner paths and case-distinct siblings' -Skip:$IsWindows {
        $fixture = New-RunnerFixture -Content @'
Describe 'confined evidence' {
    It 'test:EvidenceTruth.Confined passes' { $true | Should -BeTrue }
}
'@
        $outside = Join-Path ([System.IO.Path]::GetTempPath()) ('evidence-outside-' + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $outside)
        $script:tempRoots.Add($outside)

        $caseTest = Join-Path $fixture 'tests/Case.Tests.ps1'
        $caseTestSibling = Join-Path $fixture 'tests/case.Tests.ps1'
        Set-Content -LiteralPath $caseTest -Value @'
Describe 'case-selected evidence' {
    It 'test:EvidenceTruth.CaseSelected passes' { $true | Should -BeTrue }
}
'@ -Encoding utf8NoBOM
        if (-not (Test-Path -LiteralPath $caseTestSibling)) {
            Set-Content -LiteralPath $caseTestSibling -Value @'
Describe 'case-unselected evidence' {
    It 'test:EvidenceTruth.CaseSelected fails' { throw 'case-distinct selection widened' }
}
'@ -Encoding utf8NoBOM
            $caseResultPath = Join-Path $fixture '.github/.skalary/evidence-results/case-selection-results.json'
            $caseOutput = & pwsh -NoProfile -File $script:runner -RepoRoot $fixture `
                -TestPath 'tests/Case.Tests.ps1' -EvidenceTestId 'EvidenceTruth.CaseSelected' `
                -EvidenceResultPath $caseResultPath 2>&1
            $LASTEXITCODE | Should -Be 0 -Because ($caseOutput | Out-String)
            (Get-Content -LiteralPath $caseResultPath -Raw | ConvertFrom-Json).results[0].status |
                Should -Be 'passed'
        }

        $outsideTest = Join-Path $outside 'External.Tests.ps1'
        Set-Content -LiteralPath $outsideTest -Value @'
Describe 'external evidence' {
    It 'test:EvidenceTruth.External passes' { $true | Should -BeTrue }
}
'@ -Encoding utf8NoBOM
        [void](New-Item -ItemType SymbolicLink -Path (Join-Path $fixture 'tests/Linked.Tests.ps1') -Target $outsideTest)

        $linkedTestOutput = & pwsh -NoProfile -File $script:runner -RepoRoot $fixture `
            -TestPath 'tests/Linked.Tests.ps1' -EvidenceTestId 'EvidenceTruth.External' `
            -EvidenceResultPath '.github/.skalary/evidence-results/linked-test-results.json' 2>&1
        $LASTEXITCODE | Should -Be 12 -Because ($linkedTestOutput | Out-String)
        ($linkedTestOutput | Out-String) | Should -Match 'escapes'

        $outsideResults = Join-Path $outside 'results'
        [void](New-Item -ItemType Directory -Path $outsideResults)
        $linkedResultFixture = New-RunnerFixture -Content @'
Describe 'confined linked result evidence' {
    It 'test:EvidenceTruth.Confined passes' { $true | Should -BeTrue }
}
'@
        [void](New-Item -ItemType Directory -Path (Join-Path $linkedResultFixture '.github/.skalary') -Force)
        [void](New-Item -ItemType SymbolicLink `
                -Path (Join-Path $linkedResultFixture '.github/.skalary/evidence-results') `
                -Target $outsideResults)
        $linkedOutput = & pwsh -NoProfile -File $script:runner -RepoRoot $linkedResultFixture `
            -TestPath 'tests/Fixture.Tests.ps1' -EvidenceTestId 'EvidenceTruth.Confined' `
            -EvidenceResultPath '.github/.skalary/evidence-results/evidence.json' 2>&1
        $LASTEXITCODE | Should -Be 12 -Because ($linkedOutput | Out-String)
        Test-Path -LiteralPath (Join-Path $outsideResults 'evidence.json') | Should -BeFalse

        Set-Content -LiteralPath (Join-Path $outside 'proof.txt') -Value 'outside' -Encoding utf8NoBOM
        [void](New-Item -ItemType SymbolicLink -Path (Join-Path $fixture 'linked-proof.txt') -Target (Join-Path $outside 'proof.txt'))
        [void](New-Item -ItemType SymbolicLink -Path (Join-Path $fixture 'linked-proof-dir') -Target $outside)
        {
            Invoke-PlanFileEvidence -Marker 'file:linked-proof.txt#exists' -RepoRoot $fixture -Stage PhaseCrosscheck
        } | Should -Throw '*escapes repository root via symlink*'
        {
            Invoke-PlanFileEvidence -Marker 'file:linked-proof-dir#dircount>=1' -RepoRoot $fixture -Stage PhaseCrosscheck
        } | Should -Throw '*escapes repository root via symlink*'

        $caseRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('EvidenceCase-' + [guid]::NewGuid().ToString('N'))
        $caseSibling = $caseRoot.ToLowerInvariant()
        if ($caseSibling -ceq $caseRoot) {
            $caseSibling = $caseRoot.ToUpperInvariant()
        }
        [void](New-Item -ItemType Directory -Path $caseRoot)
        $script:tempRoots.Add($caseRoot)
        if (-not (Test-Path -LiteralPath $caseSibling)) {
            [void](New-Item -ItemType Directory -Path $caseSibling)
            $script:tempRoots.Add($caseSibling)
            Set-Content -LiteralPath (Join-Path $caseSibling 'proof.txt') -Value 'outside' -Encoding utf8NoBOM

            $relativeEscape = '../' + (Split-Path -Leaf $caseSibling) + '/proof.txt'
            {
                Invoke-PlanFileEvidence -Marker "file:$relativeEscape#exists" -RepoRoot $caseRoot -Stage PhaseCrosscheck
            } | Should -Throw '*resolves outside repository root*'
        }
    }

    It 'test:EvidenceTruth.FinalizationBlocksNonPassingResults rejects incomplete receipts and accepts exact waivers' {
        foreach ($status in @('failed', 'skipped', 'unrun', 'stale', 'degraded')) {
            $planDir = New-EvidencePlanFixture
            $receipt = & $script:builder -Result @([pscustomobject]@{
                    Req = 'REQ-1'; Marker = 'test:EvidenceTruth.Sample'; Status = $status
                }) -Commit $script:head -PlanDir $planDir -RepoRoot $script:repoRoot
            Set-Content -LiteralPath $receipt.ReceiptPath -Value $receipt.Text -Encoding utf8NoBOM
            $gate = Invoke-TestPlanFixture -PlanDir $planDir
            $gate.ExitCode | Should -Not -Be 0 -Because "$status cannot finalize"
            $gate.Output | Should -Match "is $status"
        }

        $passedPlan = New-EvidencePlanFixture
        $passed = & $script:builder -Result @([pscustomobject]@{
                Req = 'REQ-1'; Marker = 'test:EvidenceTruth.Sample'; Status = 'passed'
            }) -Commit $script:head -PlanDir $passedPlan -RepoRoot $script:repoRoot
        Set-Content -LiteralPath $passed.ReceiptPath -Value $passed.Text -Encoding utf8NoBOM
        $passedGate = Invoke-TestPlanFixture -PlanDir $passedPlan
        $passedGate.ExitCode | Should -Be 0 -Because $passedGate.Output

        $waivedPlan = New-EvidencePlanFixture
        Write-Waiver -PlanDir $waivedPlan
        $waived = & $script:builder -Result @([pscustomobject]@{
                Req = 'REQ-1'; Marker = 'test:EvidenceTruth.Sample'; Status = 'skipped'
            }) -Commit $script:head -PlanDir $waivedPlan -RepoRoot $script:repoRoot
        Set-Content -LiteralPath $waived.ReceiptPath -Value $waived.Text -Encoding utf8NoBOM
        (Invoke-TestPlanFixture -PlanDir $waivedPlan).ExitCode | Should -Be 0

        (Get-Content -LiteralPath $waived.ReceiptPath -Raw).Replace(
            'Unavailable on this platform',
            'forged reason'
        ) | Set-Content -LiteralPath $waived.ReceiptPath -Encoding utf8NoBOM
        (Invoke-TestPlanFixture -PlanDir $waivedPlan).ExitCode | Should -Not -Be 0

        $stalePlan = New-EvidencePlanFixture
        $stale = & $script:builder -Result @([pscustomobject]@{
                Req = 'REQ-1'; Marker = 'test:EvidenceTruth.Sample'; Status = 'passed'
            }) -Commit ('0' * 40) -PlanDir $stalePlan -RepoRoot $script:repoRoot
        Set-Content -LiteralPath $stale.ReceiptPath -Value $stale.Text -Encoding utf8NoBOM
        (Invoke-TestPlanFixture -PlanDir $stalePlan).Output | Should -Match 'is stale'

        $missingPlan = New-EvidencePlanFixture -Markers @(
            'test:EvidenceTruth.Sample',
            'review:cr'
        )
        $partial = & $script:builder -Result @([pscustomobject]@{
                Req = 'REQ-1'; Marker = 'test:EvidenceTruth.Sample'; Status = 'passed'
            }) -Commit $script:head -PlanDir $missingPlan -RepoRoot $script:repoRoot
        Set-Content -LiteralPath $partial.ReceiptPath -Value $partial.Text -Encoding utf8NoBOM
        (Invoke-TestPlanFixture -PlanDir $missingPlan).Output | Should -Match 'missing required marker.*review:cr'

        $casePlan = New-EvidencePlanFixture -Markers @(
            'test:EvidenceTruth.Case',
            'test:EvidenceTruth.case'
        )
        $caseReceipt = & $script:builder -Result @([pscustomobject]@{
                Req = 'REQ-1'; Marker = 'test:EvidenceTruth.Case'; Status = 'passed'
            }) -Commit $script:head -PlanDir $casePlan -RepoRoot $script:repoRoot
        Set-Content -LiteralPath $caseReceipt.ReceiptPath -Value $caseReceipt.Text -Encoding utf8NoBOM
        (Invoke-TestPlanFixture -PlanDir $casePlan).Output |
            Should -Match 'missing required marker.*test:EvidenceTruth\.case'
    }

    It 'test:EvidenceTruth.InstalledParityAndDrift keeps canonical, bundled, and dogfood evidence code identical' {
        $expectedCopies = @{
            'Build-EvidenceReceipt.ps1' = @(
                'plugins/continue-implementation/skills/ci/scripts/Build-EvidenceReceipt.ps1',
                '.github/skills/ci/scripts/Build-EvidenceReceipt.ps1'
            )
            'PlanEvidence.psm1' = @(
                'plugins/autopilot/skills/autopilot/scripts/PlanEvidence.psm1',
                'plugins/continue-implementation/skills/ci/scripts/PlanEvidence.psm1',
                'plugins/create-implementation-plan/skills/cep/scripts/PlanEvidence.psm1',
                'plugins/create-implementation-plan/skills/cip/scripts/PlanEvidence.psm1',
                '.github/skills/autopilot/scripts/PlanEvidence.psm1',
                '.github/skills/ci/scripts/PlanEvidence.psm1',
                '.github/skills/cep/scripts/PlanEvidence.psm1',
                '.github/skills/cip/scripts/PlanEvidence.psm1'
            )
            'Test-Plan.ps1' = @(
                'plugins/autopilot/skills/autopilot/scripts/Test-Plan.ps1',
                'plugins/continue-implementation/skills/ci/scripts/Test-Plan.ps1',
                'plugins/create-implementation-plan/skills/cep/scripts/Test-Plan.ps1',
                'plugins/create-implementation-plan/skills/cip/scripts/Test-Plan.ps1',
                '.github/skills/autopilot/scripts/Test-Plan.ps1',
                '.github/skills/ci/scripts/Test-Plan.ps1',
                '.github/skills/cep/scripts/Test-Plan.ps1',
                '.github/skills/cip/scripts/Test-Plan.ps1'
            )
        }
        foreach ($name in $expectedCopies.Keys) {
            $source = Join-Path $script:repoRoot "scripts/skalary/$name"
            $expectedHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
            foreach ($relativePath in $expectedCopies[$name]) {
                $copy = Join-Path $script:repoRoot $relativePath
                Test-Path -LiteralPath $copy -PathType Leaf | Should -BeTrue -Because $relativePath
                (Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash |
                    Should -BeExactly $expectedHash -Because $relativePath
            }
        }

        & (Join-Path $script:repoRoot '.github/skills/ci/scripts/Test-Plan.ps1') `
            -EvidenceMarker 'file:README.md#exists' -EvidenceStage PhaseCrosscheck
        $LASTEXITCODE | Should -Be 0
    }
}
