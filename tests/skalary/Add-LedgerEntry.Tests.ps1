#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Add-LedgerEntry script' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $scriptPath = Join-Path $repoRoot 'scripts/skalary/Add-LedgerEntry.ps1'
        $tempRoots = [System.Collections.Generic.List[string]]::new()

        # Every case below invoked the script through a child pwsh, so the file paid ~30
        # process startups to assert on exit codes and file contents. A fresh runspace is
        # the isolation those assertions actually need; ConcurrentAppend keeps real
        # processes, because contended appends are what it exists to exercise.
        Import-Module (Join-Path $PSScriptRoot '..' 'SuiteScriptHost.psm1') -Force -DisableNameChecking

        function New-TestRepoRoot {
            [CmdletBinding()]
            param()

            $path = Join-Path ([System.IO.Path]::GetTempPath()) ("add-ledger-tests-" + [System.Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path (Join-Path $path 'docs/review-ledger') -Force | Out-Null
            foreach ($category in @('security', 'performance', 'error-handling', 'consistency', 'plan-structure', 'testing', 'observability')) {
                Set-Content -LiteralPath (Join-Path $path "docs/review-ledger/$category.md") -Value '' -Encoding utf8NoBOM
            }
            New-Item -ItemType Directory -Path (Join-Path $path 'docs/review-ledger/.archive') -Force | Out-Null
            $tempRoots.Add($path)
            return $path
        }

        function Invoke-AddLedger {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [string]$Root,

                [string]$Category = 'security',
                [string]$Plan = '007',
                [string]$Src = 'ci',
                [string]$Severity = 'High',
                [string]$Entry = 'default lesson',
                [string[]]$Tags = @()
            )

            $parameters = @{
                RepoRoot = $Root
                Category = $Category
                Plan = $Plan
                Src = $Src
                Severity = $Severity
                Entry = $Entry
            }
            if (@($Tags).Count -gt 0) {
                $parameters['Tags'] = $Tags
            }

            return Invoke-SuiteScript -ScriptPath $scriptPath -Parameters $parameters
        }

        function Get-LedgerLines {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [string]$Root,

                [string]$Category = 'security'
            )

            $path = Join-Path $Root "docs/review-ledger/$Category.md"
            return ,@((Get-Content -LiteralPath $path -Encoding utf8) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }

        function Assert-GitSuccess {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [string]$RepoPath,
                [Parameter(Mandatory)]
                [string[]]$Arguments
            )

            & git -C $RepoPath @Arguments | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "git $($Arguments -join ' ') failed in '$RepoPath' (exit $LASTEXITCODE)."
            }
        }
    }

    AfterAll {
        foreach ($root in $tempRoots) {
            if (Test-Path -LiteralPath $root -PathType Container) {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }
    }

    It 'Add-LedgerEntry.Dedup' {
        $root = New-TestRepoRoot
        (Invoke-AddLedger -Root $root -Entry 'Same lesson').ExitCode | Should -Be 0
        (Invoke-AddLedger -Root $root -Entry 'Same lesson').ExitCode | Should -Be 0

        $lines = Get-LedgerLines -Root $root
        $lines.Count | Should -Be 1
        $lines[0] | Should -Match 'plan-007'
    }

    It 'Add-LedgerEntry.RecurrenceNotSkipped' {
        $root = New-TestRepoRoot
        (Invoke-AddLedger -Root $root -Plan '007' -Entry 'Recurring lesson').ExitCode | Should -Be 0
        (Invoke-AddLedger -Root $root -Plan '008' -Entry 'Recurring lesson').ExitCode | Should -Be 0

        $lines = Get-LedgerLines -Root $root
        $lines.Count | Should -Be 2
        ($lines -join "`n") | Should -Match '\[recurrence:2\]'
    }

    It 'Add-LedgerEntry.RecurrenceReRunIdempotent' {
        $root = New-TestRepoRoot
        (Invoke-AddLedger -Root $root -Plan '007' -Entry 'Recurring lesson').ExitCode | Should -Be 0
        (Invoke-AddLedger -Root $root -Plan '008' -Entry 'Recurring lesson').ExitCode | Should -Be 0
        (Invoke-AddLedger -Root $root -Plan '008' -Entry 'Recurring lesson').ExitCode | Should -Be 0

        $lines = Get-LedgerLines -Root $root
        $lines.Count | Should -Be 2
    }

    It 'Add-LedgerEntry.SanitizesUnicodeBreaks' {
        $root = New-TestRepoRoot
        $entry = "first`nsecond`rthird`u{0085}fourth`u{2028}fifth`u{2029}sixth"
        $result = Invoke-AddLedger -Root $root -Entry $entry
        $result.ExitCode | Should -Be 0

        $line = (Get-LedgerLines -Root $root)[0]
        $line | Should -Not -Match '[\u000A-\u000D\u0085\u2028\u2029]'
        $line | Should -Match 'first second third fourth fifth sixth'
    }

    It 'Add-LedgerEntry.RejectsForgery' {
        $root = New-TestRepoRoot
        $entry = 'Lesson (plan-999, src:evil, sev:Critical) #pwn'
        $result = Invoke-AddLedger -Root $root -Entry $entry
        $result.ExitCode | Should -Be 0

        $line = (Get-LedgerLines -Root $root)[0]
        $line | Should -Not -Match '\(plan-999,\s*src:evil,\s*sev:Critical\)'
        $line | Should -Not -Match 'src:evil'
        $line | Should -Not -Match 'sev:Critical'
        $line | Should -Not -Match '#pwn'
    }

    It 'Add-LedgerEntry.RejectsBadCategory' {
        $root = New-TestRepoRoot
        $result = Invoke-AddLedger -Root $root -Category 'bad-category'
        $result.ExitCode | Should -Not -Be 0
    }

    It 'Add-LedgerEntry.ConcurrentAppend' {
        $root = New-TestRepoRoot
        $processes = @()
        try {
            foreach ($plan in @('007', '007', '007', '007', '009', '010')) {
                $args = @(
                    '-NoProfile',
                    '-File', $scriptPath,
                    '-RepoRoot', $root,
                    '-Category', 'security',
                    '-Plan', $plan,
                    '-Src', 'ci',
                    '-Severity', 'High',
                    '-Entry', 'Concurrent lesson'
                )
                $processes += Start-Process -FilePath 'pwsh' -ArgumentList $args -PassThru -NoNewWindow
            }

            foreach ($process in $processes) {
                $null = $process.WaitForExit(30000)
                $process.ExitCode | Should -Be 0
            }
        }
        finally {
            foreach ($process in $processes) {
                if (-not $process.HasExited) {
                    $process.Kill()
                }
            }
        }

        $lines = Get-LedgerLines -Root $root
        $lines.Count | Should -Be 3
        ($lines -join "`n") | Should -Match 'plan-007'
        ($lines -join "`n") | Should -Match 'plan-009'
        ($lines -join "`n") | Should -Match 'plan-010'
    }

    It 'Add-LedgerEntry.ThreeWayMergeReplay' {
        $root = New-TestRepoRoot
        Assert-GitSuccess -RepoPath $root -Arguments @('init', '--quiet')
        Assert-GitSuccess -RepoPath $root -Arguments @('config', 'user.name', 'add-ledger-tests')
        Assert-GitSuccess -RepoPath $root -Arguments @('config', 'user.email', 'add-ledger-tests@example.com')
        Assert-GitSuccess -RepoPath $root -Arguments @('add', 'docs/review-ledger/security.md')
        Assert-GitSuccess -RepoPath $root -Arguments @('commit', '--quiet', '-m', 'base')
        Assert-GitSuccess -RepoPath $root -Arguments @('checkout', '-b', 'left')
        (Invoke-AddLedger -Root $root -Plan '007' -Entry 'zeta lesson').ExitCode | Should -Be 0
        Assert-GitSuccess -RepoPath $root -Arguments @('add', 'docs/review-ledger/security.md')
        Assert-GitSuccess -RepoPath $root -Arguments @('commit', '--quiet', '-m', 'left')
        Assert-GitSuccess -RepoPath $root -Arguments @('checkout', 'master')
        Assert-GitSuccess -RepoPath $root -Arguments @('checkout', '-b', 'right')
        (Invoke-AddLedger -Root $root -Plan '008' -Entry 'alpha lesson').ExitCode | Should -Be 0
        Assert-GitSuccess -RepoPath $root -Arguments @('add', 'docs/review-ledger/security.md')
        Assert-GitSuccess -RepoPath $root -Arguments @('commit', '--quiet', '-m', 'right')
        Assert-GitSuccess -RepoPath $root -Arguments @('checkout', 'left')

        & git -C $root merge --no-edit right | Out-Null
        if ($LASTEXITCODE -ne 0) {
            $conflictPath = Join-Path $root 'docs/review-ledger/security.md'
            $conflictLines = @((Get-Content -LiteralPath $conflictPath) | Where-Object { $_ -and $_ -notmatch '^(<<<<<<<|=======|>>>>>>>)' })
            Set-Content -LiteralPath $conflictPath -Value (($conflictLines -join "`n") + "`n") -Encoding utf8NoBOM
            Assert-GitSuccess -RepoPath $root -Arguments @('add', 'docs/review-ledger/security.md')
            Assert-GitSuccess -RepoPath $root -Arguments @('commit', '--quiet', '-m', 'resolve merge fixture')
        }

        (Invoke-AddLedger -Root $root -Plan '008' -Entry 'alpha lesson').ExitCode | Should -Be 0
        $mergedReplay = (Get-LedgerLines -Root $root) -join "`n"

        $canonicalRoot = New-TestRepoRoot
        (Invoke-AddLedger -Root $canonicalRoot -Plan '007' -Entry 'zeta lesson').ExitCode | Should -Be 0
        (Invoke-AddLedger -Root $canonicalRoot -Plan '008' -Entry 'alpha lesson').ExitCode | Should -Be 0
        (Invoke-AddLedger -Root $canonicalRoot -Plan '008' -Entry 'alpha lesson').ExitCode | Should -Be 0
        $canonical = (Get-LedgerLines -Root $canonicalRoot) -join "`n"

        $mergedReplay | Should -Be $canonical
    }

    It 'Add-LedgerEntry.NormalizedLesson' {
        $root = New-TestRepoRoot
        (Invoke-AddLedger -Root $root -Plan '007' -Entry '  Normalize   THIS ,  please!! ').ExitCode | Should -Be 0
        (Invoke-AddLedger -Root $root -Plan '008' -Entry 'normalize this, please!!').ExitCode | Should -Be 0

        $lines = Get-LedgerLines -Root $root
        $lines.Count | Should -Be 2
        ($lines -join "`n") | Should -Match '\[recurrence:2\]'
    }

    It 'Add-LedgerEntry.PreservesHeader' {
        $root = New-TestRepoRoot
        $seedPath = Join-Path $root 'docs/review-ledger/security.md'
        Set-Content -LiteralPath $seedPath -Value "# Security Ledger`n`nNo entries yet.`n" -Encoding utf8NoBOM

        (Invoke-AddLedger -Root $root -Entry 'Header preserved lesson').ExitCode | Should -Be 0

        $content = Get-Content -LiteralPath $seedPath -Raw -Encoding utf8
        $content | Should -Match '# Security Ledger'
        $content | Should -Not -Match 'No entries yet\.'
        $content | Should -Match 'Header preserved lesson'
        $content.IndexOf('# Security Ledger') | Should -BeLessThan $content.IndexOf('Header preserved lesson')

        # Idempotent re-run keeps the header intact.
        (Invoke-AddLedger -Root $root -Entry 'Header preserved lesson').ExitCode | Should -Be 0
        $rerun = Get-Content -LiteralPath $seedPath -Raw -Encoding utf8
        $rerun | Should -Match '# Security Ledger'
        $rerun | Should -Not -Match 'No entries yet\.'
    }

    It 'Add-LedgerEntry.SanitizesPipe' {
        $root = New-TestRepoRoot
        (Invoke-AddLedger -Root $root -Entry 'lesson with | pipe char').ExitCode | Should -Be 0

        $line = (Get-LedgerLines -Root $root)[0]
        $line | Should -Not -Match '\|'
        $line | Should -Match 'lesson with pipe char'
    }

    It 'test:ledger-hash-id accepts a 6-hex plan id and writes it canonically' {
        $root = New-TestRepoRoot
        (Invoke-AddLedger -Root $root -Plan 'abc123' -Entry 'hash plan lesson').ExitCode | Should -Be 0

        $lines = Get-LedgerLines -Root $root
        $lines.Count | Should -Be 1
        $lines[0] | Should -Match '\(plan-abc123, src:ci, sev:High\)'
    }

    It 'test:ledger-hash-id rejects an out-of-range plan id' {
        $root = New-TestRepoRoot
        (Invoke-AddLedger -Root $root -Plan 'XYZ999' -Entry 'bad id').ExitCode | Should -Not -Be 0
        (Invoke-AddLedger -Root $root -Plan '12' -Entry 'bad id').ExitCode | Should -Not -Be 0
    }

    It 'test:ledger-legacy-id still accepts a 3-digit legacy plan id' {
        $root = New-TestRepoRoot
        (Invoke-AddLedger -Root $root -Plan '006' -Entry 'legacy plan lesson').ExitCode | Should -Be 0

        $lines = Get-LedgerLines -Root $root
        $lines[0] | Should -Match '\(plan-006, src:ci, sev:High\)'
    }

    It 'test:ledger-mixed-rewrite preserves both legacy and hash lines through a canonical rewrite' {
        $root = New-TestRepoRoot
        # seed a mixed-format ledger directly, then trigger an idempotent re-add that rewrites the file
        $ledger = Join-Path $root 'docs/review-ledger/security.md'
        $seed = @(
            '- [2026-06-01] legacy seed lesson (plan-006, src:ci, sev:High)'
            '- [2026-06-02] hash seed lesson (plan-abc123, src:cr, sev:Low)'
        ) -join "`n"
        Set-Content -LiteralPath $ledger -Value ($seed + "`n") -Encoding utf8NoBOM

        # idempotent re-add of the legacy line forces a canonical rewrite of the whole file
        (Invoke-AddLedger -Root $root -Plan '006' -Src 'ci' -Severity 'High' -Entry 'legacy seed lesson').ExitCode | Should -Be 0

        $lines = Get-LedgerLines -Root $root
        $lines.Count | Should -Be 2
        ($lines -join "`n") | Should -Match 'plan-006'
        ($lines -join "`n") | Should -Match 'plan-abc123'
    }

    It 'test:ledger-dedup-nofork folds different reference schemes to one canonical id' {
        $root = New-TestRepoRoot
        # a real plan folder so Resolve-Plan can canonicalize references to its plan-id
        $planDir = Join-Path $root 'docs/implementation-plans/2026-06-27-7645b1-demo-plan'
        New-Item -ItemType Directory -Path $planDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $planDir 'plan.md') -Value "<!-- plan-id: 7645b1 -->`n# Demo`n" -Encoding utf8NoBOM

        # same lesson referenced three ways: hash prefix, full id, and date
        (Invoke-AddLedger -Root $root -Plan '7645' -Entry 'shared canonical lesson').ExitCode | Should -Be 0
        (Invoke-AddLedger -Root $root -Plan '7645b1' -Entry 'shared canonical lesson').ExitCode | Should -Be 0
        (Invoke-AddLedger -Root $root -Plan '2026-06-27' -Entry 'shared canonical lesson').ExitCode | Should -Be 0

        $lines = Get-LedgerLines -Root $root
        $lines.Count | Should -Be 1
        $lines[0] | Should -Match '\(plan-7645b1, src:ci, sev:High\)'
    }
}
