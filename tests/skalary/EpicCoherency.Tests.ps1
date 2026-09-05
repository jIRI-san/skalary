#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Direct epic coherency verdict' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:newEpic = Join-Path $script:repoRoot 'scripts/skalary/New-Epic.ps1'
        $script:roots = [System.Collections.Generic.List[string]]::new()
    }

    AfterEach {
        foreach ($root in @($script:roots)) {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
        $script:roots.Clear()
    }

    It 'accepts a direct source commit and writes no review-run identity' {
        $root = Join-Path $script:repoRoot ('tests\.epic-direct-' + [guid]::NewGuid().ToString('N'))
        $script:roots.Add($root)
        New-Item -ItemType Directory -Path (Join-Path $root 'docs\implementation-plans\epics') -Force |
            Out-Null
        $created = & $script:newEpic -Title 'Fixture epic' -Slug fixture-epic -EpicId abc123 `
            -Date 2026-08-14 -RepoRoot $root
        $bytes = [System.IO.File]::ReadAllBytes($created.EpicFile)
        $digest = 'sha256:' + [Convert]::ToHexString(
            [System.Security.Cryptography.SHA256]::HashData($bytes)
        ).ToLowerInvariant()
        $verdict = [ordered]@{
            schema = 'skalary/epic-coherency-verdict@2'
            sourceDigest = $digest
            sourceCommit = ('1' * 40)
            decision = 'keep'
            blocking = $false
            action = 'Keep the accepted cut.'
            findings = @()
        } | ConvertTo-Json -Compress

        & $script:newEpic -Epic abc123 -SetCoherencyVerdict -VerdictJson $verdict `
            -RepoRoot $root | Out-Null
        $content = Get-Content -LiteralPath $created.EpicFile -Raw
        $content | Should -Match 'skalary/epic-coherency-verdict@2'
        $content | Should -Match 'Reviewed source: `1111111111111111111111111111111111111111`'
        $content | Should -Not -Match 'Review run|reviewRunId'
    }

    It 'rejects a short source commit before mutation' {
        $root = Join-Path $script:repoRoot ('tests\.epic-direct-' + [guid]::NewGuid().ToString('N'))
        $script:roots.Add($root)
        New-Item -ItemType Directory -Path (Join-Path $root 'docs\implementation-plans\epics') -Force |
            Out-Null
        $created = & $script:newEpic -Title 'Fixture epic' -Slug fixture-epic -EpicId abc123 `
            -Date 2026-08-14 -RepoRoot $root
        $before = Get-Content -LiteralPath $created.EpicFile -Raw
        $digest = 'sha256:' + ('1' * 64)
        $verdict = [ordered]@{
            schema = 'skalary/epic-coherency-verdict@2'
            sourceDigest = $digest
            sourceCommit = 'abc123'
            decision = 'keep'
            blocking = $false
            action = 'Keep.'
            findings = @()
        } | ConvertTo-Json -Compress
        {
            & $script:newEpic -Epic abc123 -SetCoherencyVerdict -VerdictJson $verdict `
                -RepoRoot $root
        } | Should -Throw '*sourceCommit*'
        (Get-Content -LiteralPath $created.EpicFile -Raw) | Should -BeExactly $before
    }
}
