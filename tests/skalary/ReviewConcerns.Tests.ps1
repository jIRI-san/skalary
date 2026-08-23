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
