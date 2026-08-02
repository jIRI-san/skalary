#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'suite fixture' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        Import-Module (Join-Path $PSScriptRoot '..' 'SuiteFixture.psm1') -Force -DisableNameChecking

        $script:fixtureRoots = [System.Collections.Generic.List[string]]::new()

        # One fixture per case: a shared fixture that one case mutates makes the next case's
        # failure a lie about the fixture rather than about the code (RISK-1).
        function New-CaseFixture {
            $path = New-SkalaryFixtureRepo -ProjectRoot $script:repoRoot
            $script:fixtureRoots.Add($path)
            return $path
        }
    }

    AfterAll {
        foreach ($root in $script:fixtureRoots) {
            if (Test-Path -LiteralPath $root -PathType Container) {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'test:SuiteFixture.CarriesTagsForVersionResolution keeps the tag Build-Registry resolves the bootstrap ref from' {
        # RISK-12: dropping tags costs nothing a test-name inventory can see. Build-Registry
        # falls straight back to a raw SHA, so the fixture would keep passing while no longer
        # exercising version resolution at all.
        $fixture = New-CaseFixture
        $tags = @(git -C $fixture tag --points-at HEAD | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $tags.Count | Should -BeGreaterThan 0 -Because 'the synthetic fixture must carry git tag data'
        $tags | Should -Contain (Get-SkalaryFixtureTag)

        # Prove the tag is load-bearing rather than merely present: with no recorded bootstrap
        # ref to inherit, Build-Registry must resolve the version from the tag, not from a SHA.
        $registryPath = Join-Path $fixture 'registry.json'
        Remove-Item -LiteralPath $registryPath -Force

        Push-Location -LiteralPath $fixture
        try {
            & (Join-Path $fixture 'scripts/skalary/Build-Registry.ps1') -RepoRoot $fixture | Out-Null
        }
        finally {
            Pop-Location
        }

        $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json -Depth 100
        [string]$registry.bootstrap.ref | Should -Be (Get-SkalaryFixtureTag) -Because 'the bootstrap ref resolves from the tag at HEAD'
    }

    It 'test:SuiteFixture.PayloadIsAnAllowlist carries the roots the registry scripts read and none of the history' {
        $fixture = New-CaseFixture
        $payload = @(Get-SkalaryFixturePayload)
        $payload.Count | Should -BeGreaterThan 0

        foreach ($relative in $payload) {
            Test-Path -LiteralPath (Join-Path $fixture $relative) |
                Should -BeTrue -Because "the fixture must carry the payload root '$relative'"
        }

        # The point of the synthetic fixture is what it does *not* carry: the project history
        # and the trees the scripts under test never read.
        @(git -C $fixture rev-list --count HEAD)[0] |
            Should -Be '1' -Because 'the fixture is a single synthetic commit, not the project history'

        $tracked = @(git -C $fixture ls-files)
        $tracked.Count | Should -BeGreaterThan 0
        $unexpected = @($tracked | Where-Object {
                $path = $_
                -not @($payload | Where-Object { $path -eq $_ -or $path.StartsWith("$_/", [System.StringComparison]::Ordinal) })
            })
        $unexpected -join '; ' | Should -BeNullOrEmpty -Because 'the fixture tracks only allowlisted payload'
    }

    It 'test:SuiteFixture.CommitIsDeterministic gives every fixture the same commit so registry parity still runs' {
        # Install-Plugin only checks source/target registry parity when the source commit is an
        # object in the target repo. The clone-based fixture got that for free; the synthetic one
        # keeps it by building byte-identical commits.
        $first = New-CaseFixture
        $second = New-CaseFixture

        $firstSha = (git -C $first rev-parse HEAD).Trim()
        $secondSha = (git -C $second rev-parse HEAD).Trim()
        $firstSha | Should -Be $secondSha

        git -C $second cat-file -e "$firstSha^{commit}" 2>$null
        $LASTEXITCODE | Should -Be 0 -Because 'the target repo must be able to read the source commit'
    }
}
