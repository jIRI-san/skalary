#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Trusted SI proposal synchronization' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:sync = Join-Path $script:repoRoot (
            '.github/skills/si/scripts/Invoke-SiProposalSync.ps1'
        )
        Import-Module (Join-Path $script:repoRoot (
                'plugins/self-improvement/scripts/SiResolverReceipt.psm1'
            )) -Force

        function Script:New-ProposalRoot {
            $root = Join-Path ([System.IO.Path]::GetTempPath()) (
                'si-proposal-' + [Guid]::NewGuid().ToString('N')
            )
            [void](New-Item -ItemType Directory -Path $root -Force)
            return $root
        }

        function Script:Invoke-ProposalGit {
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

        function Script:Write-ProposalJson {
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

        function Script:Install-SelfImprovement {
            param([Parameter(Mandatory)][string]$Root)

            $pluginRoot = Join-Path $script:repoRoot 'plugins/self-improvement'
            $manifest = Get-Content -LiteralPath (Join-Path $pluginRoot 'plugin.json') -Raw |
                ConvertFrom-Json -Depth 100
            foreach ($file in @($manifest.files)) {
                $target = Join-Path $Root ('.github/' + [string]$file.dest)
                [void](New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force)
                Copy-Item -LiteralPath (Join-Path $pluginRoot ([string]$file.src)) `
                    -Destination $target -Force
            }
        }

        function Script:New-ProposalFixture {
            Import-Module (Join-Path $script:repoRoot (
                    'plugins/self-improvement/scripts/SiResolverReceipt.psm1'
                )) -Force
            $root = New-ProposalRoot
            $remote = New-ProposalRoot
            Install-SelfImprovement -Root $root
            [void](Invoke-ProposalGit -Root $remote -Argument @('init', '--bare', '--quiet'))
            [void](Invoke-ProposalGit -Root $root -Argument @(
                    'init', '--initial-branch=main', '--quiet'
                ))
            [void](Invoke-ProposalGit -Root $root -Argument @(
                    'config', 'user.name', 'SI Fixture'
                ))
            [void](Invoke-ProposalGit -Root $root -Argument @(
                    'config', 'user.email', 'si@example.test'
                ))
            [void](Invoke-ProposalGit -Root $root -Argument @(
                    'remote', 'add', 'origin', $remote
                ))

            $enqueue = Join-Path $root '.github/skills/si/scripts/Enqueue-SiDue.ps1'
            $enqueued = & $enqueue -RepoRoot $root -PlanId 1936cb `
                -SourceCommit ('a' * 40)
            [void](Invoke-ProposalGit -Root $root -Argument @('add', '.github', 'docs'))
            [void](Invoke-ProposalGit -Root $root -Argument @(
                    'commit', '--quiet', '-m', 'authoritative main'
                ))
            [void](Invoke-ProposalGit -Root $root -Argument @(
                    'push', '--quiet', '--set-upstream', 'origin', 'main'
                ))
            $trustedRoot = New-ProposalRoot
            Remove-Item -LiteralPath $trustedRoot -Recurse -Force
            [void](Invoke-ProposalGit -Root (Split-Path -Parent $trustedRoot) -Argument @(
                    'clone', '--quiet', '--branch', 'main', $remote, $trustedRoot
                ))
            $pinned = [string](
                Invoke-ProposalGit -Root $root -Argument @('rev-parse', 'HEAD') |
                    Select-Object -First 1
            )
            $pinned = $pinned.Trim()
            $runId = 'b' * 64
            $candidates = @(
                [pscustomobject][ordered]@{
                    title = 'Allowed proposal'
                    rationale = 'Exercise trusted synchronization'
                    sources = @('docs/review-ledger/testing.md')
                    targets = @('docs/design-notes/project/allowed.design.md')
                }
            )
            $ranked = New-SiRankedCandidates -Candidate $candidates
            $payload = [pscustomobject][ordered]@{
                protocol = 'si-resolver-receipt-v1'
                dueId = $enqueued.DueId
                runId = $runId
                pinnedBaseOid = $pinned
                snapshotDigest = 'c' * 64
                selectedDigest = 'd' * 64
                rankedSetDigest = $ranked.RankedSetDigest
                candidates = $ranked.CandidateIds
            }
            $receipt = Get-SiResolverReceiptId -Payload $payload
            Write-ProposalJson -Path (Join-Path $root (
                    "docs/self-improvement/resolver-receipts/$receipt.json"
                )) -Value ([ordered]@{
                    receiptId = $receipt
                    payload = $payload
                })
            Write-ProposalJson -Path (Join-Path $root (
                    'docs/self-improvement/harvest-index.json'
                )) -Value ([ordered]@{
                    schemaVersion = 1; protocol = 'si-harvest-index-v1'
                    planId = '1936cb'; planPath = 'docs/implementation-plans/example'
                    pinnedBaseOid = $pinned; snapshotDigest = 'c' * 64
                    selectedDigest = 'd' * 64; fileCount = 1
                    scannedByteCount = 1; sourceCount = 1; recordCount = 1
                    selectedByteCount = 1; sources = @(); selectedRecords = @()
                })
            $inputRoot = New-ProposalRoot
            $candidateInput = Join-Path $inputRoot 'candidates.json'
            $choiceInput = Join-Path $inputRoot 'choices.json'
            Write-ProposalJson -Path $candidateInput -Value ([ordered]@{
                    candidates = $candidates
                })
            Write-ProposalJson -Path $choiceInput -Value ([ordered]@{
                    choices = @(
                        [pscustomobject][ordered]@{
                            candidateId = $ranked.CandidateIds[0]
                            disposition = 'accepted'
                            proposalPr = $null
                        }
                    )
                })
            $lifecycle = Join-Path $root (
                '.github/skills/si/scripts/Invoke-SiLifecycle.ps1'
            )
            [void](& $lifecycle -RepoRoot $root -Operation Begin `
                    -DueId $enqueued.DueId -RunId $runId -Receipt $receipt `
                    -InputPath $candidateInput)
            [void](& $lifecycle -RepoRoot $root -Operation RecordChoices `
                    -DueId $enqueued.DueId -RunId $runId -Receipt $receipt `
                    -InputPath $choiceInput)
            [void](Invoke-ProposalGit -Root $root -Argument @('add', 'docs'))
            [void](Invoke-ProposalGit -Root $root -Argument @(
                    'commit', '--quiet', '-m', 'admit lifecycle state'
                ))
            $lifecycleHead = [string](
                Invoke-ProposalGit -Root $root -Argument @('rev-parse', 'HEAD') |
                    Select-Object -First 1
            )
            $lifecycleHead = $lifecycleHead.Trim()
            $allowed = Join-Path $root 'docs/design-notes/project/allowed.design.md'
            [void](New-Item -ItemType Directory -Path (Split-Path -Parent $allowed) -Force)
            [System.IO.File]::WriteAllText($allowed, "allowed proposal`n")
            [void](Invoke-ProposalGit -Root $root -Argument @(
                    'add', 'docs/design-notes/project/allowed.design.md'
                ))
            [void](Invoke-ProposalGit -Root $root -Argument @(
                    'commit', '--quiet', '-m', 'allowed proposal'
                ))
            $fixture = [pscustomobject]@{
                Root = $root
                Remote = $remote
                TrustedRoot = $trustedRoot
                Sync = Join-Path $trustedRoot (
                    '.github/skills/si/scripts/Invoke-SiProposalSync.ps1'
                )
                InputRoot = $inputRoot
                DueId = $enqueued.DueId
                RunId = $runId
                Receipt = $receipt
                LifecycleHead = $lifecycleHead
            }
            Set-ProposalProviderFixture -Fixture $fixture
            return $fixture
        }

        function Script:Set-ProposalProviderFixture {
            param([Parameter(Mandatory)]$Fixture)

            $global:SiProposalRemote = [string]$Fixture.Remote
            $global:SiProposalRaceToAfter = $false
            $global:SiProposalAfterOid = $null
            $global:SiProposalCalls = [System.Collections.Generic.List[object]]::new()
            function global:gh {
                $arguments = @($args)
                $global:LASTEXITCODE = 0
                if ($arguments.Count -gt 1 -and
                    [string]$arguments[0] -eq 'repo' -and
                    [string]$arguments[1] -eq 'view') {
                    return 'R_test'
                }
                $global:SiProposalCalls.Add(@($arguments))
                $query = [string](
                    $arguments | Where-Object { [string]$_ -like 'query=*' } |
                        Select-Object -First 1
                )
                $variables = @{}
                foreach ($argument in $arguments) {
                    if ([string]$argument -match '^(?<name>[^=]+)=(?<value>.*)$') {
                        $variables[$Matches.name] = $Matches.value
                    }
                }
                $ref = [string]$variables.name
                $after = [string]$variables.afterOid
                $global:SiProposalAfterOid = $after
                if ($global:SiProposalRaceToAfter) {
                    & git --git-dir=$global:SiProposalRemote update-ref $ref $after
                    $global:SiProposalRaceToAfter = $false
                }
                $current = [string](
                    & git --git-dir=$global:SiProposalRemote rev-parse `
                        --verify "$ref^{commit}" 2>$null
                )
                if ($LASTEXITCODE -ne 0) { $current = '' } else { $current = $current.Trim() }
                if ($query -like '*createRef*') {
                    if (-not [string]::IsNullOrWhiteSpace($current)) {
                        $global:LASTEXITCODE = 1
                        return '{"errors":[{"message":"ref already exists"}]}'
                    }
                    & git --git-dir=$global:SiProposalRemote update-ref $ref $after
                    $global:LASTEXITCODE = 0
                    return ([ordered]@{
                            data = [ordered]@{
                                createRef = [ordered]@{
                                    ref = [ordered]@{
                                        name = $ref
                                        target = [ordered]@{ oid = $after }
                                    }
                                }
                            }
                        } | ConvertTo-Json -Depth 10 -Compress)
                }
                if ($query -like '*updateRefs*') {
                    $before = [string]$variables.beforeOid
                    if ($current -ne $before) {
                        $global:LASTEXITCODE = 1
                        return '{"errors":[{"message":"beforeOid mismatch"}]}'
                    }
                    & git --git-dir=$global:SiProposalRemote update-ref $ref $after $before
                    if ($LASTEXITCODE -ne 0) {
                        $global:LASTEXITCODE = 1
                        return '{"errors":[{"message":"atomic update failed"}]}'
                    }
                    $global:LASTEXITCODE = 0
                    return '{"data":{"updateRefs":{"clientMutationId":null}}}'
                }
                $global:LASTEXITCODE = 1
                return '{"errors":[{"message":"unexpected provider operation"}]}'
            }
        }

        function Script:Remove-ProposalFixture {
            param($Fixture)
            foreach ($path in @(
                    $Fixture.Root,
                    $Fixture.Remote,
                    $Fixture.TrustedRoot,
                    $Fixture.InputRoot
                )) {
                if ($path -and (Test-Path -LiteralPath $path)) {
                    Remove-Item -LiteralPath $path -Recurse -Force
                }
            }
        }
    }

    AfterEach {
        Remove-Item Function:\global:gh -ErrorAction SilentlyContinue
        foreach ($name in @(
                'SiProposalRemote', 'SiProposalRaceToAfter',
                'SiProposalAfterOid', 'SiProposalCalls'
            )) {
            Remove-Variable $name -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It 'test:SiScope.TrustedBasePassesAllowedProposal merges main, re-derives state, and confirms the pushed OID' {
        $fixture = New-ProposalFixture
        try {
            $proposalHead = [string](
                Invoke-ProposalGit -Root $fixture.Root -Argument @('rev-parse', 'HEAD') |
                    Select-Object -First 1
            )
            $result = & $fixture.Sync -RepoRoot $fixture.Root -Operation Sync `
                -DueId $fixture.DueId -RunId $fixture.RunId `
                -Receipt $fixture.Receipt -LifecycleHeadOid $fixture.LifecycleHead `
                -ExpectedRemoteHead absent

            $result.Status | Should -Be 'complete'
            $result.ValidatedHeadOid | Should -Be $result.RemoteHeadOid
            $remoteHead = [string](
                Invoke-ProposalGit -Root $fixture.Root -Argument @(
                    'ls-remote', '--heads', 'origin', "refs/heads/si/$($fixture.DueId)"
                ) | Select-Object -First 1
            )
            $remoteHead | Should -Match "^$($result.ValidatedHeadOid)\s"
            $manifest = Get-Content -LiteralPath (
                Join-Path $fixture.Root 'docs/self-improvement/state.json'
            ) -Raw | ConvertFrom-Json -Depth 100
            @($manifest.inFlight | Where-Object dueId -EQ $fixture.DueId).Count |
                Should -Be 1
            [string](
                Invoke-ProposalGit -Root $fixture.Root -Argument @('rev-parse', 'HEAD') |
                    Select-Object -First 1
            ) | Should -Be $proposalHead
        }
        finally {
            Remove-ProposalFixture -Fixture $fixture
        }

        $handFixture = New-ProposalFixture
        try {
            $manifestPath = Join-Path $handFixture.Root (
                'docs/self-improvement/state.json'
            )
            [System.IO.File]::AppendAllText($manifestPath, "`n")
            [void](Invoke-ProposalGit -Root $handFixture.Root -Argument @(
                    'add', 'docs/self-improvement/state.json'
                ))
            [void](Invoke-ProposalGit -Root $handFixture.Root -Argument @(
                    'commit', '--quiet', '-m', 'hand edit lifecycle state'
                ))
            {
                & $handFixture.Sync -RepoRoot $handFixture.Root -Operation Sync `
                    -DueId $handFixture.DueId -RunId $handFixture.RunId `
                    -Receipt $handFixture.Receipt `
                    -LifecycleHeadOid $handFixture.LifecycleHead `
                    -ExpectedRemoteHead absent
            } | Should -Throw '*hand-edited lifecycle state*'
        }
        finally {
            Remove-ProposalFixture -Fixture $handFixture
        }

        $staleTrustedFixture = New-ProposalFixture
        try {
            [void](Invoke-ProposalGit -Root $staleTrustedFixture.TrustedRoot -Argument @(
                    'config', 'user.name', 'Untrusted Checkout'
                ))
            [void](Invoke-ProposalGit -Root $staleTrustedFixture.TrustedRoot -Argument @(
                    'config', 'user.email', 'untrusted@example.test'
                ))
            $drift = Join-Path $staleTrustedFixture.TrustedRoot 'docs/trusted-drift.md'
            [System.IO.File]::WriteAllText($drift, "drift`n")
            [void](Invoke-ProposalGit -Root $staleTrustedFixture.TrustedRoot -Argument @(
                    'add', 'docs/trusted-drift.md'
                ))
            [void](Invoke-ProposalGit -Root $staleTrustedFixture.TrustedRoot -Argument @(
                    'commit', '--quiet', '-m', 'advance trusted checkout'
                ))
            {
                & $staleTrustedFixture.Sync -RepoRoot $staleTrustedFixture.Root `
                    -Operation Sync -DueId $staleTrustedFixture.DueId `
                    -RunId $staleTrustedFixture.RunId `
                    -Receipt $staleTrustedFixture.Receipt `
                    -LifecycleHeadOid $staleTrustedFixture.LifecycleHead `
                    -ExpectedRemoteHead absent
            } | Should -Throw '*not pinned to the fetched origin/main OID*'
        }
        finally {
            Remove-ProposalFixture -Fixture $staleTrustedFixture
        }
    }

    It 'test:SiScope.ProtectedTrustAnchorsAllRefused rejects every closed-set family and an integrated guard edit' {
        $deniedPaths = @(
            'plugins/self-improvement/plugin.json',
            'plugins/self-improvement/scripts/Invoke-SiProposalSync.ps1',
            'plugins/self-improvement/schemas/run.schema.json',
            'plugins/self-improvement/skills/si/scripts/Test-SiWriteScope.ps1',
            'plugins/self-improvement/skills/si/schemas/run.schema.json',
            'plugins/self-improvement/skills/si/SKILL.md',
            'plugins/self-improvement/skills/si/assets/harvest-guide.md',
            'plugins/self-improvement/skills/si/assets/propose-guide.md',
            'plugins/self-improvement/prompts/si.prompt.md',
            '.github/skills/si/scripts/Test-SiWriteScope.ps1',
            '.github/skills/si/schemas/run.schema.json',
            '.github/skills/si/SKILL.md',
            '.github/skills/si/assets/harvest-guide.md',
            '.github/skills/si/assets/propose-guide.md',
            '.github/prompts/si.prompt.md',
            'scripts/skalary/Test-SiWriteScope.ps1'
        )
        $results = @(& $script:sync -Operation ValidatePaths `
                -Path ($deniedPaths + @('docs/design-notes/project/allowed.design.md')))
        @($results | Where-Object { -not $_.Denied }).Count | Should -Be 1
        @($results | Where-Object Denied).Count | Should -Be $deniedPaths.Count

        $fixture = New-ProposalFixture
        try {
            $skill = Join-Path $fixture.Root '.github/skills/si/SKILL.md'
            [System.IO.File]::AppendAllText($skill, "`nprotected edit`n")
            [void](Invoke-ProposalGit -Root $fixture.Root -Argument @(
                    'add', '.github/skills/si/SKILL.md'
                ))
            [void](Invoke-ProposalGit -Root $fixture.Root -Argument @(
                    'commit', '--quiet', '-m', 'attempt guard edit'
                ))

            {
                & $fixture.Sync -RepoRoot $fixture.Root -Operation Sync `
                    -DueId $fixture.DueId -RunId $fixture.RunId `
                    -Receipt $fixture.Receipt -LifecycleHeadOid $fixture.LifecycleHead `
                    -ExpectedRemoteHead absent
            } | Should -Throw '*protected SI trust anchor*'
        }
        finally {
            Remove-ProposalFixture -Fixture $fixture
        }

        $scopeFixture = New-ProposalFixture
        try {
            [System.IO.File]::WriteAllText(
                (Join-Path $scopeFixture.Root 'package.json'),
                "{}" + [Environment]::NewLine
            )
            [void](Invoke-ProposalGit -Root $scopeFixture.Root -Argument @(
                    'add', 'package.json'
                ))
            [void](Invoke-ProposalGit -Root $scopeFixture.Root -Argument @(
                    'commit', '--quiet', '-m', 'attempt out-of-scope edit'
                ))
            $scopeHead = [string](
                Invoke-ProposalGit -Root $scopeFixture.Root -Argument @('rev-parse', 'HEAD') |
                    Select-Object -First 1
            )
            {
                & $scopeFixture.Sync -RepoRoot $scopeFixture.Root -Operation Sync `
                    -DueId $scopeFixture.DueId -RunId $scopeFixture.RunId `
                    -Receipt $scopeFixture.Receipt `
                    -LifecycleHeadOid $scopeFixture.LifecycleHead `
                    -ExpectedRemoteHead absent
            } | Should -Throw '*write-scope guard refused*'
            [string](
                Invoke-ProposalGit -Root $scopeFixture.Root -Argument @('rev-parse', 'HEAD') |
                    Select-Object -First 1
            ) | Should -Be $scopeHead
        }
        finally {
            Remove-ProposalFixture -Fixture $scopeFixture
        }
    }

    It 'test:SiScope.StaleRemoteHeadRefused stops before merge or push when the fixed branch advances' {
        $fixture = New-ProposalFixture
        $competitor = New-ProposalRoot
        try {
            [void](Invoke-ProposalGit -Root $fixture.Root -Argument @(
                    'push', '--quiet', '--set-upstream', 'origin',
                    "HEAD:refs/heads/si/$($fixture.DueId)"
                ))
            $expected = [string](
                Invoke-ProposalGit -Root $fixture.Root -Argument @('rev-parse', 'HEAD') |
                    Select-Object -First 1
            )
            $expected = $expected.Trim()
            Remove-Item -LiteralPath $competitor -Recurse -Force
            [void](Invoke-ProposalGit -Root (Split-Path -Parent $competitor) -Argument @(
                    'clone', '--quiet', '--branch', "si/$($fixture.DueId)",
                    $fixture.Remote, $competitor
                ))
            [void](Invoke-ProposalGit -Root $competitor -Argument @(
                    'config', 'user.name', 'SI Competitor'
                ))
            [void](Invoke-ProposalGit -Root $competitor -Argument @(
                    'config', 'user.email', 'competitor@example.test'
                ))
            $advance = Join-Path $competitor 'docs/competitor.md'
            [System.IO.File]::WriteAllText($advance, "advance`n")
            [void](Invoke-ProposalGit -Root $competitor -Argument @(
                    'add', 'docs/competitor.md'
                ))
            [void](Invoke-ProposalGit -Root $competitor -Argument @(
                    'commit', '--quiet', '-m', 'advance remote head'
                ))
            [void](Invoke-ProposalGit -Root $competitor -Argument @(
                    'push', '--quiet', 'origin', "si/$($fixture.DueId)"
                ))
            $before = [string](
                Invoke-ProposalGit -Root $fixture.Root -Argument @('rev-parse', 'HEAD') |
                    Select-Object -First 1
            )

            {
                & $fixture.Sync -RepoRoot $fixture.Root -Operation Sync `
                    -DueId $fixture.DueId -RunId $fixture.RunId `
                    -Receipt $fixture.Receipt -LifecycleHeadOid $fixture.LifecycleHead `
                    -ExpectedRemoteHead $expected
            } | Should -Throw '*Remote head is stale*'
            [string](
                Invoke-ProposalGit -Root $fixture.Root -Argument @('rev-parse', 'HEAD') |
                    Select-Object -First 1
            ) | Should -Be $before
        }
        finally {
            Remove-ProposalFixture -Fixture $fixture
            if (Test-Path -LiteralPath $competitor) {
                Remove-Item -LiteralPath $competitor -Recurse -Force
            }
        }

        $raceFixture = New-ProposalFixture
        try {
            $expected = [string](
                Invoke-ProposalGit -Root $raceFixture.Root -Argument @('rev-parse', 'HEAD') |
                    Select-Object -First 1
            )
            $expected = $expected.Trim()
            [void](Invoke-ProposalGit -Root $raceFixture.Root -Argument @(
                    'push', '--quiet', 'origin',
                    "HEAD:refs/heads/si/$($raceFixture.DueId)"
                ))
            $global:SiProposalRaceToAfter = $true

            {
                & $raceFixture.Sync -RepoRoot $raceFixture.Root -Operation Sync `
                    -DueId $raceFixture.DueId -RunId $raceFixture.RunId `
                    -Receipt $raceFixture.Receipt `
                    -LifecycleHeadOid $raceFixture.LifecycleHead `
                    -ExpectedRemoteHead $expected
            } | Should -Throw '*beforeOid mismatch*'
            $global:SiProposalAfterOid | Should -Match '^[0-9a-f]{40}$'
            [string](
                Invoke-ProposalGit -Root $raceFixture.Root -Argument @(
                    'ls-remote', '--heads', 'origin',
                    "refs/heads/si/$($raceFixture.DueId)"
                ) | Select-Object -First 1
            ) | Should -Match "^$($global:SiProposalAfterOid)\s"
            $providerCall = [string]($global:SiProposalCalls |
                    ForEach-Object { @($_) -join ' ' } |
                    Where-Object { $_ -like '*updateRefs*' } |
                    Select-Object -Last 1)
            $providerCall | Should -Match ([regex]::Escape(
                    "beforeOid=$expected"
                ))
        }
        finally {
            Remove-ProposalFixture -Fixture $raceFixture
        }
    }
}
