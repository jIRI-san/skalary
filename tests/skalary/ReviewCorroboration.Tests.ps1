#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'review finding corroboration derivation' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:reviewModule = Import-Module (Join-Path $script:repoRoot 'scripts/skalary/ReviewRun.psm1') `
            -Force -DisableNameChecking -PassThru

        function Script:New-CorroborationRun {
            param(
                [Parameter(Mandatory)][object[]]$Findings,
                [string[]]$Roster = @('model-a', 'model-b'),
                [object[]]$Tasks = @(
                    @{ taskId = 'security-a'; concern = 'security'; model = 'model-a'; outcome = 'completed' }
                    @{ taskId = 'security-b'; concern = 'security'; model = 'model-b'; outcome = 'completed' }
                    @{ taskId = 'reliability-a'; concern = 'reliability'; model = 'model-a'; outcome = 'completed' }
                )
            )

            return [ordered]@{
                runId = '8f3c1d2e-5a47-4b90-9c61-2d7e0f4a6b35'
                reviewType = 'code'
                contentTrust = 'reviewer-authored-data'
                scope = '1 changed file'
                scopeAuthority = @{ digest = 'sha256:' + ('1' * 64) }
                planDigest = 'sha256:' + ('2' * 64)
                invocationBudget = 4
                modelSelection = @()
                roster = $Roster
                tasks = $Tasks
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

    It 'test:ReviewReport.CorroborationSeverityAndVerdict derives support conservatively and forces suspicious findings to needs-review' {
        $tasks = @(
            @{ taskId = 'security-a'; concern = 'security'; model = 'model-a'; outcome = 'completed' }
            @{ taskId = 'security-b'; concern = 'security'; model = 'model-b'; outcome = 'completed' }
            @{ taskId = 'security-c'; concern = 'security'; model = 'model-c'; outcome = 'completed' }
        )
        $findings = @(
            New-CorroborationFinding -TaskId 'security-a' -Title 'Corroborated A' -Body 'First independent observation.' -Action 'Fix boundary A.' -RootCause 'corroborated'
            New-CorroborationFinding -TaskId 'security-b' -Title 'Corroborated B' -Body 'Second distinct observation.' -Action 'Fix boundary B.' -RootCause 'corroborated'
            New-CorroborationFinding -TaskId 'security-c' -Title 'Corroborated C' -Body 'Third separate observation.' -Action 'Fix boundary C.' -RootCause 'corroborated'
            New-CorroborationFinding -TaskId 'security-a' -Title 'Suspicious echo' -Body 'Identical reviewer output.' -Action 'Inspect manually.' -RootCause 'suspicious'
            New-CorroborationFinding -TaskId 'security-b' -Title 'Suspicious echo' -Body 'Identical reviewer output.' -Action 'Inspect manually.' -RootCause 'suspicious'
            New-CorroborationFinding -TaskId 'security-c' -Title 'Suspicious echo' -Body 'Identical reviewer output.' -Action 'Inspect manually.' -RootCause 'suspicious'
            New-CorroborationFinding -TaskId 'security-a' -Title 'Single source' -Body 'Only one reviewer found this.' -Action 'Keep raw severity.' -RootCause 'single'
            New-CorroborationFinding -TaskId 'security-a' -Title 'Partial support A' -Body 'One distinct account.' -Action 'Check one.' -RootCause 'partial'
            New-CorroborationFinding -TaskId 'security-b' -Title 'Partial support B' -Body 'Another distinct account.' -Action 'Check two.' -RootCause 'partial'
        )

        $projection = ConvertTo-ReviewProjection -Run (New-CorroborationRun -Findings $findings -Roster @('model-a', 'model-b', 'model-c') -Tasks $tasks)
        $byRoot = @{}
        foreach ($entry in $projection.Findings) { $byRoot[$entry.Raw[0].RootCause] = $entry }

        $byRoot.corroborated.Support | Should -Be 'corroborated'
        $byRoot.corroborated.SupportCount | Should -Be 3
        $byRoot.corroborated.AttendanceState | Should -Be 'clean'
        $byRoot.corroborated.RawSeverity | Should -Be 'Medium'
        $byRoot.corroborated.EffectiveSeverity | Should -Be 'High'
        $byRoot.corroborated.Elevated | Should -BeTrue
        $byRoot.corroborated.Reason | Should -Match 'no suspicious similarity observed'

        $byRoot.suspicious.Support | Should -Be 'suspicious'
        $byRoot.suspicious.Similarity | Should -Be 'exact'
        $byRoot.suspicious.RawSeverity | Should -Be 'Medium'
        $byRoot.suspicious.EffectiveSeverity | Should -Be 'Medium'
        $byRoot.suspicious.Elevated | Should -BeFalse
        $byRoot.suspicious.NeedsReview | Should -BeTrue
        $byRoot.suspicious.Reason | Should -Match '^needs-review:'

        $byRoot.single.Support | Should -Be 'single-source'
        $byRoot.single.EffectiveSeverity | Should -Be 'Medium'
        $byRoot.single.NeedsReview | Should -BeFalse

        $byRoot.partial.Support | Should -Be 'corroborated'
        $byRoot.partial.SupportCount | Should -Be 2
        $byRoot.partial.Elevated | Should -BeFalse -Because 'severity elevation requires every declared model label'

        $spacedModel = ' model-a'
        $whitespaceSensitive = ConvertTo-ReviewProjection -Run (New-CorroborationRun -Roster @('model-a', $spacedModel) -Tasks @(
                @{ taskId = 'security-a'; concern = 'security'; model = 'model-a'; outcome = 'completed' }
                @{ taskId = 'security-b'; concern = 'security'; model = $spacedModel; outcome = 'completed' }
            ) -Findings @(
                New-CorroborationFinding -TaskId 'security-a' -Title 'Exact label A' -Body 'First independent account.' -Action 'Fix first.'
                New-CorroborationFinding -TaskId 'security-b' -Title 'Exact label B' -Body 'Second separate account.' -Action 'Fix second.'
            ))
        $whitespaceSensitive.Findings[0].SupportCount | Should -Be 2
        $whitespaceSensitive.Findings[0].Models | Should -Contain $spacedModel
        $whitespaceSensitive.Findings[0].Elevated | Should -BeTrue

        $reversed = ConvertTo-ReviewProjection -Run (New-CorroborationRun -Findings @($findings[($findings.Count - 1)..0]) `
                -Roster @('model-a', 'model-b', 'model-c') -Tasks @($tasks[($tasks.Count - 1)..0]))
        @($reversed.Findings | ForEach-Object { "$($_.Key):$($_.Support):$($_.EffectiveSeverity):$($_.NeedsReview)" }) |
            Should -Be @($projection.Findings | ForEach-Object { "$($_.Key):$($_.Support):$($_.EffectiveSeverity):$($_.NeedsReview)" })

        $degradedTasks = @(
            @{ taskId = 'security-a'; concern = 'security'; model = 'model-a'; outcome = 'completed' }
            @{ taskId = 'security-b'; concern = 'security'; model = 'model-b'; outcome = 'completed' }
            @{ taskId = 'security-c'; concern = 'security'; model = 'model-c'; outcome = 'failed' }
        )
        $degraded = ConvertTo-ReviewProjection -Run (New-CorroborationRun -Findings @($findings[0], $findings[1]) `
                -Roster @('model-a', 'model-b', 'model-c') -Tasks $degradedTasks)
        $degraded.Findings[0].Support | Should -Be 'degraded'
        $degraded.Findings[0].RawSeverity | Should -Be 'Medium'
        $degraded.Findings[0].EffectiveSeverity | Should -Be 'Medium'
        $degraded.Findings[0].Elevated | Should -BeFalse

        $suspiciousOnly = ConvertTo-ReviewProjection -Run (New-CorroborationRun -Findings @(
                New-CorroborationFinding -TaskId 'security-a' -Title 'Echo' -Body 'Same text.' -Action 'Review.'
                New-CorroborationFinding -TaskId 'security-b' -Title 'Echo' -Body 'Same text.' -Action 'Review.'
            ))
        {
            & $script:reviewModule {
                param($Projection)
                Get-ReviewRetainedReportText -Projection $Projection -Verdict approved
            } $suspiciousOnly
        } | Should -Throw -ExpectedMessage '*no finding marked needs-review*'
    }
}
