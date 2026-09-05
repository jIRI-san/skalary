#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Plugin script bundling' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:scriptsSource = Join-Path $repoRoot 'scripts/skalary'
        $script:syncScript = Join-Path $repoRoot 'scripts/skalary/Sync-PluginScripts.ps1'
        $script:refRegex = [regex]'\.github/skills/(?<skill>[a-z0-9][a-z0-9-]*)/scripts/(?<name>[A-Za-z0-9][A-Za-z0-9._-]*\.psm?1)'
        $script:moduleRegex = [regex]'\$PSScriptRoot\s+''(?<mod>[A-Za-z0-9_][A-Za-z0-9._-]*\.psm?1)'''

        $script:bundlePlugins = @(
            [pscustomobject]@{ Plugin = 'continue-implementation'; Skill = 'ci' },
            [pscustomobject]@{ Plugin = 'create-implementation-plan'; Skill = 'cip' },
            [pscustomobject]@{ Plugin = 'code-review'; Skill = 'cr' },
            [pscustomobject]@{ Plugin = 'design-review'; Skill = 'dr' },
            [pscustomobject]@{ Plugin = 'work-hierarchy-sync'; Skill = 'work-hierarchy-sync' }
        )

        function Get-ManifestFiles {
            param([string]$PluginRoot)
            $manifest = Get-Content -LiteralPath (Join-Path $PluginRoot 'plugin.json') -Raw | ConvertFrom-Json -Depth 100
            return @($manifest.files | ForEach-Object { ($_.src -replace '\\', '/') })
        }
    }

    It 'test:bundle-no-drift reports no drift under -WhatIf' {
        { & $syncScript -RepoRoot $repoRoot -WhatIf *> $null } | Should -Not -Throw
    }

    It 'test:bundle-byte-identical keeps each bundled script identical to its scripts/skalary source' {
        foreach ($p in $bundlePlugins) {
            $bundleDir = Join-Path $repoRoot "plugins/$($p.Plugin)/skills/$($p.Skill)/scripts"
            $bundled = @(Get-ChildItem -LiteralPath $bundleDir -File)
            $bundled.Count | Should -BeGreaterThan 0
            foreach ($file in $bundled) {
                $source = Join-Path $scriptsSource $file.Name
                Test-Path -LiteralPath $source -PathType Leaf |
                    Should -BeTrue -Because "bundled '$($file.Name)' must originate from scripts/skalary"
                (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash |
                    Should -Be (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -Because "bundle '$($file.Name)' must be byte-identical to its source"
            }
        }
    }

    It 'test:bundle-registered registers every bundled script in plugin.json files[]' {
        foreach ($p in $bundlePlugins) {
            $pluginRoot = Join-Path $repoRoot "plugins/$($p.Plugin)"
            $declared = Get-ManifestFiles -PluginRoot $pluginRoot
            $bundleDir = Join-Path $pluginRoot "skills/$($p.Skill)/scripts"
            foreach ($file in (Get-ChildItem -LiteralPath $bundleDir -File)) {
                $rel = "skills/$($p.Skill)/scripts/$($file.Name)"
                $declared | Should -Contain $rel -Because "bundled '$rel' must be registered in $($p.Plugin)/plugin.json files[]"
            }
        }
    }

    It 'test:bundle-references bundles every installed scripts path the skill calls' {
        foreach ($p in $bundlePlugins) {
            $skillDir = Join-Path $repoRoot "plugins/$($p.Plugin)/skills/$($p.Skill)"
            $bundleDir = Join-Path $skillDir 'scripts'
            foreach ($doc in (Get-ChildItem -LiteralPath $skillDir -Recurse -File -Filter '*.md')) {
                $content = Get-Content -LiteralPath $doc.FullName -Raw
                foreach ($m in $refRegex.Matches($content)) {
                    if ($m.Groups['skill'].Value -ne $p.Skill) { continue }
                    $name = $m.Groups['name'].Value
                    Test-Path -LiteralPath (Join-Path $bundleDir $name) -PathType Leaf |
                        Should -BeTrue -Because "skill references '$name' which must be bundled"
                }
            }
        }
    }

    It 'test:bundle-closure bundles the module closure of each bundled script' {
        foreach ($p in $bundlePlugins) {
            $bundleDir = Join-Path $repoRoot "plugins/$($p.Plugin)/skills/$($p.Skill)/scripts"
            foreach ($file in (Get-ChildItem -LiteralPath $bundleDir -File -Filter '*.ps1')) {
                $content = Get-Content -LiteralPath $file.FullName -Raw
                foreach ($m in $moduleRegex.Matches($content)) {
                    $mod = $m.Groups['mod'].Value
                    Test-Path -LiteralPath (Join-Path $bundleDir $mod) -PathType Leaf |
                        Should -BeTrue -Because "module '$mod' imported by '$($file.Name)' must be bundled alongside it"
                }
            }
        }
    }

    It 'test:bundle-version-bump bumps the plugin version when a bundled source changes' {
        $fixture = Join-Path ([System.IO.Path]::GetTempPath()) ('bundle-bump-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $fixture -Force | Out-Null
        try {
            git init -q $fixture 2>$null | Out-Null
            $skillDir = Join-Path $fixture 'plugins/testplug/skills/ts'
            New-Item -ItemType Directory -Path $skillDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $skillDir 'SKILL.md') `
                -Value 'Run `.github/skills/ts/scripts/Get-PlanState.ps1`.' -Encoding utf8NoBOM

            $manifest = [ordered]@{
                name = 'testplug'; version = '1.0.0'; description = 'fixture'; author = 'x'; license = 'MIT'
                tags = @('skill'); dependencies = @(); status = 'stable'
                files = @(@{ src = 'skills/ts/SKILL.md'; dest = 'skills/ts/SKILL.md' })
            }
            Set-Content -LiteralPath (Join-Path $fixture 'plugins/testplug/plugin.json') `
                -Value ($manifest | ConvertTo-Json -Depth 10) -Encoding utf8NoBOM

            $getVersion = {
                (Get-Content -LiteralPath (Join-Path $fixture 'plugins/testplug/plugin.json') -Raw | ConvertFrom-Json).version
            }

            & $syncScript -RepoRoot $fixture *> $null
            (& $getVersion) | Should -Be '1.0.1' -Because 'creating the bundle is a payload change'

            & $syncScript -RepoRoot $fixture *> $null
            (& $getVersion) | Should -Be '1.0.1' -Because 'a no-op sync must not bump the version'

            $bundled = Join-Path $fixture 'plugins/testplug/skills/ts/scripts/Get-PlanState.ps1'
            Add-Content -LiteralPath $bundled -Value "`n# drift"
            & $syncScript -RepoRoot $fixture *> $null
            (& $getVersion) | Should -Be '1.0.2' -Because 're-syncing a changed bundle is another payload change'
        }
        finally {
            Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:SyncPluginScripts.DotSourceClosure co-bundles _Common.ps1 for a .ps1 script that dot-sources it' {
        $fixture = Join-Path ([System.IO.Path]::GetTempPath()) ('bundle-ps1closure-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $fixture -Force | Out-Null
        try {
            git init -q $fixture 2>$null | Out-Null
            $skillDir = Join-Path $fixture 'plugins/pmfix/skills/lp'
            New-Item -ItemType Directory -Path $skillDir -Force | Out-Null
            # Get-Plugin.ps1 dot-sources `_Common.ps1`; the .ps1 closure must pull it in too.
            Set-Content -LiteralPath (Join-Path $skillDir 'SKILL.md') `
                -Value 'Run `.github/skills/lp/scripts/Get-Plugin.ps1`.' -Encoding utf8NoBOM

            $manifest = [ordered]@{
                name = 'pmfix'; version = '1.0.0'; description = 'fixture'; author = 'x'; license = 'MIT'
                tags = @('skill'); dependencies = @(); status = 'stable'
                files = @(@{ src = 'skills/lp/SKILL.md'; dest = 'skills/lp/SKILL.md' })
            }
            Set-Content -LiteralPath (Join-Path $fixture 'plugins/pmfix/plugin.json') `
                -Value ($manifest | ConvertTo-Json -Depth 10) -Encoding utf8NoBOM

            & $syncScript -RepoRoot $fixture *> $null

            $bundleDir = Join-Path $fixture 'plugins/pmfix/skills/lp/scripts'
            Test-Path -LiteralPath (Join-Path $bundleDir 'Get-Plugin.ps1') -PathType Leaf |
                Should -BeTrue -Because 'the referenced .ps1 script must be bundled'
            Test-Path -LiteralPath (Join-Path $bundleDir '_Common.ps1') -PathType Leaf |
                Should -BeTrue -Because 'Get-Plugin.ps1 dot-sources _Common.ps1, which the .ps1 closure must co-bundle'
        }
        finally {
            Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

}
