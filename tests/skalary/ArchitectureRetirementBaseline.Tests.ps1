#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'architecture-test retirement baseline' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:fixtureRoot = Join-Path $script:repoRoot 'tests/skalary/fixtures/plugin-retirement/architecture-tests-pre-cda9da-v1'
        $script:historicalManifest = Join-Path $script:repoRoot 'tests/skalary/fixtures/plugin-retirement/cda9da-historical-manifest.json'
        $script:manifestGate = Join-Path $script:repoRoot 'scripts/skalary/Test-HistoricalManifest.ps1'

        function Get-RetiredArchitectureRuntimeViolation {
            param(
                [Parameter(Mandatory)]
                [string]$Root,

                [Parameter(Mandatory)]
                [AllowEmptyCollection()]
                [string[]]$IncludePath
            )

            if ($IncludePath.Count -eq 0) {
                throw 'Architecture runtime scan requires at least one include root.'
            }

            $resolvedRoot = [System.IO.Path]::GetFullPath($Root)
            $rootPrefix = $resolvedRoot.TrimEnd(
                [System.IO.Path]::DirectorySeparatorChar,
                [System.IO.Path]::AltDirectorySeparatorChar
            ) + [System.IO.Path]::DirectorySeparatorChar
            $files = [System.Collections.Generic.List[System.IO.FileInfo]]::new()

            foreach ($include in $IncludePath) {
                if ([System.IO.Path]::IsPathRooted($include)) {
                    throw "Architecture runtime scan include must be repository-relative: '$include'."
                }
                $resolvedInclude = [System.IO.Path]::GetFullPath((Join-Path $resolvedRoot $include))
                if (-not $resolvedInclude.StartsWith($rootPrefix, [System.StringComparison]::Ordinal)) {
                    throw "Architecture runtime scan include is not confined to the repository: '$include'."
                }
                if (-not (Test-Path -LiteralPath $resolvedInclude)) {
                    throw "Architecture runtime scan include does not exist: '$include'."
                }

                $item = Get-Item -LiteralPath $resolvedInclude -Force
                $ancestor = $item
                while ($null -ne $ancestor) {
                    if (($ancestor.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                        throw "Architecture runtime scan include crosses a reparse point: '$include'."
                    }
                    if ([string]::Equals(
                            [System.IO.Path]::GetFullPath($ancestor.FullName),
                            $resolvedRoot,
                            [System.StringComparison]::Ordinal
                        )) {
                        break
                    }
                    $ancestor = if ($ancestor -is [System.IO.DirectoryInfo]) {
                        $ancestor.Parent
                    }
                    elseif ($ancestor -is [System.IO.FileInfo]) {
                        $ancestor.Directory
                    }
                    else {
                        throw "Architecture runtime scan include has an unsupported filesystem item: '$include'."
                    }
                }

                if ($item.PSIsContainer) {
                    foreach ($descendant in (Get-ChildItem -LiteralPath $resolvedInclude -Force -Recurse)) {
                        if (($descendant.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                            throw "Architecture runtime scan include contains a reparse point: '$include'."
                        }
                        if (-not $descendant.PSIsContainer) {
                            $files.Add($descendant)
                        }
                    }
                }
                else {
                    $files.Add($item)
                }
            }

            $retiredPathPattern = [regex]::new(
                '(^|/)(architecture-tests(/|$)|Invoke-ArchTests\.ps1$|Invoke-ArchAdapter\.ps1$|Get-ArchReviewReport\.ps1$|Assert-ArchLock\.ps1$|ArchReceipt\.psm1$|arch-test-(config|receipt)\.schema\.json$|architecture-tests\.design\.md$)',
                [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
            )
            $violations = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            foreach ($file in $files) {
                $relative = [System.IO.Path]::GetRelativePath($resolvedRoot, $file.FullName).Replace('\', '/')
                if ($retiredPathPattern.IsMatch($relative)) {
                    [void]$violations.Add($relative)
                }
            }
            $ordered = @($violations)
            [Array]::Sort($ordered, [System.StringComparer]::Ordinal)
            return $ordered
        }
    }

    It 'test:ArchitectureTestRetirement.ActiveAndHistoricalBoundary freezes a nonempty pre-retirement fixture' {
        $manifestPath = Join-Path $script:fixtureRoot 'fixture-manifest.json'
        Test-Path -LiteralPath $manifestPath -PathType Leaf | Should -BeTrue
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -Depth 20
        @($manifest.files).Count | Should -BeGreaterThan 0

        $manifestPaths = @($manifest.files | ForEach-Object { [string]$_.path } | Sort-Object)
        $fixturePaths = @(
            Get-ChildItem -LiteralPath $script:fixtureRoot -File -Recurse |
                Where-Object { $_.FullName -ne $manifestPath } |
                ForEach-Object { [System.IO.Path]::GetRelativePath($script:fixtureRoot, $_.FullName).Replace('\', '/') } |
                Sort-Object
        )
        $manifestPaths | Should -Be $fixturePaths

        foreach ($entry in @($manifest.files)) {
            $relative = ([string]$entry.path).Replace('\', '/')
            $relative | Should -Not -Match '(^|/)\.\.(/|$)'
            [System.IO.Path]::IsPathRooted($relative) | Should -BeFalse
            $path = [System.IO.Path]::GetFullPath((Join-Path $script:fixtureRoot $relative))
            $path.StartsWith(
                $script:fixtureRoot + [System.IO.Path]::DirectorySeparatorChar,
                [System.StringComparison]::Ordinal
            ) | Should -BeTrue
            Test-Path -LiteralPath $path -PathType Leaf | Should -BeTrue
            ([System.IO.File]::GetAttributes($path) -band [System.IO.FileAttributes]::ReparsePoint) |
                Should -Be 0
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() |
                Should -Be ([string]$entry.sha256)
        }
    }

    It 'test:ArchitectureTestRetirement.ActiveAndHistoricalBoundary binds copied fixture bytes and generated inventories to the starting state' {
        $fixtureManifest = Get-Content -LiteralPath (Join-Path $script:fixtureRoot 'fixture-manifest.json') -Raw |
            ConvertFrom-Json -Depth 20
        $historicalManifest = Get-Content -LiteralPath $script:historicalManifest -Raw |
            ConvertFrom-Json -Depth 20
        [string]$fixtureManifest.startingCommit | Should -Be ([string]$historicalManifest.startingCommit)

        $sourceFiles = [System.Collections.Generic.List[object]]::new()
        foreach ($entry in @($fixtureManifest.files)) {
            $fixturePath = [string]$entry.path
            $sourcePath = if ($fixturePath -match '^bootstrap/scripts/skalary/(?<leaf>.+)$') {
                "scripts/skalary/$($Matches['leaf'])"
            }
            elseif ($fixturePath -match '^installed-payload/architecture-tests/(?<tail>.+)$') {
                ".github/skills/architecture-tests/$($Matches['tail'])"
            }
            elseif ($fixturePath -eq 'manifest/plugin.json') {
                'plugins/architecture-tests/plugin.json'
            }
            else {
                $null
            }
            if ($sourcePath) {
                $sourceFiles.Add([pscustomobject]@{ path = $sourcePath; sha256 = [string]$entry.sha256 })
            }
        }
        $sourceFiles.Count | Should -BeGreaterThan 20

        $tempManifest = Join-Path ([System.IO.Path]::GetTempPath()) ("fixture-sources-" + [guid]::NewGuid().ToString('N') + '.json')
        try {
            @{
                version        = 1
                startingCommit = [string]$fixtureManifest.startingCommit
                files          = @($sourceFiles)
            } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $tempManifest
            (& $script:manifestGate -ManifestPath $tempManifest -RepoRoot $script:repoRoot -BaselineOnly).Count |
                Should -Be $sourceFiles.Count
        }
        finally {
            Remove-Item -LiteralPath $tempManifest -Force -ErrorAction SilentlyContinue
        }

        $registryEntry = Get-Content -LiteralPath (Join-Path $script:fixtureRoot 'registry/architecture-tests.json') -Raw |
            ConvertFrom-Json -Depth 100
        $receipt = Get-Content -LiteralPath (Join-Path $script:fixtureRoot 'receipt/architecture-tests.json') -Raw |
            ConvertFrom-Json -Depth 100
        $pluginManifest = Get-Content -LiteralPath (Join-Path $script:fixtureRoot 'manifest/plugin.json') -Raw |
            ConvertFrom-Json -Depth 100
        $scaffolds = @(Get-Content -LiteralPath (Join-Path $script:fixtureRoot 'manifest/scaffolds.json') -Raw |
                ConvertFrom-Json -Depth 100)
        $approval = Get-Content -LiteralPath (Join-Path $script:fixtureRoot 'approval/keys.json') -Raw |
            ConvertFrom-Json -Depth 20

        [string]$registryEntry.name | Should -Be 'architecture-tests'
        [string]$receipt.ref | Should -Be ([string]$fixtureManifest.startingCommit)
        @($receipt.files | ForEach-Object { "$($_.dest)|$($_.sha256)" } | Sort-Object) |
            Should -Be @($registryEntry.files | ForEach-Object { "$($_.dest)|$($_.sha256)" } | Sort-Object)
        @($pluginManifest.files | ForEach-Object { [string]$_.dest } | Sort-Object) |
            Should -Be @($registryEntry.files | ForEach-Object { [string]$_.dest } | Sort-Object)
        ($scaffolds | ConvertTo-Json -Depth 20 -Compress) |
            Should -Be (@($registryEntry.scaffolds) | ConvertTo-Json -Depth 20 -Compress)
        @($approval.candidateKeys) |
            Should -Contain '.github/skills/architecture-tests/scripts/Get-ArchReviewReport.ps1'
    }

    It 'test:ArchitectureTestRetirement.ActiveAndHistoricalBoundary rehashes every bounded historical artifact' {
        $result = & $script:manifestGate -ManifestPath $script:historicalManifest -RepoRoot $script:repoRoot
        $result.Count | Should -BeGreaterThan 0
        @($result.Files).Count | Should -Be $result.Count
    }

    It 'test:ArchitectureTestRetirement.ActiveAndHistoricalBoundary scans only explicit active roots and detects seeded runtime assets' {
        $activeIncludes = @(
            'plugins',
            '.github/skills',
            '.github/agents',
            'scripts',
            'schemas',
            'tools',
            'docs/design-notes',
            'README.md'
        )
        @(Get-RetiredArchitectureRuntimeViolation -Root $script:repoRoot -IncludePath $activeIncludes).Count |
            Should -Be 0

        $suffix = [guid]::NewGuid().ToString('N')
        $temp = Join-Path ([System.IO.Path]::GetTempPath()) "architecture-active-scan-$suffix"
        $outside = Join-Path ([System.IO.Path]::GetTempPath()) "architecture-active-outside-$suffix"
        [void](New-Item -ItemType Directory -Path (Join-Path $temp 'plugins/architecture-tests') -Force)
        [void](New-Item -ItemType Directory -Path (Join-Path $temp 'plugins/.hidden') -Force)
        [void](New-Item -ItemType Directory -Path $outside -Force)
        try {
            Set-Content -LiteralPath (Join-Path $temp 'plugins/architecture-tests/plugin.json') -Value '{}' -NoNewline
            Set-Content -LiteralPath (Join-Path $temp 'plugins/.hidden/Invoke-ArchTests.ps1') -Value '# retired' -NoNewline
            @(Get-RetiredArchitectureRuntimeViolation -Root $temp -IncludePath @('plugins')) |
                Should -Be @(
                    'plugins/.hidden/Invoke-ArchTests.ps1',
                    'plugins/architecture-tests/plugin.json'
                )
            { Get-RetiredArchitectureRuntimeViolation -Root $temp -IncludePath @() } |
                Should -Throw '*at least one include root*'
            { Get-RetiredArchitectureRuntimeViolation -Root $temp -IncludePath @('../outside') } |
                Should -Throw '*not confined*'

            $linkType = if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }
            [void](New-Item -ItemType $linkType -Path (Join-Path $temp 'plugins/reparse') -Target $outside)
            { Get-RetiredArchitectureRuntimeViolation -Root $temp -IncludePath @('plugins') } |
                Should -Throw '*contains a reparse point*'
        }
        finally {
            Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $outside -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:PluginRetirement.ReaderRemovalAndResultContract caps process coverage at four launches with one shared timeout' {
        $retirementTestPaths = @(
            'tests/skalary/ArchitectureTestRetirement.Tests.ps1',
            'tests/skalary/PluginRetirement.Tests.ps1'
        )
        $commands = foreach ($relativePath in $retirementTestPaths) {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                (Join-Path $script:repoRoot $relativePath),
                [ref]$tokens,
                [ref]$errors
            )
            @($errors).Count | Should -Be 0
            $ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst]
                }, $true)
        }
        $normalLaunches = @($commands | Where-Object {
                $_.GetCommandName() -ceq 'Invoke-SuiteFixtureProcess'
            }).Count
        $hardKills = @($commands | Where-Object {
                $_.GetCommandName() -ceq 'Start-Process' -and
                $_.Extent.Text -match '^Start-Process\s+pwsh\b'
            }).Count
        $unboundedPwsh = @($commands | Where-Object { $_.GetCommandName() -ceq 'pwsh' }).Count

        $normalLaunches | Should -Be 3
        $hardKills | Should -Be 1
        ($normalLaunches + $hardKills) | Should -BeLessOrEqual 4
        $unboundedPwsh | Should -Be 0
        (Get-Content -LiteralPath (Join-Path $script:repoRoot $retirementTestPaths[1]) -Raw) |
            Should -Match 'AddSeconds\(\(Get-SuiteFixtureProcessTimeoutSeconds\)\)'

        $fixtureModule = Get-Content -LiteralPath (Join-Path $script:repoRoot 'tests/SuiteFixture.psm1') -Raw
        $fixtureModule | Should -Match '\$script:FixtureProcessTimeoutSeconds\s*=\s*30'
        $fixtureModule | Should -Match '\$process\.WaitForExit\(\$TimeoutSeconds \* 1000\)'
        $fixtureModule | Should -Match '\$process\.Kill\(\$true\)'
    }

    It 'test:ArchitectureTestRetirement.ActiveAndHistoricalBoundary rejects mutation of a listed file' {
        $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("historical-mutation-" + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $temp -Force)
        try {
            git -C $temp init --quiet
            git -C $temp config user.email 'fixture@example.invalid'
            git -C $temp config user.name 'Fixture'
            Set-Content -LiteralPath (Join-Path $temp 'historical.md') -Value 'original' -NoNewline
            git -C $temp add historical.md
            git -C $temp commit --quiet -m baseline
            $commit = (git -C $temp rev-parse HEAD).Trim()
            $hash = (Get-FileHash -LiteralPath (Join-Path $temp 'historical.md') -Algorithm SHA256).Hash.ToLowerInvariant()
            @{
                version        = 1
                startingCommit = $commit
                files          = @(@{ path = 'historical.md'; sha256 = $hash })
            } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $temp 'manifest.json')

            $target = Join-Path $temp 'historical.md'
            Add-Content -LiteralPath $target -Value 'mutation'
            {
                & $script:manifestGate -ManifestPath (Join-Path $temp 'manifest.json') -RepoRoot $temp
            } | Should -Throw '*hash mismatch*'
        }
        finally {
            Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:ArchitectureTestRetirement.ActiveAndHistoricalBoundary rejects an empty historical manifest' {
        $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("historical-empty-" + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $temp -Force)
        try {
            @{
                version        = 1
                startingCommit = 'a' * 40
                files          = @()
            } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $temp 'manifest.json')
            {
                & $script:manifestGate -ManifestPath (Join-Path $temp 'manifest.json') -RepoRoot $temp
            } | Should -Throw '*at least one file*'
        }
        finally {
            Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
