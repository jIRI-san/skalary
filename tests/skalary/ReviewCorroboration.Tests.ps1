#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'review finding corroboration derivation' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        Import-Module (Join-Path $script:repoRoot 'scripts/skalary/ReviewRun.psm1') -Force -DisableNameChecking

        function Script:New-CorroborationRun {
            param([Parameter(Mandatory)][object[]]$Findings)

            return [ordered]@{
                runId = '8f3c1d2e-5a47-4b90-9c61-2d7e0f4a6b35'
                reviewType = 'code'
                contentTrust = 'reviewer-authored-data'
                scope = '1 changed file'
                scopeAuthority = @{ digest = 'sha256:' + ('1' * 64) }
                planDigest = 'sha256:' + ('2' * 64)
                invocationBudget = 4
                modelSelection = @()
                roster = @('model-a', 'model-b')
                tasks = @(
                    @{ taskId = 'security-a'; concern = 'security'; model = 'model-a'; outcome = 'completed' }
                    @{ taskId = 'security-b'; concern = 'security'; model = 'model-b'; outcome = 'completed' }
                    @{ taskId = 'reliability-a'; concern = 'reliability'; model = 'model-a'; outcome = 'completed' }
                )
                findings = $Findings
            }
        }

        function Script:New-CorroborationFinding {
            param(
                [Parameter(Mandatory)][string]$TaskId,
                [Parameter(Mandatory)][string]$Title,
                [Parameter(Mandatory)][string]$Body,
                [string]$Action = '',
                [string]$RootCause = 'shared root',
                [string]$Component = 'src/shared.ps1'
            )

            return [ordered]@{
                taskId = $TaskId
                severity = 'Medium'
                title = $Title
                body = $Body
                action = $Action
                rootCause = $RootCause
                component = $Component
            }
        }
    }

    It 'test:ReviewReport.CorroborationNormalizationAndSimilarity flags only conservative cross-reviewer matches without changing raw findings' {
        $nearLeft = 'alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima mike november oscar papa quebec romeo sierra tango'
        $nearRight = 'alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima mike november oscar papa quebec romeo sierra uniform'
        $findings = @(
            New-CorroborationFinding -TaskId 'security-a' -Title 'EXACT: Café path' -Body "Preserve`r`nspacing!" -Action 'Fix it now.'
            New-CorroborationFinding -TaskId 'security-b' -Title "exact cafe$([char]0x0301) path" -Body "preserve spacing" -Action 'fix it now'
            New-CorroborationFinding -TaskId 'security-a' -Title 'Near duplicate report' -Body $nearLeft -Action 'Apply the bounded correction.' -RootCause 'near root'
            New-CorroborationFinding -TaskId 'security-b' -Title 'Near duplicate report' -Body $nearRight -Action 'Apply the bounded correction.' -RootCause 'near root'
            New-CorroborationFinding -TaskId 'security-a' -Title 'Review finding' -Body 'Common short boilerplate only.' -Action 'Inspect this.' -RootCause 'short root'
            New-CorroborationFinding -TaskId 'security-b' -Title 'Review finding changed' -Body 'Common short boilerplate only.' -Action 'Inspect that.' -RootCause 'short root'
            New-CorroborationFinding -TaskId 'security-a' -Title 'Same declared model' -Body 'This exact record comes from one declared model.' -Action 'Do not count twice.' -RootCause 'same model'
            New-CorroborationFinding -TaskId 'reliability-a' -Title 'Same declared model' -Body 'This exact record comes from one declared model.' -Action 'Do not count twice.' -RootCause 'same model'
            New-CorroborationFinding -TaskId 'security-a' -Title 'Separate group' -Body 'identical across a merge boundary' -Action 'Keep separate.' -RootCause 'group one'
            New-CorroborationFinding -TaskId 'security-b' -Title 'Separate group' -Body 'identical across a merge boundary' -Action 'Keep separate.' -RootCause 'group two'
        )

        $projection = ConvertTo-ReviewProjection -Run (New-CorroborationRun -Findings $findings)
        $byKey = @{}
        foreach ($entry in $projection.Findings) { $byKey[$entry.Key] = $entry }

        $byKey[(Get-ReviewMergeKey -Finding $findings[0])].Similarity | Should -Be 'exact'
        $byKey[(Get-ReviewMergeKey -Finding $findings[2])].Similarity | Should -Be 'near-duplicate'
        $byKey[(Get-ReviewMergeKey -Finding $findings[4])].Similarity | Should -Be 'none' -Because 'short shared boilerplate fails the minimum-content guard'
        $byKey[(Get-ReviewMergeKey -Finding $findings[6])].Similarity | Should -Be 'none' -Because 'one declared model is not independent support'
        $byKey[(Get-ReviewMergeKey -Finding $findings[8])].Similarity | Should -Be 'none' -Because 'comparison never crosses an existing merge group'
        $byKey[(Get-ReviewMergeKey -Finding $findings[9])].Similarity | Should -Be 'none'

        $exactRaw = @($byKey[(Get-ReviewMergeKey -Finding $findings[0])].Raw)
        $exactRaw.Count | Should -Be 2
        $exactRaw[0].Body, $exactRaw[1].Body | Should -Contain "Preserve`r`nspacing!"
        $exactRaw[0].Action, $exactRaw[1].Action | Should -Contain 'Fix it now.'

        $reversed = ConvertTo-ReviewProjection -Run (New-CorroborationRun -Findings @($findings[($findings.Count - 1)..0]))
        @($reversed.Findings | ForEach-Object { "$($_.Key):$($_.Similarity)" }) |
            Should -Be @($projection.Findings | ForEach-Object { "$($_.Key):$($_.Similarity)" })
    }
}
