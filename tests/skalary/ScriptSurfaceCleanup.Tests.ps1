#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'script surface cleanup' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path

        function Get-ModuleStructure {
            param(
                [Parameter(Mandatory)][string]$Path,
                [Parameter(Mandatory)][string[]]$ExpectedExport
            )

            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $Path,
                [ref]$tokens,
                [ref]$errors
            )
            @($errors).Count | Should -Be 0

            $module = Import-Module $Path -Force -DisableNameChecking -PassThru
            try {
                $exports = @($module.ExportedCommands.Keys | Sort-Object)
                $exports | Should -Be @($ExpectedExport | Sort-Object)
            }
            finally {
                Remove-Module $module.Name -Force
            }

            $functionCount = @($ast.FindAll({
                        param($node)
                        $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
                    }, $true)).Count
            $codeLineCount = @(
                $tokens |
                    Where-Object { $_.Kind -notin @('Comment', 'NewLine', 'EndOfInput') } |
                    ForEach-Object { $_.Extent.StartLineNumber } |
                    Sort-Object -Unique
            ).Count

            return [pscustomobject]@{
                PrivateFunctions = $functionCount - $ExpectedExport.Count
                NonCommentLines = $codeLineCount
            }
        }

        function Get-FileDigest {
            param([Parameter(Mandatory)][string]$RelativePath)
            return (Get-FileHash -LiteralPath (Join-Path $script:repoRoot $RelativePath) `
                    -Algorithm SHA256).Hash
        }
    }

    It 'test:ScriptCleanup.DeadSurfaceAbsent removes unused wrappers' {
        foreach ($relative in @(
                'scripts/skalary/Invoke-PluginRetirementHistoryGate.ps1',
                'scripts/skalary/Test-PluginRetirementHistory.ps1',
                'scripts/skalary/Test-ReviewConsumerInstall.ps1')) {
            Test-Path -LiteralPath (Join-Path $script:repoRoot $relative) | Should -BeFalse
        }
    }

    It 'test:ScriptCleanup.PrefixMigrationRetired removes the completed migration' {
        foreach ($relative in @(
                'scripts/skalary/Migrate-PlanFolderPrefixes.ps1',
                'tests/skalary/Migrate-PlanFolderPrefixes.Tests.ps1')) {
            Test-Path -LiteralPath (Join-Path $script:repoRoot $relative) | Should -BeFalse
        }
    }

    It 'test:ScriptCleanup.CleanSandboxCacheRetained keeps the manual maintenance command installed' {
        $source = 'plugins/autopilot/scripts/clean-sandbox-cache.ps1'
        $installed = '.github/skills/autopilot/scripts/clean-sandbox-cache.ps1'
        Test-Path -LiteralPath (Join-Path $script:repoRoot $source) -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:repoRoot $installed) -PathType Leaf | Should -BeTrue
        Get-FileDigest $source | Should -BeExactly (Get-FileDigest $installed)

        $manifest = Get-Content -LiteralPath (
            Join-Path $script:repoRoot 'plugins/autopilot/plugin.json'
        ) -Raw | ConvertFrom-Json -Depth 30
        @($manifest.files | Where-Object {
                [string]$_.src -eq 'scripts/clean-sandbox-cache.ps1' -and
                [string]$_.dest -eq 'skills/autopilot/scripts/clean-sandbox-cache.ps1'
            }).Count | Should -Be 1
    }

    It 'test:ScriptCleanup.ModuleStructure preserves exports and beats every structural baseline' {
        $modules = @(
            @{
                Path = 'scripts/skalary/EpicAutopilot.psm1'
                MaximumPrivate = 44
                MaximumLines = 2083
                Exports = @('Invoke-EpicAutopilotHostLoop')
            },
            @{
                Path = 'scripts/skalary/WorkHierarchy.psm1'
                MaximumPrivate = 19
                MaximumLines = 1636
                Exports = @(
                    'Add-WorkHierarchyMappingItem',
                    'Assert-WorkHierarchyProvider',
                    'ConvertTo-WorkHierarchyDryRunText',
                    'ConvertTo-WorkHierarchyMappingJson',
                    'ConvertTo-WorkHierarchyProjectionJson',
                    'Get-WorkHierarchyDigest',
                    'Get-WorkHierarchyManagedRegion',
                    'Invoke-WorkHierarchyApply',
                    'Invoke-WorkHierarchyProviderRead',
                    'Invoke-WorkHierarchyProviderWrite',
                    'New-WorkHierarchyDryRun',
                    'New-WorkHierarchyMapping',
                    'New-WorkHierarchyProjection',
                    'New-WorkHierarchyProvider',
                    'Read-WorkHierarchyMappingFile',
                    'Save-WorkHierarchyMappingFile'
                )
            },
            @{
                Path = 'scripts/skalary/DirectWorkflow.psm1'
                MaximumPrivate = 8
                MaximumLines = 708
                Exports = @(
                    'ConvertTo-UntrustedReviewBlock',
                    'Invoke-DirectEvidence',
                    'Resolve-DirectReviewReportPath',
                    'Resolve-DirectReviewStandards',
                    'Test-DirectReviewResult',
                    'Test-PlanCriteriaBaseline',
                    'Write-DirectReviewReport'
                )
            }
        )

        foreach ($spec in $modules) {
            $result = Get-ModuleStructure -Path (Join-Path $script:repoRoot $spec.Path) `
                -ExpectedExport $spec.Exports
            $result.PrivateFunctions | Should -BeLessThan $spec.MaximumPrivate
            $result.NonCommentLines | Should -BeLessThan $spec.MaximumLines
        }
    }

    It 'test:ScriptCleanup.Distribution keeps canonical modules and installed copies byte-identical' {
        $copies = @{
            'scripts/skalary/EpicAutopilot.psm1' = @(
                'plugins/autopilot/skills/autopilot/scripts/EpicAutopilot.psm1',
                '.github/skills/autopilot/scripts/EpicAutopilot.psm1'
            )
            'scripts/skalary/WorkHierarchy.psm1' = @(
                'plugins/work-hierarchy-sync/skills/work-hierarchy-sync/scripts/WorkHierarchy.psm1',
                '.github/skills/work-hierarchy-sync/scripts/WorkHierarchy.psm1'
            )
            'scripts/skalary/DirectWorkflow.psm1' = @(
                'plugins/autopilot/skills/autopilot/scripts/DirectWorkflow.psm1',
                'plugins/code-review/skills/cr/scripts/DirectWorkflow.psm1',
                'plugins/continue-implementation/skills/ci/scripts/DirectWorkflow.psm1',
                'plugins/create-implementation-plan/skills/cep/scripts/DirectWorkflow.psm1',
                'plugins/create-implementation-plan/skills/cip/scripts/DirectWorkflow.psm1',
                'plugins/design-review/skills/dr/scripts/DirectWorkflow.psm1',
                '.github/skills/autopilot/scripts/DirectWorkflow.psm1',
                '.github/skills/cr/scripts/DirectWorkflow.psm1',
                '.github/skills/ci/scripts/DirectWorkflow.psm1',
                '.github/skills/cep/scripts/DirectWorkflow.psm1',
                '.github/skills/cip/scripts/DirectWorkflow.psm1',
                '.github/skills/dr/scripts/DirectWorkflow.psm1'
            )
        }

        foreach ($source in $copies.Keys) {
            $expected = Get-FileDigest $source
            foreach ($copy in $copies[$source]) {
                Test-Path -LiteralPath (Join-Path $script:repoRoot $copy) -PathType Leaf |
                    Should -BeTrue
                Get-FileDigest $copy | Should -BeExactly $expected
            }
        }
    }
}
