#requires -Version 7.0
<#
.SYNOPSIS
    Proves the generated catalogs do not depend on the building host's collation.
.DESCRIPTION
    REQ-7. `Sort-Object` compares strings through the current culture, so the order of
    every list in `registry.json`, `.github/plugin/marketplace.json` and the README
    catalog table used to be a property of whoever ran the build.

    A naive locale test does not catch this: cs-CZ and en-US agree on ordinary
    lowercase-ASCII ids, so the fixture has to be built out of ids the two cultures
    genuinely disagree about (D8) —

      * the Czech digraph `ch`, which cs-CZ treats as one letter sorted after `h`,
      * accents, which cs-CZ sorts apart from their base letter and en-US folds onto it,
      * mixed case, which no culture orders the way an ordinal comparer does.

    The plugin-name grammar is `^[a-z0-9][a-z0-9-]*$`, so accents and capitals cannot
    live in names; they are carried by the tag and file lists, which are sorted by the
    same code path.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'catalog collation stability' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:registryScript = Join-Path $script:repoRoot 'scripts/skalary/Build-Registry.ps1'
        $script:marketplaceScript = Join-Path $script:repoRoot 'scripts/skalary/Build-Marketplace.ps1'
        $script:registryGate = Join-Path $script:repoRoot 'scripts/skalary/Test-Registry.ps1'
        $script:fixtureRoots = [System.Collections.Generic.List[string]]::new()

        # The two cultures the fixture is required to disagree between.
        $script:cultures = @('en-US', 'cs-CZ')

        # `chata` sorts before `cukr` in en-US and after `hrad` in cs-CZ, because Czech
        # collation reads `ch` as a single letter placed between `h` and `i`.
        $script:pluginNames = @('chata', 'cukr', 'hrad', 'ivan')

        # Accents and mixed case, in the two places the manifest grammar allows them.
        $script:divergentTags = @('Zebra', 'zebra', 'cukr', 'čaj', 'chata')
        $script:divergentFileNames = @('Chata.md', 'cukr.md', 'čaj.md', 'hrad.md')

        function New-CollationFixture {
            <#
            .SYNOPSIS
                Builds a git repo whose plugin ids collate differently per culture.
            .NOTES
                `Build-Registry.ps1` runs bare `git` for the bootstrap ref and the origin
                URL, so the fixture needs a real repository, a GitHub origin and a tag on
                HEAD; without the tag the bootstrap ref falls back to a raw SHA (RISK-12).
            #>
            [CmdletBinding()]
            [OutputType([string])]
            param()

            $root = Join-Path ([System.IO.Path]::GetTempPath()) ('skalary-collation-' + [guid]::NewGuid().ToString('N'))
            [void](New-Item -ItemType Directory -Path $root)
            $script:fixtureRoots.Add($root)

            & git -C $root init -b main --quiet 2>&1 | Out-Null
            & git -C $root config user.name 'skalary-tests' | Out-Null
            & git -C $root config user.email 'skalary-tests@example.com' | Out-Null
            & git -C $root config commit.gpgsign false | Out-Null
            & git -C $root remote add origin 'https://github.com/jIRI-san/skalary.git' | Out-Null

            foreach ($name in $script:pluginNames) {
                $pluginRoot = Join-Path $root "plugins/$name"
                $payloadRoot = Join-Path $pluginRoot 'files'
                [void](New-Item -ItemType Directory -Path $payloadRoot -Force)

                $files = @()
                foreach ($fileName in $script:divergentFileNames) {
                    Set-Content -LiteralPath (Join-Path $payloadRoot $fileName) -Value "payload-$name-$fileName" -Encoding utf8NoBOM -NoNewline
                    $files += [ordered]@{ src = "files/$fileName"; dest = "skalary/$name/$fileName" }
                }

                $manifest = [ordered]@{
                    name         = $name
                    version      = '1.0.0'
                    description  = "collation fixture plugin $name"
                    author       = 'skalary-tests'
                    license      = 'MIT'
                    tags         = $script:divergentTags
                    dependencies = @()
                    files        = $files
                }
                Set-Content -LiteralPath (Join-Path $pluginRoot 'plugin.json') `
                    -Value ($manifest | ConvertTo-Json -Depth 10) -Encoding utf8NoBOM
            }

            & git -C $root add -- plugins | Out-Null
            $previousAuthorDate = $env:GIT_AUTHOR_DATE
            $previousCommitterDate = $env:GIT_COMMITTER_DATE
            $env:GIT_AUTHOR_DATE = '2000-01-01T00:00:00+00:00'
            $env:GIT_COMMITTER_DATE = '2000-01-01T00:00:00+00:00'
            try {
                & git -C $root commit --quiet -m 'test: collation fixture' | Out-Null
            }
            finally {
                $env:GIT_AUTHOR_DATE = $previousAuthorDate
                $env:GIT_COMMITTER_DATE = $previousCommitterDate
            }
            & git -C $root tag 'v1.0.0' | Out-Null

            return $root
        }

        function Invoke-WithCulture {
            <#
            .SYNOPSIS
                Runs a script block with the thread culture set, restoring it afterwards.
            #>
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [string]$Culture,

                [Parameter(Mandatory)]
                [scriptblock]$Body
            )

            $thread = [System.Threading.Thread]::CurrentThread
            $previousCulture = $thread.CurrentCulture
            $previousUiCulture = $thread.CurrentUICulture
            $thread.CurrentCulture = [cultureinfo]::GetCultureInfo($Culture)
            $thread.CurrentUICulture = [cultureinfo]::GetCultureInfo($Culture)
            try {
                & $Body
            }
            finally {
                # A leaked culture would silently change how every later case sorts, which is
                # the exact failure this file exists to detect — so it is restored on throw too.
                $thread.CurrentCulture = $previousCulture
                $thread.CurrentUICulture = $previousUiCulture
            }
        }

        function Build-CatalogUnderCulture {
            <#
            .SYNOPSIS
                Regenerates every catalog in the fixture under the given culture.
            #>
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [string]$Root,

                [Parameter(Mandatory)]
                [string]$Culture
            )

            Invoke-WithCulture -Culture $Culture -Body {
                Push-Location -LiteralPath $Root
                try {
                    & $script:registryScript -RepoRoot $Root *> $null
                    & $script:marketplaceScript -RepoRoot $Root *> $null
                }
                finally {
                    Pop-Location
                }
            }
        }

        function Invoke-RegistryGateUnderCulture {
            <#
            .SYNOPSIS
                Runs the registry/README drift gate under the given culture and returns its exit code.
            .NOTES
                The gate re-derives the README catalog block from registry.json and compares
                it with the checked-in one, so it is a second implementation of the same
                ordering. Generating ordinally while verifying by culture would reject a
                correct README on a cs-CZ host, which is the failure REQ-7 names.

                Run out of process because the gate ends in `exit`, which would take the
                Pester run down with it.
            #>
            [CmdletBinding()]
            [OutputType([int])]
            param(
                [Parameter(Mandatory)]
                [string]$Root,

                [Parameter(Mandatory)]
                [string]$Culture
            )

            $command = @"
[System.Threading.Thread]::CurrentThread.CurrentCulture = [cultureinfo]::GetCultureInfo('$Culture')
[System.Threading.Thread]::CurrentThread.CurrentUICulture = [cultureinfo]::GetCultureInfo('$Culture')
Set-Location -LiteralPath '$Root'
& '$($script:registryGate)' -RepoRoot '$Root'
"@
            & pwsh -NoProfile -Command $command *> $null
            return $LASTEXITCODE
        }

        function Get-CatalogOrder {
            <#
            .SYNOPSIS
                Returns the ordered id lists the catalogs carry, keyed by a readable label.
            #>
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [string]$Root
            )

            $registry = Get-Content -LiteralPath (Join-Path $Root 'registry.json') -Raw | ConvertFrom-Json -Depth 100
            $marketplace = Get-Content -LiteralPath (Join-Path $Root '.github/plugin/marketplace.json') -Raw | ConvertFrom-Json -Depth 100
            $firstPlugin = @($registry.plugins)[0]

            return [ordered]@{
                'registry plugin'    = (@($registry.plugins | ForEach-Object { [string]$_.name }) -join ', ')
                'marketplace plugin' = (@($marketplace.plugins | ForEach-Object { [string]$_.name }) -join ', ')
                'tag'                = (@($firstPlugin.tags | ForEach-Object { [string]$_ }) -join ', ')
                'file'               = (@($firstPlugin.files | ForEach-Object { [string]$_.dest }) -join ', ')
            }
        }

        function Get-CatalogHash {
            <#
            .SYNOPSIS
                Returns a byte-exact hex digest of every generated catalog, keyed by repo-relative path.
            #>
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [string]$Root
            )

            $catalogs = @('registry.json', 'README.md', '.github/plugin/marketplace.json')
            $hashByPath = [ordered]@{}
            foreach ($relative in $catalogs) {
                $path = Join-Path $Root $relative
                if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                    throw "Catalog '$relative' was not generated in '$Root'."
                }
                # Hex of the raw bytes, not the parsed content: encoding and newlines are
                # part of "byte-identical", and the CI drift gate compares files, not objects.
                $hashByPath[$relative] = [System.Convert]::ToHexString([System.IO.File]::ReadAllBytes($path))
            }
            return $hashByPath
        }

        function Get-CultureSortedOrder {
            <#
            .SYNOPSIS
                Reproduces the pre-fix ordering: Sort-Object under a given culture.
            #>
            [CmdletBinding()]
            [OutputType([string])]
            param(
                [Parameter(Mandatory)]
                [string[]]$Value,

                [Parameter(Mandatory)]
                [string]$Culture
            )

            return (Invoke-WithCulture -Culture $Culture -Body { ($Value | Sort-Object) -join "`u{241F}" })
        }

        function Get-OrdinalSortedOrder {
            [CmdletBinding()]
            [OutputType([string])]
            param(
                [Parameter(Mandatory)]
                [string[]]$Value
            )

            $copy = [string[]]@($Value)
            [array]::Sort($copy, [System.StringComparer]::Ordinal)
            return ($copy -join "`u{241F}")
        }
    }

    AfterAll {
        foreach ($root in $script:fixtureRoots) {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:BuildRegistry.FixtureIsRedBeforeFix proves the fixture ids collate differently per culture' {
        # Without this the stability assertion is vacuous: it would pass against the
        # unfixed, culture-sensitive code simply because the ids never disagreed.
        $idSets = [ordered]@{
            'plugin names' = $script:pluginNames
            'tags'         = $script:divergentTags
            'file names'   = $script:divergentFileNames
        }

        foreach ($label in $idSets.Keys) {
            $ids = [string[]]$idSets[$label]
            $enUs = Get-CultureSortedOrder -Value $ids -Culture 'en-US'
            $csCz = Get-CultureSortedOrder -Value $ids -Culture 'cs-CZ'

            $enUs | Should -Not -Be $csCz -Because "the $label fixture must genuinely diverge between en-US and cs-CZ, or it cannot demonstrate the bug (D8)"
        }

        # The same ids under the comparer the fix installs: one order, whatever the host.
        $ordinal = Get-OrdinalSortedOrder -Value ([string[]]$script:pluginNames)
        foreach ($culture in $script:cultures) {
            Invoke-WithCulture -Culture $culture -Body {
                $copy = [string[]]@($script:pluginNames)
                [array]::Sort($copy, [System.StringComparer]::Ordinal)
                ($copy -join "`u{241F}") | Should -Be $ordinal -Because 'an ordinal comparer is not a function of the host culture'
            }
        }

        # The thread culture is back where the run found it, so no later case inherits it.
        [System.Threading.Thread]::CurrentThread.CurrentCulture.Name | Should -Not -Be 'cs-CZ'
    }

    It 'test:BuildRegistry.CzechCollationFixtureIsStable rebuilds byte-identical catalogs under cs-CZ and en-US' {
        $root = New-CollationFixture

        Build-CatalogUnderCulture -Root $root -Culture 'en-US'
        $expectedOrder = Get-CatalogOrder -Root $root
        $expected = Get-CatalogHash -Root $root

        # A rebuild, not a second fixture: this is the drift gate's own scenario — a repo
        # built by one contributor, regenerated by another whose host collates differently.
        # It also keeps `generatedAt` out of the comparison, since an unchanged body
        # preserves the prior timestamp and a reordered one does not.
        Build-CatalogUnderCulture -Root $root -Culture 'cs-CZ'
        $actualOrder = Get-CatalogOrder -Root $root
        $actual = Get-CatalogHash -Root $root

        # Asserted before the byte digests so a collation regression reads as the reordered
        # list it is, rather than as the changed `generatedAt` that reordering drags with it.
        foreach ($label in $expectedOrder.Keys) {
            $actualOrder[$label] | Should -Be $expectedOrder[$label] -Because "the $label order must not follow the building host's culture (REQ-7)"
        }

        foreach ($relative in $expected.Keys) {
            $actual[$relative] | Should -Be $expected[$relative] -Because "$relative must be byte-identical whether it was generated under en-US or cs-CZ (REQ-7)"
        }

        # The generator is only half the contract: the drift gate re-derives the README
        # catalog block itself, so it has to accept the catalogs whatever the host collates like.
        foreach ($culture in $script:cultures) {
            Invoke-RegistryGateUnderCulture -Root $root -Culture $culture |
                Should -Be 0 -Because "Test-Registry.ps1 must accept the generated catalogs under $culture (REQ-7)"
        }
    }
}
