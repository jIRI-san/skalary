#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Repository maintenance corrective-plan decision history' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'RepositoryMaintenance.Fixture.ps1')
    }

    It 'test:RCS.DispositionRoundTrip records confirmed handoffs idempotently and preserves changed decision history' {
        $fixture = New-CorrectiveHandoffFixture
        $root = $fixture.Root
        $planFolder = $fixture.PlanFolder
        $decision = $fixture.Decision
        $decision.ActionResult = 'created: docs/implementation-plans/standalone-2026-10-03-aabbcc-remove-helper/plan.md'
        $assetFolder = Join-Path $planFolder 'assets'
        [void](New-Item -ItemType Directory -Path $assetFolder -Force)
        foreach ($asset in @('intent.md', 'requirements.md', 'risks.md', 'decisions.md')) {
            [System.IO.File]::WriteAllText((Join-Path $assetFolder $asset), "# $asset`nCurrent confirmed context.`n")
        }
        Import-Module $script:planStatePath -Force -DisableNameChecking
        try {
            $digest = Get-PlanningContextDigest -PlanDir $planFolder -RepoRoot $root
        }
        finally {
            Remove-Module PlanState -Force -ErrorAction SilentlyContinue
        }
        [System.IO.File]::AppendAllText((Join-Path $planFolder 'plan.md'),
            "<!-- planning-confirmed: sha256:$digest -->`n")
        (Invoke-RecordWriter -Root $root -Operation 'RecordDisposition' `
                -Json ($decision | ConvertTo-Json -Compress)).status | Should -BeExactly 'written'
        (Invoke-RecordWriter -Root $root -Operation 'RecordDisposition' `
                -Json ($decision | ConvertTo-Json -Compress)).status | Should -BeExactly 'unchanged'
        $decision.Rationale = 'The operator revisited the decision after new evidence.'
        (Invoke-RecordWriter -Root $root -Operation 'RecordDisposition' `
                -Json ($decision | ConvertTo-Json -Compress)).status | Should -BeExactly 'written'
        $content = (Invoke-RecordWriter -Root $root -Operation 'Read').content
        $content | Should -Match 'new evidence'
        $content | Should -Match 'selected a normal corrective plan'
    }
}
