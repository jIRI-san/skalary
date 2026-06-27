#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'New-Plan scaffolding' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $scriptPath = Join-Path $repoRoot 'scripts/skalary/New-Plan.ps1'
        $realTemplate = Join-Path $repoRoot 'plugins/create-implementation-plan/skills/cip/assets/plan-template.md'

        function New-TempRepo {
            $root = Join-Path ([System.IO.Path]::GetTempPath()) ("newplan-" + [guid]::NewGuid().ToString('N'))
            $plans = Join-Path $root 'docs/implementation-plans'
            New-Item -ItemType Directory -Path $plans -Force | Out-Null
            $templateDest = Join-Path $root 'plugins/create-implementation-plan/skills/cip/assets'
            New-Item -ItemType Directory -Path $templateDest -Force | Out-Null
            Copy-Item -LiteralPath $realTemplate -Destination (Join-Path $templateDest 'plan-template.md') -Force
            Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts/skalary/PlanState.psm1') -Destination (Join-Path $root 'scripts/skalary/PlanState.psm1') -Force -ErrorAction SilentlyContinue
            return $root
        }
    }

    It 'test:new-plan-scaffold creates a date-hash-slug folder with a plan-id anchor' {
        $repo = New-TempRepo
        try {
            $created = & $scriptPath -Title 'My Cool Plan' -Slug 'My Cool Plan!!' -Date '2026-07-01' -RepoRoot $repo
            $created.PlanId | Should -Match '^[0-9a-f]{6}$'
            $created.Slug | Should -Be 'my-cool-plan'
            $created.FolderName | Should -Be "2026-07-01-$($created.PlanId)-my-cool-plan"
            Test-Path -LiteralPath $created.PlanFile | Should -BeTrue

            $content = Get-Content -LiteralPath $created.PlanFile -Raw
            $content | Should -Match "(?m)^#\s+$($created.PlanId):\s+My Cool Plan$"
            $content | Should -Match "<!--\s*plan-id:\s*$($created.PlanId)\s*-->"
        }
        finally {
            Remove-Item -LiteralPath $repo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:new-plan-scaffold honors an explicit -PlanId' {
        $repo = New-TempRepo
        try {
            $created = & $scriptPath -Title 'Fixed Id' -Slug 'fixed-id' -Date '2026-07-02' -PlanId 'abcd12' -RepoRoot $repo
            $created.PlanId | Should -Be 'abcd12'
            $created.FolderName | Should -Be '2026-07-02-abcd12-fixed-id'
        }
        finally {
            Remove-Item -LiteralPath $repo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:new-plan-traversal sanitizes a traversal slug and confines the folder to the plans root' {
        $repo = New-TempRepo
        try {
            $plansRoot = [System.IO.Path]::GetFullPath((Join-Path $repo 'docs/implementation-plans'))
            $created = & $scriptPath -Title 'Evil' -Slug '../../../../etc/passwd' -Date '2026-07-03' -RepoRoot $repo

            $created.Slug | Should -Be 'etc-passwd'
            $created.FolderName | Should -Match '^2026-07-03-[0-9a-f]{6}-etc-passwd$'

            $resolved = [System.IO.Path]::GetFullPath($created.Path)
            $resolved.StartsWith($plansRoot) | Should -BeTrue

            # nothing escaped above the plans root
            Test-Path -LiteralPath (Join-Path $repo 'etc/passwd') | Should -BeFalse
        }
        finally {
            Remove-Item -LiteralPath $repo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:new-plan-traversal rejects a slug that sanitizes to empty' {
        $repo = New-TempRepo
        try {
            { & $scriptPath -Title 'Nope' -Slug '///...' -Date '2026-07-04' -RepoRoot $repo } | Should -Throw
        }
        finally {
            Remove-Item -LiteralPath $repo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'refuses to overwrite an existing plan without -Force' {
        $repo = New-TempRepo
        try {
            $first = & $scriptPath -Title 'One' -Slug 'dup' -Date '2026-07-05' -PlanId 'aaaa11' -RepoRoot $repo
            { & $scriptPath -Title 'Two' -Slug 'dup' -Date '2026-07-05' -PlanId 'aaaa11' -RepoRoot $repo } | Should -Throw
            $first.PlanId | Should -Be 'aaaa11'
        }
        finally {
            Remove-Item -LiteralPath $repo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
