#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# RISK-1: the suite got fast by building each fixture once and copying it per case, so the
# thing that has to be proven is that sharing the *construction* did not become sharing the
# *tree*. Hashing a fixture cannot prove it — `.git` mutates on its own, so a whole-tree hash
# false-fails — and asserting that two roots differ only catches the crudest form. What
# detects ordering dependence is running the cases in a different order and getting the same
# answers.
#
# Two properties have to hold together, and each is worthless alone:
#   - reordering the probes does not change any probe's answer, and
#   - every probe *would* have answered differently against a tree a neighbour had touched.
# The second is what keeps the first from passing because the probes are blind, so each probe
# ships with the mutation that changes its answer and is run against it.
Describe 'suite ordering' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        Import-Module (Join-Path $PSScriptRoot '..' 'SuiteFixture.psm1') -Force -DisableNameChecking
        Import-Module (Join-Path $PSScriptRoot '..' 'SuiteScriptHost.psm1') -Force -DisableNameChecking

        $script:roots = [System.Collections.Generic.List[string]]::new()
        $script:scriptRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("suite-ordering-" + [Guid]::NewGuid().ToString('n'))
        [void](New-Item -ItemType Directory -Path $script:scriptRoot -Force)

        function Script:New-OrderingFixture {
            $path = New-SkalaryFixtureRepo -ProjectRoot $script:repoRoot -Prefix 'suite-ordering'
            $script:roots.Add($path)
            return $path
        }

        function Script:New-OrderingScript {
            param(
                [Parameter(Mandatory)][string]$Name,
                [Parameter(Mandatory)][string]$Body
            )

            $path = Join-Path $script:scriptRoot "$Name.ps1"
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                Set-Content -LiteralPath $path -Value $Body -Encoding utf8NoBOM
            }
            return $path
        }

        $script:IsolationWriterBody = @'
$global:SuiteOrderingProbe = 'leaked'
exit 0
'@
        $script:IsolationReaderBody = @'
