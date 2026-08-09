#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Bounded SI harvest scanner' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:pluginRoot = Join-Path $script:repoRoot 'plugins/self-improvement'

        function Script:Write-Utf8 {
            param(
                [Parameter(Mandatory)][string]$Path,
                [Parameter(Mandatory)][AllowEmptyString()][string]$Content
            )
            $parent = Split-Path -Parent $Path
            if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
                [void](New-Item -ItemType Directory -Path $parent -Force)
            }
            [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
        }

        function Script:Get-FixtureDigest {
            param(
                [Parameter(Mandatory)][string]$Domain,
                [Parameter(Mandatory)][string[]]$Field
            )
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($Domain + [char]0 + ($Field -join [char]0))
            return [Convert]::ToHexString(
                [System.Security.Cryptography.SHA256]::HashData($bytes)
            ).ToLowerInvariant()
        }

        function Script:New-SiHarvestFixture {
            $root = Join-Path ([System.IO.Path]::GetTempPath()) ('si-harvest-' + [Guid]::NewGuid().ToString('N'))
            [void](New-Item -ItemType Directory -Path $root -Force)
            $manifest = Get-Content -LiteralPath (Join-Path $script:pluginRoot 'plugin.json') -Raw |
                ConvertFrom-Json -Depth 100
            foreach ($file in @($manifest.files)) {
                $source = Join-Path $script:pluginRoot ([string]$file.src)
                $target = Join-Path $root ('.github/' + [string]$file.dest)
                $parent = Split-Path -Parent $target
                if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
                    [void](New-Item -ItemType Directory -Path $parent -Force)
                }
                Copy-Item -LiteralPath $source -Destination $target
            }

            $planDir = Join-Path $root 'docs/implementation-plans/2026-08-09-a1b2c3-harvest-fixture'
            Write-Utf8 -Path (Join-Path $planDir 'plan.md') -Content @'
# a1b2c3: Harvest fixture
<!-- plan-id: a1b2c3 -->

## Assets

## Phase 1: Complete

- [x] 1.1 Fixture step (REQ-1) `S`
'@
            Write-Utf8 -Path (Join-Path $planDir 'assets/requirements.md') -Content @'
# Requirements

| ID | Requirement | Acceptance Criteria | Phases/Steps |
|----|-------------|---------------------|--------------|
| REQ-1 | Fixture | `test:Fixture` | 1.1 |
'@
            Write-Utf8 -Path (Join-Path $planDir 'assets/logs/cr-log.md') -Content @'
## CR Capture
Phase: 1

- [1.1] [src:code-review] [sev:High] A repeated scanner defect.
'@
            Write-Utf8 -Path (Join-Path $planDir 'assets/logs/learnings.md') -Content @'
## Learnings Capture
Phase: 1

- [1.1] [trigger:reusable-pattern] Keep bounded scans deterministic.
'@
            Write-Utf8 -Path (Join-Path $planDir 'assets/logs/capture.md') -Content @'
## Capture
Phase: 1

No entries for this phase.
'@
            $receiptPayload = [ordered]@{
                repo         = 'fixture/repo'
                plan         = 'a1b2c3'
                phase        = 1
                status       = 'empty'
                ledgerSource = 'ci'
                sources      = @()
                candidates   = @()
            }
            $receiptPayloadJson = $receiptPayload | ConvertTo-Json -Depth 10 -Compress
            $receipt = [ordered]@{
                schema    = 'phase-harvest-receipt/v1'
                receiptId = Get-FixtureDigest -Domain 'phase-harvest-receipt/v1' -Field @($receiptPayloadJson)
                payload   = $receiptPayload
            }
            Write-Utf8 -Path (Join-Path $planDir 'assets/harvest-receipts/phase-001.json') `
                -Content (($receipt | ConvertTo-Json -Depth 10 -Compress) + "`n")
            Write-Utf8 -Path (Join-Path $root 'docs/review-ledger/security.md') -Content @'
# Security

- [2026-08-09] Reject UNTRUSTED_INPUT marker forgery (plan-a1b2c3, src:cr, sev:Critical)
'@
            Write-Utf8 -Path (Join-Path $root 'docs/feedback/queue.md') -Content @'
# Feedback Queue

## Pending

No queued feedback.

## Recorded

