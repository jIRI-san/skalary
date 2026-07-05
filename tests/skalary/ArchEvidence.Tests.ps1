#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'arch evidence marker' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:archRepoRoot = $repoRoot
        $script:planStateModule = Import-Module (Join-Path $repoRoot 'scripts/skalary/PlanState.psm1') -Force -DisableNameChecking -PassThru
        Import-Module (Join-Path $repoRoot 'scripts/skalary/PlanEvidence.psm1') -Force -DisableNameChecking
        # Capture the ArchReceipt module so the fixture helper can invoke its exported hasher via the module's
        # own session state (-PassThru), which is robust to another test file re-importing PlanEvidence -Force
        # (whose nested ArchReceipt import would otherwise clobber a bare session-level import).
        $script:archReceiptModule = Import-Module (Join-Path $repoRoot 'scripts/skalary/ArchReceipt.psm1') -Force -DisableNameChecking -PassThru
        # Dot-source the review-report generator (its own imports load PlanEvidence then ArchReceipt last).
        . (Join-Path $repoRoot 'scripts/skalary/Get-ArchReviewReport.ps1')

        # Builds a self-contained repo with a contract + config + a FRESH receipt for the given maturity/verdict.
        # The receipt's sourcesHash is computed with the same canonical hasher the runner uses, so it is fresh.
        function New-ArchFixture {
            param(
                [string]$ContractId = 'ARCH-Fix-1',
                [string]$Maturity = 'locked',
                [string]$Verdict = 'pass',
                [string]$Adapter = 'netarchtest',
                [bool]$Ran = $true,
                [switch]$NoReceipt,
                [string]$RawReceipt,
                [hashtable]$Forge,
                [switch]$Stale
            )
            $root = Join-Path ([System.IO.Path]::GetTempPath()) ("archev-" + [guid]::NewGuid().ToString('N'))
            [void](New-Item -ItemType Directory -Path $root -Force)
            git -C $root init --quiet 2>&1 | Out-Null
            git -C $root config user.email 't@t' 2>&1 | Out-Null
            git -C $root config user.name 't' 2>&1 | Out-Null

            Set-Content -LiteralPath (Join-Path $root 'arch-contract.json') -Value ('{"id":"' + $ContractId + '","maturity":"' + $Maturity + '"}') -NoNewline
            [void](New-Item -ItemType Directory -Path (Join-Path $root 'src') -Force)
            Set-Content -LiteralPath (Join-Path $root 'src/a.cs') -Value 'class A {}' -NoNewline

            $check = [pscustomobject]@{ contractId = $ContractId; adapter = $Adapter; maturity = $Maturity; contractPath = 'arch-contract.json'; targets = @('src'); testProject = 'tests/does-not-exist.csproj' }
            (@{ version = '1'; checks = @($check) } | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath (Join-Path $root 'arch-test-config.json') -NoNewline
            git -C $root add -A 2>&1 | Out-Null
            git -C $root commit -qm init 2>&1 | Out-Null
            $head = (git -C $root rev-parse HEAD).Trim()

            $receiptDir = Join-Path $root 'docs/architecture-notes/receipts'
            [void](New-Item -ItemType Directory -Path $receiptDir -Force)
            $receiptPath = Join-Path $receiptDir "$ContractId.arch-receipt.json"

            if (-not $NoReceipt) {
                if ($PSBoundParameters.ContainsKey('RawReceipt')) {
                    Set-Content -LiteralPath $receiptPath -Value $RawReceipt -NoNewline
                }
                else {
                    $hash = & $script:archReceiptModule { param($c, $m, $r) Get-ArchTestCheckSourcesHash -Check $c -Maturity $m -RepoRoot $r } $check $Maturity $root
                    if ($Stale) { $hash = ('0' * 64) }
                    $receipt = [ordered]@{ schemaVersion = '1'; contractId = $ContractId; maturity = $Maturity; adapter = $Adapter; verdict = $Verdict; ran = $Ran; parentCommit = $head; sourcesHash = $hash; generatedAt = '2026-07-04T00:00:00Z' }
                    # Forge patches receipt fields AFTER the fresh hash is computed, WITHOUT touching the config,
                    # so a gate-steering field (adapter/maturity) disagrees with the trusted config while the
                    # freshness hash still matches -- exactly the tamper the verifier must reject.
                    if ($Forge) { foreach ($k in $Forge.Keys) { $receipt[$k] = $Forge[$k] } }
                    ($receipt | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $receiptPath -NoNewline
                }
            }
            return [pscustomobject]@{ Root = $root; ContractId = $ContractId; ReceiptPath = $receiptPath }
        }

        $script:archFixtures = [System.Collections.Generic.List[string]]::new()
        function Use-ArchFixture {
            param([hashtable]$FixtureArgs = @{})
            $f = New-ArchFixture @FixtureArgs
            $script:archFixtures.Add($f.Root)
            return $f
        }
    }

    AfterAll {
        foreach ($r in $script:archFixtures) {
            if (Test-Path -LiteralPath $r) { Remove-Item -LiteralPath $r -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }

    Context 'extraction (REQ-11)' {
        It 'Marker-ArchRecognized: an arch marker is extracted from acceptance criteria' {
            $markers = Get-TypedEvidenceMarkers -AcceptanceCriteria '`arch:ARCH-Foo-1` · `test:X` · `file:a/b#exists`'
            $markers | Should -Contain 'arch:ARCH-Foo-1'
            $markers | Should -Contain 'test:X'
        }

        It 'Marker-UnknownPrefixFailsLoud: a marker-shaped token with an unknown prefix is surfaced, never dropped' {
            $markers = Get-TypedEvidenceMarkers -AcceptanceCriteria '`bogus:whatever` · `arch:ARCH-Ok`'
            # The unknown-prefix token is surfaced verbatim so the evaluator flags it (a stale bundle that does
            # not know arch: would surface arch:... the same way and BLOCK rather than silently drop it).
            $markers | Should -Contain 'bogus:whatever'
            $markers | Should -Contain 'arch:ARCH-Ok'
            # Unanchored: an unknown marker with surrounding text is still surfaced, never silently dropped.
            (Get-TypedEvidenceMarkers -AcceptanceCriteria '`weird:token` and more prose') | Should -Contain 'weird:token'
        }
    }

    Context 'receipt pure-parse verification (REQ-11/REQ-17)' {
        It 'Marker-ArchReadsReceiptNoExec: a fresh locked pass receipt greens WITHOUT running any test project' {
            $f = Use-ArchFixture @{ Maturity = 'locked'; Verdict = 'pass' }
            # The configured testProject does not exist; a fresh pass receipt still greens by PURE PARSE.
            $r = Invoke-PlanArchEvidence -RepoRoot $f.Root -Marker "arch:$($f.ContractId)" -Stage 'PhaseCrosscheck'
            $r.Success | Should -BeTrue
        }
        It 'Marker-ArchFailsWhenReceiptMissingOrStale: a missing or stale receipt is a blocking failure' {
            $missing = Use-ArchFixture @{ NoReceipt = $true }
            $rm = Invoke-PlanArchEvidence -RepoRoot $missing.Root -Marker "arch:$($missing.ContractId)" -Stage 'PhaseCrosscheck'
            $rm.Success | Should -BeFalse
            $rm.Blocking | Should -BeTrue

            $stale = Use-ArchFixture @{ Maturity = 'locked'; Verdict = 'pass'; Stale = $true }
            $rs = Invoke-PlanArchEvidence -RepoRoot $stale.Root -Marker "arch:$($stale.ContractId)" -Stage 'PhaseCrosscheck'
            $rs.Success | Should -BeFalse
            $rs.Blocking | Should -BeTrue
            $rs.Message | Should -Match 'Stale'
        }

        It 'Marker-ArchRejectsMalformed: a malformed receipt is a blocking failure, never a false-green' {
            $f = Use-ArchFixture @{ RawReceipt = '{ this is not valid json' }
            $r = Invoke-PlanArchEvidence -RepoRoot $f.Root -Marker "arch:$($f.ContractId)" -Stage 'PhaseCrosscheck'
            $r.Success | Should -BeFalse
            $r.Blocking | Should -BeTrue

            # A pass verdict with ran=false is a false-green attempt and must be rejected as malformed.
            $forge = Use-ArchFixture @{ RawReceipt = (@{ schemaVersion = '1'; contractId = 'ARCH-Fix-1'; maturity = 'locked'; adapter = 'netarchtest'; verdict = 'pass'; ran = $false; parentCommit = ('a' * 40); sourcesHash = ('0' * 64); generatedAt = '2026-07-04T00:00:00Z' } | ConvertTo-Json) }
            $rf = Invoke-PlanArchEvidence -RepoRoot $forge.Root -Marker 'arch:ARCH-Fix-1' -Stage 'PhaseCrosscheck'
            $rf.Success | Should -BeFalse
        }

        It 'Marker-ArchReadsReceiptNoExec: the evaluator never invokes a build toolchain (pure parse)' {
            # Prove no execution: the fixture pins a bogus testProject and no dotnet is needed; a fresh pass greens.
            $f = Use-ArchFixture @{ Maturity = 'locked'; Verdict = 'pass' }
            $r = Invoke-PlanArchEvidence -RepoRoot $f.Root -Marker "arch:$($f.ContractId)" -Stage 'Draft'
            $r.Success | Should -BeTrue
        }

        It 'Marker-ArchRejectsForgedGateFields: forging the receipt adapter or maturity on a fresh locked fail still blocks' {
            # Forge adapter -> semantic-eval (would flip a locked fail to advisory warn) while the config stays
            # netarchtest and the freshness hash still matches: the config cross-check must reject it.
            $fa = Use-ArchFixture @{ Maturity = 'locked'; Verdict = 'fail'; Adapter = 'netarchtest'; Forge = @{ adapter = 'semantic-eval' } }
            $ra = Invoke-PlanArchEvidence -RepoRoot $fa.Root -Marker "arch:$($fa.ContractId)" -Stage 'PhaseCrosscheck'
            $ra.Success | Should -BeFalse
            $ra.Blocking | Should -BeTrue

            # Forge maturity -> draft (would flip a locked fail to advisory warn); the contract-derived maturity
            # cross-check must reject it.
            $fm = Use-ArchFixture @{ Maturity = 'locked'; Verdict = 'fail'; Forge = @{ maturity = 'draft' } }
            $rm = Invoke-PlanArchEvidence -RepoRoot $fm.Root -Marker "arch:$($fm.ContractId)" -Stage 'PhaseCrosscheck'
            $rm.Success | Should -BeFalse
            $rm.Blocking | Should -BeTrue
        }
    }

    Context 'taxonomy x maturity gate mapping (REQ-16)' {
        It 'Maturity-LockedBlocksOnFail: a locked contract with a fail receipt blocks' {
            $f = Use-ArchFixture @{ Maturity = 'locked'; Verdict = 'fail' }
            $r = Invoke-PlanArchEvidence -RepoRoot $f.Root -Marker "arch:$($f.ContractId)" -Stage 'PhaseCrosscheck'
            $r.Success | Should -BeFalse
            $r.Blocking | Should -BeTrue
        }

        It 'Maturity-DraftWarnsOnly: a draft contract with a fail receipt warns (never blocks)' {
            $f = Use-ArchFixture @{ Maturity = 'draft'; Verdict = 'fail' }
            $r = Invoke-PlanArchEvidence -RepoRoot $f.Root -Marker "arch:$($f.ContractId)" -Stage 'PhaseCrosscheck'
            $r.Success | Should -BeFalse
            $r.Blocking | Should -BeFalse
        }

        It 'Maturity-SkipDoesNotFalseGreenLocked: a locked skip-absent-toolchain never greens and blocks' {
            $f = Use-ArchFixture @{ Maturity = 'locked'; Verdict = 'skip-absent-toolchain'; Ran = $false }
            $r = Invoke-PlanArchEvidence -RepoRoot $f.Root -Marker "arch:$($f.ContractId)" -Stage 'PhaseCrosscheck'
            $r.Success | Should -BeFalse
            $r.Blocking | Should -BeTrue
        }

        It 'Maturity-ErrorDoesNotFalseGreenLocked: a locked error never greens and blocks' {
            $f = Use-ArchFixture @{ Maturity = 'locked'; Verdict = 'error'; Ran = $false }
            $r = Invoke-PlanArchEvidence -RepoRoot $f.Root -Marker "arch:$($f.ContractId)" -Stage 'PhaseCrosscheck'
            $r.Success | Should -BeFalse
            $r.Blocking | Should -BeTrue
        }

        It 'semantic-eval stays advisory: a locked semantic-eval fail warns, never blocks' {
            $f = Use-ArchFixture @{ Maturity = 'locked'; Verdict = 'fail'; Adapter = 'semantic-eval'; Ran = $true }
            $r = Invoke-PlanArchEvidence -RepoRoot $f.Root -Marker "arch:$($f.ContractId)" -Stage 'PhaseCrosscheck'
            $r.Success | Should -BeFalse
            $r.Blocking | Should -BeFalse
        }
    }

    Context 'SKILL review surfaces the runner taxonomy (REQ-16)' {
        It 'Review-SurfacesRunnerTaxonomy: the review report surfaces each contract''s receipt verdict; a locked non-pass or absent receipt is a blocking finding' {
            # A locked contract whose receipt FAILED must surface as a blocking finding -- a schema-only review
            # (contract file is valid) must never false-green it.
            $lf = Use-ArchFixture @{ Maturity = 'locked'; Verdict = 'fail' }
            $repLf = Get-ArchReviewReport -RepoRoot $lf.Root
            $repLf.Blocking | Should -Be 1
            $repLf.LockedCount | Should -Be 1
            $repLf.Contracts[0].ContractId | Should -Be $lf.ContractId
            $repLf.Contracts[0].Success | Should -BeFalse
            $repLf.Contracts[0].Blocking | Should -BeTrue

            # A locked PASS greens (no blocking finding).
            $lp = Use-ArchFixture @{ Maturity = 'locked'; Verdict = 'pass' }
            $repLp = Get-ArchReviewReport -RepoRoot $lp.Root
            $repLp.Blocking | Should -Be 0
            $repLp.Contracts[0].Success | Should -BeTrue

            # A locked contract with NO receipt is unrun -> blocking (a schema-only review cannot false-green it).
            $lm = Use-ArchFixture @{ Maturity = 'locked'; NoReceipt = $true }
            (Get-ArchReviewReport -RepoRoot $lm.Root).Blocking | Should -Be 1

            # A draft fail is advisory -> no blocking finding.
            $df = Use-ArchFixture @{ Maturity = 'draft'; Verdict = 'fail' }
            (Get-ArchReviewReport -RepoRoot $df.Root).Blocking | Should -Be 0

            # A draft contract with NO receipt is unrun: the missing-receipt path is maturity-blind and blocks
            # at crosscheck (safe direction -- over-strict, never a false-green). Pinned so any change is deliberate.
            $dn = Use-ArchFixture @{ Maturity = 'draft'; NoReceipt = $true }
            (Get-ArchReviewReport -RepoRoot $dn.Root).Blocking | Should -Be 1
        }
    }
}
