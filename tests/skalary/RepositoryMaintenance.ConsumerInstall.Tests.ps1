#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Repository maintenance consumer install' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'RepositoryMaintenance.Fixture.ps1')
    }

    It 'test:RCS.ConsumerInstall installs and executes the closed record and historical-reader payload' {
        $consumer = New-RecordRoot
        git -C $consumer init --quiet
        if ($LASTEXITCODE -ne 0) { throw 'Could not initialize the disposable foreign-consumer repository.' }
        $installOutput = & (Get-Command pwsh).Source -NoProfile -File $script:installPluginScript `
            -Name repository-maintenance -RepoRoot $consumer -Source $script:repoRoot
        if ($LASTEXITCODE -ne 0) {
            throw "Foreign-consumer install failed: $($installOutput -join "`n")"
        }

        $skillRoot = Join-Path $consumer '.github/skills/rcs'
        foreach ($path in @(
                'Write-RepositoryMaintenanceRecord.ps1',
                'scripts/PlanState.psm1',
                'scripts/DirectWorkflow.psm1',
                'scripts/SecretGuard.psm1',
                'scripts/Get-DirectPlanArtifactConsumerContext.ps1'
            )) {
            Test-Path -LiteralPath (Join-Path $skillRoot $path) | Should -BeTrue
        }

        $installedWriter = Join-Path $skillRoot 'Write-RepositoryMaintenanceRecord.ps1'
        (& $installedWriter -Action Read -RepoRoot $consumer | ConvertFrom-Json -Depth 10).status |
            Should -BeExactly 'missing'
        $payload = New-PublishPayload
        $published = & $installedWriter -Action Publish -RepoRoot $consumer `
            -PayloadJson ($payload | ConvertTo-Json -Depth 12 -Compress) |
            ConvertFrom-Json -Depth 10
        $published.status | Should -BeExactly 'written'
        Test-Path -LiteralPath (Join-Path $consumer 'docs/repository-maintenance.md') |
            Should -BeTrue

        $historyPlan = Join-Path $consumer 'docs/implementation-plans/2026-10-03-abcdef-smoke'
        [void](New-Item -ItemType Directory -Path (Join-Path $historyPlan 'assets') -Force)
        [System.IO.File]::WriteAllText((Join-Path $historyPlan 'plan.md'),
            "# Installed reader smoke`n<!-- plan-id: abcdef -->`n")
        [System.IO.File]::WriteAllText((Join-Path $historyPlan 'assets/requirements.md'),
            "# Requirements`n`n| ID | Requirement | Criteria | Phase |`n| --- | --- | --- | --- |")
        [System.IO.File]::WriteAllText((Join-Path $historyPlan 'assets/intent.md'),
            '# Installed consumer historical data')
        $installedReader = Join-Path $skillRoot `
            'scripts/Get-DirectPlanArtifactConsumerContext.ps1'
        $context = & $installedReader -PlanId abcdef -ArtifactKind Intent `
            -Relationship operator-selected -RepoRoot $consumer -Format Json |
            ConvertFrom-Json -Depth 12
        @($context.accepted).Count | Should -Be 1
        $context.accepted[0].authority | Should -BeExactly 'historical-context-only'
    }
}
