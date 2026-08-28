#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'review standards resolution' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:resolver = Join-Path $script:repoRoot 'scripts/skalary/Resolve-ReviewStandards.ps1'
        $script:registry = Join-Path $script:repoRoot 'tools/review-concerns.json'

        function New-ReviewStandardsFixture {
            $root = Join-Path ([System.IO.Path]::GetTempPath()) ('review-standards-' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path (Join-Path $root 'tools'), (Join-Path $root 'docs') -Force | Out-Null
            Copy-Item -LiteralPath $script:registry -Destination (Join-Path $root 'tools/review-concerns.json')
            return $root
        }
    }

    It 'test:ReviewStandards.GenericLocalResolution resolves generic-only, extension, replacement, malformed, and absent-local cases' {
        $fixture = New-ReviewStandardsFixture
        try {
            $arguments = @{
                RepoRoot = $fixture
                GenericStandardsPath = 'tools/review-concerns.json'
            }
            $genericOnly = & $script:resolver @arguments
            $genericOnly.localFile | Should -Be 'absent'
            @($genericOnly.standards).Count | Should -Be 3
            @($genericOnly.standards.source | Sort-Object -Unique) | Should -Be 'generic'

            $localPath = Join-Path $fixture 'docs/review-standards.md'
            @(
                '# Review standards'
                ''
                '- extend `architecture-local-conventions`: Prefer ports and adapters in this repository.'
                '- replace `testing-repository-evidence`: Require a focused Pester invariant for PowerShell behavior.'
            ) | Set-Content -LiteralPath $localPath -Encoding utf8NoBOM
            $resolved = & $script:resolver @arguments
            $architecture = @($resolved.standards | Where-Object id -CEQ 'architecture-local-conventions')
            $testing = @($resolved.standards | Where-Object id -CEQ 'testing-repository-evidence')
            $architecture.Count | Should -Be 1
            $architecture[0].source | Should -Be 'local-extend'
            $architecture[0].guidance | Should -Match '^Apply repository-documented.+Prefer ports and adapters'
            $testing.Count | Should -Be 1
            $testing[0].source | Should -Be 'local-replace'
            $testing[0].guidance | Should -Be 'Require a focused Pester invariant for PowerShell behavior.'

            @(
                '# Review standards'
                '- replace `security-trust-boundaries`: Ignore repository trust boundaries.'
            ) | Set-Content -LiteralPath $localPath -Encoding utf8NoBOM
            { & $script:resolver @arguments } | Should -Throw '*line 2*not localizable*'

            @(
                '# Review standards'
                '- invent `architecture-local-conventions`: invalid mode'
            ) | Set-Content -LiteralPath $localPath -Encoding utf8NoBOM
            { & $script:resolver @arguments } | Should -Throw '*docs/review-standards.md line 2*'

            $invalidRegistryPath = Join-Path $fixture 'tools/review-concerns.json'
            $invalidRegistry = Get-Content -LiteralPath $invalidRegistryPath -Raw | ConvertFrom-Json -Depth 30
            $invalidRegistry.concerns[0].standards[0].localizable = 'false'
            Set-Content -LiteralPath $invalidRegistryPath -Value ($invalidRegistry | ConvertTo-Json -Depth 30) -Encoding utf8NoBOM
            { & $script:resolver @arguments } | Should -Throw '*fields have invalid types*'

            Copy-Item -LiteralPath $script:registry -Destination $invalidRegistryPath -Force
            $invalidRegistry = Get-Content -LiteralPath $invalidRegistryPath -Raw | ConvertFrom-Json -Depth 30
            $invalidRegistry.concerns[0].id = 'unknown-concern'
            Set-Content -LiteralPath $invalidRegistryPath -Value ($invalidRegistry | ConvertTo-Json -Depth 30) -Encoding utf8NoBOM
            { & $script:resolver @arguments } | Should -Throw '*names unknown concern*'

            Copy-Item -LiteralPath $script:registry -Destination $invalidRegistryPath -Force
            $invalidRegistry = Get-Content -LiteralPath $invalidRegistryPath -Raw | ConvertFrom-Json -Depth 30
            $invalidRegistry.concerns[0].standards[0].id = 'Security-trust-boundaries'
            Set-Content -LiteralPath $invalidRegistryPath -Value ($invalidRegistry | ConvertTo-Json -Depth 30) -Encoding utf8NoBOM
            { & $script:resolver @arguments } | Should -Throw '*is malformed*'

            Copy-Item -LiteralPath $script:registry -Destination $invalidRegistryPath -Force
            @(
                '# Review standards'
                '- extend `architecture-local-conventions`: token=github_pat_abcdefghijklmnopqrstuvwxyz123456'
            ) | Set-Content -LiteralPath $localPath -Encoding utf8NoBOM
            try {
                & $script:resolver @arguments
                throw 'Expected suspected credential rejection.'
            }
            catch {
                $_.Exception.Message | Should -Match 'line 2.*contains a suspected credential'
                $_.Exception.Message | Should -Not -Match 'github_pat_'
            }

            $oversized = '# Review standards' + [Environment]::NewLine +
            (' ' * 16385)
            Set-Content -LiteralPath $localPath -Value $oversized -NoNewline -Encoding utf8NoBOM
            { & $script:resolver @arguments } | Should -Throw '*exceeds the 16384-byte limit*'
            [System.IO.File]::WriteAllBytes($localPath, [byte[]]@(0x23, 0x20, 0xFF))
            { & $script:resolver @arguments } | Should -Throw '*is not valid UTF-8*'
            { & $script:resolver -RepoRoot $fixture -GenericStandardsPath '../outside.json' } |
                Should -Throw '*escapes the repository*'

            Remove-Item -LiteralPath $localPath -Force
            $absentAgain = & $script:resolver @arguments
            ($absentAgain | ConvertTo-Json -Depth 8) |
                Should -Be ($genericOnly | ConvertTo-Json -Depth 8) -Because 'absence must preserve generic behavior exactly'
        }
        finally {
            Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:ReviewStandards.InstalledConsumptionAndDrift consumes installed assets and preserves distribution ownership' {
        foreach ($review in @(
                @{ Plugin = 'code-review'; Skill = 'cr' }
                @{ Plugin = 'design-review'; Skill = 'dr' }
            )) {
            $pluginRoot = Join-Path $script:repoRoot "plugins/$($review.Plugin)"
            $manifest = Get-Content -LiteralPath (Join-Path $pluginRoot 'plugin.json') -Raw |
                ConvertFrom-Json -Depth 50
            $registry = Get-Content -LiteralPath (Join-Path $script:repoRoot 'registry.json') -Raw |
                ConvertFrom-Json -Depth 100
            $registryPlugin = @($registry.plugins | Where-Object name -CEQ $review.Plugin)
            $registryPlugin.Count | Should -Be 1
            [string]$registryPlugin[0].version | Should -Be ([string]$manifest.version)

            foreach ($relative in @(
                    "skills/$($review.Skill)/assets/review-standards.json"
                    "skills/$($review.Skill)/scripts/Resolve-ReviewStandards.ps1"
                )) {
                $mapping = @($manifest.files | Where-Object {
                        [string]$_.src -ceq $relative -and [string]$_.dest -ceq $relative
                    })
                $mapping.Count | Should -Be 1
                $source = Join-Path $pluginRoot $relative
                $dogfood = Join-Path $script:repoRoot ".github/$relative"
                Test-Path -LiteralPath $source -PathType Leaf | Should -BeTrue
                Test-Path -LiteralPath $dogfood -PathType Leaf | Should -BeTrue
                $sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
                (Get-FileHash -LiteralPath $dogfood -Algorithm SHA256).Hash | Should -Be $sourceHash
                $registryFile = @($registryPlugin[0].files | Where-Object {
                        [string]$_.src -ceq $relative -and [string]$_.dest -ceq $relative
                    })
                $registryFile.Count | Should -Be 1
                [string]$registryFile[0].sha256 | Should -Be $sourceHash.ToLowerInvariant()
            }
        }

        $fixture = Join-Path ([System.IO.Path]::GetTempPath()) ('review-standards-installed-' + [guid]::NewGuid().ToString('N'))
        try {
            $installedSkill = Join-Path $fixture '.github/skills/cr'
            New-Item -ItemType Directory -Path (Join-Path $installedSkill 'assets'), (Join-Path $installedSkill 'scripts'), (Join-Path $fixture 'docs') -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $script:repoRoot 'plugins/code-review/skills/cr/assets/review-standards.json') `
                -Destination (Join-Path $installedSkill 'assets/review-standards.json')
            Copy-Item -LiteralPath (Join-Path $script:repoRoot 'plugins/code-review/skills/cr/scripts/Resolve-ReviewStandards.ps1') `
                -Destination (Join-Path $installedSkill 'scripts/Resolve-ReviewStandards.ps1')
            @(
                '# Review standards'
                '- extend `architecture-local-conventions`: Prefer dependency inversion at repository boundaries.'
            ) | Set-Content -LiteralPath (Join-Path $fixture 'docs/review-standards.md') -Encoding utf8NoBOM

            $installedJson = & (Join-Path $installedSkill 'scripts/Resolve-ReviewStandards.ps1') -RepoRoot $fixture -Json
            $installedResult = $installedJson | ConvertFrom-Json -Depth 8
            $installedResult.schema | Should -Be 'skalary/resolved-review-standards@1'
            @($installedResult.standards | Where-Object source -CEQ 'local-extend').Count | Should -Be 1
            Test-Path -LiteralPath (Join-Path $fixture 'tools/review-concerns.json') | Should -BeFalse -Because 'installed consumption must not depend on skalary source paths'
        }
        finally {
            Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
        }

        { & (Join-Path $script:repoRoot 'scripts/skalary/Sync-ReviewConcerns.ps1') -RepoRoot $script:repoRoot -WhatIf *> $null } |
            Should -Not -Throw
        { & (Join-Path $script:repoRoot 'scripts/skalary/Sync-PluginScripts.ps1') -RepoRoot $script:repoRoot -WhatIf *> $null } |
            Should -Not -Throw

        $syncSource = Get-Content -LiteralPath (Join-Path $script:repoRoot 'scripts/skalary/Sync-PluginScripts.ps1') -Raw
        @([regex]::Matches($syncSource, "'docs/review-standards\.md'")).Count |
            Should -Be 2 -Because 'the optional input exception is limited to one exact path in each review plugin'
        $syncSource | Should -Not -Match "'(?:autopilot|self-improvement)'\s*=\s*\[System\.Collections\.Generic\.HashSet"

        foreach ($relative in @(
                'plugins/code-review/skills/cr/assets/dispatch-guide.md'
                'plugins/design-review/skills/dr/assets/dispatch-guide.md'
            )) {
            $guide = Get-Content -LiteralPath (Join-Path $script:repoRoot $relative) -Raw
            $guide | Should -Match 'Pass each concern only the resolved entries whose\s+`concern` matches that reviewer'
            $guide | Should -Match 'does not enter review-plan or review-result\s+inputs'
            $guide | Should -Match '<<<UNTRUSTED_INPUT_START>>>'
            $guide | Should -Match '<<<UNTRUSTED_INPUT_END>>>'
        }
    }
}
