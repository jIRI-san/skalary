#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'skalary plugin registry scripts' {
    BeforeAll {
        $projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $tempRepos = [System.Collections.Generic.List[string]]::new()

        Import-Module (Join-Path $PSScriptRoot '..' 'SuiteFixture.psm1') -Force -DisableNameChecking

        function New-RepoClone {
            <#
            .SYNOPSIS
                Returns a fresh minimal skalary repository for one test case.
            .NOTES
                Synthetic rather than a clone of the project repo: these cases read four
                payload roots, so paying for the whole history and working tree bought
                nothing. The fixture carries a tag because Build-Registry resolves the
                bootstrap ref from tags (RISK-12). Each call is a private copy of a
                template built once, never the template itself (RISK-1).
            #>
            [CmdletBinding()]
            param()

            $path = New-SkalaryFixtureRepo -ProjectRoot $projectRoot
            $tempRepos.Add($path)
            return $path
        }

        function Invoke-ScriptProcess {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [string]$RepoRoot,

                [Parameter(Mandatory)]
                [string]$ScriptName,

                [string]$ScriptRepoRoot = $RepoRoot,

                [string[]]$Arguments = @()
            )

            $scriptPath = Join-Path $ScriptRepoRoot "scripts/skalary/$ScriptName"
            if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
                throw "Script not found: $scriptPath"
            }

            $argList = @('-NoProfile', '-File', $scriptPath, '-RepoRoot', $RepoRoot) + $Arguments
            Push-Location -LiteralPath $RepoRoot
            try {
                $lines = @(& pwsh @argList 2>&1)
            }
            finally {
                Pop-Location
            }

            return [pscustomobject]@{
                ExitCode = $LASTEXITCODE
                Output = ($lines | ForEach-Object { "$_" }) -join "`n"
            }
        }

        function Invoke-SkalaryScript {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [string]$RepoRoot,

                [Parameter(Mandatory)]
                [string]$ScriptName,

                [hashtable]$Parameters = @{}
            )

            $scriptPath = Join-Path $RepoRoot "scripts/skalary/$ScriptName"
            Push-Location -LiteralPath $RepoRoot
            try {
                & $scriptPath -RepoRoot $RepoRoot @Parameters
            }
            finally {
                Pop-Location
            }
        }

        function New-PluginManifest {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [string]$Root,

                [Parameter(Mandatory)]
                [string]$Name,

                [string[]]$Dependencies = @()
            )

            $pluginRoot = Join-Path $Root "plugins/$Name"
            $payloadRoot = Join-Path $pluginRoot 'files'
            [void](New-Item -ItemType Directory -Path $payloadRoot -Force)
            Set-Content -LiteralPath (Join-Path $payloadRoot "$Name.txt") -Value "payload-$Name" -NoNewline -Encoding utf8

            $manifest = [ordered]@{
                name = $Name
                version = '1.0.0'
                description = "test plugin $Name"
                author = 'skalary-tests'
                license = 'MIT'
                tags = @('test')
                dependencies = $Dependencies
                status = 'stable'
                files = @(
                    [ordered]@{
                        src = "files/$Name.txt"
                        dest = "test/$Name.txt"
                    }
                )
                evals = [ordered]@{
                    path = 'evals/'
                    status = 'none'
                    lastRun = $null
                }
            } | ConvertTo-Json -Depth 10

            Set-Content -LiteralPath (Join-Path $pluginRoot 'plugin.json') -Value "$manifest`n" -Encoding utf8
        }

        function New-ConsumerRepo {
            $path = New-SkalaryFixtureRoot -Prefix 'skalary-lifecycle'
            $tempRepos.Add($path)
            git init -q $path
            return $path
        }
    }

    AfterAll {
        foreach ($repo in $tempRepos) {
            if (Test-Path -LiteralPath $repo -PathType Container) {
                # $ErrorActionPreference is 'Stop' here, so one stubborn fixture would otherwise
                # abort the cleanup before the template below is reclaimed.
                Remove-Item -LiteralPath $repo -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        # The template outlives every case fixture, so nothing else would reclaim it.
        Remove-SkalaryFixtureTemplate
    }

    It 'test:PluginLifecycle.Install installs dependencies with minimal receipts into a clean consumer' {
        $source = New-RepoClone
        $target = New-ConsumerRepo

        $install = Invoke-ScriptProcess -RepoRoot $target -ScriptName 'Install-Plugin.ps1' `
            -ScriptRepoRoot $source `
            -Arguments @('-Name', 'continue-implementation', '-Source', $source, '-Ref', 'HEAD')
        $install.ExitCode | Should -Be 0 -Because $install.Output
        Test-Path -LiteralPath (Join-Path $target '.github/skills/ci/SKILL.md') | Should -BeTrue

        $receipts = @(Get-ChildItem -LiteralPath (Join-Path $target '.github/.skalary/receipts') -File -Filter '*.json')
        $receipts.Count | Should -BeGreaterThan 1
        foreach ($receiptPath in $receipts) {
            $receipt = Get-Content -LiteralPath $receiptPath.FullName -Raw | ConvertFrom-Json -Depth 10
            @($receipt.PSObject.Properties.Name | Sort-Object) |
                Should -Be @('name', 'ref', 'sourceIdentity', 'version')
        }

        $rerun = Invoke-ScriptProcess -RepoRoot $target -ScriptName 'Install-Plugin.ps1' `
            -ScriptRepoRoot $source `
            -Arguments @('-Name', 'continue-implementation', '-Source', $source, '-Ref', 'HEAD')
        $rerun.ExitCode | Should -Be 0 -Because $rerun.Output
    }

    It 'test:PluginLifecycle.Remove refuses modified payloads until forced and converges on retry' {
        $source = New-RepoClone
        $target = New-ConsumerRepo
        $install = Invoke-ScriptProcess -RepoRoot $target -ScriptName 'Install-Plugin.ps1' `
            -ScriptRepoRoot $source `
            -Arguments @('-Name', 'code-review', '-Source', $source, '-Ref', 'HEAD')
        $install.ExitCode | Should -Be 0 -Because $install.Output

        $payload = Join-Path $target '.github/agents/cr.agent.md'
        Set-Content -LiteralPath $payload -Value 'changed' -NoNewline -Encoding utf8
        $unforced = Invoke-ScriptProcess -RepoRoot $target -ScriptName 'Remove-Plugin.ps1' `
            -ScriptRepoRoot $source `
            -Arguments @('-Name', 'code-review', '-Source', $source, '-RegistryPath', (Join-Path $source 'registry.json'))
        $unforced.ExitCode | Should -Not -Be 0
        $unforced.Output | Should -Match 'Refusing removal of modified file'
        Test-Path -LiteralPath $payload | Should -BeTrue

        $forced = Invoke-ScriptProcess -RepoRoot $target -ScriptName 'Remove-Plugin.ps1' `
            -ScriptRepoRoot $source `
            -Arguments @('-Name', 'code-review', '-Source', $source, '-RegistryPath', (Join-Path $source 'registry.json'), '-Force')
        $forced.ExitCode | Should -Be 0 -Because $forced.Output
        Test-Path -LiteralPath $payload | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $target '.github/.skalary/receipts/code-review.json') |
            Should -BeFalse
    }
}
