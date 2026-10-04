#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Repository maintenance archive disposition' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'RepositoryMaintenance.Fixture.ps1')
    }

    It 'test:RCS.ArchiveDisposition requires a verified archive and records its successful outcome' {
        $root = New-RecordRoot
        $finding = New-RecordFinding -Id 'RCS-archive-candidate'
        (Invoke-RecordWriter -Root $root -Operation 'Publish' `
                -Json ((New-PublishPayload -Findings @($finding)) | ConvertTo-Json -Depth 12 -Compress)).status |
            Should -BeExactly 'written'
        $activePlanFolder = Join-Path $root `
            'docs/implementation-plans/standalone-2026-10-03-ab12cd-archive-candidate'
        [void](New-Item -ItemType Directory -Path $activePlanFolder -Force)
        [System.IO.File]::WriteAllText((Join-Path $activePlanFolder 'plan.md'),
            "# Archive candidate`n<!-- plan-id: ab12cd -->`n")

        $archive = [ordered]@{
            FindingId = 'RCS-archive-candidate'
            Disposition = 'archived'
            DecidedOn = '2026-10-03'
            Rationale = 'The operator separately selected archival after existing gates passed.'
            Scope = 'Only the completed standalone plan.'
            Assumptions = 'Current plan evidence remains complete.'
            RevisitWhen = 'Any new linked work reopens the plan.'
            Citations = @('docs/implementation-plans/standalone-2026-10-03-ab12cd-archive-candidate/plan.md:1')
            ActionResult = 'pending: current completion gates have not been checked'
        }
        {
            Invoke-RecordWriter -Root $root -Operation 'RecordDisposition' `
                -Json ($archive | ConvertTo-Json -Compress)
        } | Should -Throw '*verified successful archive*'
        $archive.ActionResult = 'archived: docs/implementation-plans/archived/standalone-2026-10-03-ab12cd-missing/plan.md'
        {
            Invoke-RecordWriter -Root $root -Operation 'RecordDisposition' `
                -Json ($archive | ConvertTo-Json -Compress)
        } | Should -Throw '*does not resolve to the required current repository state*'
        $archiveFolder = Join-Path $root `
            'docs/implementation-plans/archived/standalone-2026-10-03-ab12cd-archive-candidate'
        [void](New-Item -ItemType Directory -Path (Split-Path -Parent $archiveFolder) -Force)
        Move-Item -LiteralPath $activePlanFolder -Destination $archiveFolder
        $archive.ActionResult = 'archived: docs/implementation-plans/archived/standalone-2026-10-03-ab12cd-archive-candidate/plan.md'
        (Invoke-RecordWriter -Root $root -Operation 'RecordDisposition' `
                -Json ($archive | ConvertTo-Json -Compress)).status | Should -BeExactly 'written'

        $content = (Invoke-RecordWriter -Root $root -Operation 'Read').content
        $content | Should -Match 'archived: docs/implementation-plans/archived/standalone-2026-10-03-ab12cd-archive-candidate/plan.md'
        [regex]::Matches($content, '<!-- rcs-decision: RCS-D-\d{4} -->').Count |
            Should -Be 1
    }
}
