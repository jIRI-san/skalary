#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'architecture-test retirement baseline' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:fixtureRoot = Join-Path $script:repoRoot 'tests/skalary/fixtures/plugin-retirement/architecture-tests-pre-cda9da-v1'
        $script:historicalManifest = Join-Path $script:repoRoot 'tests/skalary/fixtures/plugin-retirement/cda9da-historical-manifest.json'
        $script:manifestGate = Join-Path $script:repoRoot 'scripts/skalary/Test-HistoricalManifest.ps1'
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
            (& $script:manifestGate -ManifestPath $tempManifest -RepoRoot $script:repoRoot).Count |
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
