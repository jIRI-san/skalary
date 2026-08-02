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

        Remove-SkalaryFixtureTemplate
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

    It 'test:SuiteFixture.CasesGetPrivateCopies keeps one case''s writes out of the next case''s fixture' {
        # RISK-1: the saving comes from building the fixture once, so the thing that has to be
        # proven is that sharing the *construction* did not become sharing the *tree*.
        $first = New-CaseFixture
        $second = New-CaseFixture
        $first | Should -Not -Be $second

        $marker = Join-Path $first 'README.md'
        Set-Content -LiteralPath $marker -Value 'mutated by the first case' -Encoding utf8NoBOM
        Remove-Item -LiteralPath (Join-Path $first 'registry.json') -Force

        Get-Content -LiteralPath (Join-Path $second 'README.md') -Raw |
            Should -Not -Match 'mutated by the first case' -Because 'a case writes into its own copy only'
        Test-Path -LiteralPath (Join-Path $second 'registry.json') -PathType Leaf |
            Should -BeTrue -Because 'a deletion in one case cannot reach another'

        # A hardlinked copy would pass the deletion check above and fail this one, because the
        # in-place write would land on the shared inode.
        (Get-Item -LiteralPath $marker).LinkType |
            Should -BeNullOrEmpty -Because 'the copy is a real byte copy, not a link into a shared tree'

        # Third case built after the mutations: the template it copies must still be pristine.
        $third = New-CaseFixture
        Get-Content -LiteralPath (Join-Path $third 'README.md') -Raw |
            Should -Not -Match 'mutated by the first case' -Because 'the template is never handed to a case'
    }

    It 'test:SuiteFixture.CaseRootIsFresh refuses a root that already exists' {
        # The guarantee above only holds while a case root is unconditionally new, so the
        # refusal is asserted rather than assumed.
        $template = Get-SkalaryFixtureTemplate -ProjectRoot $script:repoRoot
        $template | Should -Not -BeNullOrEmpty

        $occupied = New-SkalaryFixtureRoot -Prefix 'skalary-tests-occupied'
        $script:fixtureRoots.Add($occupied)
        Set-Content -LiteralPath (Join-Path $occupied 'someone-elses-state.txt') -Value 'x' -Encoding utf8NoBOM

        { Copy-SkalaryFixtureTree -Source $template -Destination $occupied } |
            Should -Throw -ExpectedMessage '*Refusing to reuse an existing fixture root*'

        # The refusal is a refusal, not a partial merge into the occupied tree.
        Test-Path -LiteralPath (Join-Path $occupied '.git') |
            Should -BeFalse -Because 'a refused copy writes nothing'

        # Every case root the module hands out is distinct from the template it copied.
        $case = New-CaseFixture
        $case | Should -Not -Be $template
        Test-Path -LiteralPath $template -PathType Container |
            Should -BeTrue -Because 'the template survives the cases built from it'
    }
}
