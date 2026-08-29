#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'review cycle gate' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:gate = Join-Path $script:repoRoot 'scripts/skalary/ReviewCycleGate.ps1'

        function Script:New-CyclePlan {
            $root = Join-Path ([System.IO.Path]::GetTempPath()) ('review-cycle-' + [guid]::NewGuid().ToString('N'))
            $planDir = Join-Path $root 'docs/implementation-plans/2026-08-25-abc123-review-cycle'
            [void](New-Item -ItemType Directory -Path (Join-Path $planDir 'assets') -Force)
            Set-Content -LiteralPath (Join-Path $planDir 'plan.md') -Value "# abc123: Review cycle`n<!-- plan-id: abc123 -->`n" -Encoding utf8NoBOM
            return $planDir
        }

        function Script:Invoke-CycleGate {
            param([string]$PlanDir, [string]$Action, [string]$Stage = 'step-1.1', [string]$Outcome, [string]$Summary)
            $arguments = @{ Action = $Action; PlanDir = $PlanDir; Phase = 1; Stage = $Stage }
            if ($Outcome) { $arguments.Outcome = $Outcome }
            if ($Summary) { $arguments.Summary = $Summary }
            return & $script:gate @arguments
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

    It 'test:ReviewCycleGate completes immediately when a recorded review is clean' {
        $plan = New-CyclePlan
        try {
            $result = Invoke-CycleGate -PlanDir $plan -Action Record -Outcome clean -Summary 'zero-blockers'
            $result.state | Should -Be 'complete'
            $result.cycles | Should -Be 1
            (Invoke-CycleGate -PlanDir $plan -Action Check).state | Should -Be 'complete'
        }
        finally { Remove-Item -LiteralPath $plan -Recurse -Force }
    }
}