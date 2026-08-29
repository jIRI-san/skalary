#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Plan c21cdc REQ-12/D6/RISK-14, step 1.2. Bound the cost of the worst legal envelope and keep the
# evidence discoverable. This test runs a child process (so private bytes can be sampled), builds the
# largest structurally legal envelope from the committed recipe, freezes and publishes it while a
# Stopwatch times the publish, records OS/PowerShell identity, and requires the publication to finish
# inside the platform ceiling (10s Linux, 30s Windows) and 256 MiB of memory growth. Execution is
# required, never skipped; this is the 2 MiB structural maximum whose complete full view is rejected,
# so its wall-clock bound is deliberately separate from normal-review and whole-suite receipts.
Describe 'review report maximum envelope budget' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        Import-Module (Join-Path $PSScriptRoot 'fixtures/review-run/ReviewRunTestKit.psm1') -Force -DisableNameChecking
        $script:worker = Join-Path $PSScriptRoot 'fixtures/review-run/Invoke-MaxEnvelopeBudget.ps1'
        $script:modulePath = Join-Path $script:repoRoot 'scripts/skalary/ReviewRun.psm1'
        $script:specPath = Join-Path $PSScriptRoot 'fixtures/review-run/edge/maximum-envelope.spec.json'
        $script:limits = (Get-Content -LiteralPath (Join-Path $script:repoRoot 'schemas/review/review-limits.schema.json') -Raw | ConvertFrom-Json -AsHashtable -Depth 20)['x-skalary-limits']
    }

    It 'test:ReviewReport.MaximumEnvelopeBudget processes the maximum envelope inside its platform ceiling and 256 MiB, rejecting its over-budget full view' {
        Test-Path -LiteralPath $script:worker -PathType Leaf | Should -BeTrue -Because 'the budget worker must exist and run — this test is never skipped'
        Test-Path -LiteralPath $script:specPath -PathType Leaf | Should -BeTrue

        $scratch = New-ReviewScratchRoot
        try {
            $runId = '8f3c1d2e-5a47-4b90-9c61-2d7e0f4a6b35'
            $resultPath = Join-Path $scratch 'budget-result.json'
            $errPath = Join-Path $scratch 'budget-err.txt'

            $arguments = @(
                '-NoProfile', '-File', $script:worker,
                '-ModulePath', $script:modulePath,
                '-SpecPath', $script:specPath,
                '-RepoRoot', $scratch,
                '-RunId', $runId,
                '-ResultPath', $resultPath
            )
            $proc = Start-Process -FilePath 'pwsh' -ArgumentList $arguments -PassThru -NoNewWindow -RedirectStandardError $errPath

            # Sample the child's private bytes while it runs; the growth from the first sample is the
            # publication's memory cost.
            $baseline = $null
            $peak = 0
            while (-not $proc.HasExited) {
                try {
                    $proc.Refresh()
                    $sample = [int64]$proc.PrivateMemorySize64
                    if ($sample -gt 0) {
                        if ($null -eq $baseline) { $baseline = $sample }
                        if ($sample -gt $peak) { $peak = $sample }
                    }
                }
                catch { }
                Start-Sleep -Milliseconds 40
            }
            $proc.WaitForExit()

            $stderr = $(if (Test-Path -LiteralPath $errPath) { Get-Content -LiteralPath $errPath -Raw } else { '' })
            $proc.ExitCode | Should -Be 0 -Because "the worker must complete cleanly. stderr: $stderr"
            Test-Path -LiteralPath $resultPath -PathType Leaf | Should -BeTrue -Because 'the worker must record a result'

            $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
            [string]$result.schema | Should -Be 'skalary/review-max-envelope-budget@1'

            # Identity is recorded on every leg.
            [string]$result.os | Should -Not -BeNullOrEmpty
            [string]$result.powerShell | Should -Match '^\d+\.\d+'

            # The envelope really is the maximum the recipe describes.
            [int]$result.tasks | Should -Be 128
            [int]$result.findings | Should -Be 256
            [int]$result.inputBytes | Should -BeLessOrEqual ([int]$script:limits.maxEnvelopeBytes)
            [int]$result.suspiciousFindings | Should -BeGreaterThan 0 `
                -Because 'the maximum envelope must execute and observe the distinct-model near-duplicate path'

            # Render-budget behavior of the structural maximum: the summary fits, but the full view
            # overflows the 1 MiB budget because 256 findings carry 1 MiB of bodies alone, so the
            # byte-budget admission correctly rejects it with a terminal exit 3 (RISK-3/D6). Reaching
            # that decision — canonicalize, render both complete views, admit — is what must stay
            # inside the cost budget.
            [int]$result.freezeExit | Should -Be 0
            [int]$result.summaryBytes | Should -BeGreaterThan 0
            [int]$result.summaryBytes | Should -BeLessOrEqual ([int]$script:limits.maxSummaryBytes)
            [int]$result.fullBytes | Should -BeGreaterThan ([int]$script:limits.maxFullBytes) -Because 'the structural maximum full view overflows its budget by construction'
            [int]$result.publishExit | Should -Be 3 -Because 'the over-budget full view is a terminal byte-budget admission, never truncated'
            [string]$result.publishState | Should -Be 'admission'

            # Time and memory budgets on the publication attempt, measured by an in-process sampler.
            $secondsCeiling = $(if ($IsWindows) { 30.0 } else { 10.0 })
            [double]$result.publishSeconds | Should -BeLessThan $secondsCeiling `
                -Because "the publication attempt must finish inside the $secondsCeiling-second platform budget"
            [int64]$result.peakPrivateBytes | Should -BeGreaterThan 0 -Because 'private bytes were sampled during the publish'
            ([double]$result.publishGrowthBytes / 1MB) | Should -BeLessThan 256 -Because 'publication memory growth must stay under 256 MiB'

            # The parent-sampled peak is supplementary evidence that the process never ballooned.
            if ($null -ne $baseline -and $peak -gt 0) { (($peak - $baseline) / 1MB) | Should -BeLessThan 512 }
        }
        finally { Remove-ReviewScratchRoot -Path $scratch }
    }
}
