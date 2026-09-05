#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'review result receipt compatibility' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        Import-Module (Join-Path $repoRoot 'scripts/skalary/ReviewResultReceipt.psm1') `
            -Force -DisableNameChecking
    }

    It 'accepts the extended fields emitted by current finalized reviews' {
        $runId = [guid]::NewGuid().ToString()
        $reportName = "$runId.review.md"
        $reportBytes = [System.Text.UTF8Encoding]::new($false).GetBytes('# Review')
        $reportDigest = 'sha256:' + [Convert]::ToHexString(
            [System.Security.Cryptography.SHA256]::HashData($reportBytes)
        ).ToLowerInvariant()
        $receipt = [ordered]@{
            schema = 'skalary/review-result-receipt@1'
            runId = $runId
            reviewType = 'code'
            state = 'clean'
            verdict = 'blocked'
            legacySource = $false
            planDigest = 'sha256:' + ('1' * 64)
            runDigest = 'sha256:' + ('2' * 64)
            manifestDigest = 'sha256:' + ('3' * 64)
            source = [ordered]@{
                mode = 'paths'
                head = '4' * 40
                pathCount = 1
                digest = 'sha256:' + ('5' * 64)
            }
            attendance = [ordered]@{
                completed = 1
                failed = 0
                'timed-out' = 0
                omitted = 0
                cancelled = 0
                pending = 0
            }
            findings = [ordered]@{
                merged = 1
                raw = 1
                severity = [ordered]@{ critical = 0; high = 0; medium = 1; low = 0 }
                rawSeverity = [ordered]@{ critical = 0; high = 0; medium = 1; low = 0 }
                corroboration = [ordered]@{
                    corroborated = 0
                    degraded = 0
                    'single-source' = 1
                    suspicious = 0
                }
                similarity = [ordered]@{ exact = 0; 'near-duplicate' = 0; none = 1 }
                needsReview = 0
            }
            report = [ordered]@{
                name = $reportName
                bytes = $reportBytes.Length
                digest = $reportDigest
            }
        }

        {
            Assert-ReviewResultReceipt -ReceiptContent ($receipt | ConvertTo-Json -Depth 10 -Compress) `
                -ReviewRunId $runId -ReportName $reportName -ReportBytes $reportBytes
        } | Should -Not -Throw

        $receipt.findings.Remove('similarity')
        {
            Assert-ReviewResultReceipt -ReceiptContent ($receipt | ConvertTo-Json -Depth 10 -Compress) `
                -ReviewRunId $runId -ReportName $reportName -ReportBytes $reportBytes
        } | Should -Throw '*partial extended v1 property set*'
    }
}
