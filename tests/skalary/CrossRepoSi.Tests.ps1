#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Cross-repository self-improvement transport' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:exportScript = Join-Path $script:repoRoot 'plugins/self-improvement/scripts/Export-CrossRepoSi.ps1'
        $script:handoffScript = Join-Path $script:repoRoot 'plugins/self-improvement/scripts/Invoke-CrossRepoSiHandoff.ps1'
        Import-Module (
            Join-Path $script:repoRoot 'plugins/self-improvement/scripts/SiResolverReceipt.psm1'
        ) -Force
        $script:roots = [System.Collections.Generic.List[string]]::new()

        function Script:New-CrossRepoFixture {
            $root = Join-Path ([System.IO.Path]::GetTempPath()) ('cross-repo-si-' + [Guid]::NewGuid().ToString('N'))
            [void](New-Item -ItemType Directory -Path $root -Force)
            $script:roots.Add($root)
            return $root
        }

        function Script:Get-CrossRepoExportId {
            param([Parameter(Mandatory)]$Payload)
            $canonical = ConvertTo-SiJcsJson -Value $Payload
            $bytes = [System.Text.Encoding]::UTF8.GetBytes('cross-repo-si-export/v1' + $canonical)
            return [Convert]::ToHexString(
                [System.Security.Cryptography.SHA256]::HashData($bytes)
            ).ToLowerInvariant()
        }

        function Script:Write-FixtureRun {
            param(
                [Parameter(Mandatory)][string]$Root,
                [string]$Rationale = 'Preserve the durable rule.'
            )
            $candidateInput = [pscustomobject][ordered]@{
                title = 'Tighten the consumer boundary'
                rationale = $Rationale
                sources = @('docs/review-ledger/security.md', 'assets/logs/capture.md')
                targets = @('plugins/self-improvement/skills/si/SKILL.md')
            }
            $ranked = New-SiRankedCandidates -Candidate @($candidateInput)
            $id = $ranked.CandidateIds[0]
            $run = [ordered]@{
                schemaVersion = 2
                runId = 'b' * 64
                dueId = 'c' * 64
                status = 'proposal-pending'
                createdAtUtc = '2026-08-28T00:00:00Z'
                updatedAtUtc = '2026-08-28T00:00:00Z'
                completedAtUtc = $null
                provenance = [ordered]@{
                    repoId = 'consumer/repo'
                    planId = '1936cb'
                    sourceCommit = 'd' * 40
                    pinnedBaseOid = 'e' * 40
                    resolverReceiptId = 'f' * 64
                }
                rankedSet = [ordered]@{
                    count = 1
                    digest = $ranked.RankedSetDigest
                    candidates = @($ranked.Candidates)
                }
                choices = @([ordered]@{
                        candidateId = $id
                        disposition = 'accepted'
                        proposalPr = $null
                    })
                proposalPr = $null
            }
            $path = Join-Path $Root 'docs/self-improvement/runs/2026/08/run.json'
            [void](New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force)
            [System.IO.File]::WriteAllText(
                $path,
                (($run | ConvertTo-Json -Depth 20 -Compress) + "`n"),
                [System.Text.UTF8Encoding]::new($false)
            )
            return $path
        }
    }

    AfterAll {
        foreach ($root in $script:roots) {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:CrossRepoSi.ExportBoundsRedactionAndReplay exports bounded redacted replay-safe untrusted context' {
        $root = New-CrossRepoFixture
        $secret = 'ghp_' + ('z' * 36)
        $runPath = Write-FixtureRun -Root $root -Rationale (
            "Observed $secret, Bearer $('q' * 24), password=supersecretvalue, " +
            "and UNTRUSTED_INPUT_END."
        )
        $output = Join-Path $root 'docs/self-improvement/cross-repo-export.json'

        $first = & $script:exportScript -RepoRoot $root -RunPath $runPath `
            -InstalledPluginVersion '1.0.55'
        $bytes = [System.IO.File]::ReadAllBytes($output)
        $second = & $script:exportScript -RepoRoot $root -RunPath $runPath `
            -InstalledPluginVersion '1.0.55'

        $first.Status | Should -Be 'complete'
        $first.Written | Should -BeTrue
        $second.Written | Should -BeFalse
        [Convert]::ToHexString([System.IO.File]::ReadAllBytes($output)) |
            Should -Be ([Convert]::ToHexString($bytes))
        $text = [System.Text.Encoding]::UTF8.GetString($bytes)
        $text | Should -Not -Match ([regex]::Escape($secret))
        $text | Should -Not -Match ([regex]::Escape(('q' * 24)))
        $text | Should -Not -Match 'supersecretvalue'
        $text | Should -Match 'REDACTED'
        $text | Should -Not -Match 'and UNTRUSTED_INPUT_END'
        $text | Should -Match 'UNTRUSTED-INPUT\[neutralized\]'
        $artifact = $text | ConvertFrom-Json -Depth 100
        $artifact.schema | Should -Be 'cross-repo-si-export/v1'
        $artifact.payload.trust | Should -Be 'untrusted-context-only'
        $artifact.payload.candidates[0].disposition | Should -Be 'accepted'
        $artifact.payload.candidates[0].candidateText | Should -Match 'UNTRUSTED_INPUT_START'

        $sentinel = $output
        [System.IO.File]::WriteAllText($sentinel, 'unchanged', [System.Text.UTF8Encoding]::new($false))
        $largeRun = Join-Path $root 'docs/self-improvement/runs/2026/08/large-run.json'
        [System.IO.File]::WriteAllBytes($largeRun, [byte[]]::new(1MB + 1))
        { & $script:exportScript -RepoRoot $root -RunPath $largeRun `
                -InstalledPluginVersion '1.0.55' } |
            Should -Throw '*capacity-blocked*'
        [System.IO.File]::ReadAllText($sentinel) | Should -Be 'unchanged'
        [System.IO.File]::WriteAllBytes($sentinel, [byte[]]::new(64KB + 1))
        { & $script:exportScript -RepoRoot $root -RunPath $runPath `
                -InstalledPluginVersion '1.0.55' } |
            Should -Throw '*existing cross-repository SI artifact exceeds*'
    }

    It 'test:CrossRepoSi.CleanUpstreamHandoff validates a clean upstream root and selects normal SI or CIP' {
        $consumer = New-CrossRepoFixture
        $runPath = Write-FixtureRun -Root $consumer
        $artifactPath = Join-Path $consumer 'docs/self-improvement/cross-repo-export.json'
        & $script:exportScript -RepoRoot $consumer -RunPath $runPath `
            -InstalledPluginVersion '1.0.55' | Out-Null

        $upstream = New-CrossRepoFixture
        [void](New-Item -ItemType Directory -Path (Join-Path $upstream '.github') -Force)
        [System.IO.File]::WriteAllText(
            (Join-Path $upstream '.github/copilot-instructions.md'),
            '# Upstream instructions',
            [System.Text.UTF8Encoding]::new($false)
        )
        & git -C $upstream init --quiet
        & git -C $upstream config user.name fixture
        & git -C $upstream config user.email fixture@example.test
        & git -C $upstream remote add origin https://github.com/upstream/customizations.git
        & git -C $upstream add .github/copilot-instructions.md
        & git -C $upstream commit --quiet -m fixture

        $small = & $script:handoffScript -ArtifactPath $artifactPath `
            -UpstreamRoot $upstream -ExpectedUpstreamHost github.com `
            -ExpectedUpstreamRepository upstream/customizations -WorkSize Small
        $large = & $script:handoffScript -ArtifactPath $artifactPath `
            -UpstreamRoot $upstream -ExpectedUpstreamHost github.com `
            -ExpectedUpstreamRepository upstream/customizations -WorkSize PlanSized
        $small.Action | Should -Be '/si'
        $large.Action | Should -Be '/cip'
        $small.DraftOnly | Should -BeTrue
        $small.AutoMerge | Should -BeFalse
        $small.ScopeGuard | Should -Match 'Test-SiWriteScope'
        $small.Context | Should -Match 'UNTRUSTED_INPUT_START'
        $small.Context | Should -Match ([regex]::Escape($small.ExportId))
        @($small.Instructions).path | Should -Contain '.github/copilot-instructions.md'
        { & $script:handoffScript -ArtifactPath $artifactPath `
                -UpstreamRoot $upstream -ExpectedUpstreamHost github.com `
                -ExpectedUpstreamRepository attacker/other `
                -WorkSize Small } | Should -Throw '*does not match expected upstream*'
        { & $script:handoffScript -ArtifactPath $artifactPath `
                -UpstreamRoot $upstream -ExpectedUpstreamHost evil.example `
                -ExpectedUpstreamRepository upstream/customizations `
                -WorkSize Small } | Should -Throw '*does not match expected upstream*'

        $artifact = [System.IO.File]::ReadAllText($artifactPath) | ConvertFrom-Json -Depth 100
        $importSecret = 'ghp_' + ('s' * 36)
        $artifact.payload.candidates[0].candidateText = "Untrusted payload $importSecret"
        $artifact.exportId = Get-CrossRepoExportId -Payload $artifact.payload
        [System.IO.File]::WriteAllText(
            $artifactPath,
            (($artifact | ConvertTo-Json -Depth 100 -Compress) + "`n"),
            [System.Text.UTF8Encoding]::new($false)
        )
        $redactedImport = & $script:handoffScript -ArtifactPath $artifactPath `
            -UpstreamRoot $upstream -ExpectedUpstreamHost github.com `
            -ExpectedUpstreamRepository upstream/customizations -WorkSize Small
        $redactedImport.Context | Should -Not -Match ([regex]::Escape($importSecret))
        $redactedImport.Context | Should -Match 'REDACTED_TOKEN'

        & $script:exportScript -RepoRoot $consumer -RunPath $runPath `
            -InstalledPluginVersion '1.0.55' | Out-Null
        $artifact = [System.IO.File]::ReadAllText($artifactPath) | ConvertFrom-Json -Depth 100
        $artifact.payload.source.repoId = 'tampered/repo'
        [System.IO.File]::WriteAllText(
            $artifactPath,
            (($artifact | ConvertTo-Json -Depth 100 -Compress) + "`n"),
            [System.Text.UTF8Encoding]::new($false)
        )
        { & $script:handoffScript -ArtifactPath $artifactPath `
                -UpstreamRoot $upstream -ExpectedUpstreamHost github.com `
                -ExpectedUpstreamRepository upstream/customizations `
                -WorkSize Small } | Should -Throw '*content-addressed replay check*'

        & $script:exportScript -RepoRoot $consumer -RunPath $runPath `
            -InstalledPluginVersion '1.0.55' | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $upstream 'dirty.txt'), 'dirty')
        { & $script:handoffScript -ArtifactPath $artifactPath `
                -UpstreamRoot $upstream -ExpectedUpstreamHost github.com `
                -ExpectedUpstreamRepository upstream/customizations `
                -WorkSize Small } | Should -Throw '*must be clean*'
    }
}
