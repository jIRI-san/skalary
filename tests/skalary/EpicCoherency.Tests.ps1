#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Epic coherency review contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:newEpic = Join-Path $script:repoRoot 'scripts/skalary/New-Epic.ps1'
        $script:guide = [System.IO.File]::ReadAllText(
            (Join-Path $script:repoRoot 'plugins/create-implementation-plan/skills/cep/assets/decomposition-guide.md')
        )
        $script:cepSkill = [System.IO.File]::ReadAllText(
            (Join-Path $script:repoRoot 'plugins/create-implementation-plan/skills/cep/SKILL.md')
        )
        $script:ciSkill = [System.IO.File]::ReadAllText(
            (Join-Path $script:repoRoot 'plugins/continue-implementation/skills/ci/SKILL.md')
        )
        $script:autopilotAgent = [System.IO.File]::ReadAllText(
            (Join-Path $script:repoRoot 'plugins/autopilot/agents/autopilot.agent.md')
        )
        $script:fixtureRoots = [System.Collections.Generic.List[string]]::new()

        $script:GetDigest = {
            param([Parameter(Mandatory)][string]$Path)
            $bytes = [System.IO.File]::ReadAllBytes($Path)
            return 'sha256:' + [Convert]::ToHexString(
                [System.Security.Cryptography.SHA256]::HashData($bytes)
            ).ToLowerInvariant()
        }

        $script:NewFixture = {
            $root = Join-Path ([System.IO.Path]::GetTempPath()) ('epic-coherency-' + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path (Join-Path $root 'docs/implementation-plans/epics') -Force |
                Out-Null
            $script:fixtureRoots.Add($root)
            $created = & $script:newEpic -Title 'Fixture epic' -Slug fixture-epic -EpicId abc123 `
                -Date 2026-08-14 -RepoRoot $root
            return [pscustomobject]@{
                Root = $root
                EpicFile = $created.EpicFile
            }
        }

        $script:NewVerdictJson = {
            param(
                [Parameter(Mandatory)][string]$SourceDigest,
                [AllowNull()][string]$ReviewRunId = $null,
                [object[]]$Findings = @(),
                [ValidateSet('keep', 'simplify', 'split', 'defer')][string]$Decision = 'keep',
                [bool]$Blocking = $false,
                [string]$Action = 'Keep the accepted vertical cut.'
            )
            return [ordered]@{
                schema = 'skalary/epic-coherency-verdict@1'
                sourceDigest = $SourceDigest
                reviewRunId = $ReviewRunId
                decision = $Decision
                blocking = $Blocking
                action = $Action
                findings = $Findings
            } | ConvertTo-Json -Depth 6 -Compress
        }
    }

    AfterEach {
        foreach ($root in $script:fixtureRoots) {
            if (Test-Path -LiteralPath $root) {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }
        $script:fixtureRoots.Clear()
    }

    It 'test:EpicCoherency.FixedScope activates the exact eight-label accepted-cut review' {
        $labels = @(
            'goal-success-coverage'
            'definition-of-done-coverage'
            'verticality'
            'child-independence-overlap'
            'shared-ownership'
            'necessary-direct-acyclic-dependencies'
            'usable-mvp-to-final-route'
            'prior-art-reuse'
        )
        foreach ($label in $labels) {
            ([regex]::Matches($script:guide, [regex]::Escape("| ``$label`` |"))).Count |
                Should -Be 1
        }

        $script:guide | Should -Match 'sole accepted-cut design source'
        $script:guide | Should -Match 'exact snapshot bytes'
        $script:guide | Should -Match 'all seven existing concern ids'
        $script:guide | Should -Match 'fourteen tasks'
        $script:guide | Should -Match 'complete attendance'
        $script:guide | Should -Match 'A clean final review.+performs no follow-up'
        $script:cepSkill | Should -Match 'Do not scaffold a child yet'
        $script:cepSkill | Should -Match 'ordinary `/dr` Freeze'
    }

    It 'test:EpicCoherency.IntentAndOwnership fixes ownership, overlap, and dependency evidence' {
        $script:guide | Should -Match 'every proposed mechanism'
        $script:guide | Should -Match 'exactly one owning child'
        $script:guide | Should -Match 'names every consuming child/plan'
        $script:guide | Should -Match 'Compare delivered semantic capability, not mechanism names'
        $script:guide | Should -Match 'dependent cannot implement or validate its delivered slice'
        $script:guide | Should -Match 'infrastructure-only edges'
        $script:guide | Should -Match 'usable MVP'
        $script:guide | Should -Match 'Prior art'
    }

    It 'test:EpicCoherency.ProportionalityGuardrail keeps the three closed classes and four actions' {
        foreach ($class in @('speculative platform', 'required shared contract', 'local fix')) {
            $script:guide | Should -Match ([regex]::Escape("``$class``"))
        }
        foreach ($action in @('keep', 'simplify', 'split', 'defer')) {
            $script:guide | Should -Match ([regex]::Escape($action))
        }
        $script:guide | Should -Match 'Classification is fail-closed'
        $script:guide | Should -Match 'schema, protocol, store, state machine, compatibility layer, provider, or dependency'
        $script:guide | Should -Match 'demonstrated invariant'
    }

    It 'test:EpicCoherency.VerdictAndResolution atomically creates and fully replaces one verdict' {
        $fixture = & $script:NewFixture
        $initialDigest = & $script:GetDigest $fixture.EpicFile
        $initialJson = & $script:NewVerdictJson -SourceDigest $initialDigest

        & $script:newEpic -Epic abc123 -SetCoherencyVerdict -VerdictJson $initialJson `
            -RepoRoot $fixture.Root | Out-Null
        $afterInitial = [System.IO.File]::ReadAllText($fixture.EpicFile)
        ([regex]::Matches($afterInitial, '<!-- epic-coherency-verdict:start -->')).Count | Should -Be 1
        ([regex]::Matches($afterInitial, '<!-- epic-coherency-verdict:end -->')).Count | Should -Be 1

        $finding = [ordered]@{
            taskId = 'architecture-patterns-m1'
            title = 'Shared contract | needs `one` owner'
            proportionalityClass = 'required shared contract'
            blocking = $false
            operatorDecision = 'simplify'
            action = 'Reuse the existing owner and remove the duplicate.'
        }
        $replacementJson = & $script:NewVerdictJson `
            -SourceDigest (& $script:GetDigest $fixture.EpicFile) `
            -ReviewRunId '11111111-1111-1111-1111-111111111111' `
            -Findings @($finding) -Decision simplify

        & $script:newEpic -Epic abc123 -SetCoherencyVerdict -VerdictJson $replacementJson `
            -RepoRoot $fixture.Root | Out-Null
        $replaced = [System.IO.File]::ReadAllText($fixture.EpicFile)
        ([regex]::Matches($replaced, '<!-- epic-coherency-verdict:start -->')).Count | Should -Be 1
        $replaced | Should -Match 'architecture-patterns-m1'
        $replaced | Should -Match 'Shared contract &#124; needs &#96;one&#96; owner'
        $replaced | Should -Not -Match '_not yet reviewed_'
    }

    It 'test:EpicCoherency.VerdictAndResolution rejects stale, duplicate, malformed, and out-of-shape input before mutation' {
        $fixture = & $script:NewFixture
        $digest = & $script:GetDigest $fixture.EpicFile
        $validJson = & $script:NewVerdictJson -SourceDigest $digest
        Add-Content -LiteralPath $fixture.EpicFile -Value 'source drift'
        {
            & $script:newEpic -Epic abc123 -SetCoherencyVerdict -VerdictJson $validJson `
                -RepoRoot $fixture.Root
        } | Should -Throw '*source is stale*'

        $finding = [ordered]@{
            taskId = 'security-m1'
            title = 'Duplicate identity'
            proportionalityClass = 'local fix'
            blocking = $true
            operatorDecision = 'defer'
            action = 'Return to the operator.'
        }
        $duplicateJson = & $script:NewVerdictJson `
            -SourceDigest (& $script:GetDigest $fixture.EpicFile) `
            -ReviewRunId '22222222-2222-2222-2222-222222222222' `
            -Findings @($finding, $finding) -Decision defer -Blocking $true
        {
            & $script:newEpic -Epic abc123 -SetCoherencyVerdict -VerdictJson $duplicateJson `
                -RepoRoot $fixture.Root
        } | Should -Throw '*duplicated, or conflicting*'

        Add-Content -LiteralPath $fixture.EpicFile -Value '<!-- epic-coherency-verdict:broken -->'
        $malformedJson = & $script:NewVerdictJson -SourceDigest (& $script:GetDigest $fixture.EpicFile)
        {
            & $script:newEpic -Epic abc123 -SetCoherencyVerdict -VerdictJson $malformedJson `
                -RepoRoot $fixture.Root
        } | Should -Throw '*malformed or duplicate*'

        $outOfShape = $malformedJson | ConvertFrom-Json -AsHashtable
        $outOfShape['path'] = 'outside.md'
        {
            & $script:newEpic -Epic abc123 -SetCoherencyVerdict `
                -VerdictJson ($outOfShape | ConvertTo-Json -Compress) -RepoRoot $fixture.Root
        } | Should -Throw '*unexpected or incomplete property set*'

        $writerSource = [System.IO.File]::ReadAllText($script:newEpic)
        $writerSource | Should -Match 'Test-CoherencyPathContainsReparsePoint'
        $writerSource | Should -Match '\[ValidateLength\(2, 65536\)\]'
        $writerSource | Should -Match "GetFileName\(\`$epicFile\) -cne 'epic\.md'"
    }

    It 'test:EpicCoherency.PreRunSimplicityCheck is bounded and blocks interactive and headless drift' {
        $script:ciSkill | Should -Match 'Epic current-child simplicity check'
        $script:ciSkill | Should -Match 'after deterministic admission'
        $script:ciSkill | Should -Match 'Never open a sibling child body or sibling asset'
        $script:ciSkill | Should -Match 'Unresolved overcomplication stops before mutation in every mode'
        $script:ciSkill | Should -Match 'A clean check performs no write'
        $script:autopilotAgent | Should -Match 'Epic current-child simplicity check before mutation'
        $script:autopilotAgent | Should -Match 'never read sibling\s+plan bodies or assets'
        $script:autopilotAgent | Should -Match 'exit `42` before marking a step'
    }

    It 'test:EpicCoherency.ConsumerInstall keeps writer and handoff surfaces synchronized' {
        $paths = @(
            'scripts/skalary/New-Epic.ps1'
            'plugins/create-implementation-plan/skills/cep/scripts/New-Epic.ps1'
            '.github/skills/cep/scripts/New-Epic.ps1'
        )
        $hashes = @($paths | ForEach-Object {
                (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $script:repoRoot $_)).Hash
            } | Sort-Object -Unique)
        $hashes.Count | Should -Be 1

        foreach ($path in @(
                'plugins/create-implementation-plan/skills/cep/scripts/AtomicStore.psm1'
                '.github/skills/cep/scripts/AtomicStore.psm1'
            )) {
            Test-Path -LiteralPath (Join-Path $script:repoRoot $path) -PathType Leaf | Should -BeTrue
        }

        [System.IO.File]::ReadAllText(
            (Join-Path $script:repoRoot '.github/skills/cep/SKILL.md')
        ) | Should -BeExactly $script:cepSkill
        [System.IO.File]::ReadAllText(
            (Join-Path $script:repoRoot '.github/skills/ci/SKILL.md')
        ) | Should -BeExactly $script:ciSkill
        [System.IO.File]::ReadAllText(
            (Join-Path $script:repoRoot '.github/agents/autopilot.agent.md')
        ) | Should -BeExactly $script:autopilotAgent
    }
}
