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
        $script:schemaRegex = [regex]'\$PSScriptRoot\s+''(?<schema>schemas/review/[A-Za-z0-9][A-Za-z0-9._-]*\.schema\.json)'''

        $script:bundlePlugins = @(
            [pscustomobject]@{ Plugin = 'continue-implementation'; Skill = 'ci' },
            [pscustomobject]@{ Plugin = 'create-implementation-plan'; Skill = 'cip' },
            [pscustomobject]@{ Plugin = 'code-review'; Skill = 'cr' },
            [pscustomobject]@{ Plugin = 'design-review'; Skill = 'dr' }
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

    It 'test:bundle-schema-closure copies literal schema references from canonical schemas/review' {
        foreach ($p in $bundlePlugins | Where-Object { $_.Skill -in @('cr', 'dr') }) {
            $bundleDir = Join-Path $repoRoot "plugins/$($p.Plugin)/skills/$($p.Skill)/scripts"
            $module = Get-Content -LiteralPath (Join-Path $bundleDir 'ReviewRun.psm1') -Raw
            foreach ($m in @($schemaRegex.Matches($module))) {
                $relative = $m.Groups['schema'].Value
                $source = Join-Path $repoRoot $relative
                $bundled = Join-Path $bundleDir $relative
                Test-Path -LiteralPath $bundled -PathType Leaf | Should -BeTrue
                (Get-FileHash -LiteralPath $bundled -Algorithm SHA256).Hash |
                    Should -Be (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
            }
        }
    }

    It 'test:bundle-schema-resolution ignores a parent schema directory in installed layouts' {
        $fixture = Join-Path ([System.IO.Path]::GetTempPath()) ('bundle-schema-trust-' + [guid]::NewGuid().ToString('N'))
        try {
            $bundleDir = Join-Path $fixture 'skills/cr/scripts'
            $decoyDir = Join-Path $fixture 'skills/schemas/review'
            New-Item -ItemType Directory -Path $bundleDir, $decoyDir -Force | Out-Null
            Copy-Item -Path (Join-Path $repoRoot 'plugins/code-review/skills/cr/scripts/*') `
                -Destination $bundleDir -Recurse
            Set-Content -LiteralPath (Join-Path $decoyDir 'review-limits.schema.json') `
                -Value '{"x-skalary-limits":{"maxTasks":1}}' -Encoding utf8NoBOM

            Import-Module (Join-Path $bundleDir 'ReviewRun.psm1') -Force -Prefix Bundled -DisableNameChecking
            (Get-BundledReviewLimits).maxTasks | Should -Be 128
        }
        finally {
            Remove-Module ReviewRun -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:bundle-schema-resolution recognizes canonical execution under a repo named skills' {
        $fixture = Join-Path ([System.IO.Path]::GetTempPath()) ('bundle-schema-root-' + [guid]::NewGuid().ToString('N'))
        try {
            $repo = Join-Path $fixture 'skills'
            $moduleDir = Join-Path $repo 'scripts/skalary'
            $schemaDir = Join-Path $repo 'schemas/review'
            New-Item -ItemType Directory -Path $moduleDir, $schemaDir -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts/skalary/ReviewRun.psm1') -Destination $moduleDir
            Copy-Item -Path (Join-Path $repoRoot 'schemas/review/*.json') -Destination $schemaDir

            Import-Module (Join-Path $moduleDir 'ReviewRun.psm1') -Force -Prefix Canonical -DisableNameChecking
            (Get-CanonicalReviewLimits).maxTasks | Should -Be 128
        }
        finally {
            Remove-Module ReviewRun -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
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

    It 'test:SyncPluginScripts.SchemaClosure uses canonical source, prunes stale sidecars, and bumps once' {
        $fixture = Join-Path ([System.IO.Path]::GetTempPath()) ('bundle-schema-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $fixture -Force | Out-Null
        try {
            git init -q $fixture 2>$null | Out-Null
            $skillDir = Join-Path $fixture 'plugins/review/skills/rv'
            $schemaDir = Join-Path $fixture 'schemas/review'
            New-Item -ItemType Directory -Path $skillDir, $schemaDir -Force | Out-Null
            Copy-Item -Path (Join-Path $repoRoot 'schemas/review/*.json') -Destination $schemaDir
            Set-Content -LiteralPath (Join-Path $skillDir 'SKILL.md') `
                -Value 'Run `.github/skills/rv/scripts/Build-ReviewReport.ps1`.' -Encoding utf8NoBOM

            $manifest = [ordered]@{
                name = 'review'; version = '1.0.0'; description = 'fixture'; author = 'x'; license = 'MIT'
                tags = @('skill'); dependencies = @(); status = 'stable'
                files = @(@{ src = 'skills/rv/SKILL.md'; dest = 'skills/rv/SKILL.md' })
            }
            Set-Content -LiteralPath (Join-Path $fixture 'plugins/review/plugin.json') `
                -Value ($manifest | ConvertTo-Json -Depth 10) -Encoding utf8NoBOM

            & $syncScript -RepoRoot $fixture *> $null
            $bundleDir = Join-Path $skillDir 'scripts'
            (Get-FileHash -LiteralPath (Join-Path $bundleDir 'schemas/review/review-plan.schema.json') -Algorithm SHA256).Hash |
                Should -Be (Get-FileHash -LiteralPath (Join-Path $schemaDir 'review-plan.schema.json') -Algorithm SHA256).Hash
            ((Get-Content -LiteralPath (Join-Path $fixture 'plugins/review/plugin.json') -Raw | ConvertFrom-Json).version) |
                Should -Be '1.0.1' -Because 'all closure changes in one sync produce one patch bump'

            Set-Content -LiteralPath (Join-Path $bundleDir 'schemas/review/stale.schema.json') `
                -Value '{}' -Encoding utf8NoBOM
            $nestedScript = Join-Path $bundleDir 'custom/keep.ps1'
            New-Item -ItemType Directory -Path (Split-Path -Parent $nestedScript) -Force | Out-Null
            Set-Content -LiteralPath $nestedScript -Value '# not owned by the bundle closure' -Encoding utf8NoBOM
            { & $syncScript -RepoRoot $fixture -WhatIf *> $null } | Should -Throw '*1 stale file*'
            & $syncScript -RepoRoot $fixture *> $null
            Test-Path -LiteralPath (Join-Path $bundleDir 'schemas/review/stale.schema.json') | Should -BeFalse
            Test-Path -LiteralPath $nestedScript -PathType Leaf | Should -BeTrue
            ((Get-Content -LiteralPath (Join-Path $fixture 'plugins/review/plugin.json') -Raw | ConvertFrom-Json).version) |
                Should -Be '1.0.2'
            { & $syncScript -RepoRoot $fixture -WhatIf *> $null } | Should -Not -Throw
        }
        finally {
            Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
