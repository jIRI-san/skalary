#requires -Version 7.0

$script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$script:pluginRoot = Join-Path $script:repoRoot 'plugins/repository-maintenance'
$script:writer = Join-Path $script:pluginRoot `
    'skills/rcs/Write-RepositoryMaintenanceRecord.ps1'
$script:planStatePath = Join-Path $script:repoRoot 'scripts/skalary/PlanState.psm1'
$script:indexScript = Join-Path $script:repoRoot 'scripts/skalary/Get-PlanIndex.ps1'
$script:newPlanScript = Join-Path $script:repoRoot 'scripts/skalary/New-Plan.ps1'
$script:planTemplate = Join-Path $script:repoRoot `
    'plugins/create-implementation-plan/skills/cip/assets/plan-template.md'
$script:consumerContextScript = Join-Path $script:pluginRoot `
    'skills/rcs/scripts/Get-DirectPlanArtifactConsumerContext.ps1'
$script:installPluginScript = Join-Path $script:repoRoot 'scripts/skalary/Install-Plugin.ps1'

function New-RecordFinding {
    param(
        [string]$Id = 'RCS-unused-private-helper',
        [string]$Citation = 'src/helper.ps1:3',
        [string]$Scope = 'src/helper.ps1'
    )

    [ordered]@{
        Id = $Id
        Category = 'dead-code'
        Subject = 'Private helper has no supported caller'
        Scope = $Scope
        Citations = @($Citation)
        Expectation = 'Keep only code reachable from supported entry points.'
        CurrentBehavior = 'The private helper has no caller in the enumerated repository roots.'
        Impact = 'Removing it may reduce maintenance burden without changing supported behavior.'
        CounterEvidence = 'No public export or dynamic registration was found in the selected scope.'
        Uncertainty = 'External consumers were not observable.'
        Action = 'Create a corrective plan to remove the helper after owner confirmation.'
        Benefits = 'Less unused code to maintain.'
        Tradeoffs = 'External use remains unverified.'
        Effort = 2
        Complexity = 2
    }
}

function New-PublishPayload {
    param(
        [object[]]$Findings = @((New-RecordFinding)),
        [string]$Survey = 'Plans surveyed: 2; one plan has no saved intent.',
        [string]$Coverage = 'Traced: src/helper.ps1. Unread: external consumers and old discussion.'
    )

    [ordered]@{
        SourceCommit = '0123456789abcdef0123456789abcdef01234567'
        DirtyPaths = @()
        Survey = $Survey
        Coverage = $Coverage
        Findings = $Findings
    }
}

function Invoke-RecordWriter {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Operation,
        [AllowEmptyString()][string]$Json = ''
    )

    $result = if ($Operation -eq 'Read') {
        & $script:writer -Action $Operation -RepoRoot $Root
    }
    else {
        & $script:writer -Action $Operation -RepoRoot $Root -PayloadJson $Json
    }
    return (($result -join "`n") | ConvertFrom-Json -Depth 10)
}

function New-RecordRoot {
    $root = Join-Path $TestDrive ('rcs-' + [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $root -Force)
    return $root
}

function New-CorrectiveHandoffFixture {
    $root = New-RecordRoot
    (Invoke-RecordWriter -Root $root -Operation 'Publish' `
            -Json ((New-PublishPayload) | ConvertTo-Json -Depth 12 -Compress)) | Out-Null
    $planFolder = Join-Path $root `
        'docs/implementation-plans/standalone-2026-10-03-aabbcc-remove-helper'
    [void](New-Item -ItemType Directory -Path $planFolder -Force)
    [System.IO.File]::WriteAllText((Join-Path $planFolder 'plan.md'),
        "# Remove unused helper`n<!-- plan-id: aabbcc -->`n")
    return @{
        Root = $root
        PlanFolder = $planFolder
        Decision = [ordered]@{
            FindingId = 'RCS-unused-private-helper'
            Disposition = 'corrective-plan'
            DecidedOn = '2026-10-03'
            Rationale = 'The operator selected a normal corrective plan.'
            Scope = 'Only the cited helper.'
            Assumptions = 'The public tool remains supported.'
            RevisitWhen = 'A future plan changes the manual-tool contract.'
            Citations = @('src/helper.ps1:3')
            ActionResult = 'pending: no plan has been created'
        }
    }
}
