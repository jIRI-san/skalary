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
        $installedPath = '.github/skills/si/scripts/Enqueue-SiDue.ps1'
        $agent | Should -Match ([regex]::Escape($installedPath))
        $agent | Should -Match 'bound argument array'
        $agent | Should -Match 'sha256\(repo-id\|plan-id\|source-commit\|si-due-v1\)'
        $agent | Should -Match 'degraded: SI due enqueue failed'
        $agent | Should -Match 'Headless completion does not run `/si`'
        $agent | Should -Match 'Workflow carve-out:.+Enqueue-SiDue\.ps1'
        $sourcePush = $agent.IndexOf('required post-archive `git push origin <current-branch>`')
        $enqueue = $agent.IndexOf('capture complete-source OID -> enqueue')
        $sourcePush | Should -BeGreaterThan -1
        $enqueue | Should -BeGreaterThan $sourcePush

        $autopilotRoot = New-InstallRoot
        $standaloneRoot = New-InstallRoot
        $outside = $null
        $caseVariantOutside = $null
        try {
            $versions = Install-PluginClosure -RootPlugin autopilot -TargetRoot $autopilotRoot
            $versions.Keys | Should -Contain 'self-improvement'
            $versions['autopilot'] | Should -Not -Be $versions['self-improvement']
            Test-Path -LiteralPath (Join-Path $autopilotRoot $installedPath) -PathType Leaf |
                Should -BeTrue

            $standaloneVersions = Install-PluginClosure -RootPlugin self-improvement `
                -TargetRoot $standaloneRoot
            $standaloneVersions.Keys | Should -Contain 'self-improvement'
            $writer = Join-Path $standaloneRoot $installedPath
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
            $first.Status | Should -Be 'complete'
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
}
