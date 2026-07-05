#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Copilot CLI marketplace' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:buildScript = Join-Path $script:repoRoot 'scripts/skalary/Build-Marketplace.ps1'
        $script:marketplacePath = Join-Path $script:repoRoot '.github/plugin/marketplace.json'
        $script:tempRoots = [System.Collections.Generic.List[string]]::new()

        # Documented GitHub Copilot CLI marketplace.json field set.
        $script:topLevelFields = @('name', 'owner', 'metadata', 'plugins')
        $script:entryFields = @(
            'name', 'source', 'description', 'version', 'author', 'homepage', 'repository',
            'license', 'keywords', 'category', 'tags', 'commands', 'agents', 'skills',
            'hooks', 'mcpServers', 'lspServers', 'strict'
        )

        function New-MarketFixture {
            $root = Join-Path ([System.IO.Path]::GetTempPath()) ('market-' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            git init -q $root 2>$null | Out-Null
            $script:tempRoots.Add($root)
            foreach ($name in @('alpha', 'beta')) {
                $pdir = Join-Path $root "plugins/$name"
                New-Item -ItemType Directory -Path (Join-Path $pdir 'skills/x') -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $pdir 'skills/x/SKILL.md') -Value "---`nname: x`n---`n# x" -Encoding utf8NoBOM
                $manifest = [ordered]@{
                    name = $name; version = '1.0.0'; description = "d $name"; author = 'x'; license = 'MIT'
                    tags = @('skill'); dependencies = @()
                    files = @(@{ src = 'skills/x/SKILL.md'; dest = "skills/$name/SKILL.md" })
                }
                Set-Content -LiteralPath (Join-Path $pdir 'plugin.json') -Value ($manifest | ConvertTo-Json -Depth 10) -Encoding utf8NoBOM
            }
            return $root
        }
    }

    AfterAll {
        foreach ($r in $script:tempRoots) {
            Remove-Item -LiteralPath $r -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:Marketplace.Generate emits a valid, idempotent marketplace.json' {
        $root = New-MarketFixture
        & $script:buildScript -RepoRoot $root *> $null

        $mp = Join-Path $root '.github/plugin/marketplace.json'
        Test-Path -LiteralPath $mp -PathType Leaf | Should -BeTrue

        $doc = Get-Content -LiteralPath $mp -Raw | ConvertFrom-Json
        [string]$doc.name | Should -Be 'skalary'
        [string]$doc.owner.name | Should -Not -BeNullOrEmpty
        @($doc.plugins).Count | Should -Be 2

        $alpha = @($doc.plugins | Where-Object { [string]$_.name -eq 'alpha' })
        $alpha.Count | Should -Be 1
        [string]$alpha[0].source | Should -Be 'plugins/alpha'
        [bool]$alpha[0].strict | Should -BeFalse

        $first = Get-Content -LiteralPath $mp -Raw
        & $script:buildScript -RepoRoot $root *> $null
        (Get-Content -LiteralPath $mp -Raw) | Should -Be $first
    }

    It 'test:Marketplace.Drift -WhatIf passes in sync and throws on drift' {
        $root = New-MarketFixture
        & $script:buildScript -RepoRoot $root *> $null
        { & $script:buildScript -RepoRoot $root -WhatIf *> $null } | Should -Not -Throw

        $pj = Join-Path $root 'plugins/alpha/plugin.json'
        $m = Get-Content -LiteralPath $pj -Raw | ConvertFrom-Json
        $m.version = '2.0.0'
        Set-Content -LiteralPath $pj -Value ($m | ConvertTo-Json -Depth 10) -Encoding utf8NoBOM
        { & $script:buildScript -RepoRoot $root -WhatIf *> $null } | Should -Throw -ExpectedMessage '*drift*'
    }

    It 'test:Marketplace.CopilotFields the generated marketplace conforms to the Copilot CLI field set' {
        Test-Path -LiteralPath $script:marketplacePath -PathType Leaf | Should -BeTrue
        $doc = Get-Content -LiteralPath $script:marketplacePath -Raw | ConvertFrom-Json

        # Required top-level fields present, and nothing outside the documented set.
        [string]$doc.name | Should -Not -BeNullOrEmpty
        [string]$doc.owner.name | Should -Not -BeNullOrEmpty
        @($doc.plugins).Count | Should -BeGreaterThan 0
        foreach ($prop in $doc.PSObject.Properties.Name) {
            $script:topLevelFields | Should -Contain $prop
        }

        foreach ($entry in $doc.plugins) {
            foreach ($prop in $entry.PSObject.Properties.Name) {
                $script:entryFields | Should -Contain $prop
            }
            [string]$entry.name | Should -Not -BeNullOrEmpty
            [string]$entry.source | Should -Match '^plugins/'
            [bool]$entry.strict | Should -BeFalse

            # source resolves to a real, installable plugin directory.
            $sourceDir = Join-Path $script:repoRoot ([string]$entry.source)
            Test-Path -LiteralPath (Join-Path $sourceDir 'plugin.json') -PathType Leaf | Should -BeTrue
        }
    }
}
