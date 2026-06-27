#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Get-PlanState CLI' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $scriptPath = Join-Path $repoRoot 'scripts/skalary/Get-PlanState.ps1'

        $planBody = @'
# 7645b1: Sample plan

<!-- plan-id: 7645b1 -->
<!-- execution-mode: manual -->
<!-- scope: step -->
<!-- cip-stage: dr-round-2 -->

## Phase 1: Foundation

- [x] 1.1 First step `S`
- [~] 1.2 Second step `M`
- [ ] 1.3 Third step `S`
'@

        function New-PlanRepo {
            param([string]$Body)
            $root = Join-Path ([System.IO.Path]::GetTempPath()) ("planstate-" + [guid]::NewGuid().ToString('N'))
            $dir = Join-Path $root 'docs/implementation-plans/2026-06-27-7645b1-sample'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $dir 'plan.md') -Value $Body -Encoding utf8NoBOM
            return $root
        }
    }

    It 'test:get-planstate-text prints a human text block with plan, progress and next step' {
        $repo = New-PlanRepo -Body $planBody
        try {
            $text = & $scriptPath -Reference '7645b1' -RepoRoot $repo
            $text | Should -Match 'Plan:\s+7645b1'
            $text | Should -Match 'Progress:\s+1/3 done'
            $text | Should -Match 'Next step:\s+1\.2'
            $text | Should -Match "status '~'"
        }
        finally {
            Remove-Item -LiteralPath $repo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:get-planstate-json emits a parseable object composing resolve/progress/next-step/markers' {
        $repo = New-PlanRepo -Body $planBody
        try {
            $json = & $scriptPath -Reference '7645b1' -RepoRoot $repo -Json -HasUncommittedChanges
            $obj = $json | ConvertFrom-Json
            $obj.PlanId | Should -Be '7645b1'
            $obj.Markers.ExecutionMode | Should -Be 'manual'
            $obj.Markers.Scope | Should -Be 'step'
            $obj.Markers.CipStage | Should -Be 'dr-round-2'
            $obj.Progress.Total | Should -Be 3
            $obj.Progress.Completed | Should -Be 1
            $obj.Progress.InProgress | Should -Be 1
            $obj.NextStep.Id | Should -Be '1.2'
            $obj.NextStep.IsComplete | Should -BeFalse
            $obj.HasUncommittedChanges | Should -BeTrue
        }
        finally {
            Remove-Item -LiteralPath $repo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:get-planstate-json reports completion when every step is done' {
        $done = @'
# ab12cd: Done plan

<!-- plan-id: ab12cd -->
<!-- execution-mode: autopilot -->

## Phase 1: Only

- [x] 1.1 First step `S`
'@
        $repo = New-PlanRepo -Body $done
        try {
            $json = & $scriptPath -Reference 'ab12cd' -RepoRoot $repo -Json -HasUncommittedChanges:$false
            $obj = $json | ConvertFrom-Json
            $obj.Progress.IsComplete | Should -BeTrue
            $obj.NextStep.IsComplete | Should -BeTrue
            $obj.HasUncommittedChanges | Should -BeFalse
        }
        finally {
            Remove-Item -LiteralPath $repo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
