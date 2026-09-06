#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Skalary configuration catalog and read-only adapter' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:pluginRoot = Join-Path $script:repoRoot 'plugins/skalary-config'
        $script:catalog = Get-Content -LiteralPath (Join-Path $script:pluginRoot 'skills/skalary-config/assets/catalog.md') -Raw
        $script:skill = Get-Content -LiteralPath (Join-Path $script:pluginRoot 'skills/skalary-config/SKILL.md') -Raw
        $script:reader = Join-Path $script:pluginRoot 'skills/skalary-config/scripts/Read-SkalaryConfig.ps1'
        $script:writer = Join-Path $script:pluginRoot 'skills/skalary-config/scripts/Set-SkalaryConfig.ps1'
        $script:authValidator = Join-Path $script:pluginRoot 'skills/skalary-config/scripts/Test-AutopilotAuth.ps1'
    }

    It 'test:SkalaryConfig.Catalog provides every accepted category and catalog boundary' {
        Test-Path -LiteralPath (Join-Path $script:pluginRoot 'plugin.json') -PathType Leaf | Should -BeTrue
        foreach ($category in @(
                'Autopilot', 'Models and reviews', 'Local review standards', 'Terminal approvals',
                'Evals', 'Design and architecture', 'Plugin distribution', 'Repository and toolchain'
            )) {
            $catalog | Should -Match ([regex]::Escape($category))
        }
        $catalog | Should -Match 'Canonical and default paths'
        $catalog | Should -Match 'Generated paths and precedence'
        $catalog | Should -Match 'Installed consumer'
        $catalog | Should -Match 'not executable configuration policy'
    }

    It 'test:SkalaryConfig.ReadOnly discovers source state without exposing credential values' {
        $result = & $script:reader -Action show -Category autopilot -RepoRoot $script:repoRoot | ConvertFrom-Json
        $result.Layout | Should -Be 'source'
        $result.Precedence | Should -Match 'overrides'
        $result.SourceDigest | Should -Match '^[a-f0-9]{64}$'
        $result.EffectiveValues.model | Should -Be 'primary-model-mid'
        $result | ConvertTo-Json -Depth 5 | Should -Not -Match 'github_pat_'
    }

    It 'shows all six model aliases and their role bindings from the canonical authority' {
        $result = & $script:reader -Action show -Category models-reviews -RepoRoot $script:repoRoot | ConvertFrom-Json
        @($result.EffectiveValues.Aliases.psobject.Properties).Count | Should -Be 6
        $result.EffectiveValues.Roles.Routine.Primary | Should -Be 'primary-model-low'
        $result.EffectiveValues.Roles.WazaExecutor | Should -Be 'primary-model-low'
    }

    It 'test:SkalaryConfig.Preview is category-bounded and detects changed canonical inputs' {
        $preview = & $script:reader -Action preview -Category models-reviews -RepoRoot $script:repoRoot | ConvertFrom-Json
        $preview.Proposal | Should -Match 'No requested changes'
        $preview.Redaction | Should -Match 'never read'

        {
            & $script:reader -Action preview -Category models-reviews -RepoRoot $script:repoRoot `
                -ExpectedDigest ('0' * 64) | Out-Null
        } | Should -Throw '*SourceChanged*'
    }

    It 'reports advanced categories as unavailable in an installed consumer layout' {
        $consumer = Join-Path $TestDrive 'consumer'
        New-Item -ItemType Directory -Path $consumer -Force | Out-Null
        $result = & $script:reader -Action validate -Category models-reviews -RepoRoot $consumer | ConvertFrom-Json
        $result.Layout | Should -Be 'installed-consumer'
        $result.Validation | Should -Match 'requires maintainer source'
    }

    It 'test:SkalaryConfig.Categories routes remaining categories through safe owner state' {
        $approvals = & $script:reader -Action show -Category terminal-approvals -RepoRoot $script:repoRoot | ConvertFrom-Json
        $approvals.OwnerCommand | Should -Match 'Set-ScriptApproval'
        $approvals.EffectiveValues.ReadOnlyApprovals | Should -Not -Match 'Credential'

        $evals = & $script:reader -Action show -Category evals -RepoRoot $script:repoRoot | ConvertFrom-Json
        $evals.OwnerCommand | Should -Match 'Invoke-WazaEvals'
        @($evals.EffectiveValues.WazaSpecs).Count | Should -BeGreaterThan 0
        @($evals.EffectiveValues.WazaSpecs | Where-Object { $_.Model -notmatch '^[a-z0-9][a-z0-9.-]*$' }) | Should -BeNullOrEmpty
        $evals | ConvertTo-Json -Depth 8 | Should -Not -Match 'github_pat_'

        $notes = & $script:reader -Action show -Category design-architecture -RepoRoot $script:repoRoot | ConvertFrom-Json
        $notes.EffectiveValues.DesignNotesPresent | Should -BeTrue
        $notes.EffectiveValues.ArchitectureNotesPresent | Should -BeTrue
        ($notes.OwnerCommands -join "`n") | Should -Match 'Initialize-DesignNotes'

        $advanced = & $script:reader -Action preview -Category plugin-distribution -RepoRoot $script:repoRoot | ConvertFrom-Json
        $advanced.Proposal | Should -Match 'no generic façade writer'
    }

    It 'test:SkalaryConfig.Safety refuses generic writers for remaining categories' {
        $writerText = Get-Content -LiteralPath $script:writer -Raw
        $writerText | Should -Not -Match "ValidateSet\([^)]*terminal-approvals"
        $catalog | Should -Match 'never values or a generic spec editor'
        $skill | Should -Match 'advanced, source-only owner controls'
    }

    It 'test:SkalaryConfig.Mutation previews, applies, and preserves unrelated autopilot JSON' {
        $fixture = Join-Path $TestDrive 'mutation-repo'
        New-Item -ItemType Directory -Path @(
            (Join-Path $fixture 'plugins/skalary-config/skills/skalary-config/scripts'),
            (Join-Path $fixture 'plugins/autopilot/schemas'),
            (Join-Path $fixture 'scripts/skalary')
        ) -Force | Out-Null
        Copy-Item -LiteralPath $script:reader -Destination (Join-Path $fixture 'plugins/skalary-config/skills/skalary-config/scripts/Read-SkalaryConfig.ps1')
        Copy-Item -LiteralPath $script:writer -Destination (Join-Path $fixture 'plugins/skalary-config/skills/skalary-config/scripts/Set-SkalaryConfig.ps1')
        Copy-Item -LiteralPath (Join-Path $script:repoRoot 'plugins/autopilot/.autopilot.json.example') -Destination (Join-Path $fixture 'plugins/autopilot/.autopilot.json.example')
        Copy-Item -LiteralPath (Join-Path $script:repoRoot 'plugins/autopilot/schemas/autopilot.schema.json') -Destination (Join-Path $fixture 'plugins/autopilot/schemas/autopilot.schema.json')
        $configPath = Join-Path $fixture '.autopilot.json'
        $config = Get-Content -LiteralPath (Join-Path $fixture 'plugins/autopilot/.autopilot.json.example') -Raw | ConvertFrom-Json -AsHashtable
        $config.unrelated = 'preserve-me'
        $config | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $configPath -Encoding utf8NoBOM

        $preview = & (Join-Path $fixture 'plugins/skalary-config/skills/skalary-config/scripts/Set-SkalaryConfig.ps1') `
            -Action preview -Category autopilot -RepoRoot $fixture -ChangesJson '{"model":"primary-model-low"}' | ConvertFrom-Json
        $preview.Diff | Should -Match 'primary-model-low'
        $apply = & (Join-Path $fixture 'plugins/skalary-config/skills/skalary-config/scripts/Set-SkalaryConfig.ps1') `
            -Action apply -Category autopilot -RepoRoot $fixture -ExpectedDigest $preview.SourceDigest `
            -ChangesJson '{"model":"primary-model-low"}' | ConvertFrom-Json
        $apply.Result | Should -Match 'Applied canonical'
        $written = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        $written.model | Should -Be 'primary-model-low'
        $written.unrelated | Should -Be 'preserve-me'

        $resetPreview = & (Join-Path $fixture 'plugins/skalary-config/skills/skalary-config/scripts/Set-SkalaryConfig.ps1') `
            -Action reset -Category autopilot -RepoRoot $fixture -Key model | ConvertFrom-Json
        & (Join-Path $fixture 'plugins/skalary-config/skills/skalary-config/scripts/Set-SkalaryConfig.ps1') `
            -Action apply -Category autopilot -RepoRoot $fixture -ExpectedDigest $resetPreview.SourceDigest `
            -ProposedAction reset -Key model | Out-Null
        (Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json).model | Should -Be 'primary-model-mid'

        $beforeCancel = [System.IO.File]::ReadAllBytes($configPath)
        & (Join-Path $fixture 'plugins/skalary-config/skills/skalary-config/scripts/Set-SkalaryConfig.ps1') -Action cancel -Category autopilot -RepoRoot $fixture | Out-Null
        [System.IO.File]::ReadAllBytes($configPath) | Should -Be $beforeCancel
    }

    It 'test:SkalaryConfig.Mutation refuses stale previews and executable or long-context settings without acknowledgement' {
        {
            & $script:writer -Action preview -Category autopilot -RepoRoot $script:repoRoot `
                -ExpectedDigest ('0' * 64) -ChangesJson '{"model":"primary-model-low"}' | Out-Null
        } | Should -Throw '*SourceChanged*'
        {
            & $script:writer -Action preview -Category autopilot -RepoRoot $script:repoRoot `
                -ChangesJson '{"build":"npm run dangerous"}' | Out-Null
        } | Should -Throw '*AcknowledgeExecutableSettings*'
        {
            & $script:writer -Action preview -Category autopilot -RepoRoot $script:repoRoot `
                -ChangesJson '{"context":"long_context"}' | Out-Null
        } | Should -Throw '*AcknowledgeLongContextCost*'
    }

    It 'test:SkalaryConfig.Failures requires a digest and reports direct recovery without rollback' {
        {
            & $script:writer -Action apply -Category autopilot -RepoRoot $script:repoRoot `
                -ChangesJson '{"model":"primary-model-low"}' | Out-Null
        } | Should -Throw '*Apply requires the SourceDigest*'

        $writerText = Get-Content -LiteralPath $script:writer -Raw
        $writerText | Should -Match 'Write failed for'
        $writerText | Should -Match 'Model synchronization failed'
        $writerText | Should -Match 'Model validation failed'
        $writerText | Should -Match 'No rollback was attempted; inspect the visible diff'
        $writerText | Should -Match 'Get-RecoveryCommand'
    }

    It 'test:SkalaryConfig.Models scopes model proposals to the selected alias or role and refuses invalid aliases' {
        $preview = & $script:writer -Action preview -Category models-reviews -RepoRoot $script:repoRoot `
            -ChangesJson '{"Roles.Routine.Primary":"primary-model-mid"}' | ConvertFrom-Json
        $preview.Diff | Should -Match 'Routine'
        $preview.Diff | Should -Not -Match 'Deep'
        {
            & $script:writer -Action preview -Category models-reviews -RepoRoot $script:repoRoot `
                -ChangesJson '{"Roles.Routine.Primary":"not-an-alias"}' | Out-Null
        } | Should -Throw '*known alias*'
        {
            & $script:writer -Action preview -Category models-reviews -RepoRoot $script:repoRoot `
                -ChangesJson '{"Aliases.primary-model-low.Cli":"bad''; injected = ''value"}' | Out-Null
        } | Should -Throw '*invalid host-specific format*'
    }

    It 'test:SkalaryConfig.ModelSynchronization applies a no-op model proposal through the owned sync and validator' {
        $preview = & $script:writer -Action preview -Category models-reviews -RepoRoot $script:repoRoot `
            -ChangesJson '{"Roles.Routine.Primary":"primary-model-low"}' | ConvertFrom-Json
        $result = & $script:writer -Action apply -Category models-reviews -RepoRoot $script:repoRoot `
            -ExpectedDigest $preview.SourceDigest -ChangesJson '{"Roles.Routine.Primary":"primary-model-low"}' | ConvertFrom-Json
        $result.Result | Should -Match 'Applied canonical'
        $result.FinalDiff | Should -BeNullOrEmpty
    }

    It 'bootstraps parser-compatible review standards and confines managed edits to one line' {
        $fixture = Join-Path $TestDrive 'review-standards'
        New-Item -ItemType Directory -Path (Join-Path $fixture 'docs') -Force | Out-Null
        $proposal = & $script:writer -Action bootstrap -Category local-review-standards -RepoRoot $fixture | ConvertFrom-Json
        $proposal.Diff | Should -Match '# Review standards'
        $proposal.Diff | Should -Match '\+- extend `focus`:'
        Set-Content -LiteralPath (Join-Path $fixture 'docs/review-standards.md') -Encoding utf8NoBOM -Value @'
# Review standards
- extend `focus`: Existing focus.
- replace `other`: Preserve this.
'@
        $preview = & $script:writer -Action edit -Category local-review-standards -RepoRoot $fixture `
            -ChangesJson '{"focus":"Changed focus."}' | ConvertFrom-Json
        $preview.Diff | Should -Match 'Changed focus'
        $preview.Diff | Should -Match 'Preserve this'
    }

    It 'test:SkalaryConfig.Autopilot and test:SkalaryConfig.AutopilotAuth provide separate-shell, secret-safe setup and validation' {
        $skill | Should -Match 'separate shell'
        $skill | Should -Match 'github.com/settings/tokens'
        $skill | Should -Match 'copilot login'
        $auth = Get-Content -LiteralPath $script:authValidator -Raw
        $auth | Should -Match 'copilot-autopilot'
        $auth | Should -Match 'copilot-cli'
        $auth | Should -Match 'ado'
        $auth | Should -Match 'REDACTED'
        $auth | Should -Match 'Microsoft.PowerShell.Utility\\Invoke-RestMethod'
        $auth | Should -Match 'Microsoft.PowerShell.Utility\\Invoke-WebRequest'
        $auth | Should -Not -Match 'CredentialValue'
    }
}
