#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Repository maintenance scoped decisions' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'RepositoryMaintenance.Fixture.ps1')
    }

    It 'test:RCS.DispositionRoundTrip suppresses unchanged scoped decisions and reopens changed assumptions' {
        $root = New-RecordRoot
        $findings = @(
            (New-RecordFinding -Id 'RCS-scoped-intentional-drift'),
            (New-RecordFinding -Id 'RCS-archive-candidate')
        )
        (Invoke-RecordWriter -Root $root -Operation 'Publish' `
                -Json ((New-PublishPayload -Findings $findings) | ConvertTo-Json -Depth 12 -Compress)).status |
            Should -BeExactly 'written'
        $acceptance = [ordered]@{
            FindingId = 'RCS-scoped-intentional-drift'
            Disposition = 'wont-fix'
            DecidedOn = '2026-10-03'
            Rationale = 'The operator accepts this bounded candidate for the current evidence.'
            Scope = 'Only src/helper.ps1 in this repository snapshot.'
            Assumptions = 'No supported internal caller exists.'
            RevisitWhen = 'A new repository-owned caller or a changed contract is found.'
            Citations = @('src/helper.ps1:3')
        }
        (Invoke-RecordWriter -Root $root -Operation 'RecordDisposition' `
                -Json ($acceptance | ConvertTo-Json -Compress)).status | Should -BeExactly 'written'
        (Invoke-RecordWriter -Root $root -Operation 'RecordDisposition' `
                -Json ($acceptance | ConvertTo-Json -Compress)).status | Should -BeExactly 'unchanged'

        $invalidCitation = [ordered]@{
            FindingId = $acceptance.FindingId
            Disposition = $acceptance.Disposition
            DecidedOn = $acceptance.DecidedOn
            Rationale = $acceptance.Rationale
            Scope = $acceptance.Scope
            Assumptions = $acceptance.Assumptions
            RevisitWhen = $acceptance.RevisitWhen
            Citations = @('../../outside.md:1')
        }
        {
            Invoke-RecordWriter -Root $root -Operation 'RecordDisposition' `
                -Json ($invalidCitation | ConvertTo-Json -Compress)
        } | Should -Throw '*repo-relative path*'

        $multilineOutcome = [ordered]@{}
        foreach ($key in $acceptance.Keys) { $multilineOutcome[$key] = $acceptance[$key] }
        $multilineOutcome.Disposition = 'corrective-plan'
        $multilineOutcome.ActionResult = "created: plan`n## Findings"
        {
            Invoke-RecordWriter -Root $root -Operation 'RecordDisposition' `
                -Json ($multilineOutcome | ConvertTo-Json -Compress)
        } | Should -Throw '*single line*'

        $acceptance.Assumptions = 'A newly discovered reflection registration may call this helper.'
        $acceptance.Rationale = 'The operator reopens the scoped decision after changed reachability evidence.'
        (Invoke-RecordWriter -Root $root -Operation 'RecordDisposition' `
                -Json ($acceptance | ConvertTo-Json -Compress)).status | Should -BeExactly 'written'

        $content = (Invoke-RecordWriter -Root $root -Operation 'Read').content
        $content | Should -Match 'The operator reopens the scoped decision'
        $content | Should -Match 'The operator accepts this bounded candidate'
        $content | Should -Match 'A newly discovered reflection registration'
        [regex]::Matches($content, '<!-- rcs-decision: RCS-D-\d{4} -->').Count |
            Should -Be 2
    }
}
