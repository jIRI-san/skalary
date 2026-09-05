#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Autopilot container dispatch' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:dispatch = (
            Join-Path $script:repoRoot 'plugins/autopilot/scripts/plan-dispatch.sh'
        ).Replace('\', '/')
        $script:scratch = [System.Collections.Generic.List[string]]::new()

        function Invoke-DispatchTargets {
            param(
                [Parameter(Mandatory)][string[]]$StepState,
                [ValidateSet('next-phase', 'whole-plan')][string]$Mode = 'whole-plan'
            )

            $root = Join-Path $script:repoRoot (
                'tests\.autopilot-dispatch-' + [guid]::NewGuid().ToString('N')
            )
            $script:scratch.Add($root)
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            $planPath = Join-Path $root 'plan.md'
            $lines = [System.Collections.Generic.List[string]]::new()
            for ($index = 0; $index -lt $StepState.Count; $index++) {
                $phase = $index + 1
                $lines.Add("## Phase ${phase}: Fixture")
                $lines.Add('')
                $lines.Add("- [$($StepState[$index])] ${phase}.1 Fixture")
                $lines.Add('')
            }
            [System.IO.File]::WriteAllText(
                $planPath,
                ($lines -join "`n"),
                [System.Text.UTF8Encoding]::new($false)
            )

            $output = & bash -c @'
. "$1"
autopilot_execution_targets "$2" "$3"
'@ bash $script:dispatch ($planPath.Replace('\', '/')) $Mode
            if ($LASTEXITCODE -ne 0) {
                throw "plan dispatch failed with exit $LASTEXITCODE`: $($output -join "`n")"
            }
            return @($output)
        }
    }

    AfterEach {
        foreach ($path in @($script:scratch)) {
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
        }
        $script:scratch.Clear()
    }

    It 'schedules exactly one completion target after the final incomplete phase' {
        Invoke-DispatchTargets -StepState @('x', ' ') |
            Should -BeExactly @('phase:2', 'completion-only')
        Invoke-DispatchTargets -StepState @(' ', ' ') |
            Should -BeExactly @('phase:1', 'phase:2', 'completion-only')
    }

    It 'schedules exactly one completion target when resuming an all-closed plan' {
        $targets = @(Invoke-DispatchTargets -StepState @('x', 'x'))
        $targets | Should -BeExactly @('completion-only')
        @($targets | Where-Object { $_ -eq 'completion-only' }).Count | Should -Be 1
    }

    It 'keeps one-phase dispatch phase-only and gives finalization only to completion-only' {
        Invoke-DispatchTargets -StepState @('x', ' ') -Mode next-phase |
            Should -BeExactly @('phase:2')

        $owner = & bash -c @'
. "$1"
if autopilot_target_owns_finalization "phase:2" "2"; then
    echo phase
fi
if autopilot_target_owns_finalization "completion-only" "2"; then
    echo completion-only
fi
'@ bash $script:dispatch
        $LASTEXITCODE | Should -Be 0
        @($owner) | Should -BeExactly @('completion-only')
    }
}
