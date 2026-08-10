#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Authoritative SI proposal completion' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:pluginRoot = Join-Path $script:repoRoot 'plugins/self-improvement'
        Import-Module (Join-Path $script:pluginRoot 'scripts/SiResolverReceipt.psm1') -Force

        function Script:New-CompletionRoot {
            $root = Join-Path ([System.IO.Path]::GetTempPath()) (
                'si-completion-test-' + [Guid]::NewGuid().ToString('N')
            )
            [void](New-Item -ItemType Directory -Path $root -Force)
            return $root
        }

        function Script:Invoke-CompletionGit {
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

        function Script:Write-CompletionJson {
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

        function Script:Install-CompletionPlugin {
            param([Parameter(Mandatory)][string]$Root)
            $manifest = Get-Content -LiteralPath (
                Join-Path $script:pluginRoot 'plugin.json'
            ) -Raw | ConvertFrom-Json -Depth 100
            foreach ($file in @($manifest.files)) {
                $target = Join-Path $Root ('.github/' + [string]$file.dest)
                [void](New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force)
                Copy-Item -LiteralPath (
                    Join-Path $script:pluginRoot ([string]$file.src)
                ) -Destination $target -Force
            }
        }

        function Script:New-CompletionFixture {
            param(
                [switch]$AllDeclined,
                [switch]$NoCandidates
            )

            Import-Module (Join-Path $script:pluginRoot (
                    'scripts/SiResolverReceipt.psm1'
                )) -Force
            $root = New-CompletionRoot
            $remote = New-CompletionRoot
            $trusted = New-CompletionRoot
            [void](Invoke-CompletionGit -Root $remote -Argument @('init', '--bare', '--quiet'))
            [void](Invoke-CompletionGit -Root $root -Argument @(
                    'init', '--initial-branch=main', '--quiet'
                ))
            [void](Invoke-CompletionGit -Root $root -Argument @(
                    'config', 'user.name', 'SI Fixture'
                ))
            [void](Invoke-CompletionGit -Root $root -Argument @(
                    'config', 'user.email', 'si@example.test'
                ))
            [void](Invoke-CompletionGit -Root $root -Argument @(
                    'remote', 'add', 'origin', $remote
                ))
            Install-CompletionPlugin -Root $root
            $enqueue = Join-Path $root '.github/skills/si/scripts/Enqueue-SiDue.ps1'
            $enqueued = & $enqueue -RepoRoot $root -PlanId 1936cb `
                -SourceCommit ('a' * 40)
            [void](Invoke-CompletionGit -Root $root -Argument @('add', '.github', 'docs'))
            [void](Invoke-CompletionGit -Root $root -Argument @(
                    'commit', '--quiet', '-m', 'authoritative main'
                ))
            [void](Invoke-CompletionGit -Root $root -Argument @(
                    'push', '--quiet', '--set-upstream', 'origin', 'main'
                ))
            $mainOid = ([string](Invoke-CompletionGit -Root $root -Argument @(
                        'rev-parse', 'HEAD'
                    ) | Select-Object -First 1)).Trim()
            $dueId = $enqueued.DueId
            $runId = 'b' * 64
            $branch = "si/$dueId"
            [void](Invoke-CompletionGit -Root $root -Argument @(
                    'switch', '--quiet', '--create', $branch
                ))
            [object[]]$candidateBodies = @()
            if (-not $NoCandidates) {
                $candidateBodies = @(
                [pscustomobject][ordered]@{
                    title = 'Complete proposal'
                    rationale = 'Prove expected-head completion'
                    sources = @('docs/review-ledger/testing.md')
                    targets = @('docs/design-notes/project/completed.design.md')
                },
                [pscustomobject][ordered]@{
                    title = 'Record declined outcome'
                    rationale = 'Keep the full ranked set'
                    sources = @('docs/review-ledger/reliability.md')
                    targets = @('docs/design-notes/project/declined.design.md')
                }
                )
            }
            $ranked = New-SiRankedCandidates -Candidate $candidateBodies
            $payload = [pscustomobject][ordered]@{
                protocol = 'si-resolver-receipt-v1'
                dueId = $dueId
                runId = $runId
                pinnedBaseOid = $mainOid
                snapshotDigest = 'c' * 64
                selectedDigest = 'd' * 64
                rankedSetDigest = $ranked.RankedSetDigest
                candidates = $ranked.CandidateIds
            }
            $receipt = Get-SiResolverReceiptId -Payload $payload
            Write-CompletionJson -Path (Join-Path $root (
                    "docs/self-improvement/resolver-receipts/$receipt.json"
                )) -Value ([ordered]@{ receiptId = $receipt; payload = $payload })
            Write-CompletionJson -Path (
                Join-Path $root 'docs/self-improvement/harvest-index.json'
            ) -Value ([ordered]@{
                    schemaVersion = 1
                    protocol = 'si-harvest-index-v1'
                    planId = '1936cb'
                    planPath = 'docs/implementation-plans/example'
                    pinnedBaseOid = $mainOid
                    snapshotDigest = 'c' * 64
                    selectedDigest = 'd' * 64
                    fileCount = 1
                    scannedByteCount = 1
                    sourceCount = 1
                    recordCount = 1
                    selectedByteCount = 1
                    sources = @()
                    selectedRecords = @()
                })
            $begin = Join-Path $root 'begin.json'
            $choices = Join-Path $root 'choices.json'
            Write-CompletionJson -Path $begin -Value ([ordered]@{
                    candidates = $candidateBodies
                })
            $lifecycle = Join-Path $root (
                '.github/skills/si/scripts/Invoke-SiLifecycle.ps1'
            )
            [void](& $lifecycle -RepoRoot $root -Operation Begin -DueId $dueId `
                    -RunId $runId -Receipt $receipt -InputPath $begin)
            if (-not $NoCandidates) {
                Write-CompletionJson -Path $choices -Value ([ordered]@{
                        choices = @(
                            [pscustomobject][ordered]@{
                                candidateId = $ranked.CandidateIds[0]
                                disposition = if ($AllDeclined) { 'declined' } else { 'accepted' }
                                proposalPr = $null
                            },
                            [pscustomobject][ordered]@{
                                candidateId = $ranked.CandidateIds[1]
                                disposition = 'declined'
                                proposalPr = $null
                            }
                        )
                    })
                [void](& $lifecycle -RepoRoot $root -Operation RecordChoices `
                        -DueId $dueId -RunId $runId -Receipt $receipt `
                        -InputPath $choices)
                Remove-Item -LiteralPath $choices -Force
            }
            Remove-Item -LiteralPath $begin -Force
            Remove-Item -LiteralPath (
                Join-Path $root 'docs/self-improvement/harvest-index.json'
            ) -Force
            $manifestPath = Join-Path $root 'docs/self-improvement/state.json'
            $manifest = Get-Content -LiteralPath $manifestPath -Raw |
                ConvertFrom-Json -Depth 100
            $manifest.generation = 2
            Write-CompletionJson -Path $manifestPath -Value $manifest
            [void](Invoke-CompletionGit -Root $root -Argument @(
                    'add', 'docs/self-improvement'
                ))
            [void](Invoke-CompletionGit -Root $root -Argument @(
                    'commit', '--quiet', '-m', 'record lifecycle choices'
                ))
            $lifecycleHead = ([string](
                    Invoke-CompletionGit -Root $root -Argument @(
                        'rev-parse', 'HEAD'
                    ) | Select-Object -First 1
                )).Trim()
            if (-not $AllDeclined -and -not $NoCandidates) {
                $proposalPath = Join-Path $root (
                    'docs/design-notes/project/completed.design.md'
                )
                [void](New-Item -ItemType Directory -Path (
                        Split-Path -Parent $proposalPath
                    ) -Force)
                [System.IO.File]::WriteAllText($proposalPath, "completed`n")
            }
            [void](Invoke-CompletionGit -Root $root -Argument @('add', 'docs'))
            if (@(Invoke-CompletionGit -Root $root -Argument @(
                        'status', '--porcelain=v1'
                    )).Count -gt 0) {
                [void](Invoke-CompletionGit -Root $root -Argument @(
                        'commit', '--quiet', '-m', 'SI proposal'
                    ))
            }
            [void](Invoke-CompletionGit -Root $root -Argument @(
                    'push', '--quiet', '--set-upstream', 'origin', $branch
                ))
            Remove-Item -LiteralPath $trusted -Recurse -Force
            [void](Invoke-CompletionGit -Root (Split-Path -Parent $trusted) -Argument @(
                    'clone', '--quiet', '--branch', 'main', $remote, $trusted
                ))
            [void](Invoke-CompletionGit -Root $trusted -Argument @(
                    'config', 'user.name', 'SI Trusted'
                ))
            [void](Invoke-CompletionGit -Root $trusted -Argument @(
                    'config', 'user.email', 'trusted@example.test'
                ))
            [void](Invoke-CompletionGit -Root $trusted -Argument @(
                    'checkout', '--quiet', '--detach'
                ))
            return [pscustomobject]@{
                Root = $root
                Remote = $remote
                Trusted = $trusted
                Complete = Join-Path $trusted (
                    '.github/skills/si/scripts/Complete-SiProposal.ps1'
                )
                DueId = $dueId
                RunId = $runId
                Receipt = $receipt
                LifecycleHead = $lifecycleHead
                Branch = $branch
                MainOid = $mainOid
            }
        }

        function Script:New-RepairCompletionFixture {
            $root = New-CompletionRoot
            $remote = New-CompletionRoot
            $trusted = New-CompletionRoot
            [void](Invoke-CompletionGit -Root $remote -Argument @('init', '--bare', '--quiet'))
            [void](Invoke-CompletionGit -Root $root -Argument @(
                    'init', '--initial-branch=main', '--quiet'
                ))
            [void](Invoke-CompletionGit -Root $root -Argument @(
                    'config', 'user.name', 'SI Repair'
                ))
            [void](Invoke-CompletionGit -Root $root -Argument @(
                    'config', 'user.email', 'repair@example.test'
                ))
            [void](Invoke-CompletionGit -Root $root -Argument @(
                    'remote', 'add', 'origin', $remote
                ))
            Install-CompletionPlugin -Root $root
            $state = Join-Path $root 'docs/self-improvement/state.json'
            [void](New-Item -ItemType Directory -Path (Split-Path -Parent $state) -Force)
            [System.IO.File]::WriteAllText(
                $state,
                '{"schemaVersion":1,"generation":0,"pending":[],"inFlight":[],"recentRuns":[]}' + "`n"
            )
            [void](Invoke-CompletionGit -Root $root -Argument @('add', '.github', 'docs'))
            [void](Invoke-CompletionGit -Root $root -Argument @(
                    'commit', '--quiet', '-m', 'corrupt authoritative state'
                ))
            [void](Invoke-CompletionGit -Root $root -Argument @(
                    'push', '--quiet', '--set-upstream', 'origin', 'main'
                ))
            $mainOid = ([string](Invoke-CompletionGit -Root $root -Argument @(
                        'rev-parse', 'HEAD'
                    ) | Select-Object -First 1)).Trim()
            $repair = Join-Path $root '.github/skills/si/scripts/Repair-SiState.ps1'
            $snapshot = & $repair -RepoRoot $root -Mode Snapshot -PinnedBaseOid $mainOid
            $branch = "si-repair/$($snapshot.ObservationId)"
            [void](Invoke-CompletionGit -Root $root -Argument @(
                    'switch', '--quiet', '--create', $branch
                ))
            $applied = & $repair -RepoRoot $root -Mode Apply `
                -Observation $snapshot.ObservationId
            [void](Invoke-CompletionGit -Root $root -Argument @('add', 'docs'))
            [void](Invoke-CompletionGit -Root $root -Argument @(
                    'commit', '--quiet', '-m', 'repair SI state'
                ))
            [void](Invoke-CompletionGit -Root $root -Argument @(
                    'push', '--quiet', '--set-upstream', 'origin', $branch
                ))
            Remove-Item -LiteralPath $trusted -Recurse -Force
            [void](Invoke-CompletionGit -Root (Split-Path -Parent $trusted) -Argument @(
                    'clone', '--quiet', '--branch', 'main', $remote, $trusted
                ))
            [void](Invoke-CompletionGit -Root $trusted -Argument @(
                    'checkout', '--quiet', '--detach'
                ))
            return [pscustomobject]@{
                Root = $root
                Remote = $remote
                Trusted = $trusted
                Complete = Join-Path $trusted (
                    '.github/skills/si/scripts/Complete-SiProposal.ps1'
                )
                Observation = $snapshot.ObservationId
                Receipt = $applied.ReceiptId
                Branch = $branch
                MainOid = $mainOid
            }
        }

        function Script:Remove-CompletionFixture {
            param($Fixture)
            foreach ($path in @($Fixture.Root, $Fixture.Trusted, $Fixture.Remote)) {
                if ($path -and (Test-Path -LiteralPath $path)) {
                    Remove-Item -LiteralPath $path -Recurse -Force
                }
            }
        }

        function Script:Set-ProviderFixture {
            param(
                [Parameter(Mandatory)]$Fixture,
                [switch]$FailMerge,
                [switch]$AmbiguousMerge
            )
            $global:SiCompletionRemote = [string]$Fixture.Remote
            $global:SiCompletionBranch = [string]$Fixture.Branch
            $global:SiCompletionBaseOid = [string]$Fixture.MainOid
            $global:SiCompletionIsDraft = $true
            $global:SiCompletionFailMerge = [bool]$FailMerge
            $global:SiCompletionAmbiguousMerge = [bool]$AmbiguousMerge
            $global:SiCompletionMerged = $false
            $global:SiCompletionCalls = [System.Collections.Generic.List[object]]::new()
            function global:gh {
                $arguments = @($args)
                $global:LASTEXITCODE = 0
                if ($arguments.Count -gt 1 -and
                    [string]$arguments[0] -eq 'repo' -and
                    [string]$arguments[1] -eq 'view') {
                    return 'owner/repo'
                }
                $queryArgument = [string](
                    $arguments | Where-Object { [string]$_ -like 'query=*' } |
                        Select-Object -First 1
                )
                if ($queryArgument -match '^query=mutation') {
                    $global:SiCompletionCalls.Add(@($arguments))
                    if ($global:SiCompletionFailMerge) {
                        $global:SiCompletionFailMerge = $false
                        $global:LASTEXITCODE = 1
                        return '{"errors":[{"message":"seeded failure"}]}'
                    }
                    if ($global:SiCompletionAmbiguousMerge) {
                        $global:SiCompletionAmbiguousMerge = $false
                        $head = ([string](
                                & git --git-dir=$global:SiCompletionRemote rev-parse (
                                    "refs/heads/$global:SiCompletionBranch"
                                )
                            )).Trim()
                        & git --git-dir=$global:SiCompletionRemote update-ref `
                            refs/heads/main $head
                        & git --git-dir=$global:SiCompletionRemote update-ref `
                            refs/pull/17/head $head
                        $global:SiCompletionMerged = $true
                        $global:SiCompletionIsDraft = $false
                        $global:LASTEXITCODE = 1
                        return '{"errors":[{"message":"response lost"}]}'
                    }
                    $global:SiCompletionIsDraft = $false
                    return '{"data":{"merge":{"pullRequest":{"merged":true,"mergedAt":"2026-08-10T00:00:00Z"}}}}'
                }
                $head = ([string](
                        & git --git-dir=$global:SiCompletionRemote rev-parse (
                            "refs/heads/$global:SiCompletionBranch"
                        )
                    )).Trim()
                $base = ([string](
                        & git --git-dir=$global:SiCompletionRemote rev-parse (
                            'refs/heads/main'
                        )
                    )).Trim()
                $pull = [ordered]@{
                    id = 'PR_test'
                    number = 17
                    url = 'https://github.com/owner/repo/pull/17'
                    state = if ($global:SiCompletionMerged) { 'MERGED' } else { 'OPEN' }
                    merged = $global:SiCompletionMerged
                    isDraft = $global:SiCompletionIsDraft
                    baseRefName = 'main'
                    baseRefOid = $global:SiCompletionBaseOid
                    headRefName = $global:SiCompletionBranch
                    headRefOid = $head
                    mergeCommit = if ($global:SiCompletionMerged) {
                        [ordered]@{ oid = $base }
                    }
                    else {
                        $null
                    }
                    mergedAt = if ($global:SiCompletionMerged) {
                        '2026-08-10T00:00:00Z'
                    }
                    else {
                        $null
                    }
                    headRepository = [ordered]@{ nameWithOwner = 'owner/repo' }
                }
                return ([ordered]@{
                        data = [ordered]@{
                            repository = [ordered]@{ pullRequest = $pull }
                        }
                    } | ConvertTo-Json -Depth 20 -Compress)
            }
        }
    }

    AfterEach {
        Remove-Item Function:\global:gh -ErrorAction SilentlyContinue
        foreach ($name in @(
                'SiCompletionRemote', 'SiCompletionBranch', 'SiCompletionIsDraft',
                'SiCompletionFailMerge', 'SiCompletionAmbiguousMerge',
                'SiCompletionMerged', 'SiCompletionCalls', 'SiCompletionBaseOid'
            )) {
            Remove-Variable $name -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It 'test:SiState.AuthoritativeFixedBranchLifecycleMatrix keeps main pending until merge and completes after authoritative integration' {
        $fixture = New-CompletionFixture
        try {
            Set-ProviderFixture -Fixture $fixture
            $result = & $fixture.Complete -RepoRoot $fixture.Trusted `
                -PullRequestNumber 17 -DueId $fixture.DueId `
                -RunId $fixture.RunId -Receipt $fixture.Receipt `
                -LifecycleHeadOid $fixture.LifecycleHead
            $result.Status | Should -Be 'complete'
            $mainState = & (Join-Path $fixture.Trusted (
                    '.github/skills/si/scripts/Invoke-SiLifecycle.ps1'
                )) -RepoRoot $fixture.Trusted -Operation Surface
            ($mainState.Items | Where-Object dueId -EQ $fixture.DueId).state |
                Should -Be 'pending'

            $integrator = New-CompletionRoot
            try {
                Remove-Item -LiteralPath $integrator -Recurse -Force
                [void](Invoke-CompletionGit -Root (
                        Split-Path -Parent $integrator
                    ) -Argument @(
                        'clone', '--quiet', '--branch', 'main',
                        $fixture.Remote, $integrator
                    ))
                [void](Invoke-CompletionGit -Root $integrator -Argument @(
                        'fetch', '--quiet', 'origin',
                        "$($fixture.Branch):refs/remotes/origin/$($fixture.Branch)"
                    ))
                [void](Invoke-CompletionGit -Root $integrator -Argument @(
                        'merge', '--quiet', '--ff-only',
                        "refs/remotes/origin/$($fixture.Branch)"
                    ))
                [void](Invoke-CompletionGit -Root $integrator -Argument @(
                        'push', '--quiet', 'origin', 'main'
                    ))
                $surface = & (Join-Path $integrator (
                        '.github/skills/si/scripts/Invoke-SiLifecycle.ps1'
                    )) -RepoRoot $integrator -Operation Surface
                ($surface.Items | Where-Object dueId -EQ $fixture.DueId).state |
                    Should -Be 'completed'
            }
            finally {
                if (Test-Path -LiteralPath $integrator) {
                    Remove-Item -LiteralPath $integrator -Recurse -Force
                }
            }
        }
        finally {
            Remove-CompletionFixture -Fixture $fixture
        }

        $noCandidate = New-CompletionFixture -NoCandidates
        try {
            Set-ProviderFixture -Fixture $noCandidate
            $headBefore = ([string](
                    & git --git-dir=$($noCandidate.Remote) rev-parse (
                        "refs/heads/$($noCandidate.Branch)"
                    )
                )).Trim()
            $result = & $noCandidate.Complete -RepoRoot $noCandidate.Trusted `
                -PullRequestNumber 17 -DueId $noCandidate.DueId `
                -RunId $noCandidate.RunId -Receipt $noCandidate.Receipt `
                -LifecycleHeadOid $noCandidate.LifecycleHead
            $result.StateCommitted | Should -BeFalse
            $result.ExpectedHeadOid | Should -Be $headBefore
        }
        finally {
            Remove-CompletionFixture -Fixture $noCandidate
        }
    }

    It 'test:SiState.PrFailureReconciliation resumes completed branch state after a provider failure without a duplicate commit' {
        $fixture = New-CompletionFixture
        try {
            Set-ProviderFixture -Fixture $fixture -FailMerge
            {
                & $fixture.Complete -RepoRoot $fixture.Trusted `
                    -PullRequestNumber 17 -DueId $fixture.DueId `
                    -RunId $fixture.RunId -Receipt $fixture.Receipt `
                    -LifecycleHeadOid $fixture.LifecycleHead
            } | Should -Throw '*provider request failed*'
            $completedHead = ([string](
                    & git --git-dir=$($fixture.Remote) rev-parse "refs/heads/$($fixture.Branch)"
                )).Trim()
            $result = & $fixture.Complete -RepoRoot $fixture.Trusted `
                -PullRequestNumber 17 -DueId $fixture.DueId `
                -RunId $fixture.RunId -Receipt $fixture.Receipt `
                -LifecycleHeadOid $fixture.LifecycleHead
            $result.StateCommitted | Should -BeFalse
            $result.ExpectedHeadOid | Should -Be $completedHead
        }
        finally {
            Remove-CompletionFixture -Fixture $fixture
        }

        $tampered = New-CompletionFixture
        try {
            $unrelated = Join-Path $tampered.Root (
                'docs/self-improvement/unrelated.json'
            )
            [System.IO.File]::WriteAllText($unrelated, "{}" + [Environment]::NewLine)
            [void](Invoke-CompletionGit -Root $tampered.Root -Argument @(
                    'add', 'docs/self-improvement/unrelated.json'
                ))
            [void](Invoke-CompletionGit -Root $tampered.Root -Argument @(
                    'commit', '--quiet', '-m', 'inject unrelated SI state'
                ))
            [void](Invoke-CompletionGit -Root $tampered.Root -Argument @(
                    'push', '--quiet', 'origin', $tampered.Branch
                ))
            Set-ProviderFixture -Fixture $tampered
            {
                & $tampered.Complete -RepoRoot $tampered.Trusted `
                    -PullRequestNumber 17 -DueId $tampered.DueId `
                    -RunId $tampered.RunId -Receipt $tampered.Receipt `
                    -LifecycleHeadOid $tampered.LifecycleHead
            } | Should -Throw '*unadmitted state path*'
            $global:SiCompletionCalls.Count | Should -Be 0
        }
        finally {
            Remove-CompletionFixture -Fixture $tampered
        }

        $choiceTamper = New-CompletionFixture
        try {
            $runPath = @(
                Get-ChildItem -LiteralPath (
                    Join-Path $choiceTamper.Root 'docs/self-improvement/runs'
                ) -Filter "$($choiceTamper.RunId).json" -Recurse -File
            )[0].FullName
            $run = Get-Content -LiteralPath $runPath -Raw |
                ConvertFrom-Json -Depth 100
            $run.choices[0].disposition = 'declined'
            Write-CompletionJson -Path $runPath -Value $run
            [void](Invoke-CompletionGit -Root $choiceTamper.Root -Argument @(
                    'add', 'docs/self-improvement'
                ))
            [void](Invoke-CompletionGit -Root $choiceTamper.Root -Argument @(
                    'commit', '--quiet', '-m', 'rewrite operator choice'
                ))
            [void](Invoke-CompletionGit -Root $choiceTamper.Root -Argument @(
                    'push', '--quiet', 'origin', $choiceTamper.Branch
                ))
            Set-ProviderFixture -Fixture $choiceTamper
            {
                & $choiceTamper.Complete -RepoRoot $choiceTamper.Trusted `
                    -PullRequestNumber 17 -DueId $choiceTamper.DueId `
                    -RunId $choiceTamper.RunId -Receipt $choiceTamper.Receipt `
                    -LifecycleHeadOid $choiceTamper.LifecycleHead
            } | Should -Throw '*operator-held lifecycle head*'
        }
        finally {
            Remove-CompletionFixture -Fixture $choiceTamper
        }

        $ambiguous = New-CompletionFixture
        try {
            Set-ProviderFixture -Fixture $ambiguous -AmbiguousMerge
            $result = & $ambiguous.Complete -RepoRoot $ambiguous.Trusted `
                -PullRequestNumber 17 -DueId $ambiguous.DueId `
                -RunId $ambiguous.RunId -Receipt $ambiguous.Receipt `
                -LifecycleHeadOid $ambiguous.LifecycleHead
            $result.Status | Should -Be 'complete'
            $result.MergedAt | Should -Be '2026-08-10T00:00:00Z'

            Remove-Item -LiteralPath $ambiguous.Trusted -Recurse -Force
            [void](Invoke-CompletionGit -Root (
                    Split-Path -Parent $ambiguous.Trusted
                ) -Argument @(
                    'clone', '--quiet', '--branch', 'main',
                    $ambiguous.Remote, $ambiguous.Trusted
                ))
            [void](Invoke-CompletionGit -Root $ambiguous.Trusted -Argument @(
                    'checkout', '--quiet', '--detach'
                ))
            $ambiguous.Complete = Join-Path $ambiguous.Trusted (
                '.github/skills/si/scripts/Complete-SiProposal.ps1'
            )
            $retry = & $ambiguous.Complete -RepoRoot $ambiguous.Trusted `
                -PullRequestNumber 17 -DueId $ambiguous.DueId `
                -RunId $ambiguous.RunId -Receipt $ambiguous.Receipt `
                -LifecycleHeadOid $ambiguous.LifecycleHead
            $retry.Status | Should -Be 'complete'
            $retry.MergedAt | Should -Be '2026-08-10T00:00:00Z'
        }
        finally {
            Remove-CompletionFixture -Fixture $ambiguous
        }

        $wrongBase = New-CompletionFixture
        try {
            Set-ProviderFixture -Fixture $wrongBase -FailMerge
            {
                & $wrongBase.Complete -RepoRoot $wrongBase.Trusted `
                    -PullRequestNumber 17 -DueId $wrongBase.DueId `
                    -RunId $wrongBase.RunId -Receipt $wrongBase.Receipt `
                    -LifecycleHeadOid $wrongBase.LifecycleHead
            } | Should -Throw '*provider request failed*'
            $completedHead = ([string](
                    & git --git-dir=$($wrongBase.Remote) rev-parse (
                        "refs/heads/$($wrongBase.Branch)"
                    )
                )).Trim()
            & git --git-dir=$($wrongBase.Remote) update-ref refs/heads/main `
                $completedHead
            & git --git-dir=$($wrongBase.Remote) update-ref refs/pull/17/head `
                $completedHead
            $global:SiCompletionMerged = $true
            $global:SiCompletionIsDraft = $false
            $global:SiCompletionBaseOid = $wrongBase.LifecycleHead
            $global:SiCompletionCalls.Clear()
            Remove-Item -LiteralPath $wrongBase.Trusted -Recurse -Force
            [void](Invoke-CompletionGit -Root (
                    Split-Path -Parent $wrongBase.Trusted
                ) -Argument @(
                    'clone', '--quiet', '--branch', 'main',
                    $wrongBase.Remote, $wrongBase.Trusted
                ))
            [void](Invoke-CompletionGit -Root $wrongBase.Trusted -Argument @(
                    'checkout', '--quiet', '--detach'
                ))
            $wrongBase.Complete = Join-Path $wrongBase.Trusted (
                '.github/skills/si/scripts/Complete-SiProposal.ps1'
            )
            {
                & $wrongBase.Complete -RepoRoot $wrongBase.Trusted `
                    -PullRequestNumber 17 -DueId $wrongBase.DueId `
                    -RunId $wrongBase.RunId -Receipt $wrongBase.Receipt `
                    -LifecycleHeadOid $wrongBase.LifecycleHead
            } | Should -Throw '*authoritative pull request base*'
            $global:SiCompletionCalls.Count | Should -Be 0
        }
        finally {
            Remove-CompletionFixture -Fixture $wrongBase
        }
    }

    It 'test:SiState.AllDeclinedRecordPr persists a completed state-only record with null candidate proposal links' {
        $fixture = New-CompletionFixture -AllDeclined
        try {
            Set-ProviderFixture -Fixture $fixture
            [void](& $fixture.Complete -RepoRoot $fixture.Trusted `
                    -PullRequestNumber 17 -DueId $fixture.DueId `
                    -RunId $fixture.RunId -Receipt $fixture.Receipt `
                    -LifecycleHeadOid $fixture.LifecycleHead)
            $inspection = New-CompletionRoot
            try {
                Remove-Item -LiteralPath $inspection -Recurse -Force
                [void](Invoke-CompletionGit -Root (
                        Split-Path -Parent $inspection
                    ) -Argument @(
                        'clone', '--quiet', '--branch', $fixture.Branch,
                        $fixture.Remote, $inspection
                    ))
                $run = Get-Content -LiteralPath @(
                    Get-ChildItem -LiteralPath (
                        Join-Path $inspection 'docs/self-improvement/runs'
                    ) -Filter "$($fixture.RunId).json" -Recurse -File
                )[0].FullName -Raw | ConvertFrom-Json -Depth 100
                $run.status | Should -Be 'completed'
                $run.proposalPr.url | Should -Be 'https://github.com/owner/repo/pull/17'
                @($run.choices | Where-Object { $null -ne $_.proposalPr }).Count |
                    Should -Be 0
            }
            finally {
                if (Test-Path -LiteralPath $inspection) {
                    Remove-Item -LiteralPath $inspection -Recurse -Force
                }
            }
        }
        finally {
            Remove-CompletionFixture -Fixture $fixture
        }
    }

    It 'test:SiState.CorruptionIndependentRepairLifecycle keeps corrupt main authoritative until the fixed repair branch is integrated' {
        $fixture = New-RepairCompletionFixture
        try {
            Set-ProviderFixture -Fixture $fixture
            $result = & $fixture.Complete -RepoRoot $fixture.Trusted `
                -PullRequestNumber 17 `
                -Observation $fixture.Observation -RepairReceipt $fixture.Receipt
            $result.Status | Should -Be 'complete'
            Import-Module (Join-Path $fixture.Trusted (
                    '.github/skills/si/scripts/SiStateStore.psm1'
                )) -Force
            (Get-SiStoreInspection -RepoRoot $fixture.Trusted).Status |
                Should -Be 'migration-required'
        }
        finally {
            Remove-CompletionFixture -Fixture $fixture
        }
    }

    It 'test:SiState.RepairReceiptGatesAuthoritativeMerge refuses a mutated final repair receipt before provider invocation' {
        $fixture = New-RepairCompletionFixture
        try {
            $checkout = New-CompletionRoot
            Remove-Item -LiteralPath $checkout -Recurse -Force
            [void](Invoke-CompletionGit -Root (
                    Split-Path -Parent $checkout
                ) -Argument @(
                    'clone', '--quiet', '--branch', $fixture.Branch,
                    $fixture.Remote, $checkout
                ))
            $receiptPath = Join-Path $checkout (
                "docs/self-improvement/repair-receipts/$($fixture.Receipt).json"
            )
            $receipt = Get-Content -LiteralPath $receiptPath -Raw |
                ConvertFrom-Json -Depth 20 -DateKind String
            $manifestPath = Join-Path $checkout 'docs/self-improvement/state.json'
            $manifest = Get-Content -LiteralPath $manifestPath -Raw |
                ConvertFrom-Json -Depth 20
            $manifest.generation = [int]$manifest.generation + 50
            Write-CompletionJson -Path $manifestPath -Value $manifest
            Import-Module (Join-Path $checkout (
                    '.github/skills/si/scripts/AtomicStore.psm1'
                )) -Force
            $receipt.afterDigest = Get-SiArtifactDigest -Path $manifestPath
            $payload = [ordered]@{
                protocol = [string]$receipt.protocol
                observationId = [string]$receipt.observationId
                mode = [string]$receipt.mode
                beforeDigest = [string]$receipt.beforeDigest
                afterDigest = [string]$receipt.afterDigest
                createdAtUtc = [string]$receipt.createdAtUtc
            }
            $forgedId = [Convert]::ToHexString(
                [System.Security.Cryptography.SHA256]::HashData(
                    [System.Text.Encoding]::UTF8.GetBytes(
                        ($payload | ConvertTo-Json -Compress)
                    )
                )
            ).ToLowerInvariant()
            $receipt.receiptId = $forgedId
            Remove-Item -LiteralPath $receiptPath -Force
            Write-CompletionJson -Path (Join-Path $checkout (
                    "docs/self-improvement/repair-receipts/$forgedId.json"
                )) -Value $receipt
            [void](Invoke-CompletionGit -Root $checkout -Argument @(
                    'config', 'user.name', 'Mutator'
                ))
            [void](Invoke-CompletionGit -Root $checkout -Argument @(
                    'config', 'user.email', 'mutator@example.test'
                ))
            [void](Invoke-CompletionGit -Root $checkout -Argument @(
                    'add', 'docs'
                ))
            [void](Invoke-CompletionGit -Root $checkout -Argument @(
                    'commit', '--quiet', '-m', 'mutate repair receipt'
                ))
            [void](Invoke-CompletionGit -Root $checkout -Argument @(
                    'push', '--quiet', 'origin', $fixture.Branch
                ))
            Set-ProviderFixture -Fixture $fixture
            {
                & $fixture.Complete -RepoRoot $fixture.Trusted `
                    -PullRequestNumber 17 `
                    -Observation $fixture.Observation -RepairReceipt $forgedId
            } | Should -Throw '*trusted replay*'
            $global:SiCompletionCalls.Count | Should -Be 0
            Remove-Item -LiteralPath $checkout -Recurse -Force
        }
        finally {
            Remove-CompletionFixture -Fixture $fixture
        }
    }

    It 'test:SiScope.ExpectedHeadMergeEnforced passes the freshly validated live OID to the provider merge' {
        $fixture = New-CompletionFixture
        try {
            Set-ProviderFixture -Fixture $fixture
            $result = & $fixture.Complete -RepoRoot $fixture.Trusted `
                -PullRequestNumber 17 -DueId $fixture.DueId `
                -RunId $fixture.RunId -Receipt $fixture.Receipt `
                -LifecycleHeadOid $fixture.LifecycleHead
            $mergeArguments = @($global:SiCompletionCalls[0])
            $mergeArguments | Should -Contain (
                "expectedHeadOid=$($result.ExpectedHeadOid)"
            )
            [System.IO.File]::ReadAllText(
                (Join-Path $script:pluginRoot 'skills/si/SKILL.md')
            ) | Should -Not -Match 'Complete-SiProposal'
            $result.ExpectedHeadOid | Should -Be (
                ([string](
                        & git --git-dir=$($fixture.Remote) rev-parse (
                            "refs/heads/$($fixture.Branch)"
                        )
                    )).Trim()
            )
        }
        finally {
            Remove-CompletionFixture -Fixture $fixture
        }

        $tampered = New-CompletionFixture
        try {
            [System.IO.File]::AppendAllText(
                (Join-Path $tampered.Root '.github/skills/si/SKILL.md'),
                "`npost-sync protected edit`n"
            )
            [void](Invoke-CompletionGit -Root $tampered.Root -Argument @(
                    'add', '.github/skills/si/SKILL.md'
                ))
            [void](Invoke-CompletionGit -Root $tampered.Root -Argument @(
                    'commit', '--quiet', '-m', 'mutate protected anchor after sync'
                ))
            [void](Invoke-CompletionGit -Root $tampered.Root -Argument @(
                    'push', '--quiet', 'origin', $tampered.Branch
                ))
            Set-ProviderFixture -Fixture $tampered
            {
                & $tampered.Complete -RepoRoot $tampered.Trusted `
                    -PullRequestNumber 17 -DueId $tampered.DueId `
                    -RunId $tampered.RunId -Receipt $tampered.Receipt `
                    -LifecycleHeadOid $tampered.LifecycleHead
            } | Should -Throw '*protected SI trust anchor*'
            $global:SiCompletionCalls.Count | Should -Be 0
        }
        finally {
            Remove-CompletionFixture -Fixture $tampered
        }
    }
}

