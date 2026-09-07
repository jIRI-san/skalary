#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'retired architecture-test surface' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:retiredPathPattern = [regex]::new(
            '(^|/)(architecture-tests(/|$)|Invoke-ArchTests\.ps1$|Invoke-ArchAdapter\.ps1$|' +
            'Get-ArchReviewReport\.ps1$|Assert-ArchLock\.ps1$|ArchReceipt\.psm1$|' +
            'arch-test-(config|receipt)\.schema\.json$|architecture-tests\.design\.md$)',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )

        function Get-RetiredArchitecturePath {
            param(
                [Parameter(Mandatory)][string]$Root,
                [Parameter(Mandatory)][string[]]$IncludePath
            )

            if ($IncludePath.Count -eq 0) {
                throw 'Architecture retirement scan requires at least one include root.'
            }

            $resolvedRoot = [System.IO.Path]::GetFullPath($Root)
            $prefix = $resolvedRoot.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
            $violations = [System.Collections.Generic.HashSet[string]]::new(
                [System.StringComparer]::Ordinal
            )

            foreach ($include in $IncludePath) {
                if ([System.IO.Path]::IsPathRooted($include)) {
                    throw "Architecture retirement scan include must be repository-relative: '$include'."
                }
                $path = [System.IO.Path]::GetFullPath((Join-Path $resolvedRoot $include))
                if (-not $path.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
                    throw "Architecture retirement scan include is not confined to the repository: '$include'."
                }
                if (-not (Test-Path -LiteralPath $path)) {
                    throw "Architecture retirement scan include does not exist: '$include'."
                }

                foreach ($item in @(Get-Item -LiteralPath $path -Force) +
                    @(Get-ChildItem -LiteralPath $path -Force -Recurse)) {
                    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                        throw "Architecture retirement scan include contains a reparse point: '$include'."
                    }
                    $relative = [System.IO.Path]::GetRelativePath(
                        $resolvedRoot,
                        $item.FullName
                    ).Replace('\', '/')
                    if ($script:retiredPathPattern.IsMatch($relative)) {
                        [void]$violations.Add($relative)
                    }
                }
            }

            return @($violations | Sort-Object)
        }
    }

    It 'test:ArchitectureRetirement.ActiveSurfaceAbsent keeps retired runtime paths out of active roots' {
        $activeRoots = @(
            'plugins',
            '.github/skills',
            '.github/agents',
            'scripts',
            'schemas',
            'tools',
            'docs/design-notes',
            'README.md'
        )

        @(Get-RetiredArchitecturePath -Root $script:repoRoot -IncludePath $activeRoots).Count |
            Should -Be 0
    }

    It 'test:ArchitectureRetirement.ActiveSurfaceAbsent detects representative retired paths' {
        $temp = Join-Path ([System.IO.Path]::GetTempPath()) (
            'architecture-retirement-' + [guid]::NewGuid().ToString('N')
        )
        try {
            $paths = @(
                'plugins/architecture-tests/plugin.json',
                '.github/skills/example/scripts/Invoke-ArchTests.ps1',
                'schemas/architecture/arch-test-config.schema.json'
            )
            foreach ($relative in $paths) {
                $path = Join-Path $temp $relative
                [void](New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force)
                Set-Content -LiteralPath $path -Value '{}' -NoNewline
            }

            Get-RetiredArchitecturePath -Root $temp -IncludePath @(
                'plugins',
                '.github/skills',
                'schemas'
            ) | Should -Be @(
                '.github/skills/example/scripts/Invoke-ArchTests.ps1',
                'plugins/architecture-tests',
                'plugins/architecture-tests/plugin.json',
                'schemas/architecture/arch-test-config.schema.json'
            )
        }
        finally {
            Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
