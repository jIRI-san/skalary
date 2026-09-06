#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Autopilot container dispatch' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:dispatch = (
            Join-Path $script:repoRoot 'plugins/autopilot/scripts/plan-dispatch.sh'
        ).Replace('\', '/')
        $script:phaseStateScript = Join-Path $script:repoRoot `
            'scripts/skalary/Get-PhaseExecutionState.ps1'
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

        function Invoke-PublishedPrCloseProof {
            param(
                [Parameter(Mandatory)][ValidateSet('OPEN', 'MERGED', 'CLOSED')]
                [string]$State,
                [string]$Base = 'main',
                [bool]$Published = $true
            )

            $output = & bash -c @'
. "$1"
oid="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
fixture_base="$2"
fixture_state="$3"
fixture_published="$4"
git() {
    case "$*" in
        "-C . check-ref-format --branch feature/test") return 0 ;;
        "-C . check-ref-format --branch main") return 0 ;;
        "-C . branch --show-current") printf '%s\n' 'feature/test'; return 0 ;;
        "-C . rev-parse --verify HEAD^{commit}") printf '%s\n' "${oid}"; return 0 ;;
        "-C . ls-remote --refs origin refs/heads/feature/test")
            if [ "${fixture_published}" = "true" ]; then
                printf '%s\t%s\n' "${oid}" 'refs/heads/feature/test'
            fi
            return 0
            ;;
    esac
    printf 'unexpected git call: %s\n' "$*" >&2
    return 2
}
gh() {
    printf 'feature/test\t%s\t%s\t%s\n' "${oid}" "${fixture_base}" "${fixture_state}"
}
AUTOPILOT_GH_BIN=gh
autopilot_branch_has_published_pr . feature/test main
status=$?
if [ "${status}" -eq 0 ]; then
    autopilot_completion_handoff_action 0 closed 0 3
fi
exit "${status}"
'@ bash $script:dispatch $Base $State $Published.ToString().ToLowerInvariant()
            return [pscustomobject]@{
                ExitCode = $LASTEXITCODE
                Output = @($output)
            }
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

    It 'treats open and merged pull requests as terminal close proof' {
        foreach ($state in @('OPEN', 'MERGED')) {
            $result = Invoke-PublishedPrCloseProof -State $state
            $result.ExitCode | Should -Be 0 -Because $state
            $result.Output | Should -BeExactly @('complete') -Because $state
        }

        (Invoke-PublishedPrCloseProof -State CLOSED).ExitCode | Should -Be 1
        (Invoke-PublishedPrCloseProof -State MERGED -Base wrong).ExitCode | Should -Be 1
        (Invoke-PublishedPrCloseProof -State MERGED -Published $false).ExitCode |
            Should -Be 0
        (Invoke-PublishedPrCloseProof -State OPEN -Published $false).ExitCode |
            Should -Be 1
    }

    It 'treats a clean committed archived plan phase as closed' {
        $root = Join-Path $script:repoRoot (
            'tests\.autopilot-archived-' + [guid]::NewGuid().ToString('N')
        )
        $script:scratch.Add($root)
        $planPath = Join-Path $root (
            'docs/implementation-plans/archived/' +
            'standalone-2026-01-01-abc123-fixture/plan.md'
        )
        New-Item -ItemType Directory -Path (Split-Path $planPath -Parent) -Force |
            Out-Null
        [System.IO.File]::WriteAllText(
            $planPath,
            "# Fixture`n`n## Phase 1: Done`n`n- [x] 1.1 Complete",
            [System.Text.UTF8Encoding]::new($false)
        )
        & git -C $root init --quiet --initial-branch=main
        & git -C $root config user.name 'Autopilot Fixture'
        & git -C $root config user.email 'autopilot-fixture@example.invalid'
        & git -C $root add .
        & git -C $root commit --quiet -m 'archive completed plan'

        & $script:phaseStateScript -PlanPath $planPath -Phase 1 -RepoRoot $root |
            Should -BeExactly 'closed'
    }

    It 'accepts finalization artifacts added during and after the archive commit' {
        $root = Join-Path $script:repoRoot (
            'tests\.autopilot-archive-transition-' + [guid]::NewGuid().ToString('N')
        )
        $script:scratch.Add($root)
        $activeDir = 'docs/implementation-plans/standalone-2026-01-01-abc123-fixture'
        $archivedDir = "docs/implementation-plans/archived/$(Split-Path $activeDir -Leaf)"
        $activePath = Join-Path $root $activeDir
        New-Item -ItemType Directory -Path (Join-Path $activePath 'assets') -Force |
            Out-Null
        Set-Content -LiteralPath (Join-Path $activePath 'plan.md') `
            -Value '# Fixture' -Encoding utf8NoBOM
        Set-Content -LiteralPath (Join-Path $activePath 'assets/intent.md') `
            -Value '# Intent' -Encoding utf8NoBOM
        & git -C $root init --quiet --initial-branch=main
        & git -C $root config user.name 'Autopilot Fixture'
        & git -C $root config user.email 'autopilot-fixture@example.invalid'
        & git -C $root add .
        & git -C $root commit --quiet -m 'add active plan'

        New-Item -ItemType Directory -Path (Join-Path $activePath 'assets/reviews') -Force |
            Out-Null
        Set-Content -LiteralPath (Join-Path $activePath 'assets/reviews/final.md') `
            -Value '# Final review' -Encoding utf8NoBOM
        New-Item -ItemType Directory -Path (Split-Path (Join-Path $root $archivedDir) -Parent) `
            -Force | Out-Null
        & git -C $root mv $activeDir $archivedDir
        & git -C $root add .
        & git -C $root commit --quiet -m 'archive with final review'
        $archiveCommit = (& git -C $root rev-parse HEAD)

        Add-Content -LiteralPath (Join-Path $root "$archivedDir/assets/reviews/final.md") `
            -Value 'refreshed evidence'
        & git -C $root add .
        & git -C $root commit --quiet -m 'refresh archived review'

        $result = & bash -c @'
. "$1"
autopilot_archive_transition_is_committed "$2" "$3" "$4" "$4/plan.md" "$5"
'@ bash $script:dispatch ($root.Replace('\', '/')) $activeDir $archivedDir $archiveCommit
        $LASTEXITCODE | Should -Be 0
        $result | Should -BeNullOrEmpty

        Add-Content -LiteralPath (Join-Path $root "$archivedDir/plan.md") `
            -Value 'dirty'
        & bash -c @'
. "$1"
autopilot_archive_transition_is_committed "$2" "$3" "$4" "$4/plan.md" "$5"
'@ bash $script:dispatch ($root.Replace('\', '/')) $activeDir $archivedDir $archiveCommit
        $LASTEXITCODE | Should -Be 1
    }
}
