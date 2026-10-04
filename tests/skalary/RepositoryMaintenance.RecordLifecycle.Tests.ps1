#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Repository maintenance record lifecycle' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'RepositoryMaintenance.Fixture.ps1')
    }

    It 'test:RCS.RecordRoundTrip creates, updates, preserves decisions, and is idempotent' {
        $root = New-RecordRoot
        $first = New-PublishPayload
        $firstJson = $first | ConvertTo-Json -Depth 12 -Compress
        (Invoke-RecordWriter -Root $root -Operation 'Publish' -Json $firstJson).status |
            Should -BeExactly 'written'
        $decision = [ordered]@{
            FindingId = 'RCS-unused-private-helper'
            Disposition = 'wont-fix'
            DecidedOn = '2026-10-03'
            Rationale = 'The operator tool is intentionally retained.'
            Scope = 'Only src/helper.ps1; no future candidate is covered.'
            Assumptions = 'This helper remains a supported manual tool.'
            RevisitWhen = 'A replacement removes the manual operator entry point.'
            Citations = @('src/helper.ps1:3')
        } | ConvertTo-Json -Compress
        (Invoke-RecordWriter -Root $root -Operation 'RecordDisposition' -Json $decision).status |
            Should -BeExactly 'written'

        $before = Get-Content -LiteralPath (Join-Path $root 'docs/repository-maintenance.md') -Raw
        $before = $before.Replace(
            '**Complexity:** 2/10',
            "**Complexity:** 2/10`nHuman annotation: preserve this finding-specific note."
        )
        $before = $before.Replace('## Operator decisions', "## Operator decisions`n`nHuman note: retain this history.")
        [System.IO.File]::WriteAllText((Join-Path $root 'docs/repository-maintenance.md'), $before)
        $updatedFinding = New-RecordFinding
        $updatedFinding.Impact = 'New evidence confirms that the finding affects a second caller.'
        $updated = New-PublishPayload -Survey 'Plans surveyed: 3; one active corrective plan overlaps.' `
            -Findings @($updatedFinding)
        (Invoke-RecordWriter -Root $root -Operation 'Publish' `
                -Json ($updated | ConvertTo-Json -Depth 12 -Compress)).status | Should -BeExactly 'written'

        $read = Invoke-RecordWriter -Root $root -Operation 'Read'
        $read.status | Should -BeExactly 'present'
        $read.content | Should -Match 'Human note: retain this history.'
        $read.content | Should -Match 'Human annotation: preserve this finding-specific note.'
        $read.content | Should -Match 'The operator tool is intentionally retained.'
        $read.content | Should -Match 'New evidence confirms that the finding affects a second caller.'
        $read.content | Should -Match 'Plans surveyed: 3'
        (Invoke-RecordWriter -Root $root -Operation 'Publish' `
                -Json ($updated | ConvertTo-Json -Depth 12 -Compress)).status | Should -BeExactly 'unchanged'
    }
}
