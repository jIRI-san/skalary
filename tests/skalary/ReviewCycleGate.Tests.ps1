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
                [int]$Phase = 1,
                [string]$Outcome,
                [string]$Summary,
                [string]$ReviewRunId,
                [string]$OperatorAuthorization,
                [string]$SourceRecordId,
                [string]$Reason,
                [string]$RepoRoot = $script:repoRoot,
                [string]$GatePath = $script:gate
            )
            $arguments = @{
                Action = $Action
                PlanDir = $PlanDir
                Phase = $Phase
                Stage = $Stage
                RepoRoot = $RepoRoot
            }
            if ($Outcome) { $arguments.Outcome = $Outcome }
            if ($Summary) { $arguments.Summary = $Summary }
            if ($ReviewRunId) { $arguments.ReviewRunId = $ReviewRunId }
            if ($OperatorAuthorization) { $arguments.OperatorAuthorization = $OperatorAuthorization }
            if ($SourceRecordId) { $arguments.SourceRecordId = $SourceRecordId }
            if ($Reason) { $arguments.Reason = $Reason }
            return & $GatePath @arguments
        }

        function Script:New-Ca8ba8UnauthorizedReopenFixture {
            param([string]$PlanId = 'ca8ba8')

            $root = Join-Path ([System.IO.Path]::GetTempPath()) (
                'review-cycle-ca8ba8-' + [guid]::NewGuid().ToString('N')
            )
            $planDir = Join-Path $root 'docs/implementation-plans/2026-08-08-ca8ba8-review-corroboration-truth'
            $logsDir = Join-Path $planDir 'assets/logs'
            [void](New-Item -ItemType Directory -Path $logsDir -Force)
            Set-Content -LiteralPath (Join-Path $planDir 'plan.md') -Encoding utf8NoBOM -Value @"
# $PlanId`: Review corroboration truth
<!-- plan-id: $PlanId -->

## Phase 1: Complete
- [x] 1.1 complete
"@
            Set-Content -LiteralPath (Join-Path $planDir 'assets/requirements.md') `
                -Value '# Requirements' -Encoding utf8NoBOM
            $log = @'
## CR Capture
Phase: 4

- [-] [src:note] [sev:Low] [concern:maintainability-consistency] [req:-] [review:cr] [source-record:1111111111111111111111111111111111111111111111111111111111111111] review-cycle stage=plan-finalization cycle=1 outcome=findings
- [-] [src:note] [sev:Low] [concern:maintainability-consistency] [req:-] [review:cr] [source-record:2222222222222222222222222222222222222222222222222222222222222222] review-cycle stage=plan-finalization cycle=2 outcome=findings
- [-] [src:note] [sev:Low] [concern:maintainability-consistency] [req:-] [review:cr] [source-record:3333333333333333333333333333333333333333333333333333333333333333] review-cycle stage=plan-finalization cycle=3 outcome=findings
- [-] [src:note] [sev:Low] [concern:maintainability-consistency] [req:-] [review:cr] [source-record:9711d75abcb64068567ae7893653e455fc2d2d670ae9a3f3f72f11a211203d1f] review-cycle-decision stage=plan-finalization after=3 action=continue
- [-] [src:note] [sev:Low] [concern:maintainability-consistency] [req:-] [review:cr] [source-record:cda6d7ea5631737e6fc0410973121f502916c2fcc05496f41407d50914403655] review-cycle stage=plan-finalization cycle=4 outcome=findings run=3a8b2d6d-c0e2-483b-8a0c-a9b2aaa93ac8 summary=attendance=degraded-5-failed;findings=6;fixed=3;rejected=3
- [-] [src:note] [sev:Low] [concern:maintainability-consistency] [req:-] [review:cr] [source-record:c84796eb882be0deee69cca7afa6834eab36e9ce991ea2086f34984e40af3da4] review-cycle-decision stage=plan-finalization after=4 action=continue
- [-] [src:note] [sev:Low] [concern:maintainability-consistency] [req:-] [review:cr] [source-record:23b9ecc3961506f9287576c91c8165169e4cd879227e38b21fdd19d17ce0a3a8] review-cycle-remediation stage=plan-finalization after=4 action=invalidate-continue target=sha256:6ed472818bddf95fadabf5346d1ee2872f46316d6e86d98f26218147b2ad49c7 authorization=coordinator-pr22-ca8ba8-finalization-cap timestamp=2026-08-30T02:38:54.9634610Z reason=The single authorized finalization Continue cap was already consumed after cycle 3; the after=4 Continue appended by commit 0fce38b was unauthorized.
- [-] [src:note] [sev:Low] [concern:maintainability-consistency] [req:-] [review:cr] [source-record:c5bbf0ec173965b89c01839bb37acf5752c08213c4589298c1573a4a387cf026] review-cycle-decision stage=plan-finalization after=4 action=wrap
- [-] [src:note] [sev:Low] [concern:maintainability-consistency] [req:-] [review:cr] [source-record:5bcdcfd38636c7768f0ea526e0593c91ad41edb0eead7354c62a5a3a07b9149b] review-cycle-remediation stage=plan-finalization after=4 action=reopen authorization=operator-2026-08-30-plan-completion-resume reason=Operator explicitly directed continuation of pending plan-completion review, validation, archive, push, and PR work.
'@
            Set-Content -LiteralPath (Join-Path $logsDir 'cr-log.md') `
                -Value ($log -replace "`r`n?", "`n") -Encoding utf8NoBOM -NoNewline
            return [pscustomobject]@{
                Root = $root
                PlanDir = $planDir
                LogPath = Join-Path $logsDir 'cr-log.md'
                SourceRecordId = '5bcdcfd38636c7768f0ea526e0593c91ad41edb0eead7354c62a5a3a07b9149b'
            }
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

        It 'test:ReviewCycleGate invalidates only the latest Continue append-only and permits truthful Wrap' {
            $plan = New-CyclePlan
            try {
                foreach ($cycle in 1..3) { [void](Invoke-CycleGate -PlanDir $plan -Action Record -Outcome findings) }
                $continued = Invoke-CycleGate -PlanDir $plan -Action Continue
                $before = Get-Content -LiteralPath $continued.logPath -Raw

                { Invoke-CycleGate -PlanDir $plan -Action InvalidateContinue -Reason 'unauthorized continuation' } |
                    Should -Throw '*explicit -OperatorAuthorization*'
                (Get-Content -LiteralPath $continued.logPath -Raw) | Should -BeExactly $before

                $invalidated = Invoke-CycleGate -PlanDir $plan -Action InvalidateContinue `
                    -OperatorAuthorization 'operator-ticket-continue-4' -Reason 'continuation exceeded the approved cap'
                $invalidated.state | Should -Be 'operator-decision'
                $invalidated.cycles | Should -Be 3
                $invalidated.canReview | Should -BeFalse
                $invalidated.operatorDecisionRequired | Should -BeTrue
                $invalidated.remediation.action | Should -Be 'invalidate-continue'
                $invalidated.remediation.targetEventId | Should -Match '^sha256:[0-9a-f]{64}$'
                $invalidated.remediation.timestamp | Should -Match 'Z$'

                $afterInvalidation = Get-Content -LiteralPath $invalidated.logPath -Raw
                { Invoke-CycleGate -PlanDir $plan -Action Continue } |
                    Should -Throw '*cannot be re-recorded*invalidated*'
                (Get-Content -LiteralPath $invalidated.logPath -Raw) | Should -BeExactly $afterInvalidation

                $wrapped = Invoke-CycleGate -PlanDir $plan -Action Wrap
                $wrapped.state | Should -Be 'wrap'
                $text = Get-Content -LiteralPath $wrapped.logPath -Raw
                $text | Should -Match 'review-cycle-decision stage=step-1\.1 after=3 action=continue'
                $text | Should -Match ('action=invalidate-continue target=' +
                    [regex]::Escape($invalidated.remediation.targetEventId) +
                    ' authorization=operator-ticket-continue-4 timestamp=[^ ]+ reason=continuation exceeded the approved cap')
                $text | Should -Match 'review-cycle-decision stage=step-1\.1 after=3 action=wrap'
                ($text.IndexOf('action=continue') -lt $text.IndexOf('action=invalidate-continue')) | Should -BeTrue
                ($text.IndexOf('action=invalidate-continue') -lt $text.IndexOf('action=wrap')) | Should -BeTrue
            }
            finally { Remove-Item -LiteralPath $plan -Recurse -Force }
        }

        It 'test:ReviewCycleGate rejects duplicate, wrong-stage, and missing Continue invalidations without mutation' {
            $plan = New-CyclePlan
            try {
                foreach ($cycle in 1..3) { [void](Invoke-CycleGate -PlanDir $plan -Action Record -Outcome findings) }
                $logPath = (Invoke-CycleGate -PlanDir $plan -Action Check).logPath
                $before = Get-Content -LiteralPath $logPath -Raw

                { Invoke-CycleGate -PlanDir $plan -Action InvalidateContinue `
                        -OperatorAuthorization 'operator-ticket-none' -Reason 'no target' } |
                    Should -Throw '*latest event*Continue*'
                { Invoke-CycleGate -PlanDir $plan -Action InvalidateContinue -Stage 'phase-1' `
                        -OperatorAuthorization 'operator-ticket-stage' -Reason 'wrong stage' } |
                    Should -Throw '*latest event*Continue*'
                (Get-Content -LiteralPath $logPath -Raw) | Should -BeExactly $before

                [void](Invoke-CycleGate -PlanDir $plan -Action Continue)
                [void](Invoke-CycleGate -PlanDir $plan -Action InvalidateContinue `
                        -OperatorAuthorization 'operator-ticket-once' -Reason 'void once')
                $afterFirst = Get-Content -LiteralPath $logPath -Raw
                { Invoke-CycleGate -PlanDir $plan -Action InvalidateContinue `
                        -OperatorAuthorization 'operator-ticket-twice' -Reason 'void twice' } |
                    Should -Throw '*already invalidated*'
                (Get-Content -LiteralPath $logPath -Raw) | Should -BeExactly $afterFirst
            }
            finally { Remove-Item -LiteralPath $plan -Recurse -Force }
        }

        It 'test:ReviewCycleGate rejects stale and ambiguous Continue targets without mutation' {
            $stalePlan = New-CyclePlan
            $ambiguousPlan = New-CyclePlan
            try {
                foreach ($plan in @($stalePlan, $ambiguousPlan)) {
                    foreach ($cycle in 1..3) { [void](Invoke-CycleGate -PlanDir $plan -Action Record -Outcome findings) }
                    [void](Invoke-CycleGate -PlanDir $plan -Action Continue)
                }

                $staleLog = (Invoke-CycleGate -PlanDir $stalePlan -Action Check).logPath
                $staleText = (Get-Content -LiteralPath $staleLog -Raw).
                    Replace('after=3 action=continue', 'after=2 action=continue')
                Set-Content -LiteralPath $staleLog -Value $staleText -Encoding utf8NoBOM
                $staleBefore = Get-Content -LiteralPath $staleLog -Raw
                { Invoke-CycleGate -PlanDir $stalePlan -Action InvalidateContinue `
                        -OperatorAuthorization 'operator-ticket-stale' -Reason 'stale target' } |
                    Should -Throw '*stale Continue*'
                (Get-Content -LiteralPath $staleLog -Raw) | Should -BeExactly $staleBefore

                $ambiguousLog = (Invoke-CycleGate -PlanDir $ambiguousPlan -Action Check).logPath
                $continueLine = @(Get-Content -LiteralPath $ambiguousLog |
                        Where-Object { $_ -match 'after=3 action=continue$' })[0]
                Add-Content -LiteralPath $ambiguousLog -Value $continueLine -Encoding utf8NoBOM
                $ambiguousBefore = Get-Content -LiteralPath $ambiguousLog -Raw
                { Invoke-CycleGate -PlanDir $ambiguousPlan -Action InvalidateContinue `
                        -OperatorAuthorization 'operator-ticket-ambiguous' -Reason 'ambiguous target' } |
                    Should -Throw '*ambiguous Continue target*'
                (Get-Content -LiteralPath $ambiguousLog -Raw) | Should -BeExactly $ambiguousBefore
            }
            finally {
                Remove-Item -LiteralPath $stalePlan -Recurse -Force
                Remove-Item -LiteralPath $ambiguousPlan -Recurse -Force
            }
        }

        It 'test:ReviewCycleGate rejects invalidation after a later review result' {
            $plan = New-CyclePlan
            try {
                foreach ($cycle in 1..3) { [void](Invoke-CycleGate -PlanDir $plan -Action Record -Outcome findings) }
                [void](Invoke-CycleGate -PlanDir $plan -Action Continue)
                $fourth = Invoke-CycleGate -PlanDir $plan -Action Record -Outcome findings
                $before = Get-Content -LiteralPath $fourth.logPath -Raw

                { Invoke-CycleGate -PlanDir $plan -Action InvalidateContinue `
                        -OperatorAuthorization 'operator-ticket-late' -Reason 'review already ran' } |
                    Should -Throw '*later review result*'
                (Get-Content -LiteralPath $fourth.logPath -Raw) | Should -BeExactly $before
            }
            finally { Remove-Item -LiteralPath $plan -Recurse -Force }
        }

        It 'test:ReviewCycleGate keeps generated and installed consumer behavior in parity' {
            $gatePaths = @(
                'scripts/skalary/ReviewCycleGate.ps1',
                'plugins/continue-implementation/skills/ci/scripts/ReviewCycleGate.ps1',
                'plugins/autopilot/skills/autopilot/scripts/ReviewCycleGate.ps1',
                '.github/skills/ci/scripts/ReviewCycleGate.ps1',
                '.github/skills/autopilot/scripts/ReviewCycleGate.ps1'
            )
            foreach ($relativeGate in $gatePaths) {
                $plan = New-CyclePlan
                try {
                    $gatePath = Join-Path $script:repoRoot $relativeGate
                    foreach ($cycle in 1..3) {
                        [void](Invoke-CycleGate -PlanDir $plan -Action Record -Outcome findings -GatePath $gatePath)
                    }
                    [void](Invoke-CycleGate -PlanDir $plan -Action Continue -GatePath $gatePath)
                    $invalidated = Invoke-CycleGate -PlanDir $plan -Action InvalidateContinue `
                        -OperatorAuthorization 'operator-ticket-parity' -Reason 'consumer parity' -GatePath $gatePath
                    $invalidated.state | Should -Be 'operator-decision' -Because $relativeGate
                    (Invoke-CycleGate -PlanDir $plan -Action Wrap -GatePath $gatePath).state |
                        Should -Be 'wrap' -Because $relativeGate
                }
                finally { Remove-Item -LiteralPath $plan -Recurse -Force }
            }
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

    It 'test:ReviewCycleGate invalidates the exact ca8ba8 unauthorized Reopen and restores Wrap' {
            $fixture = New-Ca8ba8UnauthorizedReopenFixture
            try {
                $before = Get-Content -LiteralPath $fixture.LogPath -Raw
                $reopened = Invoke-CycleGate -PlanDir $fixture.PlanDir -Action Check `
                    -Stage plan-finalization -Phase 4 -RepoRoot $fixture.Root
                $reopened.state | Should -Be 'allow'
                $reopened.remediation.action | Should -Be 'reopen'
                $reopened.remediation.sourceRecordId | Should -BeExactly $fixture.SourceRecordId

                { Invoke-CycleGate -PlanDir $fixture.PlanDir -Action InvalidateReopen `
                        -Stage plan-finalization -Phase 4 -RepoRoot $fixture.Root `
                        -SourceRecordId $fixture.SourceRecordId -Reason 'missing repair authority' } |
                    Should -Throw '*explicit -OperatorAuthorization*'
                { Invoke-CycleGate -PlanDir $fixture.PlanDir -Action InvalidateReopen `
                        -Stage plan-finalization -Phase 4 -RepoRoot $fixture.Root `
                        -OperatorAuthorization 'repair-missing-source' -Reason 'missing source id' } |
                    Should -Throw '*exact -SourceRecordId*'
                (Get-Content -LiteralPath $fixture.LogPath -Raw) | Should -BeExactly $before

                $repaired = Invoke-CycleGate -PlanDir $fixture.PlanDir -Action InvalidateReopen `
                    -Stage plan-finalization -Phase 4 -RepoRoot $fixture.Root `
                    -SourceRecordId $fixture.SourceRecordId `
                    -OperatorAuthorization 'coordinator-ca8ba8-reopen-repair' `
                    -Reason 'The container resume fabricated operator Reopen authority; no replacement review ran.'

                $repaired.state | Should -Be 'wrap'
                $repaired.cycles | Should -Be 4
                $repaired.canReview | Should -BeFalse
                $repaired.operatorDecisionRequired | Should -BeFalse
                $repaired.remediation.action | Should -Be 'invalidate-reopen'
                $repaired.remediation.targetSourceRecordId | Should -BeExactly $fixture.SourceRecordId
                $repaired.remediation.timestamp | Should -Match 'Z$'

                $after = Get-Content -LiteralPath $fixture.LogPath -Raw
                $after | Should -Match ([regex]::Escape($before.TrimEnd()))
                $after | Should -Match ('action=invalidate-reopen target=' + $fixture.SourceRecordId)
                $after.IndexOf('action=wrap') | Should -BeLessThan $after.IndexOf('action=reopen')
                $after.IndexOf('action=reopen') | Should -BeLessThan $after.IndexOf('action=invalidate-reopen')
                (Invoke-CycleGate -PlanDir $fixture.PlanDir -Action Check `
                        -Stage plan-finalization -Phase 4 -RepoRoot $fixture.Root).state | Should -Be 'wrap'
            }
            finally { Remove-Item -LiteralPath $fixture.Root -Recurse -Force }
        }

        It 'test:ReviewCycleGate rejects duplicate stale wrong-scope and tampered Reopen invalidations' {
            $fixture = New-Ca8ba8UnauthorizedReopenFixture
            $wrongPlan = New-Ca8ba8UnauthorizedReopenFixture -PlanId 'dec0de'
            try {
                $before = Get-Content -LiteralPath $fixture.LogPath -Raw
                { Invoke-CycleGate -PlanDir $fixture.PlanDir -Action InvalidateReopen `
                        -Stage phase-4 -Phase 4 -RepoRoot $fixture.Root `
                        -SourceRecordId $fixture.SourceRecordId `
                        -OperatorAuthorization 'repair-wrong-stage' -Reason 'wrong stage' } |
                    Should -Throw '*latest event*Reopen*'
                { Invoke-CycleGate -PlanDir $fixture.PlanDir -Action InvalidateReopen `
                        -Stage plan-finalization -Phase 4 -RepoRoot $fixture.Root `
                        -SourceRecordId ('f' * 64) `
                        -OperatorAuthorization 'repair-stale-source' -Reason 'stale source id' } |
                    Should -Throw '*stale*latest Reopen*'
                { Invoke-CycleGate -PlanDir $fixture.PlanDir -Action InvalidateReopen `
                        -Stage plan-finalization -Phase 3 -RepoRoot $fixture.Root `
                        -SourceRecordId $fixture.SourceRecordId `
                        -OperatorAuthorization 'repair-wrong-phase' -Reason 'wrong phase' } |
                    Should -Throw '*source-record digest does not match*'
                { Invoke-CycleGate -PlanDir $fixture.PlanDir -Action InvalidateReopen `
                        -Stage plan-finalization -Phase 4 -RepoRoot $script:repoRoot `
                        -SourceRecordId $fixture.SourceRecordId `
                        -OperatorAuthorization 'repair-path-escape' -Reason 'wrong root' } |
                    Should -Throw '*repository plan*'
                { Invoke-CycleGate -PlanDir $wrongPlan.PlanDir -Action InvalidateReopen `
                        -Stage plan-finalization -Phase 4 -RepoRoot $wrongPlan.Root `
                        -SourceRecordId $fixture.SourceRecordId `
                        -OperatorAuthorization 'repair-wrong-plan' -Reason 'wrong plan' } |
                    Should -Throw '*source-record digest does not match plan*'
                (Get-Content -LiteralPath $fixture.LogPath -Raw) | Should -BeExactly $before

                $tampered = $before.Replace(
                    'reason=Operator explicitly directed continuation of pending plan-completion review, validation, archive, push, and PR work.',
                    'reason=tampered'
                )
                Set-Content -LiteralPath $fixture.LogPath -Value $tampered -Encoding utf8NoBOM -NoNewline
                { Invoke-CycleGate -PlanDir $fixture.PlanDir -Action InvalidateReopen `
                        -Stage plan-finalization -Phase 4 -RepoRoot $fixture.Root `
                        -SourceRecordId $fixture.SourceRecordId `
                        -OperatorAuthorization 'repair-tampered' -Reason 'tampered target' } |
                    Should -Throw '*source-record digest does not match*'

                Set-Content -LiteralPath $fixture.LogPath -Value $before -Encoding utf8NoBOM -NoNewline
                [void](Invoke-CycleGate -PlanDir $fixture.PlanDir -Action InvalidateReopen `
                        -Stage plan-finalization -Phase 4 -RepoRoot $fixture.Root `
                        -SourceRecordId $fixture.SourceRecordId `
                        -OperatorAuthorization 'repair-once' -Reason 'invalidate once')
                $afterFirst = Get-Content -LiteralPath $fixture.LogPath -Raw
                { Invoke-CycleGate -PlanDir $fixture.PlanDir -Action InvalidateReopen `
                        -Stage plan-finalization -Phase 4 -RepoRoot $fixture.Root `
                        -SourceRecordId $fixture.SourceRecordId `
                        -OperatorAuthorization 'repair-twice' -Reason 'invalidate twice' } |
                    Should -Throw '*already invalidated*'
                (Get-Content -LiteralPath $fixture.LogPath -Raw) | Should -BeExactly $afterFirst
            }
            finally {
                Remove-Item -LiteralPath $fixture.Root -Recurse -Force
                Remove-Item -LiteralPath $wrongPlan.Root -Recurse -Force
            }
        }

        It 'test:ReviewCycleGate rejects ambiguous post-review and non-Wrap Reopen targets' {
            $ambiguous = New-Ca8ba8UnauthorizedReopenFixture
            $postReview = New-Ca8ba8UnauthorizedReopenFixture
            $legacyPlan = New-CyclePlan
            try {
                $reopenLine = @(Get-Content -LiteralPath $ambiguous.LogPath |
                        Where-Object { $_ -match "\[source-record:$($ambiguous.SourceRecordId)\]" })[0]
                Add-Content -LiteralPath $ambiguous.LogPath -Value ("`n" + $reopenLine) -Encoding utf8NoBOM
                { Invoke-CycleGate -PlanDir $ambiguous.PlanDir -Action InvalidateReopen `
                        -Stage plan-finalization -Phase 4 -RepoRoot $ambiguous.Root `
                        -SourceRecordId $ambiguous.SourceRecordId `
                        -OperatorAuthorization 'repair-ambiguous' -Reason 'ambiguous target' } |
                    Should -Throw '*ambiguous Reopen target*'

                [void](Invoke-CycleGate -PlanDir $postReview.PlanDir -Action Record `
                        -Stage plan-finalization -Phase 4 -RepoRoot $postReview.Root -Outcome findings)
                { Invoke-CycleGate -PlanDir $postReview.PlanDir -Action InvalidateReopen `
                        -Stage plan-finalization -Phase 4 -RepoRoot $postReview.Root `
                        -SourceRecordId $postReview.SourceRecordId `
                        -OperatorAuthorization 'repair-after-review' -Reason 'review already ran' } |
                    Should -Throw '*later review result*'

                [void](Invoke-CycleGate -PlanDir $legacyPlan -Action Record -Outcome findings)
                $legacyLog = (Invoke-CycleGate -PlanDir $legacyPlan -Action Check).logPath
                $legacyText = (Get-Content -LiteralPath $legacyLog -Raw).Replace(
                    'outcome=findings',
                    'outcome=clean'
                )
                Set-Content -LiteralPath $legacyLog -Value $legacyText -Encoding utf8NoBOM
                $legacyReopen = Invoke-CycleGate -PlanDir $legacyPlan -Action Reopen `
                    -OperatorAuthorization 'operator-valid-legacy-reopen' -Reason 'replace legacy clean evidence'
                $legacyRoot = Split-Path (Split-Path (Split-Path $legacyPlan -Parent) -Parent) -Parent
                { Invoke-CycleGate -PlanDir $legacyPlan -Action InvalidateReopen `
                        -RepoRoot $legacyRoot -SourceRecordId $legacyReopen.remediation.sourceRecordId `
                        -OperatorAuthorization 'repair-non-wrap' -Reason 'not a Wrap recovery' } |
                    Should -Throw '*immediately following the prior Wrap*'
            }
            finally {
                Remove-Item -LiteralPath $ambiguous.Root -Recurse -Force
                Remove-Item -LiteralPath $postReview.Root -Recurse -Force
                Remove-Item -LiteralPath $legacyPlan -Recurse -Force
            }
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