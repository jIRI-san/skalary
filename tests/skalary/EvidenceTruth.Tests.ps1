#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Evidence truth' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:builder = Join-Path $script:repoRoot 'scripts/skalary/Build-EvidenceReceipt.ps1'
        $script:testPlan = Join-Path $script:repoRoot 'scripts/skalary/Test-Plan.ps1'
        $script:runner = Join-Path $script:repoRoot 'scripts/skalary/Run-UnitTests.ps1'
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
                [string]$Reason = 'Unavailable on this platform'
            )

            [ordered]@{
                schema = 'skalary/evidence-waivers@1'
                waivers = @(
                    [ordered]@{
                        plan = $Plan
                        requirement = $Requirement
                        marker = $Marker
                        outcome = $Outcome
                        reason = $Reason
                    }
                )
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
                [Parameter(Mandatory)][string[]]$Id
            )

            $resultPath = Join-Path $Root 'evidence-results.json'
            $quotedIds = @($Id | ForEach-Object { "'$_'" }) -join ','
            $driver = Join-Path $Root 'driver.ps1'
            @"
& '$script:runner' -RepoRoot '$Root' -TestPath @('tests/Fixture.Tests.ps1') -EvidenceTestId @($quotedIds) -EvidenceResultPath '$resultPath'
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
    }

    It 'test:EvidenceTruth.FocusedStructuredResults reports pass, skip, degraded, missing, and discovery outcomes' {
        $fixture = New-RunnerFixture -Content @'
Describe 'focused evidence' {
    It 'test:EvidenceTruth.Pass works' { $true | Should -BeTrue }
    It 'test:EvidenceTruth.CaseSensitive works' { $true | Should -BeTrue }
    It 'test:EvidenceTruth.Mixed passes' { $true | Should -BeTrue }
    It 'test:EvidenceTruth.Mixed skips' { Set-ItResult -Skipped -Because seeded }
    It 'test:EvidenceTruth.Skip skips' { Set-ItResult -Skipped -Because seeded }
    It 'unselected failure stays unexecuted' { throw 'evidence selection widened' }
}
'@
        $result = Invoke-EvidenceRunner -Root $fixture -Id @(
            'EvidenceTruth.Pass',
            'EvidenceTruth.Mixed',
            'EvidenceTruth.Skip',
            'EvidenceTruth.Missing'
        )
        $result.ExitCode | Should -Be 8 -Because $result.Output
        $result.Result | Should -Not -BeNullOrEmpty -Because $result.Output
        $byMarker = @{}
        foreach ($record in $result.Result.results) { $byMarker[[string]$record.marker] = $record }
        $byMarker['test:EvidenceTruth.Pass'].status | Should -Be 'passed'
        $byMarker['test:EvidenceTruth.Mixed'].status | Should -Be 'degraded'
        $byMarker['test:EvidenceTruth.Skip'].status | Should -Be 'skipped'
        $byMarker['test:EvidenceTruth.Missing'].status | Should -Be 'unrun'
        $byMarker['test:EvidenceTruth.Mixed'].selectedCount | Should -Be 2
        $byMarker['test:EvidenceTruth.Mixed'].executedCount | Should -Be 1

        $passed = Invoke-EvidenceRunner -Root $fixture -Id @('EvidenceTruth.Pass')
        $passed.ExitCode | Should -Be 0 -Because $passed.Output
        $passed.Result.results[0].status | Should -Be 'passed'

        $wrongCase = Invoke-EvidenceRunner -Root $fixture -Id @('evidencetruth.casesensitive')
        $wrongCase.ExitCode | Should -Be 8 -Because $wrongCase.Output
        $wrongCase.Result.results[0].status | Should -Be 'unrun'

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
            $caseResultPath = Join-Path $fixture 'case-selection-results.json'
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
            -EvidenceResultPath 'linked-test-results.json' 2>&1
        $LASTEXITCODE | Should -Be 12 -Because ($linkedTestOutput | Out-String)
        ($linkedTestOutput | Out-String) | Should -Match 'escapes'

        $outsideResults = Join-Path $outside 'results'
        [void](New-Item -ItemType Directory -Path $outsideResults)
        [void](New-Item -ItemType SymbolicLink -Path (Join-Path $fixture 'linked-results') -Target $outsideResults)
        $linkedOutput = & pwsh -NoProfile -File $script:runner -RepoRoot $fixture `
            -TestPath 'tests/Fixture.Tests.ps1' -EvidenceTestId 'EvidenceTruth.Confined' `
            -EvidenceResultPath 'linked-results/evidence.json' 2>&1
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

            Import-Module (Join-Path $script:repoRoot 'scripts/skalary/PlanEvidence.psm1') -Force -DisableNameChecking
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
        foreach ($name in @('Build-EvidenceReceipt.ps1', 'PlanEvidence.psm1', 'Test-Plan.ps1')) {
            $source = Join-Path $script:repoRoot "scripts/skalary/$name"
            $expectedHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
            $copies = @(
                Get-ChildItem -LiteralPath (Join-Path $script:repoRoot 'plugins') -Recurse -File -Filter $name
                Get-ChildItem -LiteralPath (Join-Path $script:repoRoot '.github') -Recurse -File -Filter $name
            )
            $copies.Count | Should -BeGreaterThan 0
            foreach ($copy in $copies) {
                (Get-FileHash -LiteralPath $copy.FullName -Algorithm SHA256).Hash |
                    Should -BeExactly $expectedHash -Because $copy.FullName
            }
        }
    }
}
