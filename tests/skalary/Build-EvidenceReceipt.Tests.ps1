#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Build-EvidenceReceipt' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $scriptPath = Join-Path $repoRoot 'scripts/skalary/Build-EvidenceReceipt.ps1'
        $sha = 'b46143d406fc88f468f95bdd2d2edb8b29ba9ef2'
        $dash = [char]0x2014
        $check = [char]0x2713
        $cross = [char]0x2717
    }

    It 'test:evidence-receipt-format renders the golden line grammar and aggregates per REQ' {
        $results = @(
            [pscustomobject]@{ Req = 'REQ-1'; Marker = 'file:README.md#exists'; Success = $true }
            [pscustomobject]@{ Req = 'REQ-1'; Marker = 'test:foo'; Success = $true }
            [pscustomobject]@{ Req = 'REQ-2'; Marker = 'test:bar'; Success = $false; Message = 'boom' }
            [pscustomobject]@{ Req = 'REQ-3'; Marker = 'review:dr'; Success = $true; Note = 'no remaining findings' }
        )
        $receipt = & $scriptPath -Result $results -Commit $sha -Phase 2

        $receipt.Lines[0] | Should -BeExactly "$check REQ-1 $dash file:README.md#exists $dash passed $dash $sha"
        $receipt.Lines[2] | Should -BeExactly "$cross REQ-2 $dash test:bar $dash failed: boom $dash $sha"
        $receipt.Lines[3] | Should -BeExactly "$check REQ-3 $dash review:dr $dash passed: no remaining findings $dash $sha"

        $receipt.Text | Should -Match '(?m)^Phase 2 Crosscheck:$'
        $receipt.ReqStatus['REQ-1'] | Should -BeTrue
        $receipt.ReqStatus['REQ-2'] | Should -BeFalse
        $receipt.AllPassed | Should -BeFalse
    }

    It 'test:evidence-receipt-format marks a REQ passed only when all its markers pass' {
        $results = @(
            [pscustomobject]@{ Req = 'REQ-9'; Marker = 'test:a'; Success = $true }
            [pscustomobject]@{ Req = 'REQ-9'; Marker = 'test:b'; Success = $true }
        )
        $receipt = & $scriptPath -Result $results -Commit $sha
        $receipt.ReqStatus['REQ-9'] | Should -BeTrue
        $receipt.AllPassed | Should -BeTrue
        # full HEAD SHA preserved verbatim
        $receipt.Lines[0] | Should -Match ([regex]::Escape($sha) + '$')
    }

    It 'test:evidence-receipt-unrun preserves unrun markers with a cross glyph and blocks the REQ' {
        $results = @(
            [pscustomobject]@{ Req = 'REQ-4'; Marker = 'review:cr'; Success = $null }
            [pscustomobject]@{ Req = 'REQ-4'; Marker = 'test:done'; Success = $true }
        )
        $receipt = & $scriptPath -Result $results -Commit $sha

        $receipt.Lines[0] | Should -BeExactly "$cross REQ-4 $dash review:cr $dash unrun $dash $sha"
        $receipt.Lines.Count | Should -Be 2
        $receipt.ReqStatus['REQ-4'] | Should -BeFalse
        $receipt.AllPassed | Should -BeFalse
    }
}
