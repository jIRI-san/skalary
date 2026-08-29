#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Evidence truth' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:builder = Join-Path $script:repoRoot 'scripts/skalary/Build-EvidenceReceipt.ps1'
        $script:testPlan = Join-Path $script:repoRoot 'scripts/skalary/Test-Plan.ps1'
        $script:runner = Join-Path $script:repoRoot 'scripts/skalary/Run-UnitTests.ps1'
        $script:cycleGate = Join-Path $script:repoRoot 'scripts/skalary/ReviewCycleGate.ps1'
        $script:head = (& git -C $script:repoRoot rev-parse HEAD).Trim()
        $script:defaultRef = (& git -C $script:repoRoot symbolic-ref refs/remotes/origin/HEAD).Trim()
        $script:base = (& git -C $script:repoRoot merge-base $script:head $script:defaultRef).Trim()
        $script:pathCount = @(& git -C $script:repoRoot diff --name-only "$script:base..$script:head").Count
        $script:tempRoots = [System.Collections.Generic.List[string]]::new()

        function New-EvidencePlanFixture {
            param([string[]]$Markers = @('test:EvidenceTruth.Sample'))

            $root = Join-Path ([System.IO.Path]::GetTempPath()) ('evidence-truth-' + [guid]::NewGuid().ToString('N'))
            $planDir = Join-Path $root 'docs/implementation-plans/2026-08-29-abcdef-evidence-truth'
            [void](New-Item -ItemType Directory -Path $planDir -Force)
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
"@ | Set-Content -LiteralPath (Join-Path $planDir 'plan.md') -Encoding utf8NoBOM
            return $planDir
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

        function Write-CleanReviewResult {
            param(
                [Parameter(Mandatory)][string]$PlanDir,
                [string]$RunId = [guid]::NewGuid().ToString(),
                [ValidateSet('branch', 'paths')][string]$Mode = 'branch'
            )

            $store = Join-Path $PlanDir 'reviews'
            [void](New-Item -ItemType Directory -Path $store -Force)
            $reportPath = Join-Path $store "$RunId.review.md"
            Set-Content -LiteralPath $reportPath -Value "# Clean review $RunId" -Encoding utf8NoBOM
            $reportBytes = [System.IO.File]::ReadAllBytes($reportPath)
            $reportDigest = 'sha256:' + [Convert]::ToHexString(
                [System.Security.Cryptography.SHA256]::HashData($reportBytes)
            ).ToLowerInvariant()
            [ordered]@{
                schema = 'skalary/review-result-receipt@1'
                runId = $RunId
                reviewType = 'code'
                verdict = 'approved'
                state = 'clean'
                source = [ordered]@{ mode = $Mode; base = $script:base; head = $script:head; pathCount = $script:pathCount; digest = 'sha256:' + ('1' * 64) }
                planDigest = 'sha256:' + ('2' * 64)
                runDigest = 'sha256:' + ('3' * 64)
                manifestDigest = 'sha256:' + ('4' * 64)
                legacySource = $false
                attendance = [ordered]@{ completed = 1; failed = 0; 'timed-out' = 0; omitted = 0; cancelled = 0; pending = 0 }
                findings = [ordered]@{
                    merged = 0
                    raw = 0
                    severity = [ordered]@{ critical = 0; high = 0; medium = 0; low = 0 }
                }
                report = [ordered]@{ name = "$RunId.review.md"; bytes = $reportBytes.Length; digest = $reportDigest }
            } | ConvertTo-Json -Depth 10 -Compress |
                Set-Content -LiteralPath (Join-Path $store "$RunId.receipt.json") -Encoding utf8NoBOM
            return $RunId
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
    It 'test:EvidenceTruth.Mixed passes' { $true | Should -BeTrue }
    It 'test:EvidenceTruth.Mixed skips' { Set-ItResult -Skipped -Because seeded }
    It 'test:EvidenceTruth.Skip skips' { Set-ItResult -Skipped -Because seeded }
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

        Set-Content -LiteralPath (Join-Path $fixture 'tests/Fixture.Tests.ps1') -Value @'
Describe 'broken' {
    It 'test:EvidenceTruth.Broken never loads' { $true | Should -BeTrue }
'@ -Encoding utf8NoBOM
        $broken = Invoke-EvidenceRunner -Root $fixture -Id @('EvidenceTruth.Broken')
        $broken.ExitCode | Should -Be 4 -Because $broken.Output
        $broken.Result.results[0].status | Should -Be 'unrun'
        $broken.Result.results[0].message | Should -Match 'discovery error'
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
    }

    It 'test:EvidenceTruth.WrappedReviewReplacement rejects false wrap claims and accepts a clean authorized replacement' {
        $planDir = New-EvidencePlanFixture -Markers @('review:cr')
        foreach ($cycle in 1..3) {
            [void](& $script:cycleGate -Action Record -PlanDir $planDir -Phase 1 `
                    -Stage plan-finalization -Outcome findings)
        }
        [void](& $script:cycleGate -Action Wrap -PlanDir $planDir -Phase 1 -Stage plan-finalization)

        $receiptPath = Join-Path $planDir 'evidence.md'
        "✓ REQ-1 — review:cr — passed: wrapped/degraded — $script:head" |
            Set-Content -LiteralPath $receiptPath -Encoding utf8NoBOM
        $fabricated = Invoke-TestPlanFixture -PlanDir $planDir
        $fabricated.ExitCode | Should -Not -Be 0
        $fabricated.Output | Should -Match 'no qualifying review-run id'

        { & $script:builder -Result @([pscustomobject]@{
                    Req = 'REQ-1'
                    Marker = 'review:cr'
                    Status = 'passed'
                    ReviewRunId = [guid]::NewGuid().ToString()
                }) -Commit $script:head -PlanDir $planDir -RepoRoot $script:repoRoot } |
            Should -Throw "*review-cycle stage 'plan-finalization' is 'wrap'*"

        [void](& $script:cycleGate -Action Reopen -PlanDir $planDir -Phase 1 `
                -Stage plan-finalization -OperatorAuthorization 'operator-ticket-44' `
                -Reason 'replace wrapped review evidence')
        $pathRunId = Write-CleanReviewResult -PlanDir $planDir -Mode paths
        { & $script:cycleGate -Action Record -PlanDir $planDir -Phase 1 `
                -Stage plan-finalization -Outcome clean -ReviewRunId $pathRunId -RepoRoot $script:repoRoot } |
            Should -Throw '*not whole-branch evidence*'
        $runId = Write-CleanReviewResult -PlanDir $planDir
        [void](& $script:cycleGate -Action Record -PlanDir $planDir -Phase 1 `
                -Stage plan-finalization -Outcome clean -ReviewRunId $runId -RepoRoot $script:repoRoot)

        $replacement = & $script:builder -Result @([pscustomobject]@{
                Req = 'REQ-1'
                Marker = 'review:cr'
                Status = 'passed'
                ReviewRunId = $runId
            }) -Commit $script:head -PlanDir $planDir -RepoRoot $script:repoRoot
        Set-Content -LiteralPath $replacement.ReceiptPath -Value $replacement.Text -Encoding utf8NoBOM
        $replacement.Lines[0] | Should -Match "passed: review-run:$runId"
        (Invoke-TestPlanFixture -PlanDir $planDir).ExitCode | Should -Be 0
    }

    It 'test:EvidenceTruth.InstalledParityAndDrift keeps canonical, bundled, and dogfood evidence code identical' {
        $comparisons = @(
            @('scripts/skalary/Build-EvidenceReceipt.ps1', 'plugins/continue-implementation/skills/ci/scripts/Build-EvidenceReceipt.ps1'),
            @('scripts/skalary/Build-EvidenceReceipt.ps1', '.github/skills/ci/scripts/Build-EvidenceReceipt.ps1'),
            @('scripts/skalary/PlanEvidence.psm1', 'plugins/continue-implementation/skills/ci/scripts/PlanEvidence.psm1'),
            @('scripts/skalary/PlanEvidence.psm1', 'plugins/autopilot/skills/autopilot/scripts/PlanEvidence.psm1'),
            @('scripts/skalary/Test-Plan.ps1', 'plugins/continue-implementation/skills/ci/scripts/Test-Plan.ps1'),
            @('scripts/skalary/Test-Plan.ps1', 'plugins/autopilot/skills/autopilot/scripts/Test-Plan.ps1')
        )
        foreach ($pair in $comparisons) {
            $source = Join-Path $script:repoRoot $pair[0]
            $target = Join-Path $script:repoRoot $pair[1]
            (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash |
                Should -BeExactly (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
        }
    }
}
