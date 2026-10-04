#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Repository maintenance record identity' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'RepositoryMaintenance.Fixture.ps1')
    }

    It 'test:RCS.RecordRoundTrip preserves unseen findings on partial or empty runs and refuses ambiguous ID reuse' {
        $root = New-RecordRoot
        $payload = New-PublishPayload
        (Invoke-RecordWriter -Root $root -Operation 'Publish' `
                -Json ($payload | ConvertTo-Json -Depth 12 -Compress)).status | Should -BeExactly 'written'

        $partial = New-PublishPayload -Findings @() -Coverage 'Partial run; other areas were not traced.'
        (Invoke-RecordWriter -Root $root -Operation 'Publish' `
                -Json ($partial | ConvertTo-Json -Depth 12 -Compress)).status | Should -BeExactly 'written'
        $read = Invoke-RecordWriter -Root $root -Operation 'Read'
        $read.content | Should -Match 'RCS-unused-private-helper'
        $read.content | Should -Match 'Partial run'

        $ambiguous = New-RecordFinding -Citation 'src/other.ps1:9'
        $badReuse = New-PublishPayload -Findings @($ambiguous)
        {
            Invoke-RecordWriter -Root $root -Operation 'Publish' `
                -Json ($badReuse | ConvertTo-Json -Depth 12 -Compress)
        } | Should -Throw '*ambiguous identity*'
        (Invoke-RecordWriter -Root $root -Operation 'Read').content |
            Should -Match 'src/helper.ps1:3'
    }

    It 'test:RCS.RecordRoundTrip matches stable finding IDs with ordinal casing' {
        $root = New-RecordRoot
        $original = New-RecordFinding -Id 'RCS-CaseSensitive'
        (Invoke-RecordWriter -Root $root -Operation 'Publish' `
                -Json ((New-PublishPayload -Findings @($original)) | ConvertTo-Json -Depth 12 -Compress)).status |
            Should -BeExactly 'written'

        $caseChanged = New-RecordFinding -Id 'RCS-casesensitive'
        (Invoke-RecordWriter -Root $root -Operation 'Publish' `
                -Json ((New-PublishPayload -Findings @($caseChanged)) | ConvertTo-Json -Depth 12 -Compress)).status |
            Should -BeExactly 'written'
        $content = (Invoke-RecordWriter -Root $root -Operation 'Read').content
        $content | Should -Match '### RCS-CaseSensitive -'
        $content | Should -Match '### RCS-casesensitive -'
        [regex]::Matches($content, '<!-- rcs-finding: RCS-').Count | Should -Be 2
    }
}
