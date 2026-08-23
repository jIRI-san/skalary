#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'review concern authoring source' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:registryPath = Join-Path $script:repoRoot 'tools/review-concerns.json'
        $script:schemaPath = Join-Path $script:repoRoot 'schemas/review/review-concerns.schema.json'
        $script:templatePath = Join-Path $script:repoRoot 'tools/review-concern-agent.template.md'
        $script:expectedConcerns = @(
            'security'
            'correctness-reliability'
            'architecture-patterns'
            'performance'
            'testing-evidence'
            'maintainability-consistency'
            'operability-observability'
        )
    }

    It 'test:ReviewConcerns.RegistryAndTemplate validates one closed registry for the settled taxonomy and both review variants' {
        $registryJson = Get-Content -LiteralPath $script:registryPath -Raw
        Test-Json -Json $registryJson -SchemaFile $script:schemaPath | Should -BeTrue

        $registry = $registryJson | ConvertFrom-Json -Depth 20
        @($registry.concerns.id) | Should -Be $script:expectedConcerns
        @($registry.concerns.id | Sort-Object -Unique).Count | Should -Be 7

        foreach ($concern in $registry.concerns) {
            [string]$concern.sharedGuidance | Should -Not -BeNullOrEmpty

            foreach ($reviewType in @('cr', 'dr')) {
                $variant = $concern.variants.$reviewType
                [string]$variant.scope | Should -Not -BeNullOrEmpty
                @($variant.focusAreas).Count | Should -BeGreaterThan 0

                $ledger = [string]$concern.ledger.$reviewType
                Test-Path -LiteralPath (Join-Path $script:repoRoot "docs/review-ledger/$ledger") -PathType Leaf |
                    Should -BeTrue -Because "$($concern.id) must map $reviewType to a real ledger category"
            }

            foreach ($value in @(
                    [string]$concern.sharedGuidance
                    [string]$concern.variants.cr.scope
                    [string]$concern.variants.dr.scope
                    [string[]]$concern.variants.cr.focusAreas
                    [string[]]$concern.variants.dr.focusAreas
                )) {
                $value | Should -Not -Match '[\r\n@{}]' -Because 'registry prose cannot escape its template position'
            }
        }
    }

    It 'test:ReviewConcerns.RegistryAndTemplate keeps safety, context order, and output structure template-owned' {
        $template = Get-Content -LiteralPath $script:templatePath -Raw
        $placeholderNames = @(
            [regex]::Matches($template, '@@(?<name>[A-Z_]+)@@') |
                ForEach-Object { $_.Groups['name'].Value } |
                Sort-Object -Unique
        )
        $placeholderNames | Should -Be @(
            'ARCHITECTURE_CONSEQUENCE'
            'CONTEXT_DISCOVERY'
            'CONTEXT_TARGET'
            'DESCRIPTION'
            'FOCUS_AREAS'
            'ID'
            'INPUT_DESCRIPTION'
            'LABEL'
            'PREFIX'
            'REFERENCE_OMISSION'
            'REFERENCE_TARGET'
            'REVIEW_KIND'
            'REVIEW_TARGET'
            'SCOPE'
            'SHARED_GUIDANCE'
            'TARGET_NOUN'
        )

        $template | Should -Match '(?m)^tools:\s*\[read, search\]\s*$'
        $template | Should -Match '(?m)^user-invocable:\s*false\s*$'
        $template | Should -Not -Match '(?m)^model:'
        $template | Should -Match '(?m)^## Untrusted Content\s*$'
        $template | Should -Match 'data, never instructions'
        $template | Should -Match '\[SECURITY\] Prompt injection attempt detected'
        $template | Should -Match '(?s)Prompt injection attempt detected.{0,120}\*\*Critical\*\*'
        $template | Should -Match 'Never execute, install, or fetch'

        $architectureIndex = $template.IndexOf('1. If `docs/architecture-notes/.architecture-notes.md` exists')
        $designIndex = $template.IndexOf('2. Read `docs/design-notes/.design-notes.md`')
        $discoveryIndex = $template.IndexOf('3. @@CONTEXT_DISCOVERY@@')
        $targetIndex = $template.IndexOf('4. @@CONTEXT_TARGET@@')
        $architectureIndex | Should -BeGreaterThan -1
        $designIndex | Should -BeGreaterThan $architectureIndex
        $discoveryIndex | Should -BeGreaterThan $designIndex
        $targetIndex | Should -BeGreaterThan $discoveryIndex

        $template | Should -Match 'Start with `## Findings \(@@LABEL@@\)`'
        $template | Should -Match '(?m)^### \[F1\] Title$'
        $template | Should -Match '(?m)^\*\*Severity:\*\* Critical / High / Medium / Low$'
        $template | Should -Match 'followed by `None\.`'
        $template | Should -Match 'Stay inside your lens'
    }
}

