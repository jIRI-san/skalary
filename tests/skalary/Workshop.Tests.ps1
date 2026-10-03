#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Workshop skill contracts' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:pluginRoot = Join-Path $script:repoRoot 'plugins/workshop'
        $script:skill = Get-Content -LiteralPath (Join-Path $script:pluginRoot 'skills/ws/SKILL.md') -Raw
        $script:worktrees = Get-Content -LiteralPath (
            Join-Path $script:pluginRoot 'skills/ws/assets/worktrees.md'
        ) -Raw
    }

    It 'test:Workshop.Payload declares the standalone skill and complete asset closure' {
        $manifest = Get-Content -LiteralPath (Join-Path $script:pluginRoot 'plugin.json') -Raw |
            ConvertFrom-Json
        $manifest.name | Should -BeExactly 'workshop'
        @($manifest.dependencies).Count | Should -Be 0
        @($manifest.files).Count | Should -Be 2
        foreach ($file in $manifest.files) {
            Test-Path -LiteralPath (Join-Path $script:pluginRoot $file.src) -PathType Leaf |
                Should -BeTrue
            $file.dest | Should -Not -Match '(^/|\\.\\.|^[A-Za-z]:)'
        }
        $script:skill | Should -Match '(?m)^name: ws\r?$'
        $script:skill | Should -Match '(?m)^user-invocable: true\r?$'
        $script:skill | Should -Match '(?m)^disable-model-invocation: true\r?$'
        $script:skill | Should -Match '\./assets/worktrees\.md'
        [System.Text.Encoding]::UTF8.GetByteCount($script:skill) | Should -BeLessOrEqual 12000
    }

    It 'test:Workshop.ConsumerSmoke loads the installed contract without planning dependencies' {
        Import-Module (Join-Path $PSScriptRoot '..' 'ConsumerInstallFixture.psm1') `
            -Force -DisableNameChecking
        $manifest = Get-Content -LiteralPath (Join-Path $script:pluginRoot 'plugin.json') -Raw |
            ConvertFrom-Json
        $root = Join-Path $TestDrive 'workshop-consumer'
        $files = @(
            foreach ($file in $manifest.files) {
                $source = Join-Path $script:pluginRoot $file.src
                $target = Join-Path (Join-Path $root '.github') $file.dest
                New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
                Copy-Item -LiteralPath $source -Destination $target
                [pscustomobject]@{
                    Install = $true
                    Dest = [string]$file.dest
                    Sha256 = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
                }
            }
        )
        $fixture = [pscustomobject]@{
            Root = $root
            Catalog = [pscustomobject]@{
                Plugins = @([pscustomobject]@{ Name = 'workshop'; Files = $files })
            }
        }

        $result = @(Invoke-ConsumerInstalledSmokeMatrix -Fixture $fixture)
        $result.Count | Should -Be 1
        $result[0].IsClean | Should -BeTrue -Because $result[0].Output
        $result[0].Output.Trim() | Should -BeExactly 'workshop:handoff'
    }
}
