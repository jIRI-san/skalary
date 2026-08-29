#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'review finding corroboration derivation' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:reviewModule = Import-Module (Join-Path $script:repoRoot 'scripts/skalary/ReviewRun.psm1') `
            -Force -DisableNameChecking -PassThru
        Import-Module (Join-Path $PSScriptRoot 'fixtures/review-run/ReviewRunTestKit.psm1') `
            -Force -DisableNameChecking

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

        function Script:New-CorroborationProfile {
            param(
                [Parameter(Mandatory)][string]$ExactKey,
                [Parameter(Mandatory)][string[]]$Token,
                [Parameter(Mandatory)][int]$ContentLength
            )

            return [pscustomobject]@{
                ExactKey = $ExactKey
                Content = 'x' * $ContentLength
                Tokens = [System.Collections.Generic.HashSet[string]]::new(
                    $Token,
                    [System.StringComparer]::Ordinal
                )
            }
        }

        function Script:Get-CorroborationSimilarity {
            param(
                [Parameter(Mandatory)][object]$Left,
                [Parameter(Mandatory)][object]$Right
            )

            return & $script:reviewModule {
                param($LeftProfile, $RightProfile)
                Get-ReviewFindingSimilarity -LeftProfile $LeftProfile -RightProfile $RightProfile
            } $Left $Right
        }
    }

    It 'test:ReviewReport.CorroborationNormalizationAndSimilarity flags only conservative cross-declared-model matches without changing raw findings' {
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

        $rawBefore = ConvertTo-Json -InputObject $findings -Depth 10 -Compress
        $projection = ConvertTo-ReviewProjection -Run (New-CorroborationRun -Findings $findings)
        (ConvertTo-Json -InputObject $findings -Depth 10 -Compress) |
            Should -BeExactly $rawBefore -Because 'collation must not mutate any caller-owned raw finding field'
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

        $seven = 1..7 | ForEach-Object { "t$_" }
        $eight = 1..8 | ForEach-Object { "t$_" }
        Get-CorroborationSimilarity `
            -Left (New-CorroborationProfile -ExactKey left -Token $seven -ContentLength 48) `
            -Right (New-CorroborationProfile -ExactKey right -Token $seven -ContentLength 48) |
            Should -Be 'none' -Because 'seven tokens are below the minimum-content guard'
        Get-CorroborationSimilarity `
            -Left (New-CorroborationProfile -ExactKey left -Token $eight -ContentLength 48) `
            -Right (New-CorroborationProfile -ExactKey right -Token $eight -ContentLength 48) |
            Should -Be 'near-duplicate' -Because 'eight tokens meet the inclusive token boundary'
        Get-CorroborationSimilarity `
            -Left (New-CorroborationProfile -ExactKey left -Token $eight -ContentLength 47) `
            -Right (New-CorroborationProfile -ExactKey right -Token $eight -ContentLength 47) |
            Should -Be 'none' -Because '47 characters are below the minimum-content guard'
        Get-CorroborationSimilarity `
            -Left (New-CorroborationProfile -ExactKey left -Token $eight -ContentLength 48) `
            -Right (New-CorroborationProfile -ExactKey right -Token $eight -ContentLength 48) |
            Should -Be 'near-duplicate' -Because '48 characters meet the inclusive length boundary'
        Get-CorroborationSimilarity `
            -Left (New-CorroborationProfile -ExactKey left -Token (1..10 | ForEach-Object { "t$_" }) -ContentLength 48) `
            -Right (New-CorroborationProfile -ExactKey right -Token (1..9 | ForEach-Object { "t$_" }) -ContentLength 48) |
            Should -Be 'near-duplicate' -Because 'Jaccard similarity exactly 0.90 meets the threshold'
        Get-CorroborationSimilarity `
            -Left (New-CorroborationProfile -ExactKey left -Token (1..10 | ForEach-Object { "t$_" }) -ContentLength 48) `
            -Right (New-CorroborationProfile -ExactKey right -Token (1..8 | ForEach-Object { "t$_" }) -ContentLength 48) |
            Should -Be 'none' -Because 'Jaccard similarity below 0.90 does not flag'
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

        $byRoot.corroborated.CorroborationState | Should -Be 'corroborated'
        $byRoot.corroborated.SupportCount | Should -Be 3
        $byRoot.corroborated.AttendanceState | Should -Be 'clean'
        $byRoot.corroborated.RawSeverity | Should -Be 'Medium'
        $byRoot.corroborated.EffectiveSeverity | Should -Be 'High'
        $byRoot.corroborated.Elevated | Should -BeTrue
        $byRoot.corroborated.Reason | Should -Match 'no suspicious similarity observed'

        $byRoot.suspicious.CorroborationState | Should -Be 'suspicious'
        $byRoot.suspicious.Similarity | Should -Be 'exact'
        $byRoot.suspicious.RawSeverity | Should -Be 'Medium'
        $byRoot.suspicious.EffectiveSeverity | Should -Be 'Medium'
        $byRoot.suspicious.Elevated | Should -BeFalse
        $byRoot.suspicious.NeedsReview | Should -BeTrue
        $byRoot.suspicious.Reason | Should -Match '^needs-review:'

        $byRoot.single.CorroborationState | Should -Be 'single-source'
        $byRoot.single.EffectiveSeverity | Should -Be 'Medium'
        $byRoot.single.NeedsReview | Should -BeFalse

        $byRoot.partial.CorroborationState | Should -Be 'corroborated'
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
        @($reversed.Findings | ForEach-Object { "$($_.Key):$($_.CorroborationState):$($_.EffectiveSeverity):$($_.NeedsReview)" }) |
            Should -Be @($projection.Findings | ForEach-Object { "$($_.Key):$($_.CorroborationState):$($_.EffectiveSeverity):$($_.NeedsReview)" })

        $degradedTasks = @(
            @{ taskId = 'security-a'; concern = 'security'; model = 'model-a'; outcome = 'completed' }
            @{ taskId = 'security-b'; concern = 'security'; model = 'model-b'; outcome = 'completed' }
            @{ taskId = 'security-c'; concern = 'security'; model = 'model-c'; outcome = 'failed' }
        )
        $degraded = ConvertTo-ReviewProjection -Run (New-CorroborationRun -Findings @($findings[0], $findings[1]) `
                -Roster @('model-a', 'model-b', 'model-c') -Tasks $degradedTasks)
        $degraded.Findings[0].CorroborationState | Should -Be 'degraded'
        $degraded.Findings[0].RawSeverity | Should -Be 'Medium'
        $degraded.Findings[0].EffectiveSeverity | Should -Be 'Medium'
        $degraded.Findings[0].Elevated | Should -BeFalse

        $nearLeft = 'alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima mike november oscar papa quebec romeo sierra tango'
        $nearRight = 'alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima mike november oscar papa quebec romeo sierra uniform'
        $nearOnly = ConvertTo-ReviewProjection -Run (New-CorroborationRun -Findings @(
                New-CorroborationFinding -TaskId 'security-a' -Title 'Near echo' -Body $nearLeft -Action 'Review the finding.'
                New-CorroborationFinding -TaskId 'security-b' -Title 'Near echo' -Body $nearRight -Action 'Review the finding.'
            ))
        $nearOnly.Findings[0].CorroborationState | Should -Be 'suspicious'
        $nearOnly.Findings[0].Similarity | Should -Be 'near-duplicate'
        $nearOnly.Findings[0].Elevated | Should -BeFalse
        $nearOnly.Findings[0].NeedsReview | Should -BeTrue
        {
            & $script:reviewModule {
                param($Projection)
                Get-ReviewRetainedReportText -Projection $Projection -Verdict approved
            } $nearOnly
        } | Should -Throw -ExpectedMessage '*no finding marked needs-review*'

        $nearDegraded = ConvertTo-ReviewProjection -Run (New-CorroborationRun -Findings @(
                New-CorroborationFinding -TaskId 'security-a' -Title 'Near echo' -Body $nearLeft -Action 'Review the finding.'
                New-CorroborationFinding -TaskId 'security-b' -Title 'Near echo' -Body $nearRight -Action 'Review the finding.'
            ) -Roster @('model-a', 'model-b', 'model-c') -Tasks $degradedTasks)
        $nearDegraded.Findings[0].AttendanceState | Should -Be 'degraded'
        $nearDegraded.Findings[0].CorroborationState | Should -Be 'suspicious' -Because 'suspicion takes precedence over degraded attendance'
        $nearDegraded.Findings[0].EffectiveSeverity | Should -Be 'Medium'
        $nearDegraded.Findings[0].NeedsReview | Should -BeTrue
    }

    It 'test:ReviewReport.CorroborationRenderingAndRetention publishes, verifies, retains, and replays observable support truth' {
        $tasks = @(
            @{ taskId = 'security-a'; concern = 'security'; model = 'model-a' }
            @{ taskId = 'security-b'; concern = 'security'; model = 'model-b' }
        )
        $resultTasks = @($tasks | ForEach-Object {
                @{ taskId = $_.taskId; concern = $_.concern; model = $_.model; outcome = 'completed' }
            })
        $findings = @(
            New-CorroborationFinding -TaskId 'security-a' -Title 'Suspicious retained echo' `
                -Body 'Identical reviewer output is retained as observable support.' -Action 'Inspect manually.'
            New-CorroborationFinding -TaskId 'security-b' -Title 'Suspicious retained echo' `
                -Body 'Identical reviewer output is retained as observable support.' -Action 'Inspect manually.'
        )
        $run = New-CorroborationRun -Findings $findings -Tasks $resultTasks
        $projection = ConvertTo-ReviewProjection -Run $run
        $entry = $projection.Findings[0]

        foreach ($property in @(
                'SupportCount', 'AttendanceState', 'Similarity', 'CorroborationState',
                'RawSeverity', 'EffectiveSeverity', 'Reason'
            )) {
            $entry.PSObject.Properties.Name | Should -Contain $property
        }
        $entry.Raw | Should -HaveCount 2
        $entry.RawSeverity | Should -Be 'Medium'
        $entry.EffectiveSeverity | Should -Be 'Medium'
        $entry.SupportCount | Should -Be 2
        $entry.AttendanceState | Should -Be 'clean'
        $entry.Similarity | Should -Be 'exact'
        $entry.CorroborationState | Should -Be 'suspicious'

        $summary = Get-ReviewRunSummaryView -Projection $projection
        $full = Get-ReviewRunFullView -Projection $projection
        foreach ($label in @(
                'Raw severity', 'Effective severity', 'Support count', 'Attendance',
                'Similarity', 'Corroboration', 'Reason'
            )) {
            $summary | Should -Match ([regex]::Escape($label))
            $full | Should -Match ([regex]::Escape($label))
        }
        foreach ($value in @('Medium', '2', 'clean', 'exact', 'suspicious', 'needs-review:')) {
            $summary | Should -Match ([regex]::Escape($value))
            $full | Should -Match ([regex]::Escape($value))
        }
        @([regex]::Matches($full, '(?m)^\| `security-[ab]` \| `Medium` \| Suspicious retained echo \|')).Count |
            Should -Be 2 -Because 'the rendered corroboration view must preserve both raw findings'

        $scratch = New-ReviewScratchRoot
        try {
            $planDir = New-ReviewTestPlanDir -ScratchRoot $scratch
            $runDir = Resolve-ReviewRunPreparation -RunId $run.runId -PlanDir $planDir -RepoRoot $scratch |
                Select-Object -ExpandProperty runRoot
            [void](New-Item -ItemType Directory -Path $runDir -Force)
            Set-ReviewHandshake -RunDir $runDir -Kind plan -Object (
                New-ReviewTestPlan -RunId $run.runId -Roster @('model-a', 'model-b') -Tasks $tasks
            )
            (Invoke-ReviewFreeze -RunId $run.runId -PlanDir $planDir -RepoRoot $scratch).ExitCode |
                Should -Be 0
            $publishedRun = New-ReviewTestRun -RunId $run.runId -PlanDigest (Get-ReviewFrozenDigest -RunDir $runDir) `
                -Roster @('model-a', 'model-b') -Tasks $resultTasks -Findings $findings
            Set-ReviewHandshake -RunDir $runDir -Kind result -Object $publishedRun
            (Invoke-ReviewPublish -RunId $run.runId -PlanDir $planDir -RepoRoot $scratch).ExitCode |
                Should -Be 0

            $verified = Read-ReviewManifest -RunDir $runDir -Boundary $scratch
            $verified.Bytes.Keys | Should -Be @('plan', 'canonical', 'summary', 'full')
            [System.Text.Encoding]::UTF8.GetString($verified.Bytes.summary) | Should -Match 'suspicious'
            [System.Text.Encoding]::UTF8.GetString($verified.Bytes.full) | Should -Match 'needs-review:'

            Set-ReviewHandshake -RunDir $runDir -Kind result -Object $publishedRun
            (Invoke-ReviewPublish -RunId $run.runId -PlanDir $planDir -RepoRoot $scratch).ExitCode |
                Should -Be 0 -Because 'an identical v1 publication replay remains idempotent'

            $final = Finalize-ReviewPlanRun -RunId $run.runId -PlanDir $planDir -Verdict blocked -RepoRoot $scratch
            Test-Path -LiteralPath $runDir | Should -BeFalse
            $retained = Get-Content -LiteralPath $final.Report -Raw
            $retained | Should -Match 'Non-blocking needs-review findings'
            $retained | Should -Match 'corroboration=suspicious; support=2; attendance=clean; similarity=exact'
            $retained | Should -Match 'needs-review:'
            $receipt = Get-Content -LiteralPath $final.Receipt -Raw | ConvertFrom-Json -Depth 20
            $receipt.findings.rawSeverity.medium | Should -Be 1
            $receipt.findings.severity.medium | Should -Be 1
            $receipt.findings.corroboration.suspicious | Should -Be 1
            $receipt.findings.similarity.exact | Should -Be 1
            $receipt.findings.needsReview | Should -Be 1

            $replayed = Finalize-ReviewPlanRun -RunId $run.runId -PlanDir $planDir -Verdict blocked -RepoRoot $scratch
            $replayed.Replayed | Should -BeTrue
            [System.IO.File]::ReadAllBytes($replayed.Report) | Should -Be ([System.IO.File]::ReadAllBytes($final.Report))
            [System.IO.File]::ReadAllBytes($replayed.Receipt) | Should -Be ([System.IO.File]::ReadAllBytes($final.Receipt))
        }
        finally { Remove-ReviewScratchRoot -Path $scratch }
    }
}
