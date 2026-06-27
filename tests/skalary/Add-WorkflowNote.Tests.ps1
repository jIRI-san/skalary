#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Add-WorkflowNote' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $scriptPath = Join-Path $repoRoot 'scripts/skalary/Add-WorkflowNote.ps1'

        function New-PlanDir {
            $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("wfnote-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            return $dir
        }
    }

    It 'test:workflownote-init creates the section with a fail-loud placeholder' {
        $dir = New-PlanDir
        try {
            & $scriptPath -Kind CrLog -PlanDir $dir -Phase 1 | Out-Null
            $file = Join-Path $dir 'cr-log.md'
            Test-Path -LiteralPath $file | Should -BeTrue
            $text = Get-Content -LiteralPath $file -Raw
            $text | Should -Match '(?m)^## CR Capture$'
            $text | Should -Match '(?m)^Phase: 1$'
            $text | Should -Match '(?m)^No entries for this phase\.$'
        }
        finally {
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:workflownote-init is idempotent and preserves prior phase sections' {
        $dir = New-PlanDir
        try {
            & $scriptPath -Kind Learnings -PlanDir $dir -Phase 1 | Out-Null
            & $scriptPath -Kind Learnings -PlanDir $dir -Phase 2 | Out-Null
            & $scriptPath -Kind Learnings -PlanDir $dir -Phase 1 | Out-Null
            $text = Get-Content -LiteralPath (Join-Path $dir 'learnings.md') -Raw
            ([regex]::Matches($text, '(?m)^## Learnings Capture$')).Count | Should -Be 2
            ([regex]::Matches($text, '(?m)^Phase: 1$')).Count | Should -Be 1
        }
        finally {
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:workflownote-append replaces the placeholder with a typed-token entry' {
        $dir = New-PlanDir
        try {
            & $scriptPath -Kind CrLog -PlanDir $dir -Phase 2 | Out-Null
            & $scriptPath -Kind CrLog -PlanDir $dir -Phase 2 -Step '2.3' -Sev High -Message 'Null check missing' | Out-Null
            $text = Get-Content -LiteralPath (Join-Path $dir 'cr-log.md') -Raw
            $text | Should -Not -Match 'No entries for this phase'
            $text | Should -Match '(?m)^- \[2\.3\] \[src:code-review\] \[sev:High\] Null check missing$'
        }
        finally {
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:workflownote-append appends additional entries after the first' {
        $dir = New-PlanDir
        try {
            & $scriptPath -Kind Learnings -PlanDir $dir -Phase 3 -Step '3.1' -Trigger 'reusable-pattern' -Message 'First learning' | Out-Null
            & $scriptPath -Kind Learnings -PlanDir $dir -Phase 3 -Step '3.2' -Trigger 'rework>1' -Message 'Second learning' | Out-Null
            $lines = Get-Content -LiteralPath (Join-Path $dir 'learnings.md')
            ($lines | Where-Object { $_ -match '^- \[' }).Count | Should -Be 2
            $lines[-1] | Should -Match '^- \[3\.2\] \[trigger:rework>1\] Second learning$'
        }
        finally {
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:workflownote-sanitize neutralizes brackets, backticks, pipes, middots and newlines in the body' {
        $dir = New-PlanDir
        try {
            $evil = "evil ] [sev:Critical] `code` | pipe " + [char]0x00B7 + " dot`r`ninjected line"
            & $scriptPath -Kind CrLog -PlanDir $dir -Phase 1 -Step '1.1' -Sev Low -Message $evil | Out-Null
            $entry = (Get-Content -LiteralPath (Join-Path $dir 'cr-log.md') | Where-Object { $_ -match '^- \[1\.1\]' })
            @($entry).Count | Should -Be 1
            $entry | Should -Match '^- \[1\.1\] \[src:code-review\] \[sev:Low\] '
            $body = ($entry -split '\[sev:Low\] ', 2)[1]
            $body | Should -Not -Match '[\[\]`|]'
            $body | Should -Not -Match ([char]0x00B7)
            $body | Should -Match 'injected line'
        }
        finally {
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
