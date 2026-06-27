#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Repair-Plans' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $scriptPath = Join-Path $repoRoot 'scripts/skalary/Repair-Plans.ps1'

        $loosePlanBody = @'
# 005: Old plan

<!-- plan-id: 005 -->
<!-- depends-on: 004 -->

## Phase 1
<!-- worktree: agents/old-plan -->

- [x] 1.1 Something `S`
'@

        function New-Repo {
            $root = Join-Path ([System.IO.Path]::GetTempPath()) ("repair-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path (Join-Path $root 'docs/implementation-plans') -Force | Out-Null
            return $root
        }
    }

    It 'test:repair-plans-migrate moves a loose legacy plan file into a folder' {
        $repo = New-Repo
        try {
            $plans = Join-Path $repo 'docs/implementation-plans'
            $loose = Join-Path $plans '005-old-plan.md'
            Set-Content -LiteralPath $loose -Value $loosePlanBody -Encoding utf8NoBOM

            $result = & $scriptPath -RepoRoot $repo
            $result.Count | Should -Be 1
            Test-Path -LiteralPath $loose | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $plans '005-old-plan/plan.md') | Should -BeTrue
        }
        finally {
            Remove-Item -LiteralPath $repo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:repair-plans-migrate ignores non-plan loose files and the archived non-goal' {
        $repo = New-Repo
        try {
            $plans = Join-Path $repo 'docs/implementation-plans'
            Set-Content -LiteralPath (Join-Path $plans 'README.md') -Value "# index`n" -Encoding utf8NoBOM
            New-Item -ItemType Directory -Path (Join-Path $plans 'archived') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $plans 'archived/003-done.md') -Value "# 003`n" -Encoding utf8NoBOM

            $result = & $scriptPath -RepoRoot $repo
            $result.Count | Should -Be 0
            Test-Path -LiteralPath (Join-Path $plans 'README.md') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $plans 'archived/003-done.md') | Should -BeTrue
        }
        finally {
            Remove-Item -LiteralPath $repo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:repair-plans-noop is a clean no-op when there is nothing to migrate' {
        $repo = New-Repo
        try {
            $plans = Join-Path $repo 'docs/implementation-plans'
            New-Item -ItemType Directory -Path (Join-Path $plans '006-foldered') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $plans '006-foldered/plan.md') -Value "# 006`n" -Encoding utf8NoBOM

            $first = & $scriptPath -RepoRoot $repo
            $first.Count | Should -Be 0
            $second = & $scriptPath -RepoRoot $repo
            $second.Count | Should -Be 0
        }
        finally {
            Remove-Item -LiteralPath $repo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:repair-plans-preserve-id preserves plan-id, depends-on and worktree markers verbatim' {
        $repo = New-Repo
        try {
            $plans = Join-Path $repo 'docs/implementation-plans'
            $loose = Join-Path $plans '005-old-plan.md'
            Set-Content -LiteralPath $loose -Value $loosePlanBody -Encoding utf8NoBOM

            & $scriptPath -RepoRoot $repo | Out-Null
            $migrated = Get-Content -LiteralPath (Join-Path $plans '005-old-plan/plan.md') -Raw
            $migrated | Should -Match '<!-- plan-id: 005 -->'
            $migrated | Should -Match '<!-- depends-on: 004 -->'
            $migrated | Should -Match '<!-- worktree: agents/old-plan -->'
        }
        finally {
            Remove-Item -LiteralPath $repo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:repair-plans-preserve-id reports but does not move under -WhatIf' {
        $repo = New-Repo
        try {
            $plans = Join-Path $repo 'docs/implementation-plans'
            $loose = Join-Path $plans '005-old-plan.md'
            Set-Content -LiteralPath $loose -Value $loosePlanBody -Encoding utf8NoBOM

            $result = & $scriptPath -RepoRoot $repo -WhatIf
            $result.Count | Should -Be 1
            Test-Path -LiteralPath $loose | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $plans '005-old-plan/plan.md') | Should -BeFalse
        }
        finally {
            Remove-Item -LiteralPath $repo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