$value = Get-Variable -Name 'SuiteOrderingProbe' -Scope Global -ErrorAction SilentlyContinue
Write-Output $(if ($value) { 'present' } else { 'absent' })
exit 0
'@

        # Each probe is `Read` — the answer, taken over whatever tree the factory hands it —
        # paired with `Taint`, the mutation that must change that answer. `Read` never creates
        # its own fixture, so the same body runs over a pristine tree and over a tainted one;
        # a probe whose answer is a constant fails its own Taint check.
        function Script:Get-OrderingProbes {
            return [ordered]@{
                'registry-plugins' = @{
                    Read = {
                        param($NewFixture)
                        $fixture = & $NewFixture
                        return (@(Get-ChildItem -LiteralPath (Join-Path $fixture 'plugins') -Directory |
                                    ForEach-Object { $_.Name } | Sort-Object -CaseSensitive) -join ',')
                    }
                    Taint = {
                        param($Fixture)
                        Remove-Item -LiteralPath (Join-Path $Fixture 'plugins') -Recurse -Force
                        [void](New-Item -ItemType Directory -Path (Join-Path $Fixture 'plugins'))
                    }
                }

                # RISK-12: Build-Registry resolves the bootstrap ref from the tag at HEAD, and
                # nothing else here would notice the tag going missing.
                'registry-tag' = @{
                    Read = {
                        param($NewFixture)
                        $fixture = & $NewFixture
                        return (@(git -C $fixture tag --points-at HEAD | ForEach-Object { $_.Trim() } |
                                    Where-Object { $_ }) -join ',')
                    }
                    Taint = {
                        param($Fixture)
                        git -C $Fixture tag -d (Get-SkalaryFixtureTag) | Out-Null
                        if ($LASTEXITCODE -ne 0) { throw "Failed to delete the fixture tag in '$Fixture'." }
                    }
                }

                'registry-commit' = @{
                    Read = {
                        param($NewFixture)
                        $fixture = & $NewFixture
                        return (git -C $fixture rev-parse HEAD).Trim()
                    }
                    Taint = {
                        param($Fixture)
                        git -C $Fixture commit --quiet --allow-empty -m 'tainted' | Out-Null
                        if ($LASTEXITCODE -ne 0) { throw "Failed to add a commit in '$Fixture'." }
                    }
                }

                'registry-readme' = @{
                    Read = {
                        param($NewFixture)
                        $fixture = & $NewFixture
                        return (Get-FileHash -LiteralPath (Join-Path $fixture 'README.md') -Algorithm SHA256).Hash
                    }
                    Taint = {
                        param($Fixture)
                        Set-Content -LiteralPath (Join-Path $Fixture 'README.md') -Value 'tainted' -Encoding utf8NoBOM
                    }
                }

                # The destructive one. It exists so the probes above have something to be
                # protected from: whatever runs next must not be able to see this.
                'registry-gutted' = @{
                    Read = {
                        param($NewFixture)
                        $fixture = & $NewFixture
                        Remove-Item -LiteralPath (Join-Path $fixture 'registry.json') -Force -ErrorAction SilentlyContinue
                        Remove-Item -LiteralPath (Join-Path $fixture 'plugins') -Recurse -Force -ErrorAction SilentlyContinue
                        Set-Content -LiteralPath (Join-Path $fixture 'README.md') -Value 'gutted' -Encoding utf8NoBOM
                        return (@(Get-ChildItem -LiteralPath $fixture -Force | ForEach-Object { $_.Name } |
                                    Sort-Object -CaseSensitive) -join ',')
                    }
                    Taint = {
                        param($Fixture)
                        Set-Content -LiteralPath (Join-Path $Fixture 'tainted.md') -Value 'tainted' -Encoding utf8NoBOM
                    }
                }

                # The runspace host replaced a child process, so its isolation is an ordering
                # property too. Split across two probes on purpose: one writes a global, a
                # *different* one reads it. Back to back inside one probe the answer could not
                # depend on position, which is the same vacuous shape as a constant.
                'script-isolation-writer' = @{
                    Read = {
                        param($NewFixture)
                        $path = New-OrderingScript -Name 'ordering-writer' -Body $script:IsolationWriterBody
                        return [string](Invoke-SuiteScript -ScriptPath $path).ExitCode
                    }
                    Taint = $null
                }

                'script-isolation-reader' = @{
                    Read = {
                        param($NewFixture)
                        $path = New-OrderingScript -Name 'ordering-reader' -Body $script:IsolationReaderBody
                        return (Invoke-SuiteScript -ScriptPath $path).Output
                    }
                    Taint = $null
                }
            }
        }

        function Script:Invoke-OrderingProbes {
            param([Parameter(Mandatory)][string[]]$Order)

            $probes = Get-OrderingProbes
            $factory = { New-OrderingFixture }
            $results = [ordered]@{}
            foreach ($name in $Order) {
                $results[$name] = [string](& $probes[$name].Read $factory)
            }
            return $results
        }

        # Fisher-Yates over a local generator. `Get-Random -SetSeed` would replace the
        # session's generator for every later file in the same process — a process-global
        # side effect, in the one file whose subject is state escaping its case.
        function Script:Get-ShuffledOrder {
            param(
                [Parameter(Mandatory)][string[]]$Order,
                [Parameter(Mandatory)][int]$Seed
            )

            $random = [System.Random]::new($Seed)
            $shuffled = [string[]]$Order.Clone()
            for ($i = $shuffled.Count - 1; $i -gt 0; $i--) {
                $j = $random.Next($i + 1)
                $swap = $shuffled[$i]
                $shuffled[$i] = $shuffled[$j]
                $shuffled[$j] = $swap
            }
            return $shuffled
        }
    }

    AfterAll {
        foreach ($root in $script:roots) {
            if (Test-Path -LiteralPath $root) {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        if (Test-Path -LiteralPath $script:scriptRoot) {
            Remove-Item -LiteralPath $script:scriptRoot -Recurse -Force -ErrorAction SilentlyContinue
        }

        Remove-SkalaryFixtureTemplate
    }

    It 'test:SuiteOrdering.RandomisedOrderGivesIdenticalResults' {
        $declared = @((Get-OrderingProbes).Keys)
        $declared.Count | Should -BeGreaterThan 1 -Because 'a single probe cannot be reordered'

        # A fresh seed per run, so the suite keeps sampling arrangements rather than proving
        # one forever; reported on failure so the arrangement that broke is replayable. The
        # identity permutation is redrawn rather than accepted: running the declared order
        # twice would prove nothing about ordering at all.
        $seed = [int](Get-Random -Minimum 0 -Maximum ([int]::MaxValue - 32))
        $shuffled = $null
        for ($attempt = 0; $attempt -lt 32; $attempt++) {
            $candidate = Get-ShuffledOrder -Order $declared -Seed ($seed + $attempt)
            if (($candidate -join ',') -ne ($declared -join ',')) {
                $shuffled = $candidate
                $seed = $seed + $attempt
                break
            }
        }

        ($shuffled -join ',') |
            Should -Not -Be ($declared -join ',') -Because 'the probes must actually be reordered'
        @($shuffled | Sort-Object -CaseSensitive) |
            Should -Be (@($declared | Sort-Object -CaseSensitive)) -Because 'the shuffle must reorder the probes, not change the set'

        $baseline = Invoke-OrderingProbes -Order $declared
        $reordered = Invoke-OrderingProbes -Order $shuffled

        foreach ($name in $declared) {
            $reordered[$name] |
                Should -Be $baseline[$name] -Because "probe '$name' must not depend on what ran before it (seed $seed, order: $($shuffled -join ' -> '))"
        }

        # Run-to-run equality alone would also hold if the runspace host stopped isolating —
        # 'present' twice compares equal. The absolute value is what pins that down.
        $baseline['script-isolation-reader'] |
            Should -Be 'absent' -Because 'a runspace that kept the previous invocation''s globals would read back as present'
    }

    It 'test:SuiteOrdering.ProbesWouldSeeALeak' {
        # Without this, the assertion above passes when the probes are blind: a probe that
        # reports a constant is order-independent for the wrong reason. Every probe carrying
        # a Taint is run — its own body, not a copy of it — over a tree a neighbour has
        # already touched, and must disagree with its pristine answer.
        $probes = Get-OrderingProbes
        $tainted = @($probes.Keys | Where-Object { $probes[$_].Taint })
        $tainted.Count | Should -BeGreaterThan 0

        foreach ($name in $tainted) {
            $probe = $probes[$name]

            $pristineFixture = New-OrderingFixture
            $pristine = [string](& $probe.Read { $pristineFixture }.GetNewClosure())

            $leakedFixture = New-OrderingFixture
            & $probe.Taint $leakedFixture
            $fromLeaked = [string](& $probe.Read { $leakedFixture }.GetNewClosure())

            $fromLeaked |
                Should -Not -Be $pristine -Because "probe '$name' must read the tree it was handed, so a tree a neighbour touched changes its answer"
        }

        # The isolation reader carries no Taint — nothing this file can do to a *tree* changes
        # its answer. Its non-blindness is shown instead by running the same script body in a
        # session that does carry the global: it reports 'present', so the 'absent' above is a
        # reading of the runspace rather than a hard-coded string.
        $readerPath = New-OrderingScript -Name 'ordering-reader' -Body $script:IsolationReaderBody
        $global:SuiteOrderingProbe = 'set by the test host'
        try {
            $inSessionWithTheGlobal = @(& $readerPath) -join ''
        }
        finally {
            Remove-Variable -Name 'SuiteOrderingProbe' -Scope Global -ErrorAction SilentlyContinue
        }

        $inSessionWithTheGlobal | Should -Be 'present' -Because 'the reader reports what it finds, so its ''absent'' is evidence'
    }
}
