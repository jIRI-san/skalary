#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Merging 6-28 reviewer outputs is deterministic formatting, so it lives in a script rather than
# being re-derived from prose on every review run. These tests pin the three rules that decide what
# an operator sees: what collapses into one finding, when severity is elevated, and stable ordering.

Describe 'Build-ReviewReport' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:script = Join-Path $script:repoRoot 'scripts/skalary/Build-ReviewReport.ps1'
        $script:roster = @('Claude Opus 5 (copilot)', 'GPT-5.6 Sol (copilot)')

        $script:newFinding = {
            param(
                [string]$Concern,
                [string]$Model,
                [string]$Severity,
                [string]$Title,
                [string]$Body = '',
                [string[]]$References = @(),
                [string]$RootCause = '',
                [string]$Component = ''
            )

            [pscustomobject]@{
                Concern    = $Concern
                Model      = $Model
                Severity   = $Severity
                Title      = $Title
                Body       = $Body
                References = $References
                RootCause  = $RootCause
                Component  = $Component
            }
        }
    }

    It 'test:build-reviewreport-merge-dedup collapses one root cause in one component into a single entry' {
        $findings = @(
            & $script:newFinding -Concern 'security' -Model $script:roster[0] -Severity 'High' `
                -Title 'Path joined without confinement' -Body 'The handler joins caller input onto the root without canonicalizing first.' `
                -References @('src/Handler.ps1#L10') -RootCause 'unconfined path join' -Component 'src/Handler.ps1'
            & $script:newFinding -Concern 'correctness-reliability' -Model $script:roster[1] -Severity 'Medium' `
                -Title 'Unconfined join' -Body 'Caller input reaches Join-Path unchecked.' `
                -References @('src/Handler.ps1#L12') -RootCause 'Unconfined Path Join' -Component 'src/Handler.ps1'
            & $script:newFinding -Concern 'performance' -Model $script:roster[0] -Severity 'Low' `
                -Title 'Repeated full scan' -Body 'The loop rescans the tree per item.' `
                -References @('src/Scan.ps1#L4') -RootCause 'per-item rescan' -Component 'src/Scan.ps1'
        )

        $report = & $script:script -Finding $findings -Model $script:roster -InvocationCount 6

        @([regex]::Matches($report, '(?m)^### \[\d+\]')).Count | Should -Be 2
        # The merged entry keeps the strongest severity of its members before elevation, and both
        # the models and the lenses that saw it.
        $report | Should -Match 'Path joined without confinement'
        $report | Should -Match '\| \*\*Concerns\*\* \| correctness-reliability · security \|'
        $report | Should -Match '\| \*\*Models\*\* \| Claude Opus 5 \(copilot\) · GPT-5\.6 Sol \(copilot\) \|'
        $report | Should -Match 'src/Handler\.ps1#L10 · src/Handler\.ps1#L12'
        $report | Should -Match '_Also noted:_ Caller input reaches Join-Path unchecked\.'
    }

    It 'test:build-reviewreport-merge-dedup keeps distinct root causes in the same file apart' {
        $findings = @(
            & $script:newFinding -Concern 'security' -Model $script:roster[0] -Severity 'High' `
                -Title 'Secret in log' -RootCause 'secret logged' -Component 'src/A.ps1'
            & $script:newFinding -Concern 'security' -Model $script:roster[0] -Severity 'High' `
                -Title 'Missing authz check' -RootCause 'missing authz' -Component 'src/A.ps1'
        )

        $report = & $script:script -Finding $findings -Model $script:roster -InvocationCount 6
        @([regex]::Matches($report, '(?m)^### \[\d+\]')).Count | Should -Be 2
    }

    It 'test:build-reviewreport-severity-elevation raises severity only on full model agreement' {
        $agreed = @(
            & $script:newFinding -Concern 'security' -Model $script:roster[0] -Severity 'Medium' `
                -Title 'Injection via harvested text' -RootCause 'harvest injection' -Component 'skills/si'
            & $script:newFinding -Concern 'security' -Model $script:roster[1] -Severity 'Medium' `
                -Title 'Injection via harvested text' -RootCause 'harvest injection' -Component 'skills/si'
        )
        $report = & $script:script -Finding $agreed -Model $script:roster -InvocationCount 6
        $report | Should -Match '\| \*\*Severity\*\* \| High \(elevated — flagged by every dispatched model\) \|'

        # One model flagging it twice through two lenses is not corroboration.
        $sameModelTwice = @(
            & $script:newFinding -Concern 'security' -Model $script:roster[0] -Severity 'Medium' `
                -Title 'Injection via harvested text' -RootCause 'harvest injection' -Component 'skills/si'
            & $script:newFinding -Concern 'architecture-patterns' -Model $script:roster[0] -Severity 'Medium' `
                -Title 'Injection via harvested text' -RootCause 'harvest injection' -Component 'skills/si'
        )
        $report = & $script:script -Finding $sameModelTwice -Model $script:roster -InvocationCount 6
        $report | Should -Match '\| \*\*Severity\*\* \| Medium \|'
        $report | Should -Not -Match 'elevated'
    }

    It 'test:build-reviewreport-severity-elevation never elevates past Critical' {
        $findings = @(
            & $script:newFinding -Concern 'security' -Model $script:roster[0] -Severity 'Critical' `
                -Title 'Workflow write allowed' -RootCause 'workflow write' -Component 'scripts/x'
            & $script:newFinding -Concern 'security' -Model $script:roster[1] -Severity 'Critical' `
                -Title 'Workflow write allowed' -RootCause 'workflow write' -Component 'scripts/x'
        )
        $report = & $script:script -Finding $findings -Model $script:roster -InvocationCount 6
        $report | Should -Match '\| \*\*Severity\*\* \| Critical \(elevated'
        @([regex]::Matches($report, '(?m)^### \[\d+\]')).Count | Should -Be 1
    }

    It 'sorts severity-descending' {
        $findings = @(
            & $script:newFinding -Concern 'performance' -Model $script:roster[0] -Severity 'Low' -Title 'Low one' -RootCause 'a' -Component 'p'
            & $script:newFinding -Concern 'security' -Model $script:roster[0] -Severity 'Critical' -Title 'Critical one' -RootCause 'b' -Component 'p'
            & $script:newFinding -Concern 'testing-evidence' -Model $script:roster[0] -Severity 'Medium' -Title 'Medium one' -RootCause 'c' -Component 'p'
            & $script:newFinding -Concern 'operability-observability' -Model $script:roster[0] -Severity 'High' -Title 'High one' -RootCause 'd' -Component 'p'
        )
        $report = & $script:script -Finding $findings -Model $script:roster -InvocationCount 6
        $titles = @([regex]::Matches($report, '(?m)^### \[\d+\] (?<title>.+)$') | ForEach-Object { $_.Groups['title'].Value })
        $titles | Should -Be @('Critical one', 'High one', 'Medium one', 'Low one')
    }

    It 'test:build-reviewreport-deterministic returns identical text regardless of reviewer return order' {
        $findings = @(
            & $script:newFinding -Concern 'security' -Model $script:roster[1] -Severity 'High' -Title 'Alpha' -Body 'Alpha body.' -RootCause 'alpha' -Component 'src/A'
            & $script:newFinding -Concern 'performance' -Model $script:roster[0] -Severity 'High' -Title 'Beta' -Body 'Beta body.' -RootCause 'beta' -Component 'src/B'
            & $script:newFinding -Concern 'security' -Model $script:roster[0] -Severity 'High' -Title 'Alpha' -Body 'Alpha other body.' -RootCause 'alpha' -Component 'src/A'
            & $script:newFinding -Concern 'testing-evidence' -Model $script:roster[1] -Severity 'Low' -Title 'Gamma' -Body 'Gamma body.' -RootCause 'gamma' -Component 'src/C'
        )

        $first = & $script:script -Finding $findings -Model $script:roster -Scope '4 changed files' -InvocationCount 14
        $reversed = @($findings[3], $findings[1], $findings[2], $findings[0])
        $second = & $script:script -Finding $reversed -Model $script:roster -Scope '4 changed files' -InvocationCount 14

        $second | Should -Be $first
        # Same input, same output — repeated runs must not drift either.
        (& $script:script -Finding $findings -Model $script:roster -Scope '4 changed files' -InvocationCount 14) | Should -Be $first
    }

    It 'test:build-reviewreport-deterministic orders entries that tie on severity, agreement, and title' {
        # Generic titles repeated across components are the common case for concern reviewers
        # fanned out over many files; without a total order these come out in input order.
        $findings = @(
            & $script:newFinding -Concern 'testing-evidence' -Model $script:roster[0] -Severity 'Medium' -Title 'Missing test coverage' -RootCause 'no test' -Component 'src/A.ps1' -References @('src/A.ps1')
            & $script:newFinding -Concern 'testing-evidence' -Model $script:roster[0] -Severity 'Medium' -Title 'Missing test coverage' -RootCause 'no test' -Component 'src/B.ps1' -References @('src/B.ps1')
            & $script:newFinding -Concern 'testing-evidence' -Model $script:roster[0] -Severity 'Medium' -Title 'Missing test coverage' -RootCause 'no test' -Component 'src/C.ps1' -References @('src/C.ps1')
            & $script:newFinding -Concern 'testing-evidence' -Model $script:roster[0] -Severity 'Medium' -Title 'Missing test coverage' -RootCause 'no test' -Component 'src/D.ps1' -References @('src/D.ps1')
        )

        $reference = & $script:script -Finding $findings -Model $script:roster -InvocationCount 6
        foreach ($order in @(
                @($findings[3], $findings[2], $findings[1], $findings[0]),
                @($findings[1], $findings[3], $findings[0], $findings[2]))) {
            (& $script:script -Finding $order -Model $script:roster -InvocationCount 6) | Should -Be $reference
        }

        @([regex]::Matches($reference, '(?m)^### \[\d+\]')).Count | Should -Be 4
    }

    It 'test:build-reviewreport-deterministic reports the dispatch budget and handles an empty finding set' {
        $report = & $script:script -Finding @() -Model $script:roster -InvocationCount 6 -InvocationBudget 28
        $report | Should -Match 'Dispatched 6 of 28 budgeted invocations\.'
        $report | Should -Match '(?m)^No findings\.$'
        $report | Should -Match '(?m)^## Recommendations$'
    }

    It 'fails loud on a malformed finding instead of dropping it' {
        { & $script:script -Finding @([pscustomobject]@{ Concern = 'security'; Model = 'x'; Severity = 'High' }) -Model $script:roster } |
            Should -Throw '*Title*'
        { & $script:script -Finding @([pscustomobject]@{ Concern = 'security'; Model = 'x'; Severity = 'Blocker'; Title = 't' }) -Model $script:roster } |
            Should -Throw '*unknown severity*'
    }

    It 'stays a pure formatter with no file I/O' {
        # The caller owns where the report goes; a script that writes files cannot be reused by
        # both orchestrators or tested without a filesystem.
        $raw = Get-Content -LiteralPath $script:script -Raw
        $raw | Should -Not -Match '(?i)\b(Out-File|Set-Content|Add-Content|New-Item|Remove-Item|WriteAllText|WriteAllLines|Export-Csv)\b'
    }
}
