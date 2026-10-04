#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Repository maintenance corrective handoff' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'RepositoryMaintenance.Fixture.ps1')
    }

    It 'test:RCS.DispositionRoundTrip refuses pending, missing, unconfirmed, and stale corrective-plan handoffs' {
        $fixture = New-CorrectiveHandoffFixture
        $root = $fixture.Root
        $planFolder = $fixture.PlanFolder
        $decision = $fixture.Decision
        {
            Invoke-RecordWriter -Root $root -Operation 'RecordDisposition' `
                -Json ($decision | ConvertTo-Json -Compress)
        } | Should -Throw '*successfully completed*'
        $decision.ActionResult = 'created: docs/implementation-plans/standalone-2026-10-03-abcdef-missing/plan.md'
        {
            Invoke-RecordWriter -Root $root -Operation 'RecordDisposition' `
                -Json ($decision | ConvertTo-Json -Compress)
        } | Should -Throw '*does not resolve to the required current repository state*'
        $decision.ActionResult = 'created: docs/implementation-plans/standalone-2026-10-03-aabbcc-remove-helper/plan.md'
        {
            Invoke-RecordWriter -Root $root -Operation 'RecordDisposition' `
                -Json ($decision | ConvertTo-Json -Compress)
        } | Should -Throw '*does not resolve to a confirmed active plan*'
        $assetFolder = Join-Path $planFolder 'assets'
        [void](New-Item -ItemType Directory -Path $assetFolder -Force)
        foreach ($asset in @('intent.md', 'requirements.md', 'risks.md', 'decisions.md')) {
            [System.IO.File]::WriteAllText((Join-Path $assetFolder $asset), "# $asset`nCurrent confirmed context.`n")
        }
        [System.IO.File]::AppendAllText((Join-Path $planFolder 'plan.md'),
            '<!-- planning-confirmed: sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa -->' + "`n")
        {
            Invoke-RecordWriter -Root $root -Operation 'RecordDisposition' `
                -Json ($decision | ConvertTo-Json -Compress)
        } | Should -Throw '*does not resolve to a confirmed active plan*'
    }
}
