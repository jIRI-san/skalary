#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Headless SI due handoff' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        Import-Module (
            Join-Path $script:repoRoot 'plugins/self-improvement/scripts/SiResolverReceipt.psm1'
        ) -Force

        function Script:Install-PluginClosure {
            param(
                [Parameter(Mandatory)][string]$RootPlugin,
                [Parameter(Mandatory)][string]$TargetRoot
            )

            $pending = [System.Collections.Generic.Queue[string]]::new()
            $installed = [System.Collections.Generic.HashSet[string]]::new(
                [System.StringComparer]::Ordinal
            )
            $versions = @{}
            $pending.Enqueue($RootPlugin)
            while ($pending.Count -gt 0) {
                $name = $pending.Dequeue()
                if (-not $installed.Add($name)) { continue }
                $pluginRoot = Join-Path $script:repoRoot "plugins/$name"
                $manifest = Get-Content -LiteralPath (Join-Path $pluginRoot 'plugin.json') -Raw |
                    ConvertFrom-Json -Depth 100
                $versions[$name] = [string]$manifest.version
                foreach ($dependency in @($manifest.dependencies)) {
                    $pending.Enqueue([string]$dependency)
                }
                foreach ($file in @($manifest.files)) {
                    $target = Join-Path $TargetRoot ('.github/' + [string]$file.dest)
                    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force)
                    Copy-Item -LiteralPath (Join-Path $pluginRoot ([string]$file.src)) `
                        -Destination $target -Force
                }
            }
            return $versions
        }

        function Script:New-InstallRoot {
            $root = Join-Path ([System.IO.Path]::GetTempPath()) (
                'si-due-' + [Guid]::NewGuid().ToString('N')
            )
            [void](New-Item -ItemType Directory -Path $root -Force)
            return $root
        }

        function Script:Write-SiJson {
            param(
                [Parameter(Mandatory)][string]$Path,
                [Parameter(Mandatory)]$Value
            )

            [void](New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force)
            [System.IO.File]::WriteAllText(
                $Path,
                (($Value | ConvertTo-Json -Depth 100 -Compress) + "`n"),
                [System.Text.UTF8Encoding]::new($false)
            )
        }

        function Script:Invoke-FixtureGit {
            param(
                [Parameter(Mandatory)][string]$Root,
                [Parameter(Mandatory)][string[]]$Argument
            )

            $output = @(& git -C $Root @Argument 2>&1)
            if ($LASTEXITCODE -ne 0) {
                throw "Fixture git '$($Argument[0])' failed: $($output -join "`n")"
            }
            return @($output)
        }

        function Script:New-SurfaceRun {
            param(
                [Parameter(Mandatory)][string]$RunId,
                [Parameter(Mandatory)][string]$DueId,
                [Parameter(Mandatory)][string]$SourceCommit,
                [Parameter(Mandatory)][string]$Status,
                [object[]]$Candidates = @(),
                [object[]]$Choices = @(),
                [string]$ResolverReceiptId,
                [string]$RankedSetDigest = ('0' * 64)
            )

            $complete = $Status -in @('declined-before-ranking', 'no-candidates', 'completed')
            return [ordered]@{
                schemaVersion = 2
                runId = $RunId
                dueId = $DueId
                status = $Status
                createdAtUtc = '2026-08-09T00:00:00Z'
                updatedAtUtc = '2026-08-09T00:00:00Z'
                completedAtUtc = if ($complete) { '2026-08-09T01:00:00Z' } else { $null }
                provenance = [ordered]@{
                    repoId = 'origin:example.test/owner/repo'
                    planId = '1936cb'
                    sourceCommit = $SourceCommit
                    pinnedBaseOid = ('b' * 40)
                    resolverReceiptId = if ([string]::IsNullOrEmpty($ResolverReceiptId)) {
                        $null
                    }
                    else {
                        $ResolverReceiptId
                    }
                }
                rankedSet = [ordered]@{
                    count = $Candidates.Count
                    digest = $RankedSetDigest
                    candidates = $Candidates
                }
                choices = $Choices
                proposalPr = $null
            }
        }

        function Script:New-SurfaceCandidate {
            param(
                [Parameter(Mandatory)][int]$Rank,
                [Parameter(Mandatory)][string]$Sentinel
            )

            return [ordered]@{
                title = "$Sentinel title $Rank"
                rationale = "$Sentinel rationale $Rank"
                sources = @("$Sentinel-source-$Rank")
                targets = @("$Sentinel-target-$Rank")
            }
        }

        function Script:Get-SurfaceDueId {
            param([Parameter(Mandatory)][string]$SourceCommit)

            $bytes = [System.Text.Encoding]::UTF8.GetBytes(
                "origin:example.test/owner/repo|1936cb|$SourceCommit|si-due-v1"
            )
            return [Convert]::ToHexString(
                [System.Security.Cryptography.SHA256]::HashData($bytes)
            ).ToLowerInvariant()
        }
    }

    It 'test:SiDue.HeadlessDependencyInvocationAllowlistAndDedup installs independently versioned SI, invokes its writer after source persistence, and deduplicates the exact due' {
        $autopilotManifest = Get-Content -LiteralPath (
            Join-Path $script:repoRoot 'plugins/autopilot/plugin.json'
        ) -Raw | ConvertFrom-Json -Depth 100
        @($autopilotManifest.dependencies) | Should -Contain 'self-improvement'

        $agent = [System.IO.File]::ReadAllText(
            (Join-Path $script:repoRoot 'plugins/autopilot/agents/autopilot.agent.md')
        )
        $writerPath = '.github/skills/si/scripts/Enqueue-SiDue.ps1'
        $headlessPath = '.github/skills/autopilot/scripts/Invoke-SiDueEnqueue.ps1'
        $agent | Should -Match ([regex]::Escape($writerPath))
        $agent | Should -Match ([regex]::Escape($headlessPath))
        $agent | Should -Match 'bound argument array'
        $agent | Should -Match 'sha256\(repo-id\|plan-id\|source-commit\|si-due-v1\)'
        $agent | Should -Match 'degraded: SI due enqueue failed'
        $agent | Should -Match 'Headless completion does not run `/si`'
        $agent | Should -Match 'Workflow carve-out:.+Invoke-SiDueEnqueue.+Enqueue-SiDue\.ps1'
        $sourcePush = $agent.IndexOf('required post-archive `git push origin <current-branch>`')
        $enqueue = $agent.IndexOf('capture complete-source OID -> enqueue')
        $sourcePush | Should -BeGreaterThan -1
        $enqueue | Should -BeGreaterThan $sourcePush

        $autopilotRoot = New-InstallRoot
        $standaloneRoot = New-InstallRoot
        $outside = $null
        $caseVariantOutside = $null
        $handoffRemote = $null
        try {
            $versions = Install-PluginClosure -RootPlugin autopilot -TargetRoot $autopilotRoot
            $versions.Keys | Should -Contain 'self-improvement'
            $versions['autopilot'] | Should -Not -Be $versions['self-improvement']
            Test-Path -LiteralPath (Join-Path $autopilotRoot $writerPath) -PathType Leaf |
                Should -BeTrue
            Test-Path -LiteralPath (Join-Path $autopilotRoot $headlessPath) -PathType Leaf |
                Should -BeTrue

            Import-Module (
                Join-Path $autopilotRoot '.github/skills/si/scripts/SiStateStore.psm1'
            ) -Force
            $repoId = Get-SiRepoId -RepoRoot $autopilotRoot
            $manifest = New-SiManifest
            $manifest.generation = 128
            $manifest.pending = @(1..128 | ForEach-Object {
                    $commit = $_.ToString('x40')
                    [pscustomobject][ordered]@{
                        dueId = Get-SiDueId -RepoId $repoId -PlanId 1936cb `
                            -SourceCommit $commit
                        repoId = $repoId
                        planId = '1936cb'
                        sourceCommit = $commit
                        createdAtUtc = '2026-08-09T00:00:00Z'
                        deferUntilUtc = $null
                        status = 'pending'
                        runId = $null
                    }
                })
            $manifestPath = Join-Path $autopilotRoot 'docs/self-improvement/state.json'
            Write-SiJson -Path $manifestPath -Value $manifest
            $beforeFailure = [System.IO.File]::ReadAllBytes($manifestPath)
            $degraded = & (Join-Path $autopilotRoot $headlessPath) `
                -RepoRoot $autopilotRoot -PlanId 1936cb -SourceCommit ('f' * 40)
            $degraded.Status | Should -Be 'degraded'
            $degraded.Written | Should -BeFalse
            $degraded.Note | Should -Match (
                '^degraded: SI due enqueue failed: capacity-blocked:'
            )
            [Convert]::ToHexString([System.IO.File]::ReadAllBytes($manifestPath)) |
                Should -Be ([Convert]::ToHexString($beforeFailure))

            $handoffRemote = New-InstallRoot
            [void](Invoke-FixtureGit -Root $handoffRemote -Argument @('init', '--bare', '--quiet'))
            [void](Invoke-FixtureGit -Root $autopilotRoot -Argument @(
                    'init', '--initial-branch=feature/headless-handoff', '--quiet'
                ))
            [void](Invoke-FixtureGit -Root $autopilotRoot -Argument @(
                    'config', 'user.name', 'Headless Handoff Fixture'
                ))
            [void](Invoke-FixtureGit -Root $autopilotRoot -Argument @(
                    'config', 'user.email', 'headless@example.test'
                ))
            [void](Invoke-FixtureGit -Root $autopilotRoot -Argument @(
                    'remote', 'add', 'origin', $handoffRemote
                ))
            $handoffPath = Join-Path $autopilotRoot 'plan-pr-handoff.txt'
            [System.IO.File]::WriteAllText(
                $handoffPath,
                "$($degraded.Note)`n",
                [System.Text.UTF8Encoding]::new($false)
            )
            [void](Invoke-FixtureGit -Root $autopilotRoot -Argument @(
                    'add', 'plan-pr-handoff.txt'
                ))
            [void](Invoke-FixtureGit -Root $autopilotRoot -Argument @(
                    'commit', '--quiet', '-m', 'record completed plan PR handoff'
                ))
            $handoffHead = @(
                Invoke-FixtureGit -Root $autopilotRoot -Argument @('rev-parse', 'HEAD')
            )[0]
            [void](Invoke-FixtureGit -Root $autopilotRoot -Argument @(
                    'push', '--quiet', 'origin', 'HEAD:refs/heads/feature/headless-handoff'
                ))
            $remoteLine = @(
                Invoke-FixtureGit -Root $autopilotRoot -Argument @(
                    'ls-remote', 'origin', 'refs/heads/feature/headless-handoff'
                )
            )[0]
            $remoteHead = ($remoteLine -split '\s+')[0]
            $remoteHead | Should -Be $handoffHead `
                -Because 'the plan PR handoff must complete after the installed enqueue writer fails'

            $installedWriter = Join-Path $autopilotRoot $writerPath
            [System.IO.File]::WriteAllText(
                $installedWriter,
                @'
param([string]$RepoRoot, [string]$PlanId, [string]$SourceCommit)
[pscustomobject]@{
    Status = 'cas-exhausted'
    DueId = 'mixed-version-due'
    Written = $false
    Note = 'cas-exhausted'
    Attempts = 3
}
'@,
                [System.Text.UTF8Encoding]::new($false)
            )
            $returnedFailure = & (Join-Path $autopilotRoot $headlessPath) `
                -RepoRoot $autopilotRoot -PlanId 1936cb -SourceCommit ('e' * 40)
            $returnedFailure.Status | Should -Be 'degraded'
            $returnedFailure.DueId | Should -Be 'mixed-version-due'
            $returnedFailure.Written | Should -BeFalse
            $returnedFailure.Note | Should -Be (
                "degraded: SI due enqueue failed: writer status 'cas-exhausted'"
            )
            $returnedFailure.Attempts | Should -Be 3

            $standaloneVersions = Install-PluginClosure -RootPlugin self-improvement `
                -TargetRoot $standaloneRoot
            $standaloneVersions.Keys | Should -Contain 'self-improvement'
            $writer = Join-Path $standaloneRoot $writerPath
            Test-Path -LiteralPath $writer -PathType Leaf | Should -BeTrue

            & git -C $standaloneRoot init --quiet
            & git -C $standaloneRoot remote add origin https://github.com/Example/Consumer.git
            $sourceCommit = 'a' * 40
            $repoId = 'origin:github.com/Example/Consumer'
            $expectedBytes = [System.Text.Encoding]::UTF8.GetBytes(
                "$repoId|1936cb|$sourceCommit|si-due-v1"
            )
            $expectedDue = [Convert]::ToHexString(
                [System.Security.Cryptography.SHA256]::HashData($expectedBytes)
            ).ToLowerInvariant()

            $first = & $writer -RepoRoot $standaloneRoot -PlanId 1936cb `
                -SourceCommit $sourceCommit
            $manifestPath = Join-Path $standaloneRoot 'docs/self-improvement/state.json'
            $firstBytes = [System.IO.File]::ReadAllBytes($manifestPath)
            $second = & $writer -RepoRoot $standaloneRoot -PlanId 1936cb `
                -SourceCommit $sourceCommit
            $first.Status | Should -Be 'complete' `
                -Because 'the handoff flow must continue after reporting the prior enqueue degradation'
            $first.Written | Should -BeTrue
            $first.DueId | Should -Be $expectedDue
            $second.Status | Should -Be 'complete'
            $second.Written | Should -BeFalse
            $second.DueId | Should -Be $expectedDue
            [Convert]::ToHexString([System.IO.File]::ReadAllBytes($manifestPath)) |
                Should -Be ([Convert]::ToHexString($firstBytes))

            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -Depth 100
            @($manifest.pending).Count | Should -Be 1
            $manifest.pending[0].repoId | Should -Be $repoId
            $manifest.pending[0].sourceCommit | Should -Be $sourceCommit

            $outside = New-InstallRoot
            [void](New-Item -ItemType Directory -Path (Join-Path $standaloneRoot 'docs') -Force)
            Remove-Item -LiteralPath (Join-Path $standaloneRoot 'docs/self-improvement') `
                -Recurse -Force
            try {
                [void](New-Item -ItemType SymbolicLink `
                        -Path (Join-Path $standaloneRoot 'docs/self-improvement') `
                        -Target $outside -ErrorAction Stop)
            }
            catch {
                Set-ItResult -Skipped -Because 'the filesystem or account does not permit symlink creation'
                return
            }
            {
                & $writer -RepoRoot $standaloneRoot -PlanId 1936cb -SourceCommit ('b' * 40)
            } | Should -Throw '*escapes repository root via link*'
            Test-Path -LiteralPath (Join-Path $outside 'state.json') | Should -BeFalse

            Remove-Item -LiteralPath (Join-Path $standaloneRoot 'docs/self-improvement') -Force
            if (-not $IsWindows) {
                $caseVariantOutside = Join-Path (Split-Path -Parent $standaloneRoot) (
                    (Split-Path -Leaf $standaloneRoot).ToUpperInvariant()
                )
                [void](New-Item -ItemType Directory -Path $caseVariantOutside -Force)
                [void](New-Item -ItemType SymbolicLink `
                        -Path (Join-Path $standaloneRoot 'docs/self-improvement') `
                        -Target $caseVariantOutside -ErrorAction Stop)
                {
                    & $writer -RepoRoot $standaloneRoot -PlanId 1936cb -SourceCommit ('c' * 40)
                } | Should -Throw '*escapes repository root via link*'
                Test-Path -LiteralPath (Join-Path $caseVariantOutside 'state.json') |
                    Should -BeFalse
                Remove-Item -LiteralPath (Join-Path $standaloneRoot 'docs/self-improvement') -Force
            }
        }
        finally {
            Remove-Item -LiteralPath $autopilotRoot -Recurse -Force
            Remove-Item -LiteralPath $standaloneRoot -Recurse -Force
            if ($null -ne $outside -and (Test-Path -LiteralPath $outside)) {
                Remove-Item -LiteralPath $outside -Recurse -Force
            }
            if ($null -ne $caseVariantOutside -and
                (Test-Path -LiteralPath $caseVariantOutside)) {
                Remove-Item -LiteralPath $caseVariantOutside -Recurse -Force
            }
            if ($null -ne $handoffRemote -and (Test-Path -LiteralPath $handoffRemote)) {
                Remove-Item -LiteralPath $handoffRemote -Recurse -Force
            }
        }
    }

    It 'test:SiDue.InteractiveInstalledSurfaceTransitionMatrix pins main, classifies fixed branches and outcomes, and exposes metadata only' {
            $consumer = New-InstallRoot
            $remote = New-InstallRoot
            try {
                $versions = Install-PluginClosure -RootPlugin continue-implementation `
                    -TargetRoot $consumer
                $versions.Keys | Should -Contain 'continue-implementation'
                $versions.Keys | Should -Contain 'self-improvement'
                $lifecycle = Join-Path $consumer '.github/skills/si/scripts/Invoke-SiLifecycle.ps1'
                Test-Path -LiteralPath $lifecycle -PathType Leaf | Should -BeTrue

                [void](Invoke-FixtureGit -Root $remote -Argument @('init', '--bare', '--quiet'))
                [void](Invoke-FixtureGit -Root $consumer -Argument @('init', '--initial-branch=main', '--quiet'))
                [void](Invoke-FixtureGit -Root $consumer -Argument @('config', 'user.name', 'SI Fixture'))
                [void](Invoke-FixtureGit -Root $consumer -Argument @('config', 'user.email', 'si@example.test'))
                [void](Invoke-FixtureGit -Root $consumer -Argument @('remote', 'add', 'origin', $remote))

                $pendingSource = '1' * 40
                $deferredSource = '2' * 40
                $proposalSource = '3' * 40
                $declinedSource = '4' * 40
                $noCandidateSource = '5' * 40
                $completedSource = '6' * 40
                $orphanSource = '7' * 40
                $pendingDue = Get-SurfaceDueId -SourceCommit $pendingSource
                $deferredDue = Get-SurfaceDueId -SourceCommit $deferredSource
                $proposalDue = Get-SurfaceDueId -SourceCommit $proposalSource
                $declinedDue = Get-SurfaceDueId -SourceCommit $declinedSource
                $noCandidateDue = Get-SurfaceDueId -SourceCommit $noCandidateSource
                $completedDue = Get-SurfaceDueId -SourceCommit $completedSource
                $orphanDue = Get-SurfaceDueId -SourceCommit $orphanSource
                $repairObservation = '8' * 64
                $proposalRunId = 'a' * 64
                $declinedRunId = 'b' * 64
                $noCandidateRunId = 'c' * 64
                $completedRunId = 'd' * 64
                $orphanRunId = '8' * 64
                $sentinel = 'PRIVATE-SURFACE-TEXT'

                $proposalCandidate = New-SurfaceCandidate -Rank 1 -Sentinel $sentinel
                $proposalRanked = New-SiRankedCandidates -Candidate @(
                    [pscustomobject]$proposalCandidate
                )
                $proposalRun = New-SurfaceRun -RunId $proposalRunId -DueId $proposalDue `
                    -SourceCommit $proposalSource -Status proposal-pending `
                    -Candidates @($proposalRanked.Candidates) `
                    -Choices @([ordered]@{
                            candidateId = $proposalRanked.CandidateIds[0]
                            disposition = 'deferred'
                            proposalPr = $null
                        }) -ResolverReceiptId ('c' * 64) `
                    -RankedSetDigest $proposalRanked.RankedSetDigest
                $declinedRun = New-SurfaceRun -RunId $declinedRunId -DueId $declinedDue `
                    -SourceCommit $declinedSource -Status declined-before-ranking
                $emptyRanked = New-SiRankedCandidates -Candidate @()
                $noCandidateRun = New-SurfaceRun -RunId $noCandidateRunId -DueId $noCandidateDue `
                    -SourceCommit $noCandidateSource -Status no-candidates `
                    -ResolverReceiptId ('c' * 64) `
                    -RankedSetDigest $emptyRanked.RankedSetDigest
                $completedCandidateBodies = @(
                    (New-SurfaceCandidate -Rank 1 -Sentinel $sentinel),
                    (New-SurfaceCandidate -Rank 2 -Sentinel $sentinel),
                    (New-SurfaceCandidate -Rank 3 -Sentinel $sentinel)
                )
                $completedRanked = New-SiRankedCandidates -Candidate @(
                    $completedCandidateBodies | ForEach-Object { [pscustomobject]$_ }
                )
                $completedRun = New-SurfaceRun -RunId $completedRunId -DueId $completedDue `
                    -SourceCommit $completedSource -Status completed `
                    -Candidates @($completedRanked.Candidates) -Choices @(
                        [ordered]@{
                            candidateId = $completedRanked.CandidateIds[0]
                            disposition = 'accepted'
                            proposalPr = [ordered]@{
                                url = 'https://example.test/pull/1'
                                headOid = 'e' * 40
                            }
                        },
                        [ordered]@{
                            candidateId = $completedRanked.CandidateIds[1]
                            disposition = 'declined'
                            proposalPr = $null
                        },
                        [ordered]@{
                            candidateId = $completedRanked.CandidateIds[2]
                            disposition = 'deferred'
                            proposalPr = $null
                        }
                    ) -ResolverReceiptId ('c' * 64) `
                    -RankedSetDigest $completedRanked.RankedSetDigest
            $orphanRun = New-SurfaceRun -RunId $orphanRunId -DueId $pendingDue `
                    -SourceCommit $pendingSource -Status resumable

                $runRoot = Join-Path $consumer 'docs/self-improvement/runs/2026/08'
                Write-SiJson -Path (Join-Path $runRoot "$proposalRunId.json") -Value $proposalRun
                Write-SiJson -Path (Join-Path $runRoot "$declinedRunId.json") -Value $declinedRun
                Write-SiJson -Path (Join-Path $runRoot "$noCandidateRunId.json") -Value $noCandidateRun
                Write-SiJson -Path (Join-Path $runRoot "$completedRunId.json") -Value $completedRun
                Write-SiJson -Path (Join-Path $runRoot "$orphanRunId.json") -Value $orphanRun

                $manifest = [ordered]@{
                    schemaVersion = 2
                    generation = 7
                    pending = @(
                        [ordered]@{
                            dueId = $pendingDue
                            repoId = 'origin:example.test/owner/repo'
                            planId = '1936cb'
                            sourceCommit = $pendingSource
                            createdAtUtc = '2026-08-09T00:00:00Z'
                            status = 'pending'
                            runId = $null
                        },
                        [ordered]@{
                            dueId = $deferredDue
                            repoId = 'origin:example.test/owner/repo'
                            planId = '1936cb'
                            sourceCommit = $deferredSource
                            createdAtUtc = '2026-08-09T00:00:00Z'
                            deferUntilUtc = '2099-01-01T00:00:00Z'
                            status = 'pending'
                            runId = $null
                        }
                    )
                    inFlight = @([ordered]@{
                            dueId = $proposalDue
                            repoId = 'origin:example.test/owner/repo'
                            planId = '1936cb'
                            sourceCommit = $proposalSource
                            createdAtUtc = '2026-08-09T00:00:00Z'
                            deferUntilUtc = $null
                            status = 'in-flight'
                            runId = $proposalRunId
                        })
                    recentRuns = @(
                        [ordered]@{
                            runId = $declinedRunId
                            dueId = $declinedDue
                            status = 'declined-before-ranking'
                            path = "docs/self-improvement/runs/2026/08/$declinedRunId.json"
                            completedAtUtc = '2026-08-09T01:00:00Z'
                        },
                        [ordered]@{
                            runId = $noCandidateRunId
                            dueId = $noCandidateDue
                            status = 'no-candidates'
                            path = "docs/self-improvement/runs/2026/08/$noCandidateRunId.json"
                            completedAtUtc = '2026-08-09T01:00:00Z'
                        },
                        [ordered]@{
                            runId = $completedRunId
                            dueId = $completedDue
                            status = 'completed'
                            path = "docs/self-improvement/runs/2026/08/$completedRunId.json"
                            completedAtUtc = '2026-08-09T01:00:00Z'
                        }
                    )
                }
                Write-SiJson -Path (Join-Path $consumer 'docs/self-improvement/state.json') `
                    -Value $manifest

                [void](Invoke-FixtureGit -Root $consumer -Argument @('add', 'docs/self-improvement'))
                [void](Invoke-FixtureGit -Root $consumer -Argument @('commit', '--quiet', '-m', 'state fixture'))
                [void](Invoke-FixtureGit -Root $consumer -Argument @('push', '--quiet', '-u', 'origin', 'main'))
                foreach ($branch in @(
                        "si/$pendingDue",
                        "si/$proposalDue",
                        "si/$orphanDue",
                        "si-repair/$repairObservation"
                    )) {
                    [void](Invoke-FixtureGit -Root $consumer -Argument @(
                            'push', '--quiet', 'origin', "HEAD:refs/heads/$branch"
                        ))
                }

                $expectedMain = [string](
                    Invoke-FixtureGit -Root $consumer -Argument @('rev-parse', 'HEAD') |
                        Select-Object -First 1
                )
                $expectedMain = $expectedMain.Trim()
                $surface = & $lifecycle -RepoRoot $consumer -Operation Surface `
                    -AsOfUtc ([datetime]'2026-08-09T12:00:00Z')
                $surface.Status | Should -Be 'complete'
                $surface.PinnedBaseOid | Should -Be $expectedMain
                $surface.ManifestStatus | Should -Be 'valid'
                $surface.Generation | Should -Be 7

                $byDue = @{}
                foreach ($item in $surface.Items) { $byDue[$item.dueId] = $item }
                $byDue[$pendingDue].state | Should -Be 'pending'
                $byDue[$pendingDue].deferUntilUtc | Should -BeNullOrEmpty
                $byDue[$pendingDue].branchState | Should -Be 'present'
                $byDue[$deferredDue].state | Should -Be 'deferred-until'
                $byDue[$deferredDue].deferUntilUtc | Should -Match '^2099-01-01'
                $byDue[$proposalDue].state | Should -Be 'proposal-pending'
                $byDue[$proposalDue].candidateCount | Should -Be 1
                $byDue[$proposalDue].deferredCount | Should -Be 1
                $byDue[$declinedDue].state | Should -Be 'declined-before-ranking'
                $byDue[$noCandidateDue].state | Should -Be 'no-candidates'
                $byDue[$completedDue].state | Should -Be 'completed'
                $byDue[$completedDue].candidateCount | Should -Be 3
                $byDue[$completedDue].acceptedCount | Should -Be 1
                $byDue[$completedDue].declinedCount | Should -Be 1
                $byDue[$completedDue].deferredCount | Should -Be 1
                $byDue[$completedDue].proposalCount | Should -Be 1

                $surface.RepairBranches.Count | Should -Be 1
                $surface.RepairBranches[0].observationId | Should -Be $repairObservation
                $surface.OrphanDueBranches.Count | Should -Be 1
                $surface.OrphanDueBranches[0].dueId | Should -Be $orphanDue
                $surface.OrphanRuns.Count | Should -Be 1
                $surface.OrphanRuns[0].runId | Should -Be $orphanRunId
                $surface.OrphanRuns[0].state | Should -Be 'repairable-orphan'
                $serialized = $surface | ConvertTo-Json -Depth 20
                $serialized | Should -Not -Match $sentinel
                $serialized | Should -Not -Match '"(title|rationale|sources|targets|candidates|choices|candidateId)"'

                $ciGuide = [System.IO.File]::ReadAllText(
                    (Join-Path $script:repoRoot 'plugins/continue-implementation/skills/ci/assets/crosscheck-guide.md')
                )
                $ciGuide | Should -Match '\.github/skills/si/scripts/Invoke-SiLifecycle\.ps1'
                $ciGuide | Should -Match 'bound argument array'
                $ciGuide | Should -Match '\-Operation Surface'
                $ciGuide | Should -Match 'explicit non-blocking degradation'
                $lifecycleSource = [System.IO.File]::ReadAllText(
                    (Join-Path $script:repoRoot 'plugins/self-improvement/scripts/Invoke-SiLifecycle.ps1')
                )
                $lifecycleSource | Should -Match 'Invoke-SiGitBoundedLines'
                $lifecycleSource | Should -Match 'Assert-SiRunIntegrity'
                $lifecycleSource | Should -Match 'ActiveCompletedRuns'
                $lifecycleSource | Should -Match 'ActiveInFlightRuns'

                [void](Invoke-FixtureGit -Root $consumer -Argument @(
                        'push', '--quiet', 'origin', 'HEAD:refs/heads/si/not-a-fixed-id'
                    ))
                {
                    & $lifecycle -RepoRoot $consumer -Operation Surface `
                        -AsOfUtc ([datetime]'2026-08-09T12:00:00Z')
                } | Should -Throw '*fixed lifecycle identifier*'

                $manifest['untrustedProperty'] = $sentinel
                Write-SiJson -Path (Join-Path $consumer 'docs/self-improvement/state.json') `
                    -Value $manifest
                [void](Invoke-FixtureGit -Root $consumer -Argument @(
                        'add', 'docs/self-improvement/state.json'
                    ))
                [void](Invoke-FixtureGit -Root $consumer -Argument @(
                        'commit', '--quiet', '-m', 'malformed state fixture'
                    ))
                [void](Invoke-FixtureGit -Root $consumer -Argument @(
                        'push', '--quiet', 'origin', 'main'
                    ))
                $failure = try {
                    & $lifecycle -RepoRoot $consumer -Operation Surface `
                        -AsOfUtc ([datetime]'2026-08-09T12:00:00Z')
                    ''
                }
                catch {
                    $_.Exception.Message
                }
                $failure | Should -Be 'Pinned SI document failed schema validation.'
                $failure | Should -Not -Match $sentinel
            }
            finally {
                Remove-Item -LiteralPath $consumer -Recurse -Force
                Remove-Item -LiteralPath $remote -Recurse -Force
        }
    }

    It 'test:SiState.ResolverReceiptCandidateRefusalMatrix binds fresh receipts, exact candidates and complete choices with replay refusal' {
        $consumer = New-InstallRoot
        $remote = New-InstallRoot
        $emptyConsumer = New-InstallRoot
        $resumeConsumer = New-InstallRoot
        try {
        [void](Install-PluginClosure -RootPlugin self-improvement -TargetRoot $consumer)
        $lifecycle = Join-Path $consumer '.github/skills/si/scripts/Invoke-SiLifecycle.ps1'
        $enqueue = Join-Path $consumer '.github/skills/si/scripts/Enqueue-SiDue.ps1'

        [void](Invoke-FixtureGit -Root $remote -Argument @('init', '--bare', '--quiet'))
        [void](Invoke-FixtureGit -Root $consumer -Argument @(
                'init', '--initial-branch=main', '--quiet'
            ))
        [void](Invoke-FixtureGit -Root $consumer -Argument @(
                'config', 'user.name', 'SI Fixture'
            ))
        [void](Invoke-FixtureGit -Root $consumer -Argument @(
                'config', 'user.email', 'si@example.test'
            ))
        [void](Invoke-FixtureGit -Root $consumer -Argument @(
                'remote', 'add', 'origin', $remote
            ))

        $sourceCommit = 'a' * 40
        $enqueued = & $enqueue -RepoRoot $consumer -PlanId 1936cb `
            -SourceCommit $sourceCommit
        $dueId = $enqueued.DueId
        $runId = 'b' * 64
        [void](Invoke-FixtureGit -Root $consumer -Argument @('add', '.github', 'docs'))
        [void](Invoke-FixtureGit -Root $consumer -Argument @(
                'commit', '--quiet', '-m', 'authoritative SI due'
            ))
        [void](Invoke-FixtureGit -Root $consumer -Argument @(
                'push', '--quiet', '--set-upstream', 'origin', 'main'
            ))
        $pinnedOid = [string](
            Invoke-FixtureGit -Root $consumer -Argument @('rev-parse', 'HEAD') |
                Select-Object -First 1
        )
        $pinnedOid = $pinnedOid.Trim()

        $candidateBodies = @(
            [pscustomobject][ordered]@{
                title = 'First candidate'; rationale = 'First rationale'
                sources = @('docs/review-ledger/testing.md')
                targets = @('plugins/self-improvement/skills/si/SKILL.md')
            },
            [pscustomobject][ordered]@{
                title = 'Second candidate'; rationale = 'Second rationale'
                sources = @('docs/review-ledger/security.md')
                targets = @('plugins/self-improvement/scripts/Invoke-SiLifecycle.ps1')
            }
        )
        $ranked = New-SiRankedCandidates -Candidate $candidateBodies
        $snapshotDigest = 'c' * 64
        $selectedDigest = 'd' * 64
        $payload = [pscustomobject][ordered]@{
            protocol = 'si-resolver-receipt-v1'
            dueId = $dueId
            runId = $runId
            pinnedBaseOid = $pinnedOid
            snapshotDigest = $snapshotDigest
            selectedDigest = $selectedDigest
            rankedSetDigest = $ranked.RankedSetDigest
            candidates = $ranked.CandidateIds
        }
        $receiptId = Get-SiResolverReceiptId -Payload $payload
        $receiptPath = Join-Path $consumer (
            "docs/self-improvement/resolver-receipts/$receiptId.json"
        )
        Write-SiJson -Path $receiptPath -Value ([ordered]@{
                receiptId = $receiptId
                payload = $payload
            })
        $beginInput = Join-Path $consumer 'begin.json'
        Write-SiJson -Path $beginInput -Value ([ordered]@{
                candidates = $candidateBodies
            })

        $begun = & $lifecycle -RepoRoot $consumer -Operation Begin `
            -DueId $dueId -RunId $runId -Receipt $receiptId -InputPath $beginInput
        $begun.Status | Should -Be 'complete'
        $begun.Mutated | Should -BeTrue
        $begun.BranchName | Should -Be "si/$dueId"
        $begun.RunStatus | Should -Be 'ranked'
        $begun.CandidateCount | Should -Be 2
        [string](
            Invoke-FixtureGit -Root $consumer -Argument @(
                'branch', '--show-current'
            ) | Select-Object -First 1
        ) | Should -Be "si/$dueId"

        $runPath = @(Get-ChildItem -LiteralPath (
                Join-Path $consumer 'docs/self-improvement/runs'
            ) -Filter "$runId.json" -Recurse -File)[0].FullName
        $run = Get-Content -LiteralPath $runPath -Raw | ConvertFrom-Json -Depth 100
        $run.provenance.resolverReceiptId | Should -Be $receiptId
        @($run.rankedSet.candidates).Count | Should -Be 2
        @($run.choices).Count | Should -Be 0

        $manifestPath = Join-Path $consumer 'docs/self-improvement/state.json'
        $beforeReplay = [System.IO.File]::ReadAllText($manifestPath)
        $replayed = & $lifecycle -RepoRoot $consumer -Operation Begin `
            -DueId $dueId -RunId $runId -Receipt $receiptId -InputPath $beginInput
        $replayed.Mutated | Should -BeFalse
        [System.IO.File]::ReadAllText($manifestPath) | Should -Be $beforeReplay

        {
            & $lifecycle -RepoRoot $consumer -Operation Begin `
                -DueId $dueId -RunId $runId -Receipt ('e' * 64) `
                -InputPath $beginInput
        } | Should -Throw '*not found*'
        {
            & $lifecycle -RepoRoot $consumer -Operation Begin `
                -DueId $dueId -RunId ('f' * 64) -Receipt $receiptId `
                -InputPath $beginInput
        } | Should -Throw '*different due or run*'

        $stalePayload = [pscustomobject][ordered]@{
            protocol = 'si-resolver-receipt-v1'
            dueId = $dueId; runId = $runId; pinnedBaseOid = ('1' * 40)
            snapshotDigest = $snapshotDigest; selectedDigest = $selectedDigest
            rankedSetDigest = $ranked.RankedSetDigest
            candidates = $ranked.CandidateIds
        }
        $staleReceipt = Get-SiResolverReceiptId -Payload $stalePayload
        Write-SiJson -Path (Join-Path $consumer (
                "docs/self-improvement/resolver-receipts/$staleReceipt.json"
            )) -Value ([ordered]@{
                receiptId = $staleReceipt; payload = $stalePayload
            })
        {
            & $lifecycle -RepoRoot $consumer -Operation Begin `
                -DueId $dueId -RunId $runId -Receipt $staleReceipt `
                -InputPath $beginInput
        } | Should -Throw '*stale for the current pinned origin/main*'

        $candidateCases = @(
            [ordered]@{ candidates = @($candidateBodies[0]) },
            [ordered]@{
                candidates = @(
                    $candidateBodies[0], $candidateBodies[1],
                    [pscustomobject][ordered]@{
                        title = 'Extra'; rationale = 'Extra rationale'
                        sources = @('extra-source'); targets = @('extra-target')
                    }
                )
            },
            [ordered]@{
                candidates = @($candidateBodies[0], $candidateBodies[0])
            },
            [ordered]@{
                candidates = @(
                    [pscustomobject][ordered]@{
                        title = 'Rewritten candidate'; rationale = 'First rationale'
                        sources = @('docs/review-ledger/testing.md')
                        targets = @('plugins/self-improvement/skills/si/SKILL.md')
                    },
                    $candidateBodies[1]
                )
            }
        )
        foreach ($case in $candidateCases) {
            $casePath = Join-Path $consumer (
                'candidate-case-' + [Guid]::NewGuid().ToString('N') + '.json'
            )
            Write-SiJson -Path $casePath -Value $case
            {
                & $lifecycle -RepoRoot $consumer -Operation Begin `
                    -DueId $dueId -RunId $runId -Receipt $receiptId `
                    -InputPath $casePath
            } | Should -Throw
        }

        $choices = @(
            [pscustomobject][ordered]@{
                candidateId = $ranked.CandidateIds[0]
                disposition = 'accepted'
                proposalPr = $null
            },
            [pscustomobject][ordered]@{
                candidateId = $ranked.CandidateIds[1]
                disposition = 'declined'
                proposalPr = $null
            }
        )
        $choiceInput = Join-Path $consumer 'choices.json'
        Write-SiJson -Path $choiceInput -Value ([ordered]@{ choices = $choices })
        $recorded = & $lifecycle -RepoRoot $consumer -Operation RecordChoices `
            -DueId $dueId -RunId $runId -Receipt $receiptId -InputPath $choiceInput
        $recorded.Mutated | Should -BeTrue
        $recorded.RunStatus | Should -Be 'proposal-pending'
        $choiceReplay = & $lifecycle -RepoRoot $consumer -Operation RecordChoices `
            -DueId $dueId -RunId $runId -Receipt $receiptId -InputPath $choiceInput
        $choiceReplay.Mutated | Should -BeFalse

        [void](Invoke-FixtureGit -Root $consumer -Argument @('add', 'docs'))
        [void](Invoke-FixtureGit -Root $consumer -Argument @(
                'commit', '--quiet', '-m', 'persist fixed SI branch state'
            ))
        [void](Invoke-FixtureGit -Root $consumer -Argument @(
                'push', '--quiet', '--set-upstream', 'origin', "si/$dueId"
            ))
        $fixedHead = [string](
            Invoke-FixtureGit -Root $consumer -Argument @('rev-parse', 'HEAD') |
                Select-Object -First 1
        )
        $fixedHead = $fixedHead.Trim()
        Remove-Item -LiteralPath $resumeConsumer -Recurse -Force
        [void](Invoke-FixtureGit -Root (Split-Path -Parent $resumeConsumer) -Argument @(
                'clone', '--quiet', '--branch', 'main', $remote, $resumeConsumer
            ))
        [void](Invoke-FixtureGit -Root $resumeConsumer -Argument @(
                'checkout', '--quiet', '--detach', $fixedHead
            ))
        $resumeChoiceInput = Join-Path $resumeConsumer 'choices.json'
        Write-SiJson -Path $resumeChoiceInput -Value ([ordered]@{ choices = $choices })
        $resumeLifecycle = Join-Path $resumeConsumer (
            '.github/skills/si/scripts/Invoke-SiLifecycle.ps1'
        )
        $remoteReplay = & $resumeLifecycle -RepoRoot $resumeConsumer `
            -Operation RecordChoices -DueId $dueId -RunId $runId `
            -Receipt $receiptId -InputPath $resumeChoiceInput
        $remoteReplay.Mutated | Should -BeFalse
        [string](
            Invoke-FixtureGit -Root $resumeConsumer -Argument @(
                'branch', '--show-current'
            ) | Select-Object -First 1
        ) | Should -Be "si/$dueId"

        $resumeRunPath = @(Get-ChildItem -LiteralPath (
                Join-Path $resumeConsumer 'docs/self-improvement/runs'
            ) -Filter "$runId.json" -Recurse -File)[0].FullName
        $malformedRun = Get-Content -LiteralPath $resumeRunPath -Raw |
            ConvertFrom-Json -Depth 100
        $malformedRun | Add-Member -NotePropertyName unexpected -NotePropertyValue true
        Write-SiJson -Path $resumeRunPath -Value $malformedRun
        {
            & $resumeLifecycle -RepoRoot $resumeConsumer `
                -Operation RecordChoices -DueId $dueId -RunId $runId `
                -Receipt $receiptId -InputPath $resumeChoiceInput
        } | Should -Throw '*closed-schema validation*'

        $choiceCases = @(
            [ordered]@{ choices = @($choices[0]) },
            [ordered]@{
                choices = @(
                    $choices[0], $choices[1],
                    [pscustomobject][ordered]@{
                        candidateId = ('3' * 64)
                        disposition = 'declined'; proposalPr = $null
                    }
                )
            },
            [ordered]@{ choices = @($choices[0], $choices[0]) },
            [ordered]@{
                choices = @(
                    [pscustomobject][ordered]@{
                        candidateId = ('4' * 64)
                        disposition = 'accepted'; proposalPr = $null
                    },
                    $choices[1]
                )
            },
            [ordered]@{
                choices = @(
                    [pscustomobject][ordered]@{
                        candidateId = $ranked.CandidateIds[0]
                        disposition = 'deferred'; proposalPr = $null
                    },
                    $choices[1]
                )
            }
        )
        foreach ($case in $choiceCases) {
            $casePath = Join-Path $consumer (
                'choice-case-' + [Guid]::NewGuid().ToString('N') + '.json'
            )
            Write-SiJson -Path $casePath -Value $case
            {
                & $lifecycle -RepoRoot $consumer -Operation RecordChoices `
                    -DueId $dueId -RunId $runId -Receipt $receiptId `
                    -InputPath $casePath
            } | Should -Throw
        }

        Remove-Item -LiteralPath $emptyConsumer -Recurse -Force
        [void](Invoke-FixtureGit -Root (Split-Path -Parent $emptyConsumer) -Argument @(
                'clone', '--quiet', '--branch', 'main', $remote, $emptyConsumer
            ))
        [void](Invoke-FixtureGit -Root $emptyConsumer -Argument @(
                'config', 'user.name', 'SI Fixture'
            ))
        [void](Invoke-FixtureGit -Root $emptyConsumer -Argument @(
                'config', 'user.email', 'si@example.test'
            ))
        $emptyEnqueue = Join-Path $emptyConsumer (
            '.github/skills/si/scripts/Enqueue-SiDue.ps1'
        )
        $emptyDue = & $emptyEnqueue -RepoRoot $emptyConsumer -PlanId 1936cb `
            -SourceCommit ('5' * 40)
        [void](Invoke-FixtureGit -Root $emptyConsumer -Argument @(
                'add', 'docs/self-improvement/state.json'
            ))
        [void](Invoke-FixtureGit -Root $emptyConsumer -Argument @(
                'commit', '--quiet', '-m', 'second authoritative SI due'
            ))
        [void](Invoke-FixtureGit -Root $emptyConsumer -Argument @(
                'push', '--quiet', 'origin', 'main'
            ))
        $emptyPinned = [string](
            Invoke-FixtureGit -Root $emptyConsumer -Argument @('rev-parse', 'HEAD') |
                Select-Object -First 1
        )
        $emptyPinned = $emptyPinned.Trim()
        $emptyRun = '6' * 64
        $emptyRanked = New-SiRankedCandidates -Candidate @()
        $emptyPayload = [pscustomobject][ordered]@{
            protocol = 'si-resolver-receipt-v1'
            dueId = $emptyDue.DueId; runId = $emptyRun
            pinnedBaseOid = $emptyPinned; snapshotDigest = ('7' * 64)
            selectedDigest = ('8' * 64)
            rankedSetDigest = $emptyRanked.RankedSetDigest
            candidates = @()
        }
        $emptyReceipt = Get-SiResolverReceiptId -Payload $emptyPayload
        Write-SiJson -Path (Join-Path $emptyConsumer (
                "docs/self-improvement/resolver-receipts/$emptyReceipt.json"
            )) -Value ([ordered]@{
                receiptId = $emptyReceipt; payload = $emptyPayload
            })
        $emptyInput = Join-Path $emptyConsumer 'empty-candidates.json'
        Write-SiJson -Path $emptyInput -Value ([ordered]@{ candidates = @() })
        $emptyLifecycle = Join-Path $emptyConsumer (
            '.github/skills/si/scripts/Invoke-SiLifecycle.ps1'
        )
        $emptyBegin = & $emptyLifecycle -RepoRoot $emptyConsumer -Operation Begin `
            -DueId $emptyDue.DueId -RunId $emptyRun -Receipt $emptyReceipt `
            -InputPath $emptyInput
        $emptyBegin.CandidateCount | Should -Be 0
        $emptyBegin.RunStatus | Should -Be 'no-candidates'
        $emptyChoices = Join-Path $emptyConsumer 'empty-choices.json'
        Write-SiJson -Path $emptyChoices -Value ([ordered]@{ choices = @() })
        $emptyChoiceResult = & $emptyLifecycle -RepoRoot $emptyConsumer `
            -Operation RecordChoices -DueId $emptyDue.DueId -RunId $emptyRun `
            -Receipt $emptyReceipt -InputPath $emptyChoices
        $emptyChoiceResult.Mutated | Should -BeFalse
        $emptyChoiceResult.RunStatus | Should -Be 'no-candidates'
        }
        finally {
        Remove-Item -LiteralPath $consumer -Recurse -Force
        Remove-Item -LiteralPath $remote -Recurse -Force
        if (Test-Path -LiteralPath $emptyConsumer) {
            Remove-Item -LiteralPath $emptyConsumer -Recurse -Force
        }
        if (Test-Path -LiteralPath $resumeConsumer) {
            Remove-Item -LiteralPath $resumeConsumer -Recurse -Force
        }
        }
    }
}
