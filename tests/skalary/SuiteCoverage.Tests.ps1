#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'suite coverage' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:baselinePath = Join-Path $script:repoRoot 'tools/suite-coverage-baseline.json'
        $script:baseline = $null
        if (Test-Path -LiteralPath $script:baselinePath -PathType Leaf) {
            $script:baseline = Get-Content -LiteralPath $script:baselinePath -Raw | ConvertFrom-Json
        }

        # Live inventory runs in a child process: Pester discovery cannot run inside a Pester run.
        $script:livePath = Join-Path ([System.IO.Path]::GetTempPath()) ('suite-inventory-' + [guid]::NewGuid().ToString('N') + '.json')
        $inventoryScript = Join-Path $script:repoRoot 'scripts/skalary/Get-TestInventory.ps1'
        & pwsh -NoProfile -File $inventoryScript -RepoRoot $script:repoRoot -OutputPath $script:livePath *> $null
        $script:liveExitCode = $LASTEXITCODE

        $script:live = $null
        if (Test-Path -LiteralPath $script:livePath -PathType Leaf) {
            $script:live = Get-Content -LiteralPath $script:livePath -Raw | ConvertFrom-Json
        }

        # Identity is the test name, summed across files: moving a test between files is not a
        # coverage loss, while dropping one of five -TestCases rows is.
        $script:liveCounts = @{}
        foreach ($entry in @($script:live.tests)) {
            $name = [string]$entry.test
            if ($script:liveCounts.ContainsKey($name)) { $script:liveCounts[$name] += [int]$entry.count }
            else { $script:liveCounts[$name] = [int]$entry.count }
        }

        $script:removalsByTest = @{}
        foreach ($removal in @($script:baseline.removals)) {
            $script:removalsByTest[[string]$removal.test] = $removal
        }
    }

    AfterAll {
        Remove-Item -LiteralPath $script:livePath -Force -ErrorAction SilentlyContinue
    }

    It 'test:SuiteCoverage.TestNameInventoryPreserved keeps every baseline test unless its removal is enumerated with a reason' {
        Test-Path -LiteralPath $script:baselinePath -PathType Leaf |
            Should -BeTrue -Because 'tools/suite-coverage-baseline.json is the pre-rewrite inventory REQ-3 requires'
        [string]$script:baseline.schema | Should -Be 'skalary/suite-coverage@1'
        $script:liveExitCode | Should -Be 0 -Because 'the live inventory must be discoverable'
        @($script:baseline.tests).Count | Should -BeGreaterThan 0
        $script:liveCounts.Count | Should -BeGreaterThan 0

        foreach ($removal in @($script:baseline.removals)) {
            [string]$removal.test | Should -Not -BeNullOrEmpty
            [string]$removal.reason | Should -Not -BeNullOrEmpty -Because 'a removed test needs a reason a reader can accept or reject'
            [string]$removal.step | Should -Not -BeNullOrEmpty -Because 'a removal is attributable to the step that made it'
        }

        $baselineCounts = @{}
        foreach ($entry in @($script:baseline.tests)) {
            $name = [string]$entry.test
            if ($baselineCounts.ContainsKey($name)) { $baselineCounts[$name] += [int]$entry.count }
            else { $baselineCounts[$name] = [int]$entry.count }
        }

        $missing = [System.Collections.Generic.List[string]]::new()
        foreach ($name in $baselineCounts.Keys) {
            if ($script:removalsByTest.ContainsKey($name)) { continue }

            if (-not $script:liveCounts.ContainsKey($name)) {
                $missing.Add("$name (gone)")
                continue
            }

            if ($script:liveCounts[$name] -lt $baselineCounts[$name]) {
                $missing.Add("$name ($($script:liveCounts[$name]) of $($baselineCounts[$name]) case(s) left)")
            }
        }

        $missing -join '; ' |
            Should -BeNullOrEmpty -Because 'a test may only disappear through an enumerated removal with a reason'
    }

    It 'test:SuiteCoverage.ConfinementCasesRetained keeps the install-confinement rejection cases' {
        $mustKeep = @($script:baseline.mustKeep)
        $mustKeep.Count | Should -BeGreaterThan 0 -Because 'RISK-2 names the confinement rejection cases must-keep'

        # Named here as well as in the baseline so the guard cannot be emptied by editing data alone.
        $required = @(
            'rejects traversal and rooted destination paths in Test-Registry',
            'fails Test-Registry on destination collisions'
        )
        foreach ($fragment in $required) {
            @($mustKeep | Where-Object { [string]$_.test -like "*$fragment*" }).Count |
                Should -BeGreaterThan 0 -Because "'$fragment' is a must-keep confinement case"
        }

        foreach ($entry in $mustKeep) {
            $name = [string]$entry.test
            [string]$entry.reason | Should -Not -BeNullOrEmpty

            $script:removalsByTest.ContainsKey($name) |
                Should -BeFalse -Because "must-keep test '$name' can never be listed as removed"

            $script:liveCounts.ContainsKey($name) |
                Should -BeTrue -Because "must-keep test '$name' must still be discovered"
            $script:liveCounts[$name] |
                Should -BeGreaterOrEqual ([int]$entry.count) -Because "must-keep test '$name' must keep all of its cases"
        }
    }
}
