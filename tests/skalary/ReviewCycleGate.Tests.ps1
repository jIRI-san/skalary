#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'review cycle gate' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:gate = Join-Path $script:repoRoot 'scripts/skalary/ReviewCycleGate.ps1'
        $script:head = (& git -C $script:repoRoot rev-parse HEAD).Trim()

        function Script:New-CyclePlan {
            $root = Join-Path ([System.IO.Path]::GetTempPath()) ('review-cycle-' + [guid]::NewGuid().ToString('N'))
            $planDir = Join-Path $root 'docs/implementation-plans/2026-08-25-abc123-review-cycle'
            [void](New-Item -ItemType Directory -Path (Join-Path $planDir 'assets') -Force)
            Set-Content -LiteralPath (Join-Path $planDir 'plan.md') -Value "# abc123: Review cycle`n<!-- plan-id: abc123 -->`n" -Encoding utf8NoBOM
            return $planDir
        }

        function Script:Invoke-CycleGate {
            param(
                [string]$PlanDir,
                [string]$Action,
                [string]$Stage = 'step-1.1',
                [string]$Outcome,
                [string]$Summary,
                [string]$ReviewRunId,
                [string]$OperatorAuthorization,
                [string]$Reason
            )
            $arguments = @{
                Action = $Action
                PlanDir = $PlanDir
                Phase = 1
                Stage = $Stage
                RepoRoot = $script:repoRoot
            }
            if ($Outcome) { $arguments.Outcome = $Outcome }
            if ($Summary) { $arguments.Summary = $Summary }
            if ($ReviewRunId) { $arguments.ReviewRunId = $ReviewRunId }
            if ($OperatorAuthorization) { $arguments.OperatorAuthorization = $OperatorAuthorization }
            if ($Reason) { $arguments.Reason = $Reason }
            return & $script:gate @arguments
        }

        function Script:Write-CleanReviewResult {
            param([Parameter(Mandatory)][string]$PlanDir, [string]$RunId = [guid]::NewGuid().ToString())

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
                source = [ordered]@{ mode = 'branch'; base = '0' * 40; head = $script:head; pathCount = 1; digest = 'sha256:' + ('1' * 64) }
                planDigest = 'sha256:' + ('2' * 64)
                runDigest = 'sha256:' + ('3' * 64)
                manifestDigest = 'sha256:' + ('4' * 64)
                legacySource = $false
                attendance = [ordered]@{ completed = 1; failed = 0; 'timed-out' = 0; omitted = 0; cancelled = 0; pending = 0 }
                findings = [ordered]@{
                    merged = 0
                    raw = 0
                    severity = [ordered]@{ critical = 0; high = 0; medium = 0; low = 0 }
                    rawSeverity = [ordered]@{ critical = 0; high = 0; medium = 0; low = 0 }
                    corroboration = [ordered]@{ corroborated = 0; 'single-source' = 0; suspicious = 0; degraded = 0 }
                    similarity = [ordered]@{ none = 0; 'near-duplicate' = 0; exact = 0 }
                    needsReview = 0
                }
                report = [ordered]@{ name = "$RunId.review.md"; bytes = $reportBytes.Length; digest = $reportDigest }
            } | ConvertTo-Json -Depth 10 -Compress |
                Set-Content -LiteralPath (Join-Path $store "$RunId.receipt.json") -Encoding utf8NoBOM
            return $RunId
        }
    }

    It 'test:ReviewCycleGate caps automatic review at three cycles and persists across invocations' {
        $plan = New-CyclePlan
        try {
            (Invoke-CycleGate -PlanDir $plan -Action Check).state | Should -Be 'allow'
            foreach ($cycle in 1..2) {
                $result = Invoke-CycleGate -PlanDir $plan -Action Record -Outcome findings -Summary "remaining-$cycle"
                $result.cycles | Should -Be $cycle
                $result.state | Should -Be 'allow'
            }
            $third = Invoke-CycleGate -PlanDir $plan -Action Record -Outcome findings -Summary 'remaining-3'
            $third.cycles | Should -Be 3
            $third.state | Should -Be 'operator-decision'
            $third.operatorDecisionRequired | Should -BeTrue
            (Invoke-CycleGate -PlanDir $plan -Action Check).state | Should -Be 'operator-decision'
            { Invoke-CycleGate -PlanDir $plan -Action Record -Outcome findings } | Should -Throw -ExpectedMessage '*blocked*'
        }
        finally { Remove-Item -LiteralPath $plan -Recurse -Force }
    }

    It 'test:ReviewCycleGate grants one extra cycle per continue decision then asks again' {
        $plan = New-CyclePlan
        try {
            foreach ($cycle in 1..3) { [void](Invoke-CycleGate -PlanDir $plan -Action Record -Outcome findings) }
            $continued = Invoke-CycleGate -PlanDir $plan -Action Continue
            $continued.state | Should -Be 'allow'
            $continued.decision.after | Should -Be 3
            $fourth = Invoke-CycleGate -PlanDir $plan -Action Record -Outcome findings
            $fourth.cycles | Should -Be 4
            $fourth.state | Should -Be 'operator-decision'
        }
        finally { Remove-Item -LiteralPath $plan -Recurse -Force }
    }

    It 'test:ReviewCycleGate records wrap and isolates independent stages' {
        $plan = New-CyclePlan
        try {
            foreach ($cycle in 1..3) { [void](Invoke-CycleGate -PlanDir $plan -Action Record -Outcome findings) }
            $wrapped = Invoke-CycleGate -PlanDir $plan -Action Wrap
            $wrapped.state | Should -Be 'wrap'
            $wrapped.canReview | Should -BeFalse
            (Invoke-CycleGate -PlanDir $plan -Action Check -Stage 'phase-1').state | Should -Be 'allow'
            $text = Get-Content -LiteralPath $wrapped.logPath -Raw
            $text | Should -Match 'review-cycle-decision stage=step-1\.1 after=3 action=wrap'
        }
        finally { Remove-Item -LiteralPath $plan -Recurse -Force }
    }

    It 'test:ReviewCycleGate requires operator authorization and appends reopen history' {
        $plan = New-CyclePlan
        try {
            foreach ($cycle in 1..3) { [void](Invoke-CycleGate -PlanDir $plan -Action Record -Outcome findings) }
            $wrapped = Invoke-CycleGate -PlanDir $plan -Action Wrap
            $before = Get-Content -LiteralPath $wrapped.logPath -Raw

            { Invoke-CycleGate -PlanDir $plan -Action Reopen -Reason 'replacement review approved' } |
                Should -Throw '*explicit -OperatorAuthorization*'
            (Get-Content -LiteralPath $wrapped.logPath -Raw) | Should -BeExactly $before

            $reopened = Invoke-CycleGate -PlanDir $plan -Action Reopen `
                -OperatorAuthorization 'operator-ticket-42' -Reason 'replacement review approved'
            $reopened.state | Should -Be 'allow'
            $reopened.canReview | Should -BeTrue
            $reopened.remediation.authorization | Should -Be 'operator-ticket-42'

            $text = Get-Content -LiteralPath $wrapped.logPath -Raw
            $text | Should -Match 'review-cycle-decision stage=step-1\.1 after=3 action=wrap'
            $text | Should -Match 'review-cycle-remediation stage=step-1\.1 after=3 action=reopen authorization=operator-ticket-42'
        }
        finally { Remove-Item -LiteralPath $plan -Recurse -Force }
    }

    It 'test:ReviewCycleGate resumes after reopen and completes from clean replacement evidence' {
        $plan = New-CyclePlan
        try {
            foreach ($cycle in 1..3) { [void](Invoke-CycleGate -PlanDir $plan -Action Record -Outcome findings) }
            [void](Invoke-CycleGate -PlanDir $plan -Action Wrap)
            [void](Invoke-CycleGate -PlanDir $plan -Action Reopen `
                    -OperatorAuthorization 'operator-ticket-43' -Reason 'run a clean replacement')

            (Invoke-CycleGate -PlanDir $plan -Action Check).state | Should -Be 'allow'
            $runId = Write-CleanReviewResult -PlanDir $plan
            $clean = Invoke-CycleGate -PlanDir $plan -Action Record -Outcome clean -ReviewRunId $runId
            $clean.state | Should -Be 'complete'
            $clean.reviewRunId | Should -Be $runId

            $resumed = Invoke-CycleGate -PlanDir $plan -Action Check
            $resumed.state | Should -Be 'complete'
            $resumed.reviewRunId | Should -Be $runId
            $resumed.cycles | Should -Be 4
        }

        finally { Remove-Item -LiteralPath $plan -Recurse -Force }
    }

    It 'test:ReviewCycleGate reopens legacy runless clean history without rewriting it' {
        $plan = New-CyclePlan
        try {
            [void](Invoke-CycleGate -PlanDir $plan -Action Record -Outcome findings)
            $logPath = (Invoke-CycleGate -PlanDir $plan -Action Check).logPath
            $legacy = (Get-Content -LiteralPath $logPath -Raw).Replace('outcome=findings', 'outcome=clean')
            Set-Content -LiteralPath $logPath -Value $legacy -Encoding utf8NoBOM

            (Invoke-CycleGate -PlanDir $plan -Action Check).state | Should -Be 'legacy-clean'
            $before = Get-Content -LiteralPath $logPath -Raw
            $reopened = Invoke-CycleGate -PlanDir $plan -Action Reopen `
                -OperatorAuthorization 'operator-ticket-legacy' -Reason 'replace runless clean evidence'
            $reopened.state | Should -Be 'allow'
            (Get-Content -LiteralPath $logPath -Raw) | Should -Match ([regex]::Escape($before.Trim()))
        }
        finally { Remove-Item -LiteralPath $plan -Recurse -Force }
    }

    It 'test:ReviewCycleGate completes immediately when a recorded review is clean' {
        $plan = New-CyclePlan
        try {
            $runId = Write-CleanReviewResult -PlanDir $plan
            $result = Invoke-CycleGate -PlanDir $plan -Action Record -Outcome clean `
                -ReviewRunId $runId -Summary 'zero-blockers'
            $result.state | Should -Be 'complete'
            $result.cycles | Should -Be 1
            (Invoke-CycleGate -PlanDir $plan -Action Check).state | Should -Be 'complete'
        }
        finally { Remove-Item -LiteralPath $plan -Recurse -Force }
    }
}