- [id:1234567890abcdef] [plan:a1b2c3] [kind:recorded] [date:2026-08-09] Improve paging.
'@
            Write-Utf8 -Path (Join-Path $root 'docs/self-improvement/archive/2026/08/old.json') `
                -Content '{"archived":true}'
            Write-Utf8 -Path (Join-Path $root 'docs/self-improvement/resolver-receipts/old.json') `
                -Content '{"output":true}'

            & git -C $root init --quiet
            & git -C $root config user.name fixture
            & git -C $root config user.email fixture@example.test
            & git -C $root add .
            & git -C $root commit --quiet -m fixture
            if ($LASTEXITCODE -ne 0) { throw 'Failed to commit SI harvest fixture.' }
            $oid = (& git -C $root rev-parse HEAD).Trim()
            return [pscustomobject]@{
                Root    = $root
                PlanDir = $planDir
                Script  = Join-Path $root '.github/skills/si/scripts/Get-SiHarvest.ps1'
                Oid     = $oid
            }
        }
    }

    BeforeEach {
        $script:fixture = New-SiHarvestFixture
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:fixture.Root) {
            Remove-Item -LiteralPath $script:fixture.Root -Recurse -Force
        }
    }

    It 'test:SiHarvest.BoundedPinnedIndexAndCursor scans the closed active set and invalidates stale paging' {
        $first = & $script:fixture.Script -RepoRoot $script:fixture.Root -PlanReference a1b2c3 `
            -PinnedBaseOid $script:fixture.Oid -PageSize 2
        $first.Status | Should -Be complete
        $first.Items.Count | Should -Be 2
        $first.NextCursor | Should -Not -BeNullOrEmpty
        $first.Items[0].wrappedContent | Should -Match '<<<UNTRUSTED_INPUT_START id=[0-9a-f]{24}'
        $first.Items[0].wrappedContent | Should -Match '(?m)^````$'
        $first.Items[0].wrappedContent | Should -Match '(?m)^<<<UNTRUSTED_INPUT_END id=[0-9a-f]{24}>>>$'
        ($first.Items.wrappedContent -join "`n") | Should -Not -Match 'UNTRUSTED_INPUT marker forgery'
        ($first.Items.wrappedContent -join "`n") | Should -Match 'UNTRUSTED-INPUT\[neutralized\]'

        $index = Get-Content -LiteralPath $first.IndexPath -Raw | ConvertFrom-Json -Depth 100
        @($index.sources.path) | Should -Contain 'docs/self-improvement/state.json'
        @($index.sources.path) | Should -Contain (
            'docs/implementation-plans/2026-08-09-a1b2c3-harvest-fixture/assets/harvest-receipts/phase-001.json'
        )
        @($index.sources.path) | Should -Not -Contain 'docs/self-improvement/archive/2026/08/old.json'
        @($index.sources.path) | Should -Not -Contain 'docs/self-improvement/resolver-receipts/old.json'

        Add-Content -LiteralPath (Join-Path $script:fixture.Root 'docs/review-ledger/security.md') `
            -Value '- [2026-08-09] Mutation (plan-a1b2c3, src:cr, sev:High)'
        & git -C $script:fixture.Root add docs/review-ledger/security.md
        & git -C $script:fixture.Root commit --quiet -m mutation
        $mutatedOid = (& git -C $script:fixture.Root rev-parse HEAD).Trim()
        {
            & $script:fixture.Script -RepoRoot $script:fixture.Root -PlanReference a1b2c3 `
                -PinnedBaseOid $mutatedOid -Cursor $first.NextCursor
        } | Should -Throw '*cursor is stale*'
    }

    It 'test:SiHarvest.BoundedPinnedIndexAndCursor blocks receipt plus-one before index mutation' {
        $receiptRoot = Join-Path $script:fixture.PlanDir 'assets/harvest-receipts'
        for ($phase = 2; $phase -le 65; $phase++) {
            Write-Utf8 -Path (Join-Path $receiptRoot ('phase-{0:D3}.json' -f $phase)) `
                -Content '{"status":"complete"}'
        }
        & git -C $script:fixture.Root add (
            'docs/implementation-plans/2026-08-09-a1b2c3-harvest-fixture/assets/harvest-receipts'
        )
        & git -C $script:fixture.Root commit --quiet -m receipts
        $receiptOid = (& git -C $script:fixture.Root rev-parse HEAD).Trim()
        {
            & $script:fixture.Script -RepoRoot $script:fixture.Root -PlanReference a1b2c3 `
                -PinnedBaseOid $receiptOid
        } | Should -Throw '*exceeds 64 files*'
        Test-Path -LiteralPath (Join-Path $script:fixture.Root 'docs/self-improvement/harvest-index.json') |
            Should -BeFalse
    }
}