Describe 'Crash-safe SI repair journal' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        Import-Module (Join-Path $script:repoRoot (
                '.github/skills/si/scripts/SiStateStore.psm1'
            )) -Force
    }

    It 'test:SiState.RepairCrashJournalRollback rolls back by observation before a final receipt exists' {
        $root = Join-Path $TestDrive 'repair-crash'
        [void](New-Item -ItemType Directory -Path $root -Force)
        $manifestPath = Resolve-SiStatePath -RepoRoot $root -Segments @('state.json')
        [void](New-Item -ItemType Directory -Path (
                Split-Path -Parent $manifestPath
            ) -Force)
        [System.IO.File]::WriteAllText(
            $manifestPath,
            '{"schemaVersion":1,"generation":0,"pending":[],"inFlight":[],"recentRuns":[]}' + "`n"
        )
        $snapshot = Invoke-SiRepair -RepoRoot $root -Mode Snapshot `
            -PinnedBaseOid ('a' * 40)
        $backup = Resolve-SiStatePath -RepoRoot $root -Segments @(
            'backups', $snapshot.ObservationId
        )
        [void](New-Item -ItemType Directory -Path $backup -Force)
        [System.IO.File]::Copy($manifestPath, (Join-Path $backup 'state.json'), $true)
        $before = Get-SiArtifactDigest -Path $manifestPath
        [System.IO.File]::WriteAllText(
            (Join-Path $backup 'apply-journal.json'),
            (([ordered]@{
                        schemaVersion = 1
                        observationId = $snapshot.ObservationId
                        beforeDigest = $before
                        stage = 'backup-complete'
                    } | ConvertTo-Json -Compress) + "`n")
        )

        $rolledBack = Invoke-SiRepair -RepoRoot $root -Mode Rollback `
            -Observation $snapshot.ObservationId

        $rolledBack.Mutated | Should -BeFalse
        $rolledBack.ReceiptId | Should -Match '^[0-9a-f]{64}$'
        Test-Path -LiteralPath (
            Join-Path $backup 'apply-journal.json'
        ) | Should -BeFalse
        (Get-SiStoreInspection -RepoRoot $root).Status |
            Should -Be 'migration-required'

        [System.IO.File]::WriteAllText(
            (Join-Path $backup 'apply-journal.json'),
            (([ordered]@{
                        schemaVersion = 1
                        observationId = $snapshot.ObservationId
                        beforeDigest = $before
                        stage = 'mutation-started'
                    } | ConvertTo-Json -Compress) + "`n")
        )
        [System.IO.File]::WriteAllText(
            $manifestPath,
            ((New-SiManifest | ConvertTo-Json -Depth 20 -Compress) + "`n")
        )
        $restored = Invoke-SiRepair -RepoRoot $root -Mode Rollback `
            -Observation $snapshot.ObservationId
        $restored.Mutated | Should -BeTrue
        Get-SiArtifactDigest -Path $manifestPath | Should -Be $before

        [System.IO.File]::WriteAllText(
            (Join-Path $backup 'apply-journal.json'),
            (([ordered]@{
                        schemaVersion = 1
                        observationId = $snapshot.ObservationId
                        beforeDigest = $before
                        stage = 'backup-complete'
                    } | ConvertTo-Json -Compress) + "`n")
        )
        [System.IO.File]::AppendAllText($manifestPath, ' ')
        {
            Invoke-SiRepair -RepoRoot $root -Mode Rollback `
                -Observation $snapshot.ObservationId
        } | Should -Throw '*changed before repair mutation*'
        [System.IO.File]::WriteAllText(
            $manifestPath,
            [System.IO.File]::ReadAllText((Join-Path $backup 'state.json'))
        )
        [void](Invoke-SiRepair -RepoRoot $root -Mode Rollback `
                -Observation $snapshot.ObservationId)
    }
}
