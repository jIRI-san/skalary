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
        $script:corroborationMatrix = Get-Content `
            -LiteralPath (Join-Path $PSScriptRoot 'fixtures/review-run/corroboration-matrix.json') `
            -Raw | ConvertFrom-Json -Depth 30

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
            New-CorroborationFinding -TaskId 'security-a' -Title 'Boundary alpha' -Body 'bravo' -Action 'charlie' -RootCause 'field boundary'
            New-CorroborationFinding -TaskId 'security-b' -Title 'Boundary' -Body 'alpha bravo' -Action 'charlie' -RootCause 'field boundary'
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
        $byKey[(Get-ReviewMergeKey -Finding $findings[10])].Similarity |
            Should -Be 'none' -Because 'exact matching preserves normalized title, body, and action boundaries'

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

        $maximumSingleModel = @(
            1..256 | ForEach-Object {
                New-CorroborationFinding -TaskId 'security-a' -Title "Single model finding $_" `
                    -Body "alpha bravo charlie delta echo foxtrot golf hotel item $_" `
                    -Action "Inspect item $_." -RootCause 'maximum single model'
            }
        )
        $maximumRun = (
            New-CorroborationRun -Findings $maximumSingleModel -Roster @('model-a') -Tasks @(
                @{ taskId = 'security-a'; concern = 'security'; model = 'model-a'; outcome = 'completed' }
            ))
        $maximumProjection = InModuleScope $script:reviewModule.Name -Parameters @{ Run = $maximumRun } {
            param($Run)
            Mock Get-ReviewFindingSimilarityProfile {
                throw 'single-model groups must not build similarity profiles'
            }
            $result = ConvertTo-ReviewProjection -Run $Run
            Should -Invoke Get-ReviewFindingSimilarityProfile -Times 0 -Exactly
            return $result
        }
        $maximumProjection.Findings | Should -HaveCount 1
        $maximumProjection.Findings[0].RawCount | Should -Be 256
        $maximumProjection.Findings[0].Similarity | Should -Be 'none'
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
        $nearLeft = 'alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima mike november oscar papa quebec romeo sierra tango'
        $nearRight = 'alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima mike november oscar papa quebec romeo sierra uniform'
        $findings = @(
            New-CorroborationFinding -TaskId 'security-a' -Title 'Suspicious retained echo' `
                -Body 'Identical reviewer output is retained as observable support.' -Action 'Inspect manually.'
            New-CorroborationFinding -TaskId 'security-b' -Title 'Suspicious retained echo' `
                -Body 'Identical reviewer output is retained as observable support.' -Action 'Inspect manually.'
            New-CorroborationFinding -TaskId 'security-a' -Title 'Independent retained report A' `
                -Body 'The first reviewer found a shared retention defect.' -Action 'Repair the first path.' -RootCause 'elevated'
            New-CorroborationFinding -TaskId 'security-b' -Title 'Independent retained report B' `
                -Body 'The second reviewer found that retention defect separately.' -Action 'Repair the second path.' -RootCause 'elevated'
            New-CorroborationFinding -TaskId 'security-a' -Title 'Near retained echo' `
                -Body $nearLeft -Action 'Inspect the near match.' -RootCause 'near'
            New-CorroborationFinding -TaskId 'security-b' -Title 'Near retained echo' `
                -Body $nearRight -Action 'Inspect the near match.' -RootCause 'near'
        )
        $run = New-CorroborationRun -Findings $findings -Tasks $resultTasks
        $projection = ConvertTo-ReviewProjection -Run $run
        $entry = @(
            $projection.Findings |
                Where-Object { $_.CorroborationState -eq 'suspicious' -and $_.Similarity -eq 'exact' }
        )[0]

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
        $summary | Should -Match (
            '(?m)^\| \d+ \| M→M \| 2/C/X/S \| Suspicious retained echo \| `R\d+` \|$'
        )
        $suspiciousSection = [regex]::Match(
            $full,
            '(?ms)^### \[\d+\] Suspicious retained echo\r?\n(?<body>.*?)(?=^### \[\d+\] |\z)'
        )
        $suspiciousSection.Success | Should -BeTrue
        foreach ($line in @(
                '| **Raw severity** | `Medium` |',
                '| **Effective severity** | Medium |',
                '| **Support count** | 2 |',
                '| **Attendance state** | `clean` |',
                '| **Similarity** | `exact` |',
                '| **Corroboration state** | `suspicious` |'
            )) {
            $suspiciousSection.Groups['body'].Value | Should -Match ([regex]::Escape($line))
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
            $receipt.findings.rawSeverity.medium | Should -Be 3
            $receipt.findings.rawSeverity.high | Should -Be 0
            $receipt.findings.severity.medium | Should -Be 2
            $receipt.findings.severity.high | Should -Be 1
            $receipt.findings.corroboration.suspicious | Should -Be 2
            $receipt.findings.corroboration.corroborated | Should -Be 1
            $receipt.findings.similarity.exact | Should -Be 1
            $receipt.findings.similarity.'near-duplicate' | Should -Be 1
            $receipt.findings.similarity.none | Should -Be 1
            $receipt.findings.needsReview | Should -Be 2

            $replayed = Finalize-ReviewPlanRun -RunId $run.runId -PlanDir $planDir -Verdict blocked -RepoRoot $scratch
            $replayed.Replayed | Should -BeTrue
            [System.IO.File]::ReadAllBytes($replayed.Report) | Should -Be ([System.IO.File]::ReadAllBytes($final.Report))
            [System.IO.File]::ReadAllBytes($replayed.Receipt) | Should -Be ([System.IO.File]::ReadAllBytes($final.Receipt))

            $largeRunId = [guid]::NewGuid().ToString()
            $largeRunDir = Resolve-ReviewRunPreparation -RunId $largeRunId -PlanDir $planDir -RepoRoot $scratch |
                Select-Object -ExpandProperty runRoot
            [void](New-Item -ItemType Directory -Path $largeRunDir -Force)
            $largeTask = @{ taskId = 'security-large'; concern = 'security'; model = 'model-a' }
            Set-ReviewHandshake -RunDir $largeRunDir -Kind plan -Object (
                New-ReviewTestPlan -RunId $largeRunId -Roster @('model-a') -Tasks @($largeTask) -InvocationBudget 128
            )
            (Invoke-ReviewFreeze -RunId $largeRunId -PlanDir $planDir -RepoRoot $scratch).ExitCode | Should -Be 0
            $largeFindings = @(1..128 | ForEach-Object {
                    @{
                        taskId = 'security-large'
                        severity = 'High'
                        title = ('Gate finding {0:d3} ' -f $_) + ('x' * 143)
                        body = 'Gate-relevant detail remains in live authority.'
                        rootCause = "retained-root-$_"
                        component = "src/retained-$_.ps1"
                    }
                })
            $largeResultTask = @{ taskId = 'security-large'; concern = 'security'; model = 'model-a'; outcome = 'completed' }
            $largePublishedRun = New-ReviewTestRun -RunId $largeRunId `
                -PlanDigest (Get-ReviewFrozenDigest -RunDir $largeRunDir) -Roster @('model-a') `
                -Tasks @($largeResultTask) -Findings $largeFindings -InvocationBudget 128
            Set-ReviewHandshake -RunDir $largeRunDir -Kind result -Object $largePublishedRun
            (Invoke-ReviewPublish -RunId $largeRunId -PlanDir $planDir -RepoRoot $scratch).ExitCode | Should -Be 0

            $largeFinal = Finalize-ReviewPlanRun -RunId $largeRunId -PlanDir $planDir -Verdict blocked -RepoRoot $scratch
            Test-Path -LiteralPath $largeRunDir | Should -BeFalse
            $largeReportBytes = [System.IO.File]::ReadAllBytes($largeFinal.Report)
            $largeReportBytes.Length | Should -BeLessOrEqual ([int](Get-ReviewLimits)['maxRetainedReportBytes'])
            [System.Text.Encoding]::UTF8.GetString($largeReportBytes) |
                Should -Match 'additional blocking finding\(s\) omitted'
            $largeReceipt = Get-Content -LiteralPath $largeFinal.Receipt -Raw | ConvertFrom-Json -Depth 20
            $largeReceipt.findings.merged | Should -Be 128
            $largeReceipt.findings.corroboration.'single-source' | Should -Be 128
            $largeReceipt.findings.similarity.none | Should -Be 128

            $degradedRunId = [guid]::NewGuid().ToString()
            $degradedRunDir = Resolve-ReviewRunPreparation -RunId $degradedRunId -PlanDir $planDir -RepoRoot $scratch |
                Select-Object -ExpandProperty runRoot
            [void](New-Item -ItemType Directory -Path $degradedRunDir -Force)
            $degradedPlanTasks = @(
                @{ taskId = 'security-a'; concern = 'security'; model = 'model-a' }
                @{ taskId = 'security-b'; concern = 'security'; model = 'model-b' }
                @{ taskId = 'security-c'; concern = 'security'; model = 'model-c' }
            )
            Set-ReviewHandshake -RunDir $degradedRunDir -Kind plan -Object (
                New-ReviewTestPlan -RunId $degradedRunId -Roster @('model-a', 'model-b', 'model-c') `
                    -Tasks $degradedPlanTasks
            )
            (Invoke-ReviewFreeze -RunId $degradedRunId -PlanDir $planDir -RepoRoot $scratch).ExitCode | Should -Be 0
            $degradedResultTasks = @(
                @{ taskId = 'security-a'; concern = 'security'; model = 'model-a'; outcome = 'completed' }
                @{ taskId = 'security-b'; concern = 'security'; model = 'model-b'; outcome = 'completed' }
                @{ taskId = 'security-c'; concern = 'security'; model = 'model-c'; outcome = 'failed'; diagnostic = 'reviewer unavailable' }
            )
            $degradedFindings = @(
                New-CorroborationFinding -TaskId 'security-a' -Title 'Near degraded echo' `
                    -Body $nearLeft -Action 'Inspect the degraded near match.' -RootCause 'near-degraded'
                New-CorroborationFinding -TaskId 'security-b' -Title 'Near degraded echo' `
                    -Body $nearRight -Action 'Inspect the degraded near match.' -RootCause 'near-degraded'
                New-CorroborationFinding -TaskId 'security-a' -Title 'Attendance degraded' `
                    -Body 'One completed reviewer reported this separate issue.' -Action 'Do not elevate.' -RootCause 'degraded'
            )
            $degradedPublishedRun = New-ReviewTestRun -RunId $degradedRunId `
                -PlanDigest (Get-ReviewFrozenDigest -RunDir $degradedRunDir) -Roster @('model-a', 'model-b', 'model-c') `
                -Tasks $degradedResultTasks -Findings $degradedFindings
            Set-ReviewHandshake -RunDir $degradedRunDir -Kind result -Object $degradedPublishedRun
            (Invoke-ReviewPublish -RunId $degradedRunId -PlanDir $planDir -RepoRoot $scratch).ExitCode | Should -Be 5
            $degradedFinal = Finalize-ReviewPlanRun -RunId $degradedRunId -PlanDir $planDir -Verdict blocked -RepoRoot $scratch
            Test-Path -LiteralPath $degradedRunDir | Should -BeFalse
            $degradedReceipt = Get-Content -LiteralPath $degradedFinal.Receipt -Raw | ConvertFrom-Json -Depth 20
            $degradedReceipt.findings.corroboration.suspicious | Should -Be 1
            $degradedReceipt.findings.corroboration.degraded | Should -Be 1
            $degradedReceipt.findings.similarity.'near-duplicate' | Should -Be 1
            $degradedReceipt.findings.similarity.none | Should -Be 1
        }
        finally { Remove-ReviewScratchRoot -Path $scratch }
    }

    It 'test:ReviewReport.CorroborationMatrix covers support regimes deterministically and rejects caller-forged derived fields' {
        $script:corroborationMatrix.schema | Should -Be 'skalary/review-corroboration-matrix@1'
        @($script:corroborationMatrix.cases.id) | Should -Be @(
            'exact-duplicate',
            'near-duplicate',
            'unrelated-boilerplate',
            'unicode-tokenization',
            'single-source',
            'incomplete-attendance',
            'malicious-echo',
            'merged-severity-boundaries',
            'input-order-stability',
            'unchanged-clean-elevation'
        )

        foreach ($case in $script:corroborationMatrix.cases) {
            $rawBefore = ConvertTo-Json -InputObject $case.findings -Depth 20 -Compress
            $projection = ConvertTo-ReviewProjection -Run (
                New-CorroborationRun -Roster $case.roster -Tasks $case.tasks -Findings $case.findings
            )
            (ConvertTo-Json -InputObject $case.findings -Depth 20 -Compress) |
                Should -BeExactly $rawBefore -Because "$($case.id) must not mutate caller findings"
            @($projection.Findings | ForEach-Object { @($_.Raw).Count } | Measure-Object -Sum).Sum |
                Should -Be @($case.findings).Count -Because "$($case.id) must preserve every raw finding"

            $byRoot = @{}
            foreach ($entry in $projection.Findings) { $byRoot[[string]$entry.Raw[0].RootCause] = $entry }
            foreach ($expected in $case.expected) {
                $entry = $byRoot[[string]$expected.rootCause]
                $entry | Should -Not -BeNullOrEmpty -Because "$($case.id) must retain group '$($expected.rootCause)'"
                $entry.SupportCount | Should -Be $expected.supportCount -Because $case.id
                $entry.AttendanceState | Should -Be $expected.attendanceState -Because $case.id
                $entry.Similarity | Should -Be $expected.similarity -Because $case.id
                $entry.CorroborationState | Should -Be $expected.corroborationState -Because $case.id
                $entry.RawSeverity | Should -Be $expected.rawSeverity -Because $case.id
                $entry.EffectiveSeverity | Should -Be $expected.effectiveSeverity -Because $case.id
                $entry.NeedsReview | Should -Be $expected.needsReview -Because $case.id
                $entry.Elevated | Should -Be $expected.elevated -Because $case.id
                $entry.Reason | Should -Not -BeNullOrEmpty -Because "$($case.id) needs an observable explanation"
            }

            $full = Get-ReviewRunFullView -Projection $projection
            foreach ($label in @(
                    'Raw severity', 'Effective severity', 'Support count', 'Attendance state',
                    'Similarity', 'Corroboration state', 'Reason'
                )) {
                $full | Should -Match ([regex]::Escape($label)) -Because "$($case.id) must render '$label'"
            }

            $reversed = ConvertTo-ReviewProjection -Run (
                New-CorroborationRun -Roster $case.roster `
                    -Tasks @($case.tasks[($case.tasks.Count - 1)..0]) `
                    -Findings @($case.findings[($case.findings.Count - 1)..0])
            )
            $signature = {
                param($value)
                @($value.Findings | ForEach-Object {
                        "$($_.Key):$($_.SupportCount):$($_.AttendanceState):$($_.Similarity):" +
                        "$($_.CorroborationState):$($_.RawSeverity):$($_.EffectiveSeverity):$($_.NeedsReview)"
                    })
            }
            & $signature $reversed | Should -Be (& $signature $projection) -Because "$($case.id) must be input-order stable"
        }

        $baseRun = New-ReviewTestRun `
            -RunId '8f3c1d2e-5a47-4b90-9c61-2d7e0f4a6b35' `
            -PlanDigest ('sha256:' + ('1' * 64)) `
            -Roster @('model-a') `
            -Tasks @(@{ taskId = 'security-a'; concern = 'security'; model = 'model-a'; outcome = 'completed' }) `
            -Findings @(@{
                taskId = 'security-a'
                severity = 'Medium'
                title = 'Schema-owned derivation'
                body = 'Callers provide only raw reviewer data.'
                rootCause = 'schema'
                component = 'src/schema.ps1'
            })
        $baseJson = ConvertTo-ReviewCanonicalJson -Node $baseRun
        (Test-ReviewSchema -Json $baseJson -SchemaName 'review-run.schema.json') |
            Should -BeTrue -Because 'the raw fixture must be valid before forged fields are added'
        foreach ($forbidden in $script:corroborationMatrix.forbiddenFindingFields) {
            $forged = $baseJson | ConvertFrom-Json -AsHashtable -Depth 30
            $forged['findings'][0][[string]$forbidden.name] = $forbidden.value
            $forgedJson = (ConvertTo-Json -InputObject $forged -Depth 30 -Compress) + "`n"
            (Test-ReviewSchema -Json $forgedJson -SchemaName 'review-run.schema.json') |
                Should -BeFalse -Because "callers cannot supply derived finding field '$($forbidden.name)'"
        }
    }
}