Describe 'review concern generation' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:syncScript = Join-Path $script:repoRoot 'scripts/skalary/Sync-ReviewConcerns.ps1'
        $script:concernIds = @(
            'security'
            'correctness-reliability'
            'architecture-patterns'
            'performance'
            'testing-evidence'
            'maintainability-consistency'
            'operability-observability'
        )

        function New-ReviewConcernFixture {
            $root = Join-Path ([System.IO.Path]::GetTempPath()) ('review-concerns-' + [guid]::NewGuid().ToString('N'))
            foreach ($directory in @(
                    'tools'
                    'schemas/review'
                    'docs/review-ledger'
                    'plugins/code-review/agents'
                    'plugins/code-review/skills/cr/assets'
                    'plugins/design-review/agents'
                    'plugins/design-review/skills/dr/assets'
                )) {
                New-Item -ItemType Directory -Path (Join-Path $root $directory) -Force | Out-Null
            }
            Copy-Item -LiteralPath (Join-Path $script:repoRoot 'tools/review-concerns.json') -Destination (Join-Path $root 'tools/review-concerns.json')
            Copy-Item -LiteralPath (Join-Path $script:repoRoot 'tools/review-concern-agent.template.md') -Destination (Join-Path $root 'tools/review-concern-agent.template.md')
            Copy-Item -LiteralPath (Join-Path $script:repoRoot 'schemas/review/review-concerns.schema.json') -Destination (Join-Path $root 'schemas/review/review-concerns.schema.json')

            $registry = Get-Content -LiteralPath (Join-Path $root 'tools/review-concerns.json') -Raw | ConvertFrom-Json -Depth 30
            foreach ($category in @(
                    $registry.concerns.ledger.cr
                    $registry.concerns.ledger.dr
                ) | Sort-Object -Unique) {
                Set-Content -LiteralPath (Join-Path $root "docs/review-ledger/$category") -Value "# $category" -Encoding utf8NoBOM
            }
            return $root
        }

        function Get-ExpectedReviewConcernOutputs {
            param([Parameter(Mandatory)][string]$Root)

            $paths = [System.Collections.Generic.List[string]]::new()
            foreach ($reviewType in @(
                    @{ Prefix = 'cr'; Plugin = 'code-review'; Skill = 'cr' }
                    @{ Prefix = 'dr'; Plugin = 'design-review'; Skill = 'dr' }
                )) {
                foreach ($concernId in $script:concernIds) {
                    $paths.Add((Join-Path $Root "plugins/$($reviewType.Plugin)/agents/$($reviewType.Prefix)-$concernId.agent.md"))
                }
                $paths.Add((Join-Path $Root "plugins/$($reviewType.Plugin)/skills/$($reviewType.Skill)/assets/concern-ledger-map.md"))
            }
            return @($paths)
        }

        function Get-ReviewConcernOutputHashes {
            param([Parameter(Mandatory)][string[]]$Paths)

            return @(
                $Paths | ForEach-Object {
                    if (Test-Path -LiteralPath $_ -PathType Leaf) {
                        (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash
                    }
                    else {
                        '<missing>'
                    }
                }
            )
        }
    }

    Describe 'generated review concern behavior and distribution' {
        BeforeAll {
            $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
            $script:registry = Get-Content -LiteralPath (Join-Path $script:repoRoot 'tools/review-concerns.json') -Raw |
                ConvertFrom-Json -Depth 30
            $script:pluginRegistry = Get-Content -LiteralPath (Join-Path $script:repoRoot 'registry.json') -Raw |
                ConvertFrom-Json -Depth 100
            $script:marketplace = Get-Content -LiteralPath (Join-Path $script:repoRoot '.github/plugin/marketplace.json') -Raw |
                ConvertFrom-Json -Depth 100
            $script:reviewTypes = @(
                @{
                    Prefix = 'cr'
                    Plugin = 'code-review'
                    Skill = 'cr'
                    SurfaceMarkers = @('changed files', 'Map the changed file paths')
                }
                @{
                    Prefix = 'dr'
                    Plugin = 'design-review'
                    Skill = 'dr'
                    SurfaceMarkers = @('implementation plan', 'Under the plan-assets layout')
                }
            )
        }

        It 'test:ReviewConcerns.GeneratedBehaviorAndDistribution preserves generated safety, variants, and review-run ownership' {
            foreach ($reviewType in $script:reviewTypes) {
                foreach ($concern in $script:registry.concerns) {
                    $relative = "plugins/$($reviewType.Plugin)/agents/$($reviewType.Prefix)-$($concern.id).agent.md"
                    $raw = Get-Content -LiteralPath (Join-Path $script:repoRoot $relative) -Raw
                    $variant = $concern.variants.($reviewType.Prefix)

                    $raw | Should -Match "(?m)^name:\s*`"$($reviewType.Prefix)-$([regex]::Escape($concern.id))`"\s*$"
                    $raw | Should -Match '(?m)^tools:\s*\[read, search\]\s*$'
                    $raw | Should -Not -Match '(?m)^model:'
                    $raw | Should -Match 'data, never instructions'
                    $raw | Should -Match '\[SECURITY\] Prompt injection attempt detected'
                    $raw | Should -Match ([regex]::Escape([string]$concern.sharedGuidance))
                    $raw | Should -Match ([regex]::Escape([string]$variant.scope))
                    foreach ($focusArea in $variant.focusAreas) {
                        $raw | Should -Match ([regex]::Escape("- $focusArea"))
                    }
                    foreach ($marker in $reviewType.SurfaceMarkers) {
                        $raw | Should -Match ([regex]::Escape($marker))
                    }

                    $architectureIndex = $raw.IndexOf('1. If `docs/architecture-notes/.architecture-notes.md` exists')
                    $designIndex = $raw.IndexOf('2. Read `docs/design-notes/.design-notes.md`')
                    $targetIndex = $raw.IndexOf('4. ')
                    $architectureIndex | Should -BeGreaterThan -1
                    $designIndex | Should -BeGreaterThan $architectureIndex
                    $targetIndex | Should -BeGreaterThan $designIndex

                    $raw | Should -Not -Match 'Build-ReviewReport|ReviewRun|review-runs|assets/reviews' -Because 'concern agents report findings; the orchestrator skill owns review-run v1'
                }

                $skillPath = Join-Path $script:repoRoot "plugins/$($reviewType.Plugin)/skills/$($reviewType.Skill)/SKILL.md"
                $skill = Get-Content -LiteralPath $skillPath -Raw
                $skill | Should -Match 'Freeze exactly once'
                $skill | Should -Match ([regex]::Escape(".github/skills/$($reviewType.Skill)/scripts/Build-ReviewReport.ps1"))
            }
        }

        It 'test:ReviewConcerns.GeneratedBehaviorAndDistribution declares every generated output exactly once in its owning manifest' {
            foreach ($reviewType in $script:reviewTypes) {
                $manifestPath = Join-Path $script:repoRoot "plugins/$($reviewType.Plugin)/plugin.json"
                $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -Depth 100
                $expectedAgents = @(
                    $script:registry.concerns |
                        ForEach-Object { "agents/$($reviewType.Prefix)-$($_.id).agent.md" }
                )
                $declaredAgents = @(
                    $manifest.files |
                        Where-Object { [string]$_.src -match "^agents/$($reviewType.Prefix)-.+\.agent\.md$" } |
                        ForEach-Object { [string]$_.src }
                )

                @($declaredAgents | Sort-Object) | Should -Be @($expectedAgents | Sort-Object)
                foreach ($relative in $expectedAgents) {
                    $entries = @($manifest.files | Where-Object {
                            [string]$_.src -ceq $relative -and [string]$_.dest -ceq $relative
                        })
                    $entries.Count | Should -Be 1
                }

                $mapRelative = "skills/$($reviewType.Skill)/assets/concern-ledger-map.md"
                @($manifest.files | Where-Object {
                        [string]$_.src -ceq $mapRelative -and [string]$_.dest -ceq $mapRelative
                    }).Count | Should -Be 1

                foreach ($runtimeScript in @(
                        'Build-ReviewReport.ps1'
                        'Get-ReviewRun.ps1'
                        'Remove-ReviewRun.ps1'
                        'ReviewRun.psm1'
                    )) {
                    $runtimeRelative = "skills/$($reviewType.Skill)/scripts/$runtimeScript"
                    @($manifest.files | Where-Object {
                            [string]$_.src -ceq $runtimeRelative -and [string]$_.dest -ceq $runtimeRelative
                        }).Count | Should -Be 1
                }
            }
        }

        It 'test:ReviewConcerns.GeneratedBehaviorAndDistribution synchronizes dogfood, marketplace versions, and registry hashes' {
            foreach ($reviewType in $script:reviewTypes) {
                $manifestPath = Join-Path $script:repoRoot "plugins/$($reviewType.Plugin)/plugin.json"
                $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -Depth 100
                $registryEntry = @($script:pluginRegistry.plugins | Where-Object {
                        [string]$_.name -ceq $reviewType.Plugin
                    })
                $marketplaceEntry = @($script:marketplace.plugins | Where-Object {
                        [string]$_.name -ceq $reviewType.Plugin
                    })

                $registryEntry.Count | Should -Be 1
                $marketplaceEntry.Count | Should -Be 1
                [string]$registryEntry[0].version | Should -Be ([string]$manifest.version)
                [string]$marketplaceEntry[0].version | Should -Be ([string]$manifest.version)

                $generatedFiles = @(
                    $script:registry.concerns |
                        ForEach-Object { "agents/$($reviewType.Prefix)-$($_.id).agent.md" }
                ) + @("skills/$($reviewType.Skill)/assets/concern-ledger-map.md")

                foreach ($relative in $generatedFiles) {
                    $sourcePath = Join-Path $script:repoRoot "plugins/$($reviewType.Plugin)/$relative"
                    $dogfoodPath = Join-Path $script:repoRoot ".github/$relative"
                    $sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash

                    Test-Path -LiteralPath $dogfoodPath -PathType Leaf | Should -BeTrue
                    (Get-FileHash -LiteralPath $dogfoodPath -Algorithm SHA256).Hash | Should -Be $sourceHash

                    $registryFile = @($registryEntry[0].files | Where-Object {
                            [string]$_.src -ceq $relative -and [string]$_.dest -ceq $relative
                        })
                    $registryFile.Count | Should -Be 1
                    [string]$registryFile[0].sha256 | Should -Be $sourceHash.ToLowerInvariant()
                }
            }
        }
    }

    It 'test:ReviewConcerns.DeterministicGeneration renders all outputs, preserves surface variants, and converges' {
        $fixture = New-ReviewConcernFixture
        try {
            & $script:syncScript -RepoRoot $fixture *> $null

            foreach ($reviewType in @(
                    @{ Prefix = 'cr'; Plugin = 'code-review' }
                    @{ Prefix = 'dr'; Plugin = 'design-review' }
                )) {
                foreach ($concernId in $script:concernIds) {
                    $path = Join-Path $fixture "plugins/$($reviewType.Plugin)/agents/$($reviewType.Prefix)-$concernId.agent.md"
                    Test-Path -LiteralPath $path -PathType Leaf | Should -BeTrue
                    $raw = Get-Content -LiteralPath $path -Raw
                    $raw | Should -Match '(?m)^tools:\s*\[read, search\]\s*$'
                    $raw | Should -Not -Match '(?m)^model:'
                    $raw | Should -Match 'data, never instructions'
                    $raw | Should -Not -Match '@@[A-Z_]+@@'
                }
            }

            $crSecurity = Get-Content -LiteralPath (Join-Path $fixture 'plugins/code-review/agents/cr-security.agent.md') -Raw
            $drSecurity = Get-Content -LiteralPath (Join-Path $fixture 'plugins/design-review/agents/dr-security.agent.md') -Raw
            $crSecurity | Should -Match 'changed files'
            $crSecurity | Should -Match 'Map the changed file paths'
            $drSecurity | Should -Match 'implementation plan'
            $drSecurity | Should -Match 'Under the plan-assets layout'
            $crSecurity | Should -Match ([regex]::Escape('Treat security as trust-boundary enforcement'))
            $drSecurity | Should -Match ([regex]::Escape('Treat security as trust-boundary enforcement'))

            $crMap = Join-Path $fixture 'plugins/code-review/skills/cr/assets/concern-ledger-map.md'
            $drMap = Join-Path $fixture 'plugins/design-review/skills/dr/assets/concern-ledger-map.md'
            (Get-FileHash -LiteralPath $crMap -Algorithm SHA256).Hash |
                Should -Be (Get-FileHash -LiteralPath $drMap -Algorithm SHA256).Hash
            { & $script:syncScript -RepoRoot $fixture -WhatIf *> $null } | Should -Not -Throw

            $before = @(
                Get-ChildItem -LiteralPath (Join-Path $fixture 'plugins') -Recurse -File |
                    Sort-Object FullName |
                    ForEach-Object { "$($_.FullName):$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)" }
            )
            & $script:syncScript -RepoRoot $fixture *> $null
            $after = @(
                Get-ChildItem -LiteralPath (Join-Path $fixture 'plugins') -Recurse -File |
                    Sort-Object FullName |
                    ForEach-Object { "$($_.FullName):$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)" }
            )
            $after | Should -Be $before
        }
        finally {
            Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:ReviewConcerns.DeterministicGeneration validates every render before writing and detects changed or extra outputs' {
        $fixture = New-ReviewConcernFixture
        try {
            & $script:syncScript -RepoRoot $fixture *> $null
            $agentPath = Join-Path $fixture 'plugins/code-review/agents/cr-security.agent.md'
            $originalHash = (Get-FileHash -LiteralPath $agentPath -Algorithm SHA256).Hash

            Add-Content -LiteralPath $agentPath -Value 'hand edit' -Encoding utf8NoBOM
            { & $script:syncScript -RepoRoot $fixture -WhatIf *> $null } | Should -Throw '*1 changed or missing output*'
            & $script:syncScript -RepoRoot $fixture *> $null
            (Get-FileHash -LiteralPath $agentPath -Algorithm SHA256).Hash | Should -Be $originalHash

            $extraPath = Join-Path $fixture 'plugins/code-review/agents/cr-extra.agent.md'
            Set-Content -LiteralPath $extraPath -Value 'extra' -Encoding utf8NoBOM
            { & $script:syncScript -RepoRoot $fixture -WhatIf *> $null } | Should -Throw '*1 extra agent*'
            & $script:syncScript -RepoRoot $fixture *> $null
            Test-Path -LiteralPath $extraPath | Should -BeFalse

            $registryPath = Join-Path $fixture 'tools/review-concerns.json'
            $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json -Depth 30
            $registry.concerns[6].variants.dr.scope = 'unsafe@@placeholder'
            Set-Content -LiteralPath $registryPath -Value ($registry | ConvertTo-Json -Depth 30) -Encoding utf8NoBOM
            { & $script:syncScript -RepoRoot $fixture *> $null } | Should -Throw
            (Get-FileHash -LiteralPath $agentPath -Algorithm SHA256).Hash |
                Should -Be $originalHash -Because 'an invalid late registry value must be rejected before any output is written'
        }
        finally {
            Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:ReviewConcerns.GenerationDrift detects every drift shape without writing and converges deterministically after a registry mutation' {
        { & $script:syncScript -RepoRoot $script:repoRoot -WhatIf *> $null } | Should -Not -Throw

        $fixture = New-ReviewConcernFixture
        try {
            & $script:syncScript -RepoRoot $fixture *> $null
            $expectedPaths = Get-ExpectedReviewConcernOutputs -Root $fixture
            $expectedPaths.Count | Should -Be 16
            $baselineHashes = Get-ReviewConcernOutputHashes -Paths $expectedPaths

            $agentPath = Join-Path $fixture 'plugins/code-review/agents/cr-security.agent.md'
            Add-Content -LiteralPath $agentPath -Value 'hand-edited agent' -Encoding utf8NoBOM
            $handEditedAgentHash = (Get-FileHash -LiteralPath $agentPath -Algorithm SHA256).Hash
            { & $script:syncScript -RepoRoot $fixture -WhatIf *> $null } |
                Should -Throw '*1 changed or missing output(s), 0 extra agent(s)*'
            (Get-FileHash -LiteralPath $agentPath -Algorithm SHA256).Hash |
                Should -Be $handEditedAgentHash -Because '-WhatIf must not repair a hand edit'
            & $script:syncScript -RepoRoot $fixture *> $null

            Remove-Item -LiteralPath $agentPath -Force
            { & $script:syncScript -RepoRoot $fixture -WhatIf *> $null } |
                Should -Throw '*1 changed or missing output(s), 0 extra agent(s)*'
            Test-Path -LiteralPath $agentPath | Should -BeFalse -Because '-WhatIf must not recreate a missing output'
            & $script:syncScript -RepoRoot $fixture *> $null

            $extraPath = Join-Path $fixture 'plugins/design-review/agents/dr-extra.agent.md'
            Set-Content -LiteralPath $extraPath -Value 'extra generated-looking agent' -Encoding utf8NoBOM
            { & $script:syncScript -RepoRoot $fixture -WhatIf *> $null } |
                Should -Throw '*0 changed or missing output(s), 1 extra agent(s)*'
            Test-Path -LiteralPath $extraPath -PathType Leaf | Should -BeTrue -Because '-WhatIf must not prune an extra output'
            & $script:syncScript -RepoRoot $fixture *> $null

            $mapPath = Join-Path $fixture 'plugins/code-review/skills/cr/assets/concern-ledger-map.md'
            Add-Content -LiteralPath $mapPath -Value 'hand-edited mapping' -Encoding utf8NoBOM
            $handEditedMapHash = (Get-FileHash -LiteralPath $mapPath -Algorithm SHA256).Hash
            { & $script:syncScript -RepoRoot $fixture -WhatIf *> $null } |
                Should -Throw '*1 changed or missing output(s), 0 extra agent(s)*'
            (Get-FileHash -LiteralPath $mapPath -Algorithm SHA256).Hash |
                Should -Be $handEditedMapHash -Because '-WhatIf must not repair a hand-edited mapping'
            & $script:syncScript -RepoRoot $fixture *> $null

            $agentBytes = [System.IO.File]::ReadAllBytes($agentPath)
            $preamble = [System.Text.UTF8Encoding]::new($true).GetPreamble()
            $bytesWithPreamble = [byte[]]::new($preamble.Length + $agentBytes.Length)
            [System.Array]::Copy($preamble, 0, $bytesWithPreamble, 0, $preamble.Length)
            [System.Array]::Copy($agentBytes, 0, $bytesWithPreamble, $preamble.Length, $agentBytes.Length)
            [System.IO.File]::WriteAllBytes($agentPath, $bytesWithPreamble)
            $encodingDriftHash = (Get-FileHash -LiteralPath $agentPath -Algorithm SHA256).Hash
            { & $script:syncScript -RepoRoot $fixture -WhatIf *> $null } |
                Should -Throw '*1 changed or missing output(s), 0 extra agent(s)*'
            (Get-FileHash -LiteralPath $agentPath -Algorithm SHA256).Hash |
                Should -Be $encodingDriftHash -Because '-WhatIf must not normalize encoding drift'
            & $script:syncScript -RepoRoot $fixture *> $null

            [System.IO.File]::WriteAllBytes($agentPath, [byte[]]::new(0))
            { & $script:syncScript -RepoRoot $fixture -WhatIf *> $null } |
                Should -Throw '*1 changed or missing output(s), 0 extra agent(s)*'
            (Get-Item -LiteralPath $agentPath).Length |
                Should -Be 0 -Because '-WhatIf must not repair a truncated output'
            & $script:syncScript -RepoRoot $fixture *> $null
            (Get-Item -LiteralPath $agentPath).Length |
                Should -BeGreaterThan 0 -Because 'apply mode must repair a truncated generated output'

            $registryPath = Join-Path $fixture 'tools/review-concerns.json'
            $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json -Depth 30
            $existingLedger = [string]$registry.concerns[0].ledger.cr
            for ($index = 0; $index -lt $registry.concerns.Count; $index++) {
                $registry.concerns[$index].sharedGuidance = "$($registry.concerns[$index].sharedGuidance) Mutation sentinel $index"
                $registry.concerns[$index].ledger.cr = $existingLedger
                $registry.concerns[$index].ledger.dr = $existingLedger
            }
            Set-Content -LiteralPath $registryPath -Value ($registry | ConvertTo-Json -Depth 30) -Encoding utf8NoBOM

            { & $script:syncScript -RepoRoot $fixture -WhatIf *> $null } |
                Should -Throw '*16 changed or missing output(s), 0 extra agent(s)*'
            (Get-ReviewConcernOutputHashes -Paths $expectedPaths) |
                Should -Be $baselineHashes -Because 'detect-only validation must leave every expected output unchanged'

            & $script:syncScript -RepoRoot $fixture *> $null
            $mutatedHashes = Get-ReviewConcernOutputHashes -Paths $expectedPaths
            for ($index = 0; $index -lt $expectedPaths.Count; $index++) {
                $mutatedHashes[$index] | Should -Not -Be $baselineHashes[$index] -Because "$($expectedPaths[$index]) must derive from the registry"
            }

            { & $script:syncScript -RepoRoot $fixture -WhatIf *> $null } | Should -Not -Throw
            & $script:syncScript -RepoRoot $fixture *> $null
            (Get-ReviewConcernOutputHashes -Paths $expectedPaths) |
                Should -Be $mutatedHashes -Because 'a clean second generation pass must be byte-deterministic'
        }
        finally {
            Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:ReviewConcerns.DeterministicGeneration refuses a managed output symlink that escapes the repository' -Skip:$IsWindows {
        $fixture = New-ReviewConcernFixture
        $outside = Join-Path ([System.IO.Path]::GetTempPath()) ('review-concerns-outside-' + [guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path $outside -Force | Out-Null
            $agentDir = Join-Path $fixture 'plugins/code-review/agents'
            Remove-Item -LiteralPath $agentDir -Recurse -Force
            New-Item -ItemType SymbolicLink -Path $agentDir -Target $outside | Out-Null

            { & $script:syncScript -RepoRoot $fixture *> $null } |
                Should -Throw '*resolves outside the repository*'
            @(Get-ChildItem -LiteralPath $outside -Force).Count | Should -Be 0
        }
        finally {
            Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $outside -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:ReviewConcerns.DeterministicGeneration refuses a directory at an expected output path' {
        $fixture = New-ReviewConcernFixture
        try {
            $agentPath = Join-Path $fixture 'plugins/code-review/agents/cr-security.agent.md'
            New-Item -ItemType Directory -Path $agentPath -Force | Out-Null

            { & $script:syncScript -RepoRoot $fixture *> $null } |
                Should -Throw '*is not a regular file*'
            @(Get-ChildItem -LiteralPath $agentPath -Force).Count | Should -Be 0
        }
        finally {
            Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
