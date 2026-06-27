#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Set-PlanStage' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $scriptPath = Join-Path $repoRoot 'scripts/skalary/Set-PlanStage.ps1'

        function New-PlanFile {
            param([string]$Body)
            $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("planstage-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $file = Join-Path $dir 'plan.md'
            Set-Content -LiteralPath $file -Value $Body -Encoding utf8NoBOM
            return $file
        }
    }

    It 'test:set-planstage inserts the anchor after plan-id when absent' {
        $file = New-PlanFile -Body "# 7645b1: Plan`n`n<!-- plan-id: 7645b1 -->`n<!-- execution-mode: manual -->`n`n## Phase 1`n"
        try {
            & $scriptPath -PlanFile $file -Stage 'dr-round-1' | Out-Null
            $text = Get-Content -LiteralPath $file -Raw
            $text | Should -Match '(?m)^<!-- cip-stage: dr-round-1 -->$'
            ([regex]::Matches($text, 'cip-stage:')).Count | Should -Be 1
            # inserted immediately after the plan-id anchor
            $text | Should -Match "(?s)<!-- plan-id: 7645b1 -->\n<!-- cip-stage: dr-round-1 -->"
        }
        finally {
            Remove-Item -LiteralPath (Split-Path $file) -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:set-planstage updates an existing anchor in place and stays idempotent' {
        $file = New-PlanFile -Body "# x: Plan`n<!-- plan-id: abc123 -->`n<!-- cip-stage: drafting -->`n`n## Phase 1`n"
        try {
            & $scriptPath -PlanFile $file -Stage 'dr-round-2' | Out-Null
            $afterFirst = Get-Content -LiteralPath $file -Raw
            $afterFirst | Should -Match '(?m)^<!-- cip-stage: dr-round-2 -->$'
            ([regex]::Matches($afterFirst, 'cip-stage:')).Count | Should -Be 1
            $afterFirst | Should -Not -Match 'drafting'

            & $scriptPath -PlanFile $file -Stage 'dr-round-2' | Out-Null
            $afterSecond = Get-Content -LiteralPath $file -Raw
            $afterSecond | Should -Be $afterFirst
        }
        finally {
            Remove-Item -LiteralPath (Split-Path $file) -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:set-planstage rejects a stage containing markup terminators' {
        $file = New-PlanFile -Body "# x: Plan`n<!-- plan-id: abc123 -->`n"
        try {
            { & $scriptPath -PlanFile $file -Stage 'bad -->' } | Should -Throw
        }
        finally {
            Remove-Item -LiteralPath (Split-Path $file) -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
