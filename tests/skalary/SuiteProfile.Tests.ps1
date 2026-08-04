#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'suite cost model' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:profilePath = Join-Path $script:repoRoot 'tools/suite-profile.json'
        $script:costlyOperations = @('New-RepoClone', 'Install-Plugin', 'Build-Registry', 'Test-Registry')

        $script:suiteProfile = $null
        if (Test-Path -LiteralPath $script:profilePath -PathType Leaf) {
            $script:suiteProfile = Get-Content -LiteralPath $script:profilePath -Raw | ConvertFrom-Json
        }

        function Get-ProfiledOperation {
            param([string]$Name)
            return @($script:suiteProfile.operations | Where-Object { [string]$_.operation -eq $Name })
        }

        function Get-TestSubtree {
            param([string]$RelativePath)
            $parts = ($RelativePath -replace '\\', '/').Split('/')
            if ($parts.Count -lt 2) { return $parts[0] }
            return "$($parts[0])/$($parts[1])"
        }
    }

    It 'test:SuiteProfile.RecordsPerOperationCosts records call counts and aggregate seconds per costly operation' {
        Test-Path -LiteralPath $script:profilePath -PathType Leaf |
            Should -BeTrue -Because 'tools/suite-profile.json is the measured cost model REQ-1 requires'
        [string]$script:suiteProfile.schema | Should -Be 'skalary/suite-profile@1'

        foreach ($operation in $script:costlyOperations) {
            $entry = @(Get-ProfiledOperation -Name $operation)
            $entry.Count | Should -Be 1 -Because "'$operation' must appear exactly once in the cost model"

            [int]$entry[0].count | Should -BeGreaterThan 0 -Because "'$operation' must have a measured call count"
            [double]$entry[0].totalSeconds | Should -BeGreaterThan 0 -Because "'$operation' must have measured aggregate seconds"
            [double]$entry[0].meanSeconds | Should -BeGreaterThan 0

            $sources = @($entry[0].sources)
            $sources.Count | Should -BeGreaterThan 0 -Because "'$operation' costs must be attributable to a test file"
            foreach ($source in $sources) {
                [string]$source.source | Should -Match '^tests/'
                [int]$source.count | Should -BeGreaterThan 0
            }
        }

        # A profile that recorded one call per operation would be a smoke test, not a cost model.
        [int]@(Get-ProfiledOperation -Name 'New-RepoClone')[0].count |
            Should -BeGreaterThan 1 -Because 'the clone cost is a repetition cost'

        [double]$script:suiteProfile.run.instrumentedSeconds | Should -BeGreaterThan 0
        [double]$script:suiteProfile.run.instrumentedSeconds |
            Should -BeLessOrEqual ([double]$script:suiteProfile.run.wallClockSeconds) -Because 'instrumented time is a subset of the run'
    }

    It 'test:SuiteProfile.CoversWholeTestTree profiles every test subtree rather than a single file' {
        [string]$script:suiteProfile.scope.root | Should -Be 'tests'
        [string]$script:suiteProfile.scope.pattern | Should -Be '*.Tests.ps1'

        $profiledFiles = @($script:suiteProfile.scope.testFiles)
        [int]$script:suiteProfile.scope.fileCount | Should -Be $profiledFiles.Count
        $profiledFiles.Count | Should -BeGreaterThan 1

        $testRoot = Join-Path $script:repoRoot 'tests'
        $actualFiles = @(
            Get-ChildItem -LiteralPath $testRoot -Recurse -File -Filter '*.Tests.ps1' |
                ForEach-Object { ($_.FullName.Substring($script:repoRoot.Length).TrimStart([char]'/', [char]'\')) -replace '\\', '/' }
        )

        # Whole-tree scope is asserted per subtree, not per file: an added or removed test file
        # is a coverage question (REQ-3 owns it), while a missing subtree means the profile was
        # taken over part of the tree.
        $actualSubtrees = @($actualFiles | ForEach-Object { Get-TestSubtree $_ } | Sort-Object -Unique)
        $profiledSubtrees = @($profiledFiles | ForEach-Object { Get-TestSubtree $_ } | Sort-Object -Unique)
        $profiledSubtrees | Should -Be $actualSubtrees -Because 'every subtree under tests/ must be in the profiled scope'

        foreach ($file in $profiledFiles) {
            [string]$file | Should -Match '^tests/.+\.Tests\.ps1$'
        }

        [int]$script:suiteProfile.run.totalTests | Should -BeGreaterThan 0
        @($script:suiteProfile.files).Count | Should -BeGreaterThan 1 -Because 'the per-file breakdown locates where the runtime sits'
        [string]$script:suiteProfile.run.budgetCommand | Should -Be 'npm test'
        @($script:suiteProfile.phases).Count | Should -BeGreaterThan 0 -Because 'each reduction phase records its achieved figure here'
    }

    It 'test:SuiteProfile.PhaseTargetsMet fails a reduction phase that missed the saving it declared' {
        # D4: each reduction phase declares a required saving and a stop condition. A stop
        # condition recorded only in prose stops nothing, so the recorded rows are the gate.
        $phases = @($script:suiteProfile.phases)
        $phases.Count | Should -BeGreaterThan 0

        $misses = [System.Collections.Generic.List[string]]::new()
        foreach ($row in $phases) {
            $names = $row.PSObject.Properties.Name
            foreach ($field in @('phase', 'label', 'scope', 'baselineSeconds', 'scopeSeconds', 'targetSavingSeconds', 'achievedSavingSeconds', 'metTarget', 'note')) {
                $names | Should -Contain $field -Because "phase row $([int]$row.phase) must record '$field'"
            }

            $target = [double]$row.targetSavingSeconds
            $achieved = [double]$row.achievedSavingSeconds

            # metTarget is recomputed from the two figures rather than trusted: a hand-edited
            # flag would otherwise turn a missed target into a passing gate.
            [bool]$row.metTarget |
                Should -Be ($achieved -ge $target) -Because "phase $([int]$row.phase)'s metTarget must follow from its own numbers"

            if ($target -le 0) { continue }

            # A declared target has to be measured against something. A zero baseline would
            # score the phase against nothing and read as a saving of whatever it cost.
            [double]$row.baselineSeconds |
                Should -BeGreaterThan 0 -Because "phase $([int]$row.phase) declared a target, so it must record what it was measured against"

            if ($achieved -lt $target) {
                $misses.Add("phase $([int]$row.phase) saved $($achieved)s of $($target)s on '$([string]$row.scope)'")
            }
        }

        $misses -join '; ' |
            Should -BeNullOrEmpty -Because 'a phase that misses its declared target escalates rather than continuing'
    }
}